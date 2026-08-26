import AVFoundation
import SwiftUI
import TVVLCKit
import UIKit

/// tvOS VLCKit fallback for streams that do not behave well in mpv. The same
/// SwiftUI chrome drives both engines through `HarborPlayerController`.
struct VLCPlayerView: UIViewControllerRepresentable {
    let url: URL
    let model: PlayerModel
    var startAt: Double = 0
    var requestHeaders: [String: String] = [:]

    func makeUIViewController(context: Context) -> VLCViewController {
        let controller = VLCViewController(url: url, model: model, startAt: startAt,
                                           requestHeaders: requestHeaders)
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: VLCViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: VLCViewController, coordinator: ()) {
        controller.shutdown()
    }
}

@MainActor
final class VLCViewController: UIViewController, HarborPlayerController {
    private let engine = HarborVLCEngine()
    private weak var model: PlayerModel?
    private let url: URL
    private let startAt: Double
    private let requestHeaders: [String: String]
    private var appliedStart = false
    private var shuttingDown = false

    private(set) var videoSizeMode = UserDefaults.standard.string(
        forKey: SubtitleStyle.Key.videoSize) ?? "original"

    init(url: URL, model: PlayerModel, startAt: Double,
         requestHeaders: [String: String]) {
        self.url = url
        self.model = model
        self.startAt = startAt
        self.requestHeaders = requestHeaders
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        attachVideoView()
        activateAudioSession()
        bindEngine()

        let defaults = UserDefaults.standard
        let cache = defaults.bool(forKey: SubtitleStyle.Key.mpvBufferBoost) ? 8_000 : 3_000
        engine.load(url: url, networkCachingMs: cache, headers: requestHeaders)
        engine.play()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        engine.videoView.frame = view.bounds
    }

    private func attachVideoView() {
        let video = engine.videoView
        video.removeFromSuperview()
        video.frame = view.bounds
        video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(video)
    }

    private func bindEngine() {
        engine.onState = { [weak self] playing, buffering, ended, errored in
            guard let self, !self.shuttingDown, let model = self.model else { return }
            model.paused = !playing && !buffering
            if playing || buffering { model.ready = true }
            if ended { model.ended = true }
            if errored {
                model.logLines.append("[vlc] Playback error")
                if model.logLines.count > 40 { model.logLines.removeFirst(model.logLines.count - 40) }
            }
            if !self.appliedStart, self.startAt > 1, playing {
                self.appliedStart = true
                self.engine.seek(to: self.startAt)
            }
        }
        engine.onTime = { [weak self] position, duration in
            guard let self, !self.shuttingDown, let model = self.model else { return }
            if position.isFinite, position >= 0 { model.position = position }
            if duration.isFinite, duration > 0 {
                model.duration = duration
                model.ready = true
            }
        }
    }

    // MARK: HarborPlayerController

    func togglePause() {
        if engine.isPlaying { engine.pause() } else { engine.play() }
    }

    func seekRelative(_ delta: Double) { seekAbsolute(engine.currentTime + delta) }

    func seekAbsolute(_ seconds: Double) {
        engine.seek(to: max(0, min(model?.duration ?? seconds, seconds)))
    }

    func tracks(ofType type: String) -> [MPVTrack] {
        let source = type == "audio" ? engine.audioTracks : engine.subtitleTracks
        let selected = type == "audio" ? engine.currentAudioID : engine.currentSubtitleID
        return source.map { track in
            MPVTrack(id: Int(track.id), type: type, title: track.name,
                     lang: languageCode(from: track.name), selected: track.id == selected,
                     external: false)
        }
    }

    func setAudioTrack(_ id: Int) { engine.selectAudio(Int32(id)) }
    func setSubtitleTrack(_ id: Int) { engine.selectSubtitle(Int32(id)) }
    func setSpeed(_ speed: Double) { engine.rate = Float(speed) }

    // libVLC's tvOS wrapper does not expose stable generic delay/style APIs.
    // Track selection remains native; advanced caption styling stays an mpv feature.
    func setSubDelay(_ seconds: Double) {}
    func setAudioDelay(_ seconds: Double) {}
    func setAnime4K(_ enabled: Bool) {}
    func applySubtitleStyle() {}
    func chapters() -> [MediaChapter] { [] }

    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String) {
        (Int(engine.naturalSize.height), "VLC", model?.ready == true ? "vlc" : "")
    }

    func recoverAudioOutput(forceStereo: Bool) {
        activateAudioSession()
        guard !engine.isPlaying else { return }
        engine.play()
    }

    func setVideoSize(_ mode: String) {
        videoSizeMode = mode
        UserDefaults.standard.set(mode, forKey: SubtitleStyle.Key.videoSize)
        engine.setVideoMode(mode)
    }

    func shutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        engine.onState = nil
        engine.onTime = nil
        engine.stop()
        model?.controller = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func languageCode(from name: String) -> String {
        let value = name.lowercased()
        let names: [(String, String)] = [
            ("german", "de"), ("deutsch", "de"), ("english", "en"),
            ("spanish", "es"), ("french", "fr"), ("italian", "it"),
            ("japanese", "ja"), ("korean", "ko"), ("chinese", "zh"),
            ("portuguese", "pt"), ("russian", "ru"), ("arabic", "ar"),
        ]
        if let match = names.first(where: { value.contains($0.0) }) { return match.1 }
        for code in ["de", "en", "es", "fr", "it", "ja", "ko", "zh", "pt", "ru", "ar"] {
            if value.contains("[(code)]") || value.contains("((code))") { return code }
        }
        return "und"
    }
}

/// NSObject delegate kept separate from the UIViewController so VLCKit's
/// Objective-C callbacks stay nonisolated. VLCKit invokes them on the main runloop.
private final class HarborVLCEngine: NSObject {
    let player = VLCMediaPlayer()
    let videoView = UIView()

    var onState: (@MainActor (Bool, Bool, Bool, Bool) -> Void)?
    var onTime: (@MainActor (TimeInterval, TimeInterval) -> Void)?

    override init() {
        super.init()
        videoView.backgroundColor = .black
        player.drawable = videoView
        player.delegate = self
    }

    func load(url: URL, networkCachingMs: Int, headers: [String: String]) {
        let media = VLCMedia(url: url)
        for (key, value) in headers {
            switch key.lowercased() {
            case "referer", "referrer": media.addOption(":http-referrer=(value)")
            case "user-agent": media.addOption(":http-user-agent=(value)")
            default: break
            }
        }
        media.addOption(":network-caching=(networkCachingMs)")
        media.addOption(":file-caching=(networkCachingMs)")
        media.addOption(":http-reconnect")
        media.addOption(":no-video-title-show")
        player.media = media
    }

    func play() { player.play() }
    func pause() { if player.isPlaying { player.pause() } }
    func stop() { player.stop() }
    func seek(to seconds: TimeInterval) {
        player.time = VLCTime(int: Int32(max(0, seconds) * 1000))
    }

    var currentTime: TimeInterval { Double(player.time.intValue) / 1000 }
    var duration: TimeInterval { Double(player.media?.length.intValue ?? 0) / 1000 }
    var isPlaying: Bool { player.isPlaying }
    var naturalSize: CGSize { player.videoSize }
    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    struct EngineTrack { let id: Int32; let name: String }

    var audioTracks: [EngineTrack] {
        zip(player.audioTrackIndexes, player.audioTrackNames).compactMap { index, name in
            guard let id = (index as? NSNumber)?.int32Value else { return nil }
            return EngineTrack(id: id, name: (name as? String) ?? "Audio (id)")
        }
    }

    var subtitleTracks: [EngineTrack] {
        zip(player.videoSubTitlesIndexes, player.videoSubTitlesNames).compactMap { index, name in
            guard let id = (index as? NSNumber)?.int32Value else { return nil }
            return EngineTrack(id: id, name: (name as? String) ?? "Subtitle (id)")
        }
    }

    var currentAudioID: Int32 { player.currentAudioTrackIndex }
    var currentSubtitleID: Int32 { player.currentVideoSubTitleIndex }
    func selectAudio(_ id: Int32) { player.currentAudioTrackIndex = id }
    func selectSubtitle(_ id: Int32) { player.currentVideoSubTitleIndex = id }

    func setVideoMode(_ mode: String) {
        // VLCKit owns final video composition. Resetting the scale is reliable;
        // fill/stretch remain best-effort in VLC and do not interrupt playback.
        player.scaleFactor = mode == "original" ? 0 : 1
    }
}

extension HarborVLCEngine: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification) {
        let state = player.state
        let playing = player.isPlaying
        let buffering = state == .buffering || state == .opening
        let ended = state == .ended
        let errored = state == .error
        MainActor.assumeIsolated { onState?(playing, buffering, ended, errored) }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        let current = currentTime
        let total = duration
        MainActor.assumeIsolated { onTime?(current, total) }
    }
}
