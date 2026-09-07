import AVFoundation

@MainActor
enum PlaybackAudioSession {
    private static var ownership = PlaybackOwnership()

    @discardableResult
    static func activate(for owner: AnyObject) -> Bool {
        ownership.claim(owner)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            return true
        } catch { return false }
    }

    static func release(_ owner: AnyObject) {
        guard ownership.release(owner) else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
