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

    func makeUIViewController(context: Context) -> MPVViewController {
        let vc = MPVViewController(url: url, model: model)
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
}

final class MPVViewController: UIViewController {
    private var mpv: OpaquePointer?
    private let url: URL
    private weak var model: PlayerModel?
    private var metalLayer: CAMetalLayer?
    private var poll: Timer?
    private let mpvQueue = DispatchQueue(label: "app.harbor.tvos.mpv")
    private let log = Logger(subsystem: "app.harbor.tvos", category: "mpv")

    init(url: URL, model: PlayerModel) {
        self.url = url
        self.model = model
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
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

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

    private func setupMPV() {
        guard let layer = metalLayer, let ctx = mpv_create() else { return }
        mpv = ctx
        // "fast" baseline for constrained GPUs, then our explicit options.
        mpv_set_option_string(ctx, "profile", "fast")
        mpv_request_log_messages(ctx, "warn")   // surfaced via the event loop below
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &wid)
        setOpt("vo", "gpu-next")
        setOpt("gpu-api", "vulkan")
        setOpt("gpu-context", "moltenvk")
        setOpt("hwdec", "videotoolbox")
        setOpt("video-rotate", "no")
        // No `ao` override: with the MPVKit-GPL build the DEFAULT driver chain is the
        // proven-on-Apple-TV configuration (StremioX ships exactly this). Explicit lists
        // were only ever attempted against the non-GPL build, whose tvOS slice never
        // initialized any audio output at all.
        // Subtitles: match OS language, auto-load, embedded fonts.
        setOpt("subs-match-os-language", "yes")
        setOpt("subs-fallback", "yes")
        setOpt("embeddedfonts", "yes")
        setOpt("sub-auto", "fuzzy")
        for (name, value) in SubtitleStyle.mpvOptions { setOpt(name, value) }
        applyVideoSize(setOpt)
        // Debrid/addon URLs prefer a browser UA; follow redirects; reconnect on drops.
        setOpt("user-agent",
               "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
        setOpt("network-timeout", "30")
        setOpt("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=7")
        if UserDefaults.standard.bool(forKey: SubtitleStyle.Key.audioNormalize) {
            setOpt("af", "dynaudnorm")   // loudness normalization (quiet dialogue / loud action)
        }
        setOpt("cache", "yes")
        setOpt("demuxer-readahead-secs", "300")
        setOpt("demuxer-max-bytes", "512MiB")
        setOpt("demuxer-max-back-bytes", "64MiB")
        setOpt("keep-open", "yes")
        mpv_initialize(ctx)

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
                selected: getFlag("track-list/\(i)/selected")))
        }
        return result
    }

    func setAudioTrack(_ id: Int) { mpvQueue.async { [weak self] in self?.setString("aid", id < 0 ? "no" : String(id)) } }
    func setSubtitleTrack(_ id: Int) { mpvQueue.async { [weak self] in self?.setString("sid", id < 0 ? "no" : String(id)) } }
    func setSpeed(_ speed: Double) { mpvQueue.async { [weak self] in self?.setString("speed", String(format: "%.2f", speed)) } }
    func setSubDelay(_ s: Double) { mpvQueue.async { [weak self] in self?.setString("sub-delay", String(format: "%.2f", s)) } }
    func setAudioDelay(_ s: Double) { mpvQueue.async { [weak self] in self?.setString("audio-delay", String(format: "%.2f", s)) } }

    /// Media summary for the metadata line: encoded video height, active audio codec, and the
    /// audio-output driver actually in use ("" = audio failed to initialize — the key diagnostic
    /// for the no-sound reports).
    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String) {
        guard mpv != nil else { return (0, "", "") }
        return (getInt("video-params/h"),
                getString("audio-codec-name") ?? "",
                getString("current-ao") ?? "")
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
