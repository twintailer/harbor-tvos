import SwiftUI
import AVFoundation
import Libmpv

// libmpv-backed player for tvOS. AVPlayer can't decode MKV / most Stremio
// stream containers; mpv plays everything. This mirrors the hard-won iOS
// settings (hwdec=videotoolbox-copy, vulkan-swap-mode=fifo) minus the Tauri
// main-thread dance — here it's a plain presented UIViewController.
struct MPVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> MPVViewController {
        MPVViewController(url: url, onExit: onExit)
    }
    func updateUIViewController(_ vc: MPVViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: MPVViewController, coordinator: ()) {
        vc.shutdown()
    }
}

final class MPVViewController: UIViewController {
    private var mpv: OpaquePointer?
    private let url: URL
    private let onExit: () -> Void
    private var metalLayer: CAMetalLayer?
    private let mpvQueue = DispatchQueue(label: "app.harbor.tvos.mpv")

    init(url: URL, onExit: @escaping () -> Void) {
        self.url = url
        self.onExit = onExit
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

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

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        mpvQueue.async { [weak self] in self?.setupMPV() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer?.frame = view.bounds
        metalLayer?.drawableSize = CGSize(
            width: view.bounds.width * UIScreen.main.scale,
            height: view.bounds.height * UIScreen.main.scale)
    }

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

    private func setupMPV() {
        guard let layer = metalLayer, let ctx = mpv_create() else { return }
        mpv = ctx
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &wid)
        setOpt("vo", "gpu-next")
        setOpt("gpu-api", "vulkan")
        setOpt("gpu-context", "moltenvk")
        setOpt("hwdec", "videotoolbox-copy")
        setOpt("ao", "audiounit")
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

    func shutdown() {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv else { return }
            self.mpv = nil
            mpv_terminate_destroy(ctx)
        }
    }

    // Siri Remote: menu = exit, play/pause & select = toggle pause.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .menu:
                handled = true
                shutdown()
                onExit()
            case .playPause, .select:
                handled = true
                mpvQueue.async { [weak self] in self?.command(["cycle", "pause"]) }
            default:
                break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}
