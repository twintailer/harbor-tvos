import SwiftUI
import UIKit

struct PlayerTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    var startAt: Double = 0
    var isAnime: Bool = false
    var contentID: String = ""
    var season: Int? = nil
    var episode: Int? = nil
    var requestHeaders: [String: String] = [:]
    var onProgress: ((Double, Double) -> Void)? = nil
    var onEnded: (() -> Void)? = nil
}

/// Full-screen libmpv player for tvOS. ALL remote input is handled at the UIKit level by a focusable
/// `RemoteCatcher` (pressesBegan) — SwiftUI `@FocusState` + command modifiers are unreliable inside a
/// full-screen cover on tvOS (that was the "control bar shows only sporadically" bug). The bar and the
/// options panel are driven by plain state, no SwiftUI focus.
struct PlayerView: View {
    let target: PlayerTarget
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()

    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showOptions = false
    @State private var panelKind: PanelKind = .audio
    @State private var optionRow = 0
    @State private var audioTracks: [MPVTrack] = []
    @State private var subtitleTracks: [MPVTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var pendingAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int = -1
    @State private var videoHeight = 0
    @State private var audioCodec = ""
    @State private var audioOut = ""
    @State private var appliedAutoTracks = false
    @State private var lastTrackRefresh = Date.distantPast
    @State private var animeActive = false
    @State private var confirmingLeave = false
    @State private var handledEnd = false
    @State private var lastSavedPosition = 0.0
    @State private var subtitleDelay = 0.0
    @State private var audioDelay = 0.0
    @State private var readyAt = Date.distantFuture
    @State private var lastMediaRefresh = Date.distantPast
    @State private var lastAudioRecovery = Date.distantPast
    @State private var audioRecoveryStage = 0
    @State private var skipSegments: [SkipSegment] = []
    @State private var activeSkip: SkipSegment?
    @State private var introSkipLoaded = false
    @State private var autoSkippedSegments = Set<String>()
    @State private var skipButtonVisible = false
    @State private var skipHideTask: Task<Void, Never>?

    // Scrub-to-seek
    @State private var scrubbing = false
    @State private var scrubTarget = 0.0
    @State private var scrubStep = 10.0
    @State private var lastScrubAt = 0.0
    @State private var scrubCommit: Task<Void, Never>?

    @AppStorage(SubtitleStyle.Key.style) private var subStyle = SubtitleStyle.defaultStyle
    @AppStorage(SubtitleStyle.Key.bold) private var subBold = false
    @AppStorage(SubtitleStyle.Key.borderSize) private var subBorderSize = 2.0
    @AppStorage(SubtitleStyle.Key.margin) private var subMargin = 12.0
    @AppStorage(SubtitleStyle.Key.opacity) private var subOpacity = 1.0
    @AppStorage(SubtitleStyle.Key.alignment) private var subAlignment = "center"
    @AppStorage(SubtitleStyle.Key.font) private var subFont = "inter"
    @AppStorage(SubtitleStyle.Key.fontSize) private var subFontSize = SubtitleStyle.defaultFontSize
    @AppStorage(SubtitleStyle.Key.fontColor) private var subFontColor = SubtitleStyle.defaultFontColor
    @AppStorage(SubtitleStyle.Key.borderColor) private var subBorderColor = SubtitleStyle.defaultBorderColor
    @AppStorage(SubtitleStyle.Key.boxColor) private var subBoxColor = SubtitleStyle.defaultBoxColor
    @AppStorage(SubtitleStyle.Key.boxOpacity) private var subBoxOpacity = 0.6
    @AppStorage(SubtitleStyle.Key.assOverride) private var subAssOverride = "no"
    @AppStorage(SubtitleStyle.Key.lineSpacing) private var subLineSpacing = 0.0
    @AppStorage(SubtitleStyle.Key.subLang) private var prefSubLang = ""
    @AppStorage(SubtitleStyle.Key.secondarySubLang) private var secondarySubLang = ""
    @AppStorage(SubtitleStyle.Key.preferForcedSubs) private var preferForcedSubs = false
    @AppStorage(SubtitleStyle.Key.audioLang) private var prefAudioLang = ""
    @AppStorage(SubtitleStyle.Key.subsOff) private var subsOffByDefault = false
    @AppStorage(SubtitleStyle.Key.preferEmbedded) private var preferEmbedded = false
    @AppStorage(SubtitleStyle.Key.defaultSpeed) private var defaultSpeed = 1.0
    @AppStorage(SubtitleStyle.Key.playerEngine) private var playerEngine = "auto"
    @AppStorage(SubtitleStyle.Key.seekBackStep) private var seekBackStep = 10
    @AppStorage(SubtitleStyle.Key.seekForwardStep) private var seekForwardStep = 10
    @AppStorage(SubtitleStyle.Key.controlsHideSeconds) private var controlsHideSeconds = 5
    @AppStorage(SubtitleStyle.Key.showQualityInfo) private var showQualityInfo = true
    @AppStorage(SubtitleStyle.Key.playerTitleScale) private var playerTitleScale = 1.0
    @AppStorage(SubtitleStyle.Key.confirmLeave) private var confirmLeave = true
    @AppStorage(SubtitleStyle.Key.autoPlayNext) private var autoPlayNext = true
    @AppStorage(SubtitleStyle.Key.accent) private var accentID = "green"
    @AppStorage(SubtitleStyle.Key.anime4KEnabled) private var anime4KEnabled = false
    @AppStorage(SubtitleStyle.Key.anime4KAnimeOnly) private var anime4KAnimeOnly = true
    @AppStorage(SubtitleStyle.Key.anime4KIndicator) private var anime4KIndicator = true
    @AppStorage(SubtitleStyle.Key.anime4KMode) private var anime4KMode = "A"
    @AppStorage(SubtitleStyle.Key.showSkipButton) private var showSkipButton = true
    @AppStorage(SubtitleStyle.Key.autoSkipIntro) private var autoSkipIntro = false
    @AppStorage(SubtitleStyle.Key.autoSkipRecap) private var autoSkipRecap = false
    @AppStorage(SubtitleStyle.Key.autoSkipOutro) private var autoSkipOutro = false
    @AppStorage(SubtitleStyle.Key.skipButtonHideSec) private var skipButtonHideSec = 10
    @AppStorage(SubtitleStyle.Key.nextEpisodeLeadSec) private var nextEpisodeLeadSec = -1
    @AppStorage(SubtitleStyle.Key.showRestartButton) private var showRestartButton = true
    @AppStorage(SubtitleStyle.Key.showSeekButtons) private var showSeekButtons = true
    @AppStorage(SubtitleStyle.Key.showNextButton) private var showNextButton = true
    @AppStorage(SubtitleStyle.Key.showSpeedButton) private var showSpeedButton = true
    @AppStorage(SubtitleStyle.Key.showSubtitleButton) private var showSubtitleButton = true
    @AppStorage(SubtitleStyle.Key.showAudioButton) private var showAudioButton = true
    @AppStorage(SubtitleStyle.Key.showAspectButton) private var showAspectButton = true
    @AppStorage(SubtitleStyle.Key.showAnimeButton) private var showAnimeButton = true

    private enum Control: Hashable { case scrub, restart, back, play, fwd, next, audio, subs, aspect, speed, anime }
    private enum PanelKind { case audio, subtitles, subtitleSettings, aspect, speed, anime, debug }
    @State private var selected: Control = .play
    @State private var lastButton: Control = .play
    @State private var speed: Double = 1.0

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var controlsHidden: Bool { !showInfo && !showOptions }
    private var accent: Color { HarborSettings.accentColor(accentID) }
    private var animeAvailable: Bool {
        let nested = Bundle.main.urls(forResourcesWithExtension: "glsl", subdirectory: "Anime4K") ?? []
        let root = Bundle.main.urls(forResourcesWithExtension: "glsl", subdirectory: nil) ?? []
        return Set(nested + root).count >= 11
    }
    private var shouldStartAnime4K: Bool {
        anime4KEnabled && animeAvailable && (!anime4KAnimeOnly || target.isAnime)
    }
    private var usesVLC: Bool { playerEngine == "vlc" }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if usesVLC {
                VLCPlayerView(url: target.url, model: model, startAt: target.startAt,
                              requestHeaders: target.requestHeaders)
                    .ignoresSafeArea()
            } else {
                MPVPlayerView(url: target.url, model: model, startAt: target.startAt,
                              anime4K: shouldStartAnime4K, requestHeaders: target.requestHeaders)
                    .ignoresSafeArea()
            }

            // UIKit owns ALL remote input.
            RemoteCatcher(onPress: { handlePress($0) }, onSwipe: { showControls() })
            RemoteMenuCatcher { handleBack() }

            if !model.ready {
                ProgressView().controlSize(.large).tint(accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showInfo { controlBar }
            if showOptions { optionsPanel }
            if let segment = activeSkip, skipButtonVisible, showSkipButton, !showOptions {
                skipPill(segment)
            } else if upNextActive, !showOptions {
                upNextPill
            }
            if animeActive && anime4KIndicator {
                VStack {
                    HStack {
                        Spacer()
                        Label("Anime4K", systemImage: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .foregroundStyle(accent)
                    }
                    Spacer()
                }
                .padding(34)
            }
        }
        .onReceive(model.$ready) {
            if $0 {
                if readyAt == .distantFuture { readyAt = Date() }
                refreshTracksSoon()
                loadIntroSkipIfNeeded()
            }
        }
        .onReceive(model.$position) { position in
            maybeAutoSelectTracks()
            monitorAudioOutput()
            loadIntroSkipIfNeeded()
            updateActiveSkip(at: position)
            if model.duration > 0, position > 0, abs(position - lastSavedPosition) >= 30 {
                lastSavedPosition = position
                target.onProgress?(position, model.duration)
            }
        }
        .onReceive(model.$ended) { ended in
            guard ended, !handledEnd else { return }
            handledEnd = true
            target.onProgress?(model.duration, model.duration)
            if autoPlayNext, let onEnded = target.onEnded { onEnded() }
            dismiss()
        }
        .onAppear {
            showInfo = true; selected = .play; scheduleHide()
            animeActive = shouldStartAnime4K
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            hideTask?.cancel(); scrubCommit?.cancel(); skipHideTask?.cancel()
            if !handledEnd { target.onProgress?(model.position, model.duration) }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog("Leave playback?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Playback", role: .destructive) { dismiss() }
            Button("Keep Watching", role: .cancel) { scheduleHide() }
        }
    }

    // MARK: - Remote handling

    private func handlePress(_ type: UIPress.PressType) {
        if showOptions {
            switch type {
            case .upArrow: moveOption(-1)
            case .downArrow: moveOption(1)
            case .select: activateOption()
            default: break
            }
            return
        }
        if controlsHidden {
            switch type {
            case .playPause:
                if activeSkip != nil, skipButtonVisible { performSkip() } else { toggle() }
            case .select:
                if activeSkip != nil, skipButtonVisible { performSkip() } else { showControls() }
            default: showControls()
            }
            return
        }
        // Bar shown: 2D navigation.
        switch type {
        case .playPause:
            if activeSkip != nil, skipButtonVisible { performSkip() } else { toggle() }
        case .select: activate(selected)
        case .leftArrow: horizontal(-1)
        case .rightArrow: horizontal(1)
        case .upArrow: vertical(-1)
        case .downArrow: vertical(1)
        default: break
        }
    }

    /// One Back press always moves exactly one UI level. A window-level menu
    /// recognizer owns the press, so it cannot also fall through to tvOS and
    /// dismiss the player/app a second time.
    private func handleBack() {
        if showOptions {
            switch panelKind {
            case .subtitleSettings: openPanel(.subtitles)
            case .debug: openPanel(.aspect)
            default: closePanel()
            }
            return
        }
        if scrubbing {
            cancelScrub()
            return
        }
        if showInfo {
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.14)) { showInfo = false }
            return
        }
        requestDismiss()
    }

    private var buttonRow: [Control] {
        var c: [Control] = []
        if showRestartButton { c.append(.restart) }
        if showSeekButtons { c.append(.back) }
        c.append(.play)
        if showSeekButtons { c.append(.fwd) }
        if showNextButton, target.onEnded != nil { c.append(.next) }
        if showSpeedButton { c.append(.speed) }
        if showSubtitleButton { c.append(.subs) }
        if showAudioButton, !audioTracks.isEmpty { c.append(.audio) }
        if showAspectButton { c.append(.aspect) }
        // Anime4K is a video filter, not an anime-only destination. Keep the
        // control visible for movies and series as requested; automatic startup
        // may still be limited by the separate "anime only" preference.
        if showAnimeButton { c.append(.anime) }
        return c
    }

    private func horizontal(_ d: Int) {
        switch selected {
        case .scrub: scrubBy(d)
        default:
            let row = buttonRow
            let i = row.firstIndex(of: selected) ?? 0
            selected = row[max(0, min(row.count - 1, i + d))]
            lastButton = selected
            flashControls()
        }
    }

    /// Two deterministic rows, matching Orivio: timeline ↔ play/pause. Returning
    /// from the timeline never lands on a stale far-right utility button.
    private func vertical(_ d: Int) {
        commitScrubIfNeeded()
        switch selected {
        case .scrub: if d > 0 { selected = .play; lastButton = .play }
        default: if d < 0 { selected = .scrub }
        }
        flashControls()
    }

    private func activate(_ c: Control) {
        switch c {
        case .scrub:   scrubbing ? commitScrub() : toggle()
        case .restart: requestDismiss()
        case .back:    seek(-Double(seekBackStep))
        case .fwd:     seek(Double(seekForwardStep))
        case .play:    toggle()
        case .next:    playNextNow()
        case .audio:   openPanel(.audio)
        case .subs:    openPanel(.subtitles)
        case .aspect:  openPanel(.aspect)
        case .speed:   openPanel(.speed)
        case .anime:   openPanel(.anime)
        }
    }

    // MARK: - Control bar

    private var metadataLine: String {
        var parts: [String] = []
        if showQualityInfo { switch videoHeight {
        case 2000...:     parts.append("4K")
        case 1300..<2000: parts.append("1440p")
        case 900..<1300:  parts.append("1080p")
        case 600..<900:   parts.append("720p")
        case 1..<600:     parts.append("\(videoHeight)p")
        default:          break
        } }
        if showQualityInfo, !audioCodec.isEmpty { parts.append(audioCodec.uppercased()) }
        if abs(speed - 1.0) > 0.01 { parts.append(String(format: "%gx", speed)) }
        return parts.joined(separator: "  ·  ")
    }

    /// Bottom player chrome matching the supplied Apple TV reference: title and
    /// transport on one line, utility circles on the right, then a full-width
    /// timeline and elapsed/remaining clocks over a soft video gradient.
    private var controlBar: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 28) {
                    VStack(alignment: .leading, spacing: 3) {
                    if !target.title.isEmpty {
                            Text(target.title)
                                .font(.system(size: 40 * playerTitleScale, weight: .bold))
                            .foregroundStyle(.white).lineLimit(1)
                    }
                    if !metadataLine.isEmpty {
                            Text(metadataLine).font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                    }
                    Spacer()
                }

                HStack(alignment: .center, spacing: 16) {
                    HStack(spacing: 14) {
                        if showRestartButton { ctrlButton(.restart, "stop.fill") }
                        if showSeekButtons { ctrlButton(.back, "gobackward.\(seekBackStep)") }
                        ctrlButton(.play, model.paused ? "play.fill" : "pause.fill", big: true)
                        if showSeekButtons { ctrlButton(.fwd, "goforward.\(seekForwardStep)") }
                        if showNextButton, target.onEnded != nil { ctrlButton(.next, "forward.end.fill") }
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        if showSpeedButton { ctrlButton(.speed, "speedometer") }
                        if showSubtitleButton { ctrlButton(.subs, "captions.bubble.fill") }
                        if showAudioButton, !audioTracks.isEmpty { ctrlButton(.audio, "waveform.circle.fill") }
                        if showAspectButton { ctrlButton(.aspect, "aspectratio") }
                        if showAnimeButton { ctrlButton(.anime, "sparkles") }
                    }
                }

                scrubber

                HStack {
                    Text(timeString(scrubbing ? scrubTarget : model.position))
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(scrubbing ? accent : .white.opacity(0.92))
                    Spacer()
                    let shown = scrubbing ? scrubTarget : model.position
                    Text("−\(timeString(max(0, model.duration - shown)))")
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(.horizontal, 68)
            .padding(.bottom, 42)
        }
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.24), location: 0.24),
                    .init(color: .black.opacity(0.78), location: 0.72),
                    .init(color: .black.opacity(0.94), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 430)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private var scrubber: some View {
        let focused = (selected == .scrub)
        let shown = scrubbing ? scrubTarget : model.position
        return GeometryReader { geo in
            let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
            let w = geo.size.width
            let barH: CGFloat = focused ? 11 : 7
            let knob: CGFloat = focused ? 28 : 20
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.32)).frame(height: barH)
                Capsule().fill(.white.opacity(0.96)).frame(width: max(0, w * frac), height: barH)
                Circle().fill(.white).frame(width: knob, height: knob)
                    .offset(x: max(0, w * frac - knob / 2))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.12), value: frac)
        }
        .frame(height: 30)
    }

    private func ctrlButton(_ c: Control, _ icon: String, big: Bool = false) -> some View {
        let sel = (selected == c)
        let d: CGFloat = big ? 78 : 68
        return Image(systemName: icon)
            .font(.system(size: big ? 31 : 25, weight: .semibold))
            .foregroundStyle(sel ? .black : .white)
            .frame(width: d, height: d)
            .background(Circle().fill(sel ? Color.white : Color.white.opacity(0.13)))
            .harborGlass(cornerRadius: d / 2, tint: sel ? .white.opacity(0.7) : .black.opacity(0.04))
            .overlay(Circle().stroke(.white.opacity(sel ? 0.92 : 0.28), lineWidth: sel ? 2.5 : 1))
            .shadow(color: .black.opacity(0.42), radius: 15, y: 8)
            .scaleEffect(sel ? 1.10 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: sel)
    }

    private func skipPill(_ segment: SkipSegment) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "forward.end.fill")
                    Text(segment.label)
                }
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .harborGlass(cornerRadius: 30, tint: Color.black.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 9)
            }
            .padding(.trailing, 68)
            .padding(.bottom, showInfo ? 355 : 46)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var upNextActive: Bool {
        guard target.onEnded != nil, nextEpisodeLeadSec != 0, model.duration > 0 else { return false }
        let automatic = max(25, min(90, Int(model.duration * 0.045)))
        let lead = nextEpisodeLeadSec < 0 ? automatic : nextEpisodeLeadSec
        return model.position > 0 && model.duration - model.position <= Double(lead)
    }

    private var upNextPill: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "forward.end.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Up Next").font(.system(size: 17, weight: .medium))
                        Text("Next Episode").font(.system(size: 23, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 13)
                .harborGlass(cornerRadius: 28, tint: Color.black.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 9)
            }
            .padding(.trailing, 68)
            .padding(.bottom, showInfo ? 355 : 46)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Options panel

    private struct OptionRow: Identifiable {
        let id = UUID()
        let label: String
        var detail: String = ""
        var isSelected: Bool = false
        var isHeader: Bool = false
        var action: () -> Void = {}
    }

    private var optionRows: [OptionRow] {
        switch panelKind {
        case .audio:
            var rows = groupedTrackRows(audioTracks, selectedID: selectedAudioTrackID) { setAudio($0) }
            rows.append(OptionRow(label: "Audio sync", detail: String(format: "%+.1fs", audioDelay), isHeader: true))
            rows.append(OptionRow(label: "Audio 0.1s earlier") { audioDelay -= 0.1; model.controller?.setAudioDelay(audioDelay) })
            rows.append(OptionRow(label: "Reset audio sync") { audioDelay = 0; model.controller?.setAudioDelay(0) })
            rows.append(OptionRow(label: "Audio 0.1s later") { audioDelay += 0.1; model.controller?.setAudioDelay(audioDelay) })
            return rows
        case .subtitles:
            var rows = [OptionRow(label: "Off", isSelected: selectedSubtitleTrackID < 0) {
                selectedSubtitleTrackID = -1
                model.controller?.setSubtitleTrack(-1); refreshTracksSoon()
            }]
            rows += groupedTrackRows(subtitleTracks, selectedID: selectedSubtitleTrackID) { setSub($0) }
            rows.append(OptionRow(label: "Subtitle Settings", detail: "›") { openPanel(.subtitleSettings) })
            rows.append(OptionRow(label: "Subtitle sync", detail: String(format: "%+.1fs", subtitleDelay), isHeader: true))
            rows.append(OptionRow(label: "Subtitles 0.1s earlier") { subtitleDelay -= 0.1; model.controller?.setSubDelay(subtitleDelay) })
            rows.append(OptionRow(label: "Reset subtitle sync") { subtitleDelay = 0; model.controller?.setSubDelay(0) })
            rows.append(OptionRow(label: "Subtitles 0.1s later") { subtitleDelay += 0.1; model.controller?.setSubDelay(subtitleDelay) })
            return rows
        case .subtitleSettings:
            var rows: [OptionRow] = [OptionRow(label: "Background", isHeader: true)]
            for value in SubtitleStyle.styles {
                rows.append(OptionRow(label: value.label, isSelected: subStyle == value.id) {
                    subStyle = value.id; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Styled (ASS) subtitles", isHeader: true))
            for value in SubtitleStyle.assOverrides {
                rows.append(OptionRow(label: value.label, isSelected: subAssOverride == value.id) {
                    subAssOverride = value.id; applySubtitleStyleSoon()
                })
            }
            if subStyle == "box" {
                rows.append(OptionRow(label: "Background opacity", isHeader: true))
                for value in SubtitleStyle.opacities {
                    rows.append(OptionRow(label: "\(Int(value * 100))%", isSelected: abs(subBoxOpacity - value) < 0.01) {
                        subBoxOpacity = value; applySubtitleStyleSoon()
                    })
                }
            }
            if subStyle == "outline" {
                rows.append(OptionRow(label: "Outline thickness", isHeader: true))
                for value in SubtitleStyle.outlineSizes.dropFirst() {
                    rows.append(OptionRow(label: String(format: "%.0f px", value), isSelected: abs(subBorderSize - value) < 0.01) {
                        subBorderSize = value; applySubtitleStyleSoon()
                    })
                }
            }
            rows.append(OptionRow(label: "Font", isHeader: true))
            for value in SubtitleStyle.fonts {
                rows.append(OptionRow(label: value.label, isSelected: subFont == value.id) {
                    subFont = value.id; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Bold text", detail: subBold ? "On" : "Off", isSelected: subBold) {
                subBold.toggle(); applySubtitleStyleSoon()
            })
            rows.append(OptionRow(label: "Size", isHeader: true))
            for value in SubtitleStyle.fontSizes {
                rows.append(OptionRow(label: String(format: "%.0f px", value), isSelected: abs(subFontSize - value) < 0.01) {
                    subFontSize = value; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Opacity", isHeader: true))
            for value in SubtitleStyle.opacities {
                rows.append(OptionRow(label: "\(Int(value * 100))%", isSelected: abs(subOpacity - value) < 0.01) {
                    subOpacity = value; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Distance from bottom", isHeader: true))
            for value in SubtitleStyle.margins {
                rows.append(OptionRow(label: String(format: "%.0f%%", value), isSelected: abs(subMargin - value) < 0.01) {
                    subMargin = value; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Alignment", isHeader: true))
            for value in ["left", "center", "right"] {
                rows.append(OptionRow(label: value.capitalized, isSelected: subAlignment == value) {
                    subAlignment = value; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Line spacing", isHeader: true))
            for value in SubtitleStyle.lineSpacings {
                rows.append(OptionRow(label: String(format: "%+.0f px", value), isSelected: abs(subLineSpacing - value) < 0.01) {
                    subLineSpacing = value; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Text color", isHeader: true))
            for value in SubtitleStyle.textColors {
                rows.append(OptionRow(label: value.label, isSelected: subFontColor == value.id) {
                    subFontColor = value.id; applySubtitleStyleSoon()
                })
            }
            rows.append(OptionRow(label: "Outline color", isHeader: true))
            for value in SubtitleStyle.edgeColors {
                rows.append(OptionRow(label: value.label, isSelected: subBorderColor == value.id) {
                    subBorderColor = value.id; applySubtitleStyleSoon()
                })
            }
            if subStyle == "box" {
                rows.append(OptionRow(label: "Box color", isHeader: true))
                for value in SubtitleStyle.edgeColors {
                    rows.append(OptionRow(label: value.label, isSelected: subBoxColor == value.id) {
                        subBoxColor = value.id; applySubtitleStyleSoon()
                    })
                }
            }
            rows.append(OptionRow(label: "Reset subtitle appearance") {
                resetSubtitleAppearance(); applySubtitleStyleSoon()
            })
            return rows
        case .aspect:
            let mode = model.controller?.videoSizeMode ?? "original"
            return [
                OptionRow(label: "Fit  ·  default", isSelected: mode == "original") { model.controller?.setVideoSize("original") },
                OptionRow(label: "Fill  ·  crop to screen", isSelected: mode == "fill" || mode == "zoom") { model.controller?.setVideoSize("fill") },
                OptionRow(label: "Stretch  ·  fill, distort", isSelected: mode == "stretch") { model.controller?.setVideoSize("stretch") },
                OptionRow(label: "Debug info", detail: "›") { openPanel(.debug) },
            ]
        case .debug:
            var rows = [OptionRow(label: "Audio output: \(audioOut.isEmpty ? "none" : audioOut)", isHeader: true)]
            if model.logLines.isEmpty {
                rows.append(OptionRow(label: "No warnings logged."))
            } else {
                rows += model.logLines.suffix(24).map { OptionRow(label: $0) }
            }
            return rows
        case .speed:
            return speeds.map { s in
                OptionRow(label: s == 1.0 ? "Normal" : String(format: "%gx", s), isSelected: abs(speed - s) < 0.01) {
                    speed = s; model.controller?.setSpeed(s)
                }
            }
        case .anime:
            if usesVLC {
                return [
                    OptionRow(label: "Anime4K needs MPV", detail: "VLC cannot run GLSL shaders", isHeader: true),
                    OptionRow(label: "Use MPV next playback", isSelected: false) { playerEngine = "mpv" },
                ]
            }
            if !animeAvailable {
                return [OptionRow(label: "Anime4K shaders are missing", isHeader: true)]
            }
            var rows = [OptionRow(label: "Off", isSelected: !animeActive) {
                animeActive = false
                model.controller?.setAnime4K(false)
            }]
            rows += HarborSettings.animeModes.map { choice in
                OptionRow(label: choice.label, detail: choice.detail,
                          isSelected: animeActive && anime4KMode == choice.id) {
                    anime4KMode = choice.id
                    animeActive = true
                    model.controller?.setAnime4K(true)
                }
            }
            return rows
        }
    }

    private func groupedTrackRows(_ tracks: [MPVTrack], selectedID: Int?, select: @escaping (Int) -> Void) -> [OptionRow] {
        let groups = Dictionary(grouping: tracks) { $0.lang.isEmpty ? "und" : $0.lang.lowercased() }
        var rows: [OptionRow] = []
        for code in groups.keys.sorted(by: { langName($0) < langName($1) }) {
            let ts = groups[code]!
            if ts.count == 1 {
                let t = ts[0]
                let base = t.title.isEmpty ? "Track \(t.id)" : t.title
                rows.append(OptionRow(label: "\(base)  ·  [\(langName(code))]",
                                      isSelected: selectedID == t.id) { select(t.id) })
            } else {
                rows.append(OptionRow(label: langName(code), isHeader: true))
                for (i, t) in ts.enumerated() {
                    let base = t.title.isEmpty ? "Track \(i + 1)" : t.title
                    rows.append(OptionRow(label: base, isSelected: selectedID == t.id) { select(t.id) })
                }
            }
        }
        return rows
    }

    private func langName(_ code: String) -> String {
        let c = code.lowercased()
        if c.isEmpty || c == "und" { return "Unknown" }
        return Locale.current.localizedString(forLanguageCode: c)?.capitalized ?? code.uppercased()
    }

    private var panelTitle: String {
        switch panelKind {
        case .audio: return "Audio"
        case .subtitles: return "Subtitles"
        case .subtitleSettings: return "Subtitle Settings"
        case .aspect: return "Aspect Ratio"
        case .speed: return "Playback Speed"
        case .anime: return "Anime4K"
        case .debug: return "Debug"
        }
    }

    private var optionsPanel: some View {
        let rows = optionRows
        let wide = panelKind == .subtitleSettings || panelKind == .debug
        return VStack {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text(panelTitle)
                        .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 10)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                    if row.isHeader {
                                        Text(row.label.uppercased())
                                            .font(.system(size: 15, weight: .bold)).tracking(1.2)
                                            .foregroundStyle(.white.opacity(0.48))
                                            .padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 3)
                                            .id(i)
                                    } else {
                                        let focused = i == optionRow
                                        HStack(spacing: 14) {
                                            if row.isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .frame(width: 24)
                                            } else {
                                                Color.clear.frame(width: 24, height: 1)
                                            }
                                            Text(row.label).lineLimit(wide ? 2 : 1)
                                            Spacer(minLength: 12)
                                            if !row.isSelected, !row.detail.isEmpty {
                                                Text(row.detail).lineLimit(1)
                                                    .foregroundStyle(focused ? .black.opacity(0.64) : .white.opacity(0.58))
                                            }
                                        }
                                        .font(.system(size: 22, weight: focused ? .semibold : .medium))
                                        .foregroundStyle(focused ? .black : .white)
                                        .padding(.horizontal, 18).padding(.vertical, 11)
                                        .background(focused ? Color.white.opacity(0.94) : Color.clear)
                                        .clipShape(Capsule(style: .continuous))
                                        .scaleEffect(focused ? 1.012 : 1)
                                        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: optionRow)
                                        .id(i)
                                    }
                                }
                            }
                            .padding(.horizontal, 18).padding(.bottom, 20)
                        }
                        .onChange(of: optionRow) { _ in
                            withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(optionRow, anchor: .center) }
                        }
                    }
                }
                .frame(width: wide ? 690 : 540)
                .frame(height: wide ? 720 : min(600, CGFloat(max(2, rows.count)) * 61 + 82))
                .harborGlass(cornerRadius: 34, tint: Color.black.opacity(0.20))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.26), lineWidth: 1.2)
                }
                .shadow(color: .black.opacity(0.58), radius: 34, y: 18)
                .padding(.trailing, 68)
            }
            .padding(.bottom, wide ? 44 : 220)
        }
        .ignoresSafeArea()
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
    }

    private func moveOption(_ d: Int) {
        let rows = optionRows
        let selectable = rows.indices.filter { !rows[$0].isHeader }
        guard !selectable.isEmpty else { return }
        let cur = selectable.firstIndex(of: optionRow) ?? 0
        optionRow = selectable[max(0, min(selectable.count - 1, cur + d))]
    }
    private func activateOption() {
        let rows = optionRows
        guard optionRow >= 0, optionRow < rows.count, !rows[optionRow].isHeader else { return }
        let previousPanel = panelKind
        rows[optionRow].action()
        // A normal choice is committed immediately and the popup disappears,
        // matching native tvOS menus. Rows that intentionally open a deeper
        // panel change `panelKind` and therefore remain on screen.
        if panelKind == previousPanel { closePanel() }
    }
    private func openPanel(_ kind: PanelKind) {
        panelKind = kind
        refreshTracks()
        hideTask?.cancel()
        let rows = optionRows
        optionRow = rows.firstIndex { $0.isSelected } ?? rows.firstIndex { !$0.isHeader } ?? 0
        withAnimation { showOptions = true }
    }
    private func closePanel() {
        withAnimation { showOptions = false }
        showInfo = true; selected = .play; scheduleHide()
    }

    private func setAudio(_ id: Int) {
        selectedAudioTrackID = id
        pendingAudioTrackID = id
        audioRecoveryStage = 0
        lastAudioRecovery = .distantPast
        model.controller?.setAudioTrack(id)
        refreshTracksSoon()
    }
    private func setSub(_ id: Int) {
        selectedSubtitleTrackID = id
        model.controller?.setSubtitleTrack(id)
        refreshTracksSoon()
    }

    private func refreshTracks() {
        let freshAudio = model.controller?.tracks(ofType: "audio") ?? []
        let freshSubtitles = model.controller?.tracks(ofType: "sub") ?? []
        audioTracks = freshAudio
        subtitleTracks = freshSubtitles
        let actualAudio = freshAudio.first(where: \.selected)?.id
        if let pendingAudioTrackID {
            selectedAudioTrackID = pendingAudioTrackID
            if actualAudio == pendingAudioTrackID { self.pendingAudioTrackID = nil }
        } else {
            selectedAudioTrackID = actualAudio
        }
        selectedSubtitleTrackID = freshSubtitles.first(where: \.selected)?.id ?? -1
        let s = model.controller?.mediaSummary()
        videoHeight = s?.height ?? 0; audioCodec = s?.audioCodec ?? ""; audioOut = s?.audioOut ?? ""
    }
    private func refreshTracksSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { refreshTracks() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { refreshTracks() }
    }

    private func monitorAudioOutput() {
        let now = Date()
        guard now.timeIntervalSince(lastMediaRefresh) >= 0.8 else { return }
        lastMediaRefresh = now
        let summary = model.controller?.mediaSummary()
        videoHeight = summary?.height ?? videoHeight
        audioCodec = summary?.audioCodec ?? audioCodec
        audioOut = summary?.audioOut ?? ""
        if !audioOut.isEmpty {
            audioRecoveryStage = 0
            return
        }
        guard now.timeIntervalSince(readyAt) >= 2,
              !audioTracks.isEmpty,
              audioRecoveryStage < 2,
              now.timeIntervalSince(lastAudioRecovery) >= 2.5 else { return }
        lastAudioRecovery = now
        model.controller?.recoverAudioOutput(forceStereo: audioRecoveryStage == 1)
        audioRecoveryStage += 1
        refreshTracksSoon()
    }

    private func applySubtitleStyleSoon() {
        DispatchQueue.main.async { model.controller?.applySubtitleStyle() }
    }

    private func resetSubtitleAppearance() {
        subStyle = SubtitleStyle.defaultStyle
        subAssOverride = "no"
        subBoxOpacity = 0.6
        subBorderSize = 2
        subFont = "inter"
        subBold = false
        subFontSize = SubtitleStyle.defaultFontSize
        subOpacity = 1
        subMargin = 12
        subAlignment = "center"
        subLineSpacing = 0
        subFontColor = SubtitleStyle.defaultFontColor
        subBorderColor = SubtitleStyle.defaultBorderColor
        subBoxColor = SubtitleStyle.defaultBoxColor
    }

    /// Once the file is playing, apply default speed + preferred audio/subtitle language once
    /// (tracks aren't known until decode starts).
    private func maybeAutoSelectTracks() {
        guard model.ready, !appliedAutoTracks else { return }
        if Date().timeIntervalSince(lastTrackRefresh) < 0.5 { return }
        lastTrackRefresh = Date()
        refreshTracks()
        guard !(audioTracks.isEmpty && subtitleTracks.isEmpty) else { return }
        appliedAutoTracks = true

        // Default playback speed.
        if abs(defaultSpeed - 1.0) > 0.01 { speed = defaultSpeed; model.controller?.setSpeed(defaultSpeed) }

        // Preferred audio language.
        if !prefAudioLang.isEmpty, let a = audioTracks.first(where: { $0.lang.lowercased().hasPrefix(prefAudioLang) }) {
            setAudio(a.id)
        }
        // Subtitles: off by default, or preferred language.
        if subsOffByDefault {
            setSub(-1)
        } else {
            let primary = subtitleTracks.filter { prefSubLang.isEmpty || $0.lang.lowercased().hasPrefix(prefSubLang) }
            let secondary = subtitleTracks.filter { !secondarySubLang.isEmpty && $0.lang.lowercased().hasPrefix(secondarySubLang) }
            let ordered = primary + secondary
            let forced = preferForcedSubs ? ordered.first(where: {
                $0.title.localizedCaseInsensitiveContains("forced")
                    || $0.title.localizedCaseInsensitiveContains("signs")
            }) : nil
            let embedded = preferEmbedded ? ordered.first(where: { !$0.external }) : nil
            if let track = forced ?? embedded ?? ordered.first { setSub(track.id) }
        }
        refreshTracksSoon()
    }

    // MARK: - Playback helpers

    private func toggle() { model.controller?.togglePause(); showControls() }
    private func seek(_ delta: Double) { model.controller?.seekRelative(delta); flashControls() }
    private func restart() {
        commitScrubIfNeeded()
        model.controller?.seekAbsolute(0)
        model.position = 0
        flashControls()
    }

    private func playNextNow() {
        guard let next = target.onEnded else { return }
        handledEnd = true
        target.onProgress?(model.position, model.duration)
        dismiss()
        next()
    }

    // MARK: - Intro / recap / credits skipping

    private func loadIntroSkipIfNeeded() {
        guard !introSkipLoaded, model.duration > 0 else { return }
        introSkipLoaded = true
        let chapters = model.controller?.chapters() ?? []
        let contentID = target.contentID
        let season = target.season
        let episode = target.episode
        let duration = model.duration
        let isAnime = target.isAnime
        Task {
            let segments = await IntroSkipService.segments(
                contentID: contentID, season: season, episode: episode,
                duration: duration, isAnime: isAnime, chapters: chapters)
            await MainActor.run {
                skipSegments = segments
                updateActiveSkip(at: model.position)
            }
        }
    }

    private func updateActiveSkip(at position: Double) {
        let segment = skipSegments.first {
            position >= $0.start && position < $0.end - 0.75
        }
        guard let segment else {
            if activeSkip != nil {
                activeSkip = nil
                skipButtonVisible = false
                skipHideTask?.cancel()
            }
            return
        }

        if shouldAutoSkip(segment), !autoSkippedSegments.contains(segment.id) {
            autoSkippedSegments.insert(segment.id)
            activeSkip = nil
            skipButtonVisible = false
            model.controller?.seekAbsolute(segment.end)
            model.position = segment.end
            flashControls()
            return
        }

        guard activeSkip?.id != segment.id else { return }
        activeSkip = segment
        skipButtonVisible = showSkipButton
        skipHideTask?.cancel()
        guard skipButtonHideSec > 0 else { return }
        skipHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(skipButtonHideSec) * 1_000_000_000)
            guard !Task.isCancelled, activeSkip?.id == segment.id else { return }
            withAnimation { skipButtonVisible = false }
        }
    }

    private func shouldAutoSkip(_ segment: SkipSegment) -> Bool {
        switch segment.kind {
        case .intro: return autoSkipIntro
        case .recap: return autoSkipRecap
        case .outro: return autoSkipOutro
        }
    }

    private func performSkip() {
        guard let segment = activeSkip else { return }
        autoSkippedSegments.insert(segment.id)
        model.controller?.seekAbsolute(segment.end)
        model.position = segment.end
        activeSkip = nil
        skipButtonVisible = false
        skipHideTask?.cancel()
        flashControls()
    }

    // MARK: - Scrub-to-seek

    private func scrubBy(_ dir: Int) {
        guard model.duration > 0 else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if !scrubbing {
            scrubbing = true; scrubTarget = model.position; scrubStep = 10
        } else if now - lastScrubAt < 0.4 {
            scrubStep = min(scrubStep * 1.6, 120)
        } else {
            scrubStep = 10
        }
        lastScrubAt = now
        scrubTarget = min(model.duration, max(0, scrubTarget + Double(dir) * scrubStep))
        flashControls()
        scheduleScrubCommit()
    }
    private func scheduleScrubCommit() {
        scrubCommit?.cancel()
        scrubCommit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, scrubbing else { return }
            commitScrub()
        }
    }
    private func commitScrub() {
        scrubCommit?.cancel()
        guard scrubbing else { return }
        scrubbing = false
        model.controller?.seekAbsolute(scrubTarget)
        model.position = scrubTarget
        flashControls()
    }
    private func commitScrubIfNeeded() { if scrubbing { commitScrub() } }
    private func cancelScrub() { scrubCommit?.cancel(); scrubbing = false; flashControls() }

    private func showControls() {
        let wasHidden = controlsHidden
        withAnimation { showInfo = true }
        if wasHidden { selected = .play }
        scheduleHide()
    }
    private func flashControls() {
        withAnimation { showInfo = true }
        scheduleHide()
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsHideSeconds > 0 else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(controlsHideSeconds) * 1_000_000_000)
            guard !Task.isCancelled, !showOptions else { return }
            withAnimation { showInfo = false }
        }
    }

    private func requestDismiss() {
        if confirmLeave && model.ready && model.position > 5 && !model.ended {
            hideTask?.cancel()
            confirmingLeave = true
        } else {
            dismiss()
        }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

private extension View {
    @ViewBuilder
    func harborGlass(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(tvOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - UIKit remote catcher

/// A focusable UIView that captures every Siri-remote press and forwards it to SwiftUI. Far more
/// reliable than SwiftUI `@FocusState` + `onMoveCommand` inside a full-screen cover on tvOS.
private struct RemoteCatcher: UIViewControllerRepresentable {
    var onPress: (UIPress.PressType) -> Void
    var onSwipe: () -> Void

    func makeUIViewController(context: Context) -> CatchVC {
        let vc = CatchVC(); vc.onPress = onPress; vc.onSwipe = onSwipe; return vc
    }
    func updateUIViewController(_ vc: CatchVC, context: Context) { vc.onPress = onPress; vc.onSwipe = onSwipe }

    final class FocusableView: UIView {
        override var canBecomeFocused: Bool { true }
    }

    final class CatchVC: UIViewController {
        var onPress: ((UIPress.PressType) -> Void)?
        var onSwipe: (() -> Void)?

        override func loadView() { view = FocusableView() }

        override var preferredFocusEnvironments: [UIFocusEnvironment] {
            isViewLoaded ? [view] : super.preferredFocusEnvironments
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSurfaceTouch))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            view.addGestureRecognizer(pan)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setNeedsFocusUpdate(); updateFocusIfNeeded()
        }

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            if isViewLoaded, view.window != nil, context.nextFocusedItem !== view { return false }
            return super.shouldUpdateFocus(in: context)
        }

        @objc private func handleSurfaceTouch(_ g: UIPanGestureRecognizer) {
            if g.state == .began { onSwipe?() }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                switch press.type {
                case .select, .playPause:
                    onPress?(press.type); handled = true
                case .menu:
                    // The window-level RemoteMenuCatcher performs the action;
                    // consume this responder event so UIKit cannot dismiss too.
                    handled = true
                case .upArrow, .downArrow, .leftArrow, .rightArrow:
                    onPress?(press.type); handled = true
                default: break
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = Set(presses.filter { !captures($0.type) })
            if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = Set(presses.filter { !captures($0.type) })
            if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
        }

        private func captures(_ type: UIPress.PressType) -> Bool {
            switch type {
            case .select, .menu, .playPause, .upArrow, .downArrow, .leftArrow, .rightArrow: return true
            default: return false
            }
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if isViewLoaded, view.window != nil, (context.nextFocusedItem as? UIView) !== view {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isViewLoaded, self.view.window != nil, !self.view.isFocused else { return }
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }
        }
    }
}

/// Captures Menu/Back at window level. This prevents UIKit's presentation
/// dismissal from racing the player's own one-level-at-a-time back handling.
private struct RemoteMenuCatcher: UIViewRepresentable {
    let onMenu: () -> Void

    func makeUIView(context: Context) -> MenuHostView {
        let view = MenuHostView()
        view.onMenu = onMenu
        return view
    }

    func updateUIView(_ view: MenuHostView, context: Context) { view.onMenu = onMenu }
    static func dismantleUIView(_ view: MenuHostView, coordinator: ()) { view.removeRecognizer() }
}

private final class MenuHostView: UIView, UIGestureRecognizerDelegate {
    var onMenu: () -> Void = {}
    private var recognizer: UITapGestureRecognizer?
    private weak var attachedWindow: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        removeRecognizer()
        guard let window else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMenu))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        tap.delegate = self
        window.addGestureRecognizer(tap)
        recognizer = tap
        attachedWindow = window
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func removeRecognizer() {
        if let recognizer, let attachedWindow { attachedWindow.removeGestureRecognizer(recognizer) }
        recognizer = nil
        attachedWindow = nil
    }

    @objc private func handleMenu() { onMenu() }
}
