import SwiftUI
import AVFoundation
import Libmpv

// libmpv-backed player for tvOS. AVPlayer can't decode MKV / most Stremio
// containers; mpv plays everything. Mirrors the hard-won iOS settings
// (hwdec=videotoolbox-copy, vulkan-swap-mode=fifo). SwiftUI draws the controls
// overlay on top; input comes from onPlayPauseCommand / onExitCommand there.
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

final class MPVViewController: UIViewController {
    private var mpv: OpaquePointer?
    private let url: URL
    private weak var model: PlayerModel?
    private var metalLayer: CAMetalLayer?
    private var poll: Timer?
    private let mpvQueue = DispatchQueue(label: "app.harbor.tvos.mpv")

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

        // Audio session MUST be active + .playback before mpv opens its audio
        // unit, or tvOS routes nothing to HDMI (that was the "no sound").
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true, options: [])

        mpvQueue.async { [weak self] in self?.setupMPV() }

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

    private func setupMPV() {
        guard let layer = metalLayer, let ctx = mpv_create() else { return }
        mpv = ctx
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &wid)
        setOpt("vo", "gpu-next")
        setOpt("gpu-api", "vulkan")
        setOpt("gpu-context", "moltenvk")
        setOpt("hwdec", "videotoolbox-copy")
        // Audio: force the tvOS audio unit and never silently fall back to null.
        setOpt("ao", "audiounit")
        setOpt("audio-fallback-to-null", "no")
        setOpt("volume", "100")
        setOpt("volume-max", "100")
        setOpt("mute", "no")
        setOpt("vulkan-swap-mode", "fifo")
        setOpt("deband", "no")
        setOpt("scale", "bilinear")
        setOpt("dscale", "bilinear")
        setOpt("hdr-compute-peak", "no")
        setOpt("cache", "yes")
        setOpt("demuxer-max-bytes", "64MiB")
        setOpt("network-timeout", "30")
        setOpt("keep-open", "yes")
        setOpt("sub-auto", "fuzzy")
        mpv_initialize(ctx)
        command(["loadfile", url.absoluteString])
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

    // MARK: control API (called from SwiftUI)
    func togglePause() { mpvQueue.async { [weak self] in self?.command(["cycle", "pause"]) } }
    func seekRelative(_ delta: Double) {
        mpvQueue.async { [weak self] in
            self?.command(["seek", String(delta), "relative"])
        }
    }

    func shutdown() {
        poll?.invalidate(); poll = nil
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv else { return }
            self.mpv = nil
            mpv_terminate_destroy(ctx)
        }
    }
}
