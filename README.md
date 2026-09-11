# Harbor for Apple TV

A native SwiftUI port of Harbor for tvOS. Apple TV does not provide WebKit, so
the Tauri/React shell used on Windows and Android cannot run here. The tvOS app
recreates Harbor with the tvOS focus engine and a native MPVKit player while
using the same Stremio account, add-on, catalog, metadata and stream APIs.

## Playback stability and TV experience — 0.4.2

- Next episode, source changes, engine changes and Back share a native teardown
  barrier. VLC waits for `stopped`; MPV retains its Metal surface until destruction
  finishes on its serial queue. Decoder callbacks no longer own presentation.
- Cancelled/stale stream requests cannot open another player; source sheets finish
  dismissing before presenting video. Audio-session ownership spans player models.
- Player actions have readable labels, menus restore the last button, Down reaches
  the timeline, and Play/Pause always controls playback, even during a skip prompt.
- Next-episode titles, cancellable stream loading, explicit playback-error recovery,
  catalog retry and focusable page-loading actions replace ambiguous waiting states.
- Off-main MPV metadata snapshots, stable menu identities, coalesced/limited artwork
  loading, a 64 MiB decoded-art cache and 30-episode batches reduce UI/memory work.
- Playback progress saves are ordered; full library refresh runs after leaving video.

Native framework crashes and HDMI/Anime4K frame pacing still require Apple TV
hardware verification. A successful compile or logic test is not a device soak test.

## Current feature set

- Harbor navigation: Home, Discover, Catalogs, Movies, Series, Anime, Library,
  Add-ons, Search and Settings
- Stremio sign-in, add-on sync, catalog browsing, library/history and Continue
  Watching
- Stream resolution through the user's installed Stremio add-ons, remembered
  sources, Harbor ranking and safety filtering
- MPVKit-GPL 1.0 playback for HLS, MKV, HDR, multichannel audio and embedded
  tracks, using the tvOS AVFoundation audio output with AudioUnit fallback
- A top navigation bar for Search, Home, Series, Movies, Anime, Catalogs and
  My Harbor, with Discover/Add-ons in More and direct access to Settings
- Reference-matched Liquid Glass player chrome with floating speed, subtitle,
  audio, aspect and Anime4K menus
- Back on Home returns to the Apple TV Home screen. Other top-level sections
  return to Harbor Home; details and settings subpages go back one level
- Focus selects the wide preview in catalog and Continue Watching rows, with
  matching artwork/synopsis and retained selection after leaving a row
- MPV and VLC playback engines (MPV/Anime4K default, TVVLCKit compatibility fallback)
- Harbor, Orivio Max-inspired Midnight and Orivio Netflix-inspired Cinema styles
- Window-level player Back handling and auto-closing track/speed menus
- Skip Intro, Skip Recap and Skip Credits using AniSkip, TheIntroDB and media
  chapters, including independent auto-skip controls
- Optional torrent playback through a user-hosted TorrServer
- Resume/progress sync, next-episode playback, independent seek steps, playback
  speed, audio/subtitle selection and aspect controls
- A settings dashboard with seven categories and at most six tiles per category.
  Quick access opens common settings directly; longer panels use short pages for
  playback, audio, intro skip, subtitle styling, library, video and appearance
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

Artifact: `harbor-tvos` → `Harbor_tvOS_0.4.4_unsigned.ipa`.

The workflow uses the standard `macos-latest` runner in the public repository;
it does not consume private-repository included minutes. A public-only job guard
prevents runs if the repository becomes private. This is still GitHub Actions,
not a local or self-hosted Mac.

Before building, the workflow compiles and runs `Tests/PlaybackLifecycleTests.swift`
against the production lifecycle types and `PlayerModel`. It checks duplicate stops,
late callbacks, rapid cancellation, overlapping exit/engine switches, audio ownership
and directional remote navigation without requiring a simulator.

`Tests/TVNavigationTests.swift` also checks root Back policy, preview selection
through focus changes/pagination/removal, and complete settings navigation within
the dashboard's six-tile budget. These pure rules can run on Linux as well:

```sh
swiftc -swift-version 5 -parse-as-library Sources/Models/TVNavigation.swift \
  Tests/TVNavigationTests.swift -o /tmp/harbor-navigation-tests
/tmp/harbor-navigation-tests
```

The navigation rules and Swift syntax can be checked without Xcode. A full tvOS
build still needs the Apple TV SDK; focus geometry, the system Home transition
and layout need simulator/device verification with the Siri Remote.

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
