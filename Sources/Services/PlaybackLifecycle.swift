import Foundation

/// One teardown, any number of waiters. Completion means the native decoder
/// has stopped using its surface, not merely that a dismiss animation finished.
@MainActor
final class PlaybackShutdownGate {
    private(set) var isStopping = false
    private var finished = false
    private var waiters: [@MainActor () -> Void] = []

    func begin(_ completion: @escaping @MainActor () -> Void) -> Bool {
        if finished { completion(); return false }
        waiters.append(completion)
        guard !isStopping else { return false }
        isStopping = true
        return true
    }

    func finish() {
        guard isStopping, !finished else { return }
        finished = true
        let callbacks = waiters
        waiters.removeAll()
        callbacks.forEach { $0() }
    }
}

/// Resolvers may ignore task cancellation. A response must also belong to the
/// most recent user request before it may present a player or source picker.
struct PlaybackRequestGate {
    private var current: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        current = id
        return id
    }

    func accepts(_ id: UUID) -> Bool { current == id }
    mutating func cancel() { current = nil }
}

/// Ownership is app-wide: successive full-screen players have different models
/// but share one AVAudioSession. An old decoder cannot release the new route.
struct PlaybackOwnership {
    private var owner: ObjectIdentifier?
    mutating func claim(_ candidate: AnyObject) { owner = ObjectIdentifier(candidate) }
    func contains(_ candidate: AnyObject) -> Bool { owner == ObjectIdentifier(candidate) }
    mutating func release(_ candidate: AnyObject) -> Bool {
        guard contains(candidate) else { return false }
        owner = nil
        return true
    }
}

enum PlaybackControl: Hashable {
    case skip, upNext, restart, back, play, fwd, next, source, engine, audio, subs, aspect, speed, anime, scrub

    static func vertical(from current: Self, direction: Int, lastButton: Self,
                         buttons: [Self], action: Self?) -> Self {
        let restored = buttons.contains(lastButton) ? lastButton : .play
        switch current {
        case .scrub: return direction < 0 ? restored : .scrub
        case .skip, .upNext: return direction > 0 ? restored : current
        default: return direction > 0 ? .scrub : (action ?? current)
        }
    }
}

enum PlaybackPresentation {
    static func progress(position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    static func shouldShowUpNext(position: Double, duration: Double,
                                 leadSeconds: Int, hasNextEpisode: Bool) -> Bool {
        guard hasNextEpisode, leadSeconds != 0,
              position.isFinite, duration.isFinite, duration > 0, position > 0 else { return false }
        // Clamp BEFORE converting to Int: malformed media durations must not trap.
        let automatic = max(25, min(90, duration * 0.045))
        let lead = leadSeconds < 0 ? automatic.rounded(.down) : Double(leadSeconds)
        return duration - position <= lead
    }
}
