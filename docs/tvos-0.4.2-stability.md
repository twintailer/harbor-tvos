# tvOS 0.4.2 — Folgenwechsel und TV-Bedienung

## Befunde und Änderungen

Ohne Crashreport vom Apple TV ist keine bestimmte native Exception bewiesen.
Die Prüfung hat aber mehrere konkrete Lebensdauer- und Nebenläufigkeitsfehler
im bisherigen Folgenwechsel ergeben:

1. `finishPlayback()` rief `dismiss()` noch synchron aus der Player-Rückmeldung
   auf; nur der separate Leave-Pfad verzögerte das Dismiss. Alle Exit-Pfade
   starten jetzt auf einem neuen Main-Actor-Durchlauf, sperren weitere Eingaben,
   speichern einmal und warten auf `PlayerModel.shutdown()`.
2. VLCs `stop()` ist asynchron. Der Wrapper hält jetzt Controller/Drawable bis
   zur `stopped`-Rückmeldung und entfernt erst danach Delegate, Media und Drawable.
   Siehe [VLCKit-3-Implementierung](https://github.com/videolan/vlckit/blob/3.0/Sources/VLCMediaPlayer.m).
3. MPV zerstörte seinen Core im Hintergrund, ohne die Metal-Oberfläche so lange
   zu halten. Das ist jetzt ein gemeinsamer Lebenszyklus. Native Abfragen,
   Ereignisverarbeitung und Zerstörung sind auf derselben Queue; die UI erhält
   nur Snapshots. Der unretained Wakeup-Callback entfällt. Laut
   [libmpv-API](https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h)
   dürfen während `mpv_terminate_destroy` keine anderen Aufrufe desselben Handles laufen.
4. Ein verzögerter Audio-Session-Release konnte zur nächsten Player-Instanz
   gehören. Die Audio-Ownership gilt jetzt appweit, nicht nur pro SwiftUI-Modell.
5. Resolver-Tasks und der Quellen-Picker konnten neue Präsentationen starten,
   obwohl ein neuer Auftrag oder Zurück bereits erfolgte. Request-IDs verwerfen
   veraltete Ergebnisse; Sheet/Cover-Wechsel erfolgen über deren `onDismiss`.
6. Intro-Skip-Caches waren ungeschützte statische Dictionaries. Ihre Zugriffe
   sind jetzt Main-Actor-isoliert; zugehörige UI-Tasks werden beim Exit abgebrochen.

## Bedienung und Ressourcen

- Player-Aktionen sind beschriftet; Timeline, Skip und nächste Folge folgen ihrer
  sichtbaren vertikalen Reihenfolge. Untermenüs kehren zum letzten Button zurück.
- Play/Pause löst nicht mehr versehentlich Skip Intro aus. Beim Pausieren oder
  Bedienen von Timeline/Skip verschwinden die Controls nicht per Timeout.
- Nächste Folge zeigt den tatsächlichen Titel. Laden ist abbrechbar und besitzt
  einen eigenen Fokus; die darunterliegenden Detail-Buttons sind gesperrt.
- Decoderfehler wechseln kontrolliert zum nächsten Backend. Nach allen Versuchen
  bleiben Quellenwahl, Wiederholen oder Zurück bedienbar.
- MPV-Metadatenabfragen blockieren den UI-Thread nicht mehr. Unveränderte Werte
  werden nicht ständig erneut veröffentlicht. Menüzeilen behalten stabile IDs.
- Artwork: maximal vier gleichzeitige Loads, geteilte Requests identischer Bilder,
  64 statt 128 MiB Decode-Cache und Freigabe bei Memory Warning.
- Episodenlisten beginnen mit 30 Einträgen und besitzen „Show more“. Die bisherige
  stille 200-Episoden-Grenze entfällt. Katalogränder haben einen fokussierbaren
  Nachladebutton statt eines nicht erreichbaren Spinners.
- Fortschritt wird in Auftragsreihenfolge gespeichert. Vollständiges Library-/CW-
  Reload findet nach Playback statt, nicht alle 30 Sekunden hinter dem Video.
- Ruhigere Fokusanimationen, System-Reduce-Motion, bessere Textkontraste,
  Home-Lade-/Leerzustände. Der erfundene „98% Match“-Wert wurde entfernt.
- Kataloge laden nahe dem Listenende vor und haben zusätzlich einen bedienbaren
  Nachladebutton. Duplikate werden ohne Verfälschen des Server-Offsets entfernt;
  veraltete Seiten nach Filterwechsel werden verworfen. Bestehende Browse-Seiten
  werden bei Rückkehr von Details nicht unnötig geleert.
- Next Episode überspringt doppelte Metadateneinträge und funktioniert auch bei
  unsortierten Listen. Überlaufende Episodenzahlen werden sicher verworfen.

## Verifikation

`Tests/PlaybackLifecycleTests.swift` verwendet die produktiven Lifecycle-Typen
und `PlayerModel` mit einem steuerbaren Fake-Decoder. Getestet werden unter
anderem doppelte Stops, verspätete Aufträge, Enginewechsel plus Exit gleichzeitig,
Ownership über Modellwechsel, Richtungsnavigation und ungültige Zeitwerte.

Der Release-Build wird für echtes `appletvos`/arm64 erstellt, nicht für Simulator.
Die Tests beweisen keine Fehlerfreiheit von VLC/MPV auf einem echten HDMI-/HDR-
Gerät. Es liegen hier weder Gerätelog noch gemessene FPS/Temperaturwerte vor.

### Geräteprüfung für die neue IPA

1. VLC, MPV und KSPlayer jeweils mehrfach: Next während laufender Folge, Next
   am natürlichen Ende, zwei schnelle Select-Drücke, Wechsel über Staffelgrenze.
2. Engine wechseln und sofort Zurück; Quellenwahl öffnen, auswählen, abbrechen;
   langsame/defekte Quelle laden und abbrechen. Kein zweiter Player darf auftauchen.
3. Nach jedem Wechsel Ton, Position, bevorzugte Sprache und Untertitel prüfen.
4. 1080p-Anime mit Anime4K, 4K/HDR ohne Anime4K und längere Wiedergabe getrennt testen.
5. Lange Episodenliste und Katalog bis hinter den ersten Batch navigieren; Home
   nach Playback öffnen und aktualisierten Continue-Watching-Eintrag kontrollieren.

Bei einem verbleibenden Crash werden das tvOS-Crashlog, gewählter Decoder,
Apple-TV-Modell und ein reproduzierbarer Wechsel benötigt, um den nativen Stack
statt nur die äußere Zustandsmaschine untersuchen zu können.
