import Foundation

/// Common surface used by the player chrome. MPV, VLC and KSPlayer conform, so
/// controls never need to know which decoder currently owns the video view.
@MainActor
protocol HarborPlayerController: AnyObject {
    var videoSizeMode: String { get }
    func togglePause()
    func seekRelative(_ delta: Double)
    func seekAbsolute(_ seconds: Double)
    func tracks(ofType type: String) -> [MPVTrack]
    func setAudioTrack(_ id: Int)
    func setSubtitleTrack(_ id: Int)
    func setSpeed(_ speed: Double)
    func setSubDelay(_ seconds: Double)
    func setAudioDelay(_ seconds: Double)
    func setAnime4K(_ enabled: Bool)
    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String)
    func chapters() -> [MediaChapter]
    func recoverAudioOutput(forceStereo: Bool)
    func setVideoSize(_ mode: String)
    func applySubtitleStyle()
}

// Bridges the active playback engine to the SwiftUI controls overlay.
@MainActor
final class PlayerModel: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var paused: Bool = false
    @Published var ready: Bool = false
    @Published var ended: Bool = false
    @Published var anime4KActive: Bool = false
    /// Last mpv warn/error log lines, shown in the in-player Debug panel so playback
    /// problems can be read directly on the Apple TV (no Mac needed).
    @Published var logLines: [String] = []

    weak var controller: (any HarborPlayerController)?

    func togglePause() { controller?.togglePause() }
    func seekRelative(_ delta: Double) { controller?.seekRelative(delta) }

    var timeText: String { Self.fmt(position) }
    var remainingText: String { "-" + Self.fmt(max(0, duration - position)) }
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }

    static func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}
