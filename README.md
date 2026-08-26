# Harbor for Apple TV

A native SwiftUI port of Harbor for tvOS. Apple TV does not provide WebKit, so
the Tauri/React shell used on Windows and Android cannot run here. The tvOS app
recreates Harbor with the tvOS focus engine and a native MPVKit player while
using the same Stremio account, add-on, catalog, metadata and stream APIs.

## Current feature set — 0.2

- Harbor navigation: Home, Discover, Catalogs, Movies, Series, Anime, Library,
  Add-ons, Search and Settings
- Stremio sign-in, add-on sync, catalog browsing, library/history and Continue
  Watching
- Stream resolution through the user's installed Stremio add-ons, remembered
  sources, Harbor ranking and safety filtering
- MPVKit-GPL 1.0 playback for HLS, MKV, HDR, multichannel audio and embedded
  tracks, using the tvOS AVFoundation audio output with AudioUnit fallback
- Left-side tvOS navigation matching Harbor's desktop sections instead of a
  top tab strip
- Reference-matched Liquid Glass player chrome with floating speed, subtitle,
  audio, aspect and Anime4K menus
- Skip Intro, Skip Recap and Skip Credits using AniSkip, TheIntroDB and media
  chapters, including independent auto-skip controls
- Optional torrent playback through a user-hosted TorrServer
- Resume/progress sync, next-episode playback, independent seek steps, playback
  speed, audio/subtitle selection and aspect controls
- tvOS-native settings in the same group order as Harbor desktop/Android:
  library, streaming, player, video tuning, Anime4K, player layout, languages,
  theme and advanced
- Anime4K GLSL shaders bundled from a pinned upstream revision, with Harbor's
  modes and performance/high-quality tiers
- Session tokens stored in the tvOS Keychain

Desktop-only concepts such as hotkeys, system tray behavior, native title bars,
download-folder pickers and Discord Rich Presence are intentionally excluded.
Raw torrent/magnet playback still requires a debrid/direct URL from a stream
add-on; Apple TV does not run Harbor's desktop torrent engine.

## Build

The GitHub workflow builds an unsigned tvOS IPA on a macOS runner:

```sh
gh workflow run tvos-build.yml
```

Artifact: `harbor-tvos` → `Harbor_tvOS_0.3.0_unsigned.ipa`.

For a local build on macOS, install Pillow and XcodeGen, then run
`python3 scripts/generate-assets.py`, `bash scripts/fetch-anime4k.sh` and
`xcodegen generate`. Resolve the MPVKit package and build the `HarborTV` scheme
for Apple TV.

## Installing on Apple TV

Pair the Apple TV with Xcode using Window → Devices and Simulators, then install
the built app after signing it with your Apple ID or development team. An
unsigned CI artifact must be re-signed before it can be installed.

## Remaining parity work

- Native OAuth/device-code flows for Trakt, AniList, MyAnimeList, Simkl and
  Letterboxd
- Harbor Relay / Watch Together and webhook automation settings
- Remote P2P/server playback for torrent-only results
- Calendar, live TV, playlists, downloads and profile/PIN management
- Full metadata-provider configuration and richer stream-filter rule editing
