import AVFoundation
import KSPlayer
import SwiftUI
import UIKit

/// KSPlayer's lightweight KSAVPlayer engine behind Harbor's own tvOS chrome.
/// Its optional FFmpeg fallback is deliberately excluded because Harbor's
/// Anime4K-capable MPVKit already owns that native codec namespace.
struct KSPlayerEngineView: UIViewControllerRepresentable {
    let url: URL
    let model: PlayerModel
    var startAt: Double = 0
    var requestHeaders: [String: String] = [:]

    func makeUIViewController(context: Context) -> KSPlayerViewController {
        let controller = KSPlayerViewController(
            url: url, model: model, startAt: startAt, requestHeaders: requestHeaders)
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: KSPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: KSPlayerViewController,
                                           coordinator: ()) {
        controller.shutdown()
    }
}

@MainActor
final class KSPlayerViewController: UIViewController, HarborPlayerController,
                                    PlayerControllerDelegate {
    private let playerView = KSPlayer.VideoPlayerView()
    private weak var model: PlayerModel?
    private let url: URL
    private let startAt: Double
    private let requestHeaders: [String: String]
    private var shuttingDown = false
    private var appliedStart = false

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

    override func loadView() {
        view = playerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        activateAudioSession()

        // Harbor supplies the complete controls/focus layer. Keep only KSPlayer's
        // video and subtitle surfaces to avoid duplicate focus work on every frame.
        playerView.delegate = self
        playerView.controllerView.isHidden = true
        playerView.contentOverlayView.isUserInteractionEnabled = false
        playerView.tapGesture.isEnabled = false
        playerView.doubleTapGesture.isEnabled = false
        playerView.panGesture.isEnabled = false

        let defaults = UserDefaults.standard
        let options = KSOptions()
        options.registerRemoteControll = false
        options.hardwareDecode = true
        options.isSecondOpen = false
        options.isAccurateSeek = false
        options.preferredForwardBufferDuration = defaults.bool(
            forKey: SubtitleStyle.Key.mpvBufferBoost) ? 5 : 2.5
        options.maxBufferDuration = defaults.bool(
            forKey: SubtitleStyle.Key.mpvBufferBoost) ? 30 : 15
        options.startPlayTime = max(0, startAt)
        options.startPlayRate = Float(defaults.double(
            forKey: SubtitleStyle.Key.defaultSpeed).nonZeroOrOne)
        options.userAgent = requestHeaders.first {
            $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame
        }?.value ?? "Harbor tvOS"
        options.appendHeader(requestHeaders)
        playerView.set(url: url, options: options)
        playerView.play()
        applySubtitleStyle()
        setVideoSize(videoSizeMode)
    }

    // MARK: PlayerControllerDelegate

    func playerController(state: KSPlayerState) {
        guard !shuttingDown, let model else { return }
        switch state {
        case .readyToPlay:
            model.ready = true
            model.paused = false
            applyInitialSeekIfNeeded()
        case .bufferFinished:
            model.ready = true
            model.playbackStarted = true
            model.paused = false
            applyInitialSeekIfNeeded()
        case .buffering, .preparing:
            model.ready = true
        case .paused:
            model.paused = true
        case .playedToTheEnd:
            model.ended = true
        case .error:
            model.logLines.append("[ksplayer] Playback error")
            if model.logLines.count > 40 {
                model.logLines.removeFirst(model.logLines.count - 40)
            }
        default:
            break
        }
    }

    func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
        guard !shuttingDown, let model else { return }
        if currentTime.isFinite, currentTime >= 0,
           abs(model.position - currentTime) > 0.12 {
            model.position = currentTime
        }
        if currentTime.isFinite, currentTime > max(0.05, startAt + 0.05) {
            model.playbackStarted = true
        }
        if totalTime.isFinite, totalTime > 0,
           abs(model.duration - totalTime) > 0.2 {
            model.duration = totalTime
            model.ready = true
        }
        applyInitialSeekIfNeeded()
    }

    func playerController(finish error: Error?) {
        guard !shuttingDown, let model else { return }
        if let error {
            model.logLines.append("[ksplayer] \(error.localizedDescription)")
        } else {
            model.ended = true
        }
    }

    func playerController(maskShow: Bool) {}
    func playerController(action: PlayerButtonType) {}
    func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
    func playerController(seek: TimeInterval) {}

    // MARK: HarborPlayerController

    func togglePause() {
        if playerView.playerLayer?.player.isPlaying == true {
            playerView.pause()
        } else {
            playerView.play()
        }
    }

    func seekRelative(_ delta: Double) {
        seekAbsolute((playerView.playerLayer?.player.currentPlaybackTime ?? 0) + delta)
    }

    func seekAbsolute(_ seconds: Double) {
        playerView.seek(time: max(0, seconds)) { _ in }
    }

    func tracks(ofType type: String) -> [MPVTrack] {
        guard let player = playerView.playerLayer?.player else { return [] }
        let mediaType: AVMediaType = type == "audio" ? .audio : .subtitle
        return player.tracks(mediaType: mediaType).map { track in
            let title = track.name
            return MPVTrack(
                id: Int(track.trackID), type: type, title: title,
                lang: track.languageCode ?? "", selected: track.isEnabled,
                external: false,
                forced: title.localizedCaseInsensitiveContains("forced")
                    || title.localizedCaseInsensitiveContains("signs"),
                defaultTrack: track.isEnabled,
                hearingImpaired: title.localizedCaseInsensitiveContains("sdh")
                    || title.localizedCaseInsensitiveContains("hearing impaired"),
                codec: "KSPlayer", externalFilename: "")
        }
    }

    func setAudioTrack(_ id: Int) { selectTrack(id, mediaType: .audio) }

    func setSubtitleTrack(_ id: Int) {
        guard let player = playerView.playerLayer?.player else { return }
        let tracks = player.tracks(mediaType: .subtitle)
        if id < 0 {
            tracks.forEach { $0.isEnabled = false }
            playerView.srtControl.selectedSubtitleInfo = nil
        } else if let track = tracks.first(where: { $0.trackID == Int32(id) }) {
            player.select(track: track)
        }
    }

    func setSpeed(_ speed: Double) {
        playerView.playerLayer?.player.playbackRate = Float(speed)
    }

    func setSubDelay(_ seconds: Double) {
        playerView.srtControl.subtitleDelay = seconds
    }

    func setAudioDelay(_ seconds: Double) {}
    func setAnime4K(_ enabled: Bool) {}

    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String) {
        guard let player = playerView.playerLayer?.player else { return (0, "", "") }
        return (Int(player.naturalSize.height), "KSPlayer", player.isReadyToPlay ? "ksplayer" : "")
    }

    func chapters() -> [MediaChapter] {
        (playerView.playerLayer?.player.chapters ?? []).map {
            MediaChapter(title: $0.title, start: $0.start, end: $0.end)
        }
    }

    func recoverAudioOutput(forceStereo: Bool) {
        activateAudioSession()
        if playerView.playerLayer?.player.isPlaying != true { playerView.play() }
    }

    func setVideoSize(_ mode: String) {
        videoSizeMode = mode
        UserDefaults.standard.set(mode, forKey: SubtitleStyle.Key.videoSize)
        switch mode {
        case "fill", "zoom": playerView.playerLayer?.player.contentMode = .scaleAspectFill
        case "stretch": playerView.playerLayer?.player.contentMode = .scaleToFill
        default: playerView.playerLayer?.player.contentMode = .scaleAspectFit
        }
    }

    func applySubtitleStyle() {
        let defaults = UserDefaults.standard
        SubtitleModel.textFontSize = CGFloat(defaults.double(
            forKey: SubtitleStyle.Key.fontSize).nonZeroOr(SubtitleStyle.defaultFontSize))
        SubtitleModel.textBold = defaults.bool(forKey: SubtitleStyle.Key.bold)
        SubtitleModel.textColor = Self.color(
            defaults.string(forKey: SubtitleStyle.Key.fontColor)
                ?? SubtitleStyle.defaultFontColor)
        let background = defaults.string(forKey: SubtitleStyle.Key.style) == "box"
            ? Self.color(defaults.string(forKey: SubtitleStyle.Key.boxColor)
                ?? SubtitleStyle.defaultBoxColor).opacity(defaults.double(
                    forKey: SubtitleStyle.Key.boxOpacity).nonZeroOr(0.6))
            : Color.clear
        SubtitleModel.textBackgroundColor = background
        playerView.updateSrt()
    }

    func shutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        playerView.delegate = nil
        playerView.pause()
        playerView.playerLayer?.stop()
        if model?.releaseController(self) == true {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }

    private func selectTrack(_ id: Int, mediaType: AVMediaType) {
        guard let player = playerView.playerLayer?.player,
              let track = player.tracks(mediaType: mediaType).first(where: {
                  $0.trackID == Int32(id)
              }) else { return }
        player.select(track: track)
    }

    private func applyInitialSeekIfNeeded() {
        guard !appliedStart, startAt > 1,
              playerView.playerLayer?.player.isReadyToPlay == true else { return }
        appliedStart = true
        seekAbsolute(startAt)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private static func color(_ raw: String) -> Color {
        let hex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .white }
        return Color(red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }
}

private extension Double {
    var nonZeroOrOne: Double { self > 0 ? self : 1 }
    func nonZeroOr(_ fallback: Double) -> Double { self > 0 ? self : fallback }
}
