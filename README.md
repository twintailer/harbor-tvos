# Harbor for Apple TV (tvOS)

A **native SwiftUI** port of [Harbor](https://github.com/twintailer/harbor) for
Apple TV. tvOS has no WebKit/WKWebView, so the Tauri + React app that powers the
iPhone/desktop builds cannot run here — this is a ground-up native rewrite using
the tvOS focus engine, sharing Harbor's data sources (Stremio addons / Cinemeta).

## Status — v0.1 (foundation)

- Home: focus-navigable poster rows (Trending / Top rated) from Cinemeta
- Discover: type + genre browsing grid
- Search: live movie/series search
- Detail: backdrop, metadata, episode list
- Player: native AVKit (AVPlayer) — currently plays a public HLS test stream;
  the real addon/debrid stream resolver lands in a later round

## Build

CI builds an **unsigned** tvOS IPA on a macOS runner:

```
gh workflow run tvos-build.yml
```

Artifact: `harbor-tvos` → `Harbor_tvOS_0.1.0_unsigned.ipa`.

## Installing on Apple TV

Sideloading tvOS is harder than iPhone — there is no AltStore for tvOS. You need
**Xcode on a Mac** with the Apple TV paired (Xcode → Window → Devices and
Simulators → your Apple TV → install the app), which re-signs it with your Apple
ID. A free Apple ID works but the app expires after 7 days, same as iOS.

## Roadmap

1. User's installed Stremio addons (not just Cinemeta)
2. Stream resolution (Torrentio / debrid) + real playback
3. Watch progress / library sync
4. Subtitles, audio tracks, next-episode
