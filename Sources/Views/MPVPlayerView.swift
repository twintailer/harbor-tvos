import SwiftUI
import Libmpv
import AVFoundation
import os

// libmpv-backed player for tvOS. AVPlayer can't decode MKV / most Stremio
// containers; mpv plays everything. Mirrors the hard-won iOS settings
// (hwdec, moltenvk). The control bar is drawn by SwiftUI, but ALL remote
// input is captured by a UIKit RemoteCatcher in PlayerView.
struct MPVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let model: PlayerModel
    var startAt: Double = 0
    var anime4K: Bool = false
    var requestHeaders: [String: String] = [:]

    func makeUIViewController(context: Context) -> MPVViewController {
        let vc = MPVViewController(url: url, model: model, startAt: startAt,
                                   anime4K: anime4K, requestHeaders: requestHeaders)
        model.controller = vc
        return vc
    }
    func updateUIViewController(_ vc: MPVViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: MPVViewController, coordinator: ()) {
        vc.shutdown()
    }
}

// One audio / subtitle / video track from mpv's track-list.
struct MPVTrack: Identifiable, Hashable {
    let id: Int
    let type: String
    let title: String
    let lang: String
    let selected: Bool
    let external: Bool
}

final class MPVViewController: UIViewController {
    private var mpv: OpaquePointer?
    private let url: URL
    private weak var model: PlayerModel?
    private let startAt: Double
    private let requestHeaders: [String: String]
    private(set) var anime4KActive: Bool
    private var metalLayer: CAMetalLayer?
    private var poll: Timer?
    private let mpvQueue = DispatchQueue(label: "app.harbor.tvos.mpv")
    private let log = Logger(subsystem: "app.harbor.tvos", category: "mpv")

    init(url: URL, model: PlayerModel, startAt: Double, anime4K: Bool,
         requestHeaders: [String: String]) {
        self.url = url
        self.model = model
        self.startAt = startAt
        self.anime4KActive = anime4K
        self.requestHeaders = requestHeaders
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = CAMetalLayer()
        layer.frame = view.bounds
        layer.contentsScale = UIScreen.main.scale
        layer.framebufferOnly = true
        layer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(layer)
        metalLayer = layer

        // Activate the playback session BEFORE mpv probes its audio output — on the main
        // thread, so the driver init finds a ready session.
        activateAudioSession()

        // mpv is created + initialized ON THE MAIN THREAD (background-queue init rendered
        // video but produced no audio-unit output on Apple TV).
        setupMPV()

        poll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer?.frame = view.bounds
        metalLayer?.drawableSize = CGSize(
            width: view.bounds.width * UIScreen.main.scale,
            height: view.bounds.height * UIScreen.main.scale)
    }

    // MARK: mpv helpers
    private func setOpt(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_option_string(mpv, name, value)
    }
    private func command(_ args: [String]) {
        guard let mpv else { return }
        let owned = args.map { strdup($0) }
        defer { owned.forEach { free($0) } }
        var c = owned.map { UnsafePointer($0) }
        c.append(nil)
        c.withUnsafeMutableBufferPointer { _ = mpv_command(mpv, $0.baseAddress) }
    }
    private func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0 }
        var v = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &v)
        return v
    }
    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var v = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &v)
        return v != 0
    }
    private func getInt(_ name: String) -> Int {
        guard let mpv else { return 0 }
        var v = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &v)
        return Int(v)
    }
    private func getString(_ name: String) -> String? {
        guard let mpv else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }
    private func setString(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, name, value)
    }

    @discardableResult
    private func activateAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            return true
        } catch {
            log.error("AVAudioSession activation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func setupMPV() {
        guard let layer = metalLayer, let ctx = mpv_create() else { return }
        mpv = ctx
        // Tune the bundled mpv for the selected Apple TV quality profile.
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: SubtitleStyle.Key.mpvQuality) ?? "balanced" {
        case "quality":
            mpv_set_option_string(ctx, "profile", "gpu-hq")
            setOpt("scale", "ewa_lanczossharp")
            setOpt("cscale", "ewa_lanczossoft")
        case "performance":
            mpv_set_option_string(ctx, "profile", "fast")
            setOpt("scale", "bilinear")
            setOpt("cscale", "bilinear")
        default:
            mpv_set_option_string(ctx, "profile", "fast")
            setOpt("scale", "spline36")
            setOpt("cscale", "spline36")
        }
        // Keep audio-driver diagnostics visible on the Apple TV. MPVKit 1.0.0's
        // AVFoundation fallback is selected below specifically for tvOS HDMI routes.
        mpv_request_log_messages(ctx, "info")
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &wid)
        setOpt("vo", "gpu-next")
        setOpt("gpu-api", "vulkan")
        setOpt("gpu-context", "moltenvk")
        switch defaults.string(forKey: SubtitleStyle.Key.mpvHWDec) ?? "auto" {
        case "off": setOpt("hwdec", "no")
        default: setOpt("hwdec", "videotoolbox")
        }
        setOpt("video-rotate", "no")
        // MPVKit 1.0.0 enables mpv's AVSampleBufferAudioRenderer output on tvOS.
        // Prefer it because AudioUnit cannot query the channel layout of some tvOS 26
        // HDMI routes (notably the 32-channel route exposed by Apple TV 4K), which
        // leaves `current-ao` empty and produces no sound. Keep AudioUnit as a fallback
        // for older/simple routes rather than falling through to the null output.
        setOpt("ao", "avfoundation,audiounit")
        setOpt("audio-channels", defaults.bool(forKey: SubtitleStyle.Key.mpvDownmix) ? "stereo" : "auto-safe")
        setOpt("audio-exclusive", "no")
        // Subtitles: match OS language, auto-load, embedded fonts.
        setOpt("subs-match-os-language", "yes")
        setOpt("subs-fallback", "yes")
        setOpt("embeddedfonts", "yes")
        setOpt("sub-auto", "fuzzy")
        for (name, value) in SubtitleStyle.mpvOptions { setOpt(name, value) }
        applyVideoSize(setOpt)
        if startAt > 1 { setOpt("start", String(format: "%.3f", startAt)) }
        // Debrid/addon URLs prefer a browser UA; follow redirects; reconnect on drops.
        setOpt("user-agent",
               "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
        applyRequestHeaders()
        setOpt("network-timeout", "30")
        setOpt("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=7")
        applyAudioOptions(defaults)
        applyPictureOptions(defaults)
        if anime4KActive { applyAnime4K(setOpt) }
        setOpt("cache", "yes")
        if defaults.bool(forKey: SubtitleStyle.Key.mpvBufferBoost) {
            setOpt("demuxer-readahead-secs", "300")
            setOpt("demuxer-max-bytes", "512MiB")
            setOpt("demuxer-max-back-bytes", "64MiB")
        } else {
            setOpt("demuxer-readahead-secs", "90")
            setOpt("demuxer-max-bytes", "192MiB")
            setOpt("demuxer-max-back-bytes", "32MiB")
        }
        setOpt("keep-open", "yes")
        let initializeResult = mpv_initialize(ctx)
        guard initializeResult >= 0 else {
            let message = String(cString: mpv_error_string(initializeResult))
            log.error("mpv initialization failed: \(message, privacy: .public)")
            mpv = nil
            mpv_terminate_destroy(ctx)
            return
        }

        // Event loop: drain mpv's queue off-main. Captures warnings/errors (incl. audio-output
        // failures) into the unified log and keeps the queue from overflowing.
        mpv_set_wakeup_callback(ctx, { ctx in
            let me = unsafeBitCast(ctx, to: MPVViewController.self)
            me.drainEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        command(["loadfile", url.absoluteString])
    }

    private func drainEvents() {
        mpvQueue.async { [weak self] in
            guard let self else { return }
            // Capture the handle per iteration: destroy is serialized on this same queue, so a
            // non-nil handle read here stays valid for the duration of the block.
            while let handle = self.mpv {
                guard let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE else { break }
                switch event.pointee.event_id {
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        let prefix = String(cString: msg.pointee.prefix)
                        let text = String(cString: msg.pointee.text).trimmingCharacters(in: .newlines)
                        if !text.isEmpty {
                            self.log.warning("[\(prefix, privacy: .public)] \(text, privacy: .public)")
                            // Also surface in the in-player debug panel, so a problem on the
                            // Apple TV can be read (and screenshotted) without a Mac.
                            let line = "[\(prefix)] \(text)"
                            DispatchQueue.main.async { [weak self] in
                                guard let m = self?.model else { return }
                                m.logLines.append(line)
                                if m.logLines.count > 40 { m.logLines.removeFirst(m.logLines.count - 40) }
                            }
                        }
                    }
                case MPV_EVENT_END_FILE:
                    if let data = event.pointee.data {
                        let ef = UnsafePointer<mpv_event_end_file>(OpaquePointer(data)).pointee
                        if ef.reason == MPV_END_FILE_REASON_ERROR {
                            let msg = String(cString: mpv_error_string(ef.error))
                            self.log.error("end-file error: \(msg, privacy: .public)")
                        } else if ef.reason == MPV_END_FILE_REASON_EOF {
                            DispatchQueue.main.async { [weak self] in self?.model?.ended = true }
                        }
                    }
                default: break
                }
            }
        }
    }

    private func tick() {
        mpvQueue.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            let pos = self.getDouble("time-pos")
            let dur = self.getDouble("duration")
            let paused = self.getFlag("pause")
            DispatchQueue.main.async {
                guard let m = self.model else { return }
                if pos.isFinite { m.position = pos }
                if dur.isFinite, dur > 0 { m.duration = dur; m.ready = true }
                m.paused = paused
            }
        }
    }

    // MARK: control API (called from SwiftUI, hopped onto the mpv queue)
    func togglePause() { mpvQueue.async { [weak self] in self?.command(["cycle", "pause"]) } }
    func seekRelative(_ delta: Double) {
        mpvQueue.async { [weak self] in
            self?.command(["seek", String(format: "%.1f", delta), "relative"])
        }
    }
    func seekAbsolute(_ seconds: Double) {
        mpvQueue.async { [weak self] in
            self?.command(["seek", String(format: "%.2f", seconds), "absolute"])
        }
    }

    /// Read the current tracks of a type (audio / sub). mpv's property getters are thread-safe, so
    /// this reads directly on the caller (main) thread without a queue hop that could stall the UI.
    func tracks(ofType type: String) -> [MPVTrack] {
        guard mpv != nil else { return [] }
        let count = getInt("track-list/count")
        guard count > 0 else { return [] }
        var result: [MPVTrack] = []
        for i in 0..<count where (getString("track-list/\(i)/type") ?? "") == type {
            result.append(MPVTrack(
                id: getInt("track-list/\(i)/id"),
                type: type,
                title: getString("track-list/\(i)/title") ?? "",
                lang: getString("track-list/\(i)/lang") ?? "",
                selected: getFlag("track-list/\(i)/selected"),
                external: getFlag("track-list/\(i)/external")))
        }
        return result
    }

    func setAudioTrack(_ id: Int) {
        mpvQueue.async { [weak self] in self?.setString("aid", id < 0 ? "no" : String(id)) }
    }
    func setSubtitleTrack(_ id: Int) { mpvQueue.async { [weak self] in self?.setString("sid", id < 0 ? "no" : String(id)) } }
    func setSpeed(_ speed: Double) { mpvQueue.async { [weak self] in self?.setString("speed", String(format: "%.2f", speed)) } }
    func setSubDelay(_ s: Double) { mpvQueue.async { [weak self] in self?.setString("sub-delay", String(format: "%.2f", s)) } }
    func setAudioDelay(_ s: Double) { mpvQueue.async { [weak self] in self?.setString("audio-delay", String(format: "%.2f", s)) } }

    func setAnime4K(_ enabled: Bool) {
        anime4KActive = enabled
        mpvQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                let chain = Anime4KShaders.chain()
                self.setString("glsl-shaders", chain.map(\.path).joined(separator: ":"))
            } else {
                self.setString("glsl-shaders", "")
            }
        }
    }

    /// Media summary for the metadata line: encoded video height, active audio codec, and the
    /// audio-output driver actually in use ("" = audio failed to initialize — the key diagnostic
    /// for the no-sound reports).
    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String) {
        guard mpv != nil else { return (0, "", "") }
        return (getInt("video-params/h"),
                getString("audio-codec-name") ?? "",
                getString("current-ao") ?? "")
    }

    /// Named chapters exposed by mpv. They are also an offline source for Harbor's
    /// Skip Intro / Recap / Credits feature when AniSkip or TheIntroDB has no match.
    func chapters() -> [MediaChapter] {
        guard mpv != nil else { return [] }
        let count = getInt("chapter-list/count")
        guard count > 0 else { return [] }
        let duration = getDouble("duration")
        var values: [(String, Double)] = []
        for index in 0..<count {
            let title = getString("chapter-list/\(index)/title") ?? ""
            let start = getDouble("chapter-list/\(index)/time")
            values.append((title, max(0, start)))
        }
        return values.enumerated().map { index, value in
            let end = values.indices.contains(index + 1) ? values[index + 1].1 : duration
            return MediaChapter(title: value.0, start: value.1, end: max(value.1, end))
        }
    }

    /// Re-open the AudioUnit output after a late HDMI/session route. The second-stage stereo
    /// fallback handles receivers that advertise a surround layout they cannot actually accept.
    func recoverAudioOutput(forceStereo: Bool) {
        activateAudioSession()
        mpvQueue.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            if forceStereo { self.setString("audio-channels", "stereo") }
            self.command(["ao-reload"])
        }
    }

    private(set) var videoSizeMode = UserDefaults.standard.string(forKey: SubtitleStyle.Key.videoSize) ?? "original"

    func setVideoSize(_ mode: String) {
        videoSizeMode = mode
        UserDefaults.standard.set(mode, forKey: SubtitleStyle.Key.videoSize)
        mpvQueue.async { [weak self] in self?.applyVideoSize { self?.setString($0, $1) } }
    }
    private func applyVideoSize(_ set: (String, String) -> Void) {
        switch videoSizeMode {
        case "zoom", "fill": set("keepaspect", "yes"); set("panscan", "1.0")
        case "stretch":      set("keepaspect", "no");  set("panscan", "0.0")
        default:             set("keepaspect", "yes"); set("panscan", "0.0")
        }
    }

    private func applyAudioOptions(_ defaults: UserDefaults) {
        var filters: [String] = []
        if defaults.bool(forKey: SubtitleStyle.Key.audioNormalize) { filters.append("dynaudnorm") }
        switch defaults.string(forKey: SubtitleStyle.Key.audioProfile) ?? "off" {
        case "voice": filters.append("lavfi=[equalizer=f=3000:t=q:w=1:g=4]")
        case "night": filters.append("lavfi=[acompressor=threshold=-18dB:ratio=4:attack=20:release=250]")
        case "bass": filters.append("lavfi=[bass=g=5]")
        case "bass-reduce": filters.append("lavfi=[bass=g=-6]")
        default: break
        }
        if !filters.isEmpty { setOpt("af", filters.joined(separator: ",")) }
        if defaults.bool(forKey: SubtitleStyle.Key.mpvDownmix) { setOpt("audio-channels", "stereo") }
    }

    private func applyRequestHeaders() {
        var fields: [String] = []
        for (key, value) in requestHeaders {
            if key.caseInsensitiveCompare("User-Agent") == .orderedSame {
                setOpt("user-agent", value)
            } else {
                fields.append("\(key): \(value)")
            }
        }
        if !fields.isEmpty { setOpt("http-header-fields", fields.joined(separator: ",")) }
    }

    private func applyPictureOptions(_ defaults: UserDefaults) {
        for (key, option) in [
            (SubtitleStyle.Key.brightness, "brightness"),
            (SubtitleStyle.Key.contrast, "contrast"),
            (SubtitleStyle.Key.saturation, "saturation"),
            (SubtitleStyle.Key.gamma, "gamma"),
        ] {
            let value = defaults.double(forKey: key)
            if abs(value) > 0.01 { setOpt(option, String(format: "%.0f", value)) }
        }
        let toneMapping = defaults.string(forKey: SubtitleStyle.Key.toneMapping) ?? "auto"
        if toneMapping != "auto" { setOpt("tone-mapping", toneMapping) }
        setOpt("target-colorspace-hint", "yes")
        if defaults.bool(forKey: SubtitleStyle.Key.motionInterpolation) {
            setOpt("video-sync", "display-resample")
            setOpt("interpolation", "yes")
            setOpt("tscale", "oversample")
        }
    }

    private func applyAnime4K(_ set: (String, String) -> Void) {
        let chain = Anime4KShaders.chain()
        guard !chain.isEmpty else { anime4KActive = false; return }
        set("glsl-shaders", chain.map(\.path).joined(separator: ":"))
    }

    /// Re-apply subtitle appearance to a running player (after a settings change).
    func applySubtitleStyle() {
        mpvQueue.async { [weak self] in
            guard let self else { return }
            for (name, value) in SubtitleStyle.mpvOptions { self.setString(name, value) }
        }
    }

    func shutdown() {
        poll?.invalidate(); poll = nil
        guard let ctx = mpv else { return }
        // Clear the wakeup callback FIRST so it can't fire into a deallocated controller,
        // then wind the core down now (quit is thread-safe) and destroy off-main.
        mpv_set_wakeup_callback(ctx, nil, nil)
        mpv_command_string(ctx, "quit")
        mpv = nil
        mpvQueue.async {
            mpv_terminate_destroy(ctx)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private enum Anime4KShaders {
    static func chain() -> [URL] {
        let defaults = UserDefaults.standard
        let tier = defaults.string(forKey: SubtitleStyle.Key.anime4KTier) ?? "fast"
        let large = tier == "hq" ? "VL" : "M"
        let mode = defaults.string(forKey: SubtitleStyle.Key.anime4KMode) ?? "A"
        let clamp = "Anime4K_Clamp_Highlights.glsl"
        let down2 = "Anime4K_AutoDownscalePre_x2.glsl"
        let down4 = "Anime4K_AutoDownscalePre_x4.glsl"
        let upscaleMedium = "Anime4K_Upscale_CNN_x2_M.glsl"
        let restore = "Anime4K_Restore_CNN_\(large).glsl"
        let restoreSoft = "Anime4K_Restore_CNN_Soft_\(large).glsl"
        let upscale = "Anime4K_Upscale_CNN_x2_\(large).glsl"
        let denoise = "Anime4K_Upscale_Denoise_CNN_x2_\(large).glsl"
        let files: [String]
        switch mode {
        case "B": files = [clamp, restoreSoft, upscale, down2, down4, upscaleMedium]
        case "C": files = [clamp, denoise, down2, down4, upscaleMedium]
        case "A+A", "AA": files = [clamp, restore, upscale, "Anime4K_Restore_CNN_M.glsl", down2, down4, upscaleMedium]
        case "B+B", "BB": files = [clamp, restoreSoft, upscale, down2, "Anime4K_Restore_CNN_Soft_M.glsl", down4, upscaleMedium]
        case "C+A", "CA": files = [clamp, denoise, down2, down4, "Anime4K_Restore_CNN_M.glsl", upscaleMedium]
        default: files = [clamp, restore, upscale, down2, down4, upscaleMedium]
        }
        let urls = files.compactMap { filename in
            let name = filename.replacingOccurrences(of: ".glsl", with: "")
            return Bundle.main.url(forResource: name, withExtension: "glsl", subdirectory: "Anime4K")
                ?? Bundle.main.url(forResource: name, withExtension: "glsl")
        }
        return urls.count == files.count ? urls : []
    }
}
