import SwiftUI
import UIKit

struct PlayerTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

/// Full-screen libmpv player for tvOS. ALL remote input is handled at the UIKit level by a focusable
/// `RemoteCatcher` (pressesBegan) — SwiftUI `@FocusState` + command modifiers are unreliable inside a
/// full-screen cover on tvOS (that was the "control bar shows only sporadically" bug). The bar and the
/// options panel are driven by plain state, no SwiftUI focus.
struct PlayerView: View {
    let target: PlayerTarget
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()

    private let accent = Color.green

    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showOptions = false
    @State private var panelKind: PanelKind = .audio
    @State private var optionRow = 0
    @State private var audioTracks: [MPVTrack] = []
    @State private var subtitleTracks: [MPVTrack] = []
    @State private var videoHeight = 0
    @State private var audioCodec = ""
    @State private var audioOut = ""
    @State private var appliedAutoTracks = false
    @State private var lastTrackRefresh = Date.distantPast

    // Scrub-to-seek
    @State private var scrubbing = false
    @State private var scrubTarget = 0.0
    @State private var scrubStep = 10.0
    @State private var lastScrubAt = 0.0
    @State private var scrubCommit: Task<Void, Never>?

    @AppStorage(SubtitleStyle.Key.size) private var subSize = SubtitleStyle.defaultSize
    @AppStorage(SubtitleStyle.Key.color) private var subColor = SubtitleStyle.defaultColor
    @AppStorage(SubtitleStyle.Key.style) private var subStyle = SubtitleStyle.defaultStyle
    @AppStorage(SubtitleStyle.Key.bold) private var subBold = false
    @AppStorage(SubtitleStyle.Key.subLang) private var prefSubLang = ""
    @AppStorage(SubtitleStyle.Key.audioLang) private var prefAudioLang = ""
    @AppStorage(SubtitleStyle.Key.subsOff) private var subsOffByDefault = false
    @AppStorage(SubtitleStyle.Key.defaultSpeed) private var defaultSpeed = 1.0
    @AppStorage(SubtitleStyle.Key.seekStep) private var seekStep = 10

    private enum Control: Hashable { case scrub, restart, back, play, fwd, audio, subs, aspect, speed }
    private enum PanelKind { case audio, subtitles, subtitleSettings, aspect, speed, debug }
    @State private var selected: Control = .play
    @State private var lastButton: Control = .play
    @State private var speed: Double = 1.0

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var controlsHidden: Bool { !showInfo && !showOptions }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            MPVPlayerView(url: target.url, model: model)
                .ignoresSafeArea()

            // UIKit owns ALL remote input.
            RemoteCatcher(onPress: { handlePress($0) }, onSwipe: { showControls() })

            if !model.ready {
                ProgressView().controlSize(.large).tint(accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showInfo && !showOptions { controlBar }
            if showOptions { optionsPanel }
        }
        .onReceive(model.$ready) { if $0 { refreshTracksSoon() } }
        .onReceive(model.$position) { _ in maybeAutoSelectTracks() }
        .onAppear {
            showInfo = true; selected = .play; scheduleHide()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            hideTask?.cancel(); scrubCommit?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Remote handling

    private func handlePress(_ type: UIPress.PressType) {
        if showOptions {
            switch type {
            case .menu:
                switch panelKind {
                case .subtitleSettings: openPanel(.subtitles)
                case .debug: openPanel(.aspect)
                default: closePanel()
                }
            case .upArrow: moveOption(-1)
            case .downArrow: moveOption(1)
            case .select: activateOption()
            default: break
            }
            return
        }
        if controlsHidden {
            switch type {
            case .menu: dismiss()
            case .playPause: toggle()
            default: showControls()
            }
            return
        }
        // Bar shown: 2D navigation.
        switch type {
        case .menu:
            if scrubbing { cancelScrub() } else { dismiss() }
        case .playPause: toggle()
        case .select: activate(selected)
        case .leftArrow: horizontal(-1)
        case .rightArrow: horizontal(1)
        case .upArrow: vertical(-1)
        case .downArrow: vertical(1)
        default: break
        }
    }

    private var buttonRow: [Control] {
        var c: [Control] = [.restart, .back, .play, .fwd]
        if !audioTracks.isEmpty { c.append(.audio) }
        c.append(.subs)
        c.append(.aspect)
        c.append(.speed)
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

    /// Two rows only: scrubber ↔ buttons.
    private func vertical(_ d: Int) {
        commitScrubIfNeeded()
        switch selected {
        case .scrub: if d > 0 { selected = lastButton }
        default: if d < 0 { selected = .scrub }
        }
        flashControls()
    }

    private func activate(_ c: Control) {
        switch c {
        case .scrub:   scrubbing ? commitScrub() : toggle()
        case .restart: restart()
        case .back:    seek(-Double(seekStep))
        case .fwd:     seek(Double(seekStep))
        case .play:    toggle()
        case .audio:   openPanel(.audio)
        case .subs:    openPanel(.subtitles)
        case .aspect:  openPanel(.aspect)
        case .speed:   openPanel(.speed)
        }
    }

    // MARK: - Control bar

    private var metadataLine: String {
        var parts: [String] = []
        switch videoHeight {
        case 2000...:     parts.append("4K")
        case 1300..<2000: parts.append("1440p")
        case 900..<1300:  parts.append("1080p")
        case 600..<900:   parts.append("720p")
        case 1..<600:     parts.append("\(videoHeight)p")
        default:          break
        }
        if !audioCodec.isEmpty { parts.append(audioCodec.uppercased()) }
        if abs(speed - 1.0) > 0.01 { parts.append(String(format: "%gx", speed)) }
        // Audio-output diagnostic: which driver is actually producing sound ("AO —" = none).
        parts.append(audioOut.isEmpty ? "AO —" : "AO \(audioOut)")
        return parts.joined(separator: "  ·  ")
    }

    /// Harbor-style bar: ONE block hugging the bottom edge — title + info line,
    /// then the scrubber, then the transport row (left cluster) and the
    /// track/format buttons (right cluster).
    private var controlBar: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    if !target.title.isEmpty {
                        Text(target.title).font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                    }
                    if !metadataLine.isEmpty {
                        Text(metadataLine).font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 16) {
                    Text(timeString(scrubbing ? scrubTarget : model.position)).font(.callout.monospacedDigit())
                        .foregroundStyle(scrubbing ? accent : .white)
                    scrubber
                    Text(timeString(model.duration)).font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                }
                HStack {
                    HStack(spacing: 18) {
                        ctrlButton(.restart, "arrow.counterclockwise")
                        ctrlButton(.back, "gobackward.\(seekStep)")
                        ctrlButton(.play, model.paused ? "play.fill" : "pause.fill", big: true)
                        ctrlButton(.fwd, "goforward.\(seekStep)")
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        if !audioTracks.isEmpty { ctrlButton(.audio, "waveform") }
                        ctrlButton(.subs, "captions.bubble")
                        ctrlButton(.speed, "speedometer")
                        ctrlButton(.aspect, "aspectratio")
                    }
                }
            }
            .padding(.horizontal, 70)
            .padding(.top, 60)
            .padding(.bottom, 36)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.92)],
                               startPoint: .top, endPoint: .bottom)
            )
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
            let barH: CGFloat = focused ? 10 : 6
            let knob: CGFloat = focused ? 28 : 18
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: barH)
                Capsule().fill(accent).frame(width: max(0, w * frac), height: barH)
                Circle().fill(accent).frame(width: knob, height: knob)
                    .offset(x: max(0, w * frac - knob / 2))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.12), value: frac)
        }
        .frame(height: 28)
    }

    private func ctrlButton(_ c: Control, _ icon: String, big: Bool = false) -> some View {
        let sel = (selected == c)
        let d: CGFloat = big ? 92 : 64
        return Image(systemName: icon)
            .font(.system(size: big ? 38 : 26, weight: .semibold))
            .foregroundStyle(sel ? .black : .white)
            .frame(width: d, height: d)
            .background(Circle().fill(sel ? accent : Color.white.opacity(0.12)))
            .scaleEffect(sel ? 1.12 : 1.0)
            .animation(.easeOut(duration: 0.18), value: sel)
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
            return groupedTrackRows(audioTracks) { setAudio($0) }
        case .subtitles:
            var rows = [OptionRow(label: "Off", isSelected: subtitleTracks.allSatisfy { !$0.selected }) {
                model.controller?.setSubtitleTrack(-1); refreshTracksSoon()
            }]
            rows += groupedTrackRows(subtitleTracks) { setSub($0) }
            rows.append(OptionRow(label: "Subtitle Settings", detail: "›") { openPanel(.subtitleSettings) })
            return rows
        case .subtitleSettings:
            var rows: [OptionRow] = [OptionRow(label: "Size", isHeader: true)]
            for s in SubtitleStyle.sizes { rows.append(OptionRow(label: s.label, isSelected: subSize == s.id) { subSize = s.id; model.controller?.applySubtitleStyle() }) }
            rows.append(OptionRow(label: "Colour", isHeader: true))
            for c in SubtitleStyle.colors { rows.append(OptionRow(label: c.label, isSelected: subColor == c.id) { subColor = c.id; model.controller?.applySubtitleStyle() }) }
            rows.append(OptionRow(label: "Style", isHeader: true))
            for s in SubtitleStyle.styles { rows.append(OptionRow(label: s.label, isSelected: subStyle == s.id) { subStyle = s.id; model.controller?.applySubtitleStyle() }) }
            rows.append(OptionRow(label: "Bold", detail: subBold ? "On" : "Off", isSelected: subBold) { subBold.toggle(); model.controller?.applySubtitleStyle() })
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
        }
    }

    private func groupedTrackRows(_ tracks: [MPVTrack], select: @escaping (Int) -> Void) -> [OptionRow] {
        let groups = Dictionary(grouping: tracks) { $0.lang.isEmpty ? "und" : $0.lang.lowercased() }
        var rows: [OptionRow] = []
        for code in groups.keys.sorted(by: { langName($0) < langName($1) }) {
            let ts = groups[code]!
            if ts.count == 1 {
                let t = ts[0]
                rows.append(OptionRow(label: langName(code), detail: t.title, isSelected: t.selected) { select(t.id) })
            } else {
                rows.append(OptionRow(label: langName(code), isHeader: true))
                for (i, t) in ts.enumerated() {
                    rows.append(OptionRow(label: t.title.isEmpty ? "Track \(i + 1)" : t.title, isSelected: t.selected) { select(t.id) })
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
        case .debug: return "Debug"
        }
    }

    private var optionsPanel: some View {
        let rows = optionRows
        return HStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text(panelTitle)
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                if row.isHeader {
                                    Text(row.label.uppercased())
                                        .font(.system(size: 18, weight: .semibold)).tracking(1)
                                        .foregroundStyle(.white.opacity(0.45))
                                        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 2)
                                        .id(i)
                                } else {
                                    HStack {
                                        Text(row.label).lineLimit(1)
                                            .foregroundStyle(i == optionRow ? .black : .white)
                                        Spacer()
                                        if row.isSelected {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(i == optionRow ? .black : accent)
                                        } else if !row.detail.isEmpty {
                                            Text(row.detail)
                                                .foregroundStyle(i == optionRow ? .black.opacity(0.85) : .white.opacity(0.6))
                                        }
                                    }
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(i == optionRow ? accent : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .id(i)
                                }
                            }
                        }
                        .padding(24)
                    }
                    .onChange(of: optionRow) { _ in withAnimation { proxy.scrollTo(optionRow, anchor: .center) } }
                }
            }
            .frame(width: 760)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.08).opacity(0.98))
        }
        .ignoresSafeArea()
        .transition(.move(edge: .trailing))
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
        rows[optionRow].action()
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

    private func setAudio(_ id: Int) { model.controller?.setAudioTrack(id); refreshTracksSoon() }
    private func setSub(_ id: Int) { model.controller?.setSubtitleTrack(id); refreshTracksSoon() }

    private func refreshTracks() {
        audioTracks = model.controller?.tracks(ofType: "audio") ?? []
        subtitleTracks = model.controller?.tracks(ofType: "sub") ?? []
        let s = model.controller?.mediaSummary()
        videoHeight = s?.height ?? 0; audioCodec = s?.audioCodec ?? ""; audioOut = s?.audioOut ?? ""
    }
    private func refreshTracksSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { refreshTracks() }
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
            model.controller?.setAudioTrack(a.id)
        }
        // Subtitles: off by default, or preferred language.
        if subsOffByDefault {
            model.controller?.setSubtitleTrack(-1)
        } else if !prefSubLang.isEmpty, let s = subtitleTracks.first(where: { $0.lang.lowercased().hasPrefix(prefSubLang) }) {
            model.controller?.setSubtitleTrack(s.id)
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
        withAnimation { showInfo = true }
        if controlsHidden { selected = .play }
        scheduleHide()
    }
    private func flashControls() {
        withAnimation { showInfo = true }
        scheduleHide()
    }
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, !showOptions else { return }
            withAnimation { showInfo = false }
        }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
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

        private var repeatTimer: Timer?
        private var repeatType: UIPress.PressType?
        private var repeatCount = 0

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                switch press.type {
                case .select, .menu, .playPause:
                    onPress?(press.type); handled = true
                case .upArrow, .downArrow, .leftArrow, .rightArrow:
                    onPress?(press.type); handled = true
                    startRepeat(press.type)
                default: break
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stopRepeat(); super.pressesEnded(presses, with: event)
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stopRepeat(); super.pressesCancelled(presses, with: event)
        }

        private func startRepeat(_ type: UIPress.PressType) {
            stopRepeat()
            repeatType = type; repeatCount = 0
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] t in
                guard let self, let type = self.repeatType else { t.invalidate(); return }
                self.repeatCount += 1
                if self.repeatCount > 120 { self.stopRepeat(); return }
                self.onPress?(type)
            }
            timer.fireDate = Date().addingTimeInterval(0.45)
            RunLoop.main.add(timer, forMode: .common)
            repeatTimer = timer
        }
        private func stopRepeat() { repeatTimer?.invalidate(); repeatTimer = nil; repeatType = nil }

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
