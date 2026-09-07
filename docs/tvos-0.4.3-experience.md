# Harbor tvOS 0.4.3 — TV experience and performance

## Interface

- Continue Watching leads Home when history is available, with large 16:9 artwork,
  an independent progress strip, episode context and remaining minutes when known.
- Catalog rails combine a wide lead tile with portrait posters. A short, cancellable
  focus debounce updates the synopsis below the rail; card widths never animate or
  reflow on focus, keeping directional navigation predictable.
- Detail pages use a full-screen backdrop, left-aligned real metadata and a vertical
  Play/Resume, More Episodes and My List action stack. Back from the episodes returns
  to the overview before leaving the detail screen.
- The previously requested left navigation stays. Navigation/actions/player panels
  share tvOS 26 Liquid Glass, with a material fallback on older tvOS and an opaque
  Reduce Transparency fallback. Poster grids do not each incur a live blur pass.
- White focus rings, smaller focus scaling and short transitions replace the former
  extra colored focus strip (which could be mistaken for playback progress).

## Concrete performance changes

- PlaybackClock publishes position/duration independently of PlayerModel. Only the
  visible timeline observes it; playback ticks no longer invalidate every menu and
  native player surface. Up-next state is updated only when its boundary changes.
- Timeline progress no longer starts an implicit animation on every decoder tick.
  Long player menus use lazy rows; their animations depend on local focus.
- MPV still polls the clock at 4 Hz and the audio recovery summary at 1 Hz. Full
  track metadata is refreshed on count/selection changes, explicit invalidation or
  a 15-second fallback. Chapter snapshots use count changes/30-second fallback.
- MPV warnings are deduplicated, batched and bounded; a warning storm no longer
  schedules a separate main-thread publication for each line.
- Artwork has a four-operation download/decode budget and consumer-aware
  cancellation. Offscreen requests stop when no visible consumer needs them.
  ImageIO decodes run off the cache actor, so cache hits/cancellation stay responsive.
- Cached artwork reappears without another decode. Offscreen card state releases
  its image instead of retaining every visited poster forever. The shared cache
  remains bounded to 64 MiB; generations prevent requests refilling a purged cache.
- Add-on catalog/search fan-out is bounded to four requests, preserving provider
  order. Catalog pages have a 60-second, 32-page/3,000-title bounded memory cache.
  Cancelled searches no longer continue into fallback providers.
- Library and Continue Watching derive from one coalesced datastore fetch instead
  of two identical requests. Mutations invalidate in-flight snapshots.
- Episode lists memoize date parsing/sorting. Hidden spoiler thumbnails neither
  download nor blur artwork; rows and player options instantiate lazily.

## Verification and limits

The native regression executable covers lifecycle serialization, stale-request and
controller ownership, directional player navigation, metadata edge cases, clock
publication isolation (240 ticks without a PlayerModel UI invalidation), progress
geometry and up-next boundaries. The release workflow compiles the complete app
against the Apple TV SDK and packages an unsigned arm64 IPA.

These are code-level improvements, not a claimed hardware FPS benchmark. Actual
Siri Remote focus, TV layout and Anime4K GPU frame times must still be tested on an
Apple TV. Existing shutdown/drawable ownership barriers remain intact. Anime4K's
source-resolution protection is not relaxed to obtain artificial quality gains.

Builds use the standard `macos-latest` GitHub-hosted runner in the existing public
repository, guarded against private repository execution. No larger paid runner or
private Actions-minute consumption is required. Installation needs signing.
