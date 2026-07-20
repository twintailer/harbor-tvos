import Foundation

// Bridges mpv playback state to the SwiftUI controls overlay.
@MainActor
final class PlayerModel: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var paused: Bool = false
    @Published var ready: Bool = false

    weak var controller: MPVViewController?

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
