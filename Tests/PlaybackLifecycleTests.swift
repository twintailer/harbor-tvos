import Foundation

/// Runs on the standard macOS runner without simulator/framework downloads.
/// Tests the production gates AND PlayerModel with a controllable decoder.
@main
struct PlaybackLifecycleTests {
    @MainActor static func main() async {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }

        let gate = PlaybackShutdownGate()
        var callbacks = 0
        expect(gate.begin { callbacks += 1 }, "First stop owns teardown")
        expect(!gate.begin { callbacks += 1 }, "Duplicate stop joins teardown")
        expect(callbacks == 0, "Cannot finish before native acknowledgement")
        gate.finish()
        expect(callbacks == 2, "Both waiters resume")
        gate.finish()
        expect(callbacks == 2, "Duplicate native notification is ignored")
        expect(!gate.begin { callbacks += 1 }, "Dismantle after stop does not restart teardown")
        expect(callbacks == 3, "Late waiter resumes immediately")

        var requests = PlaybackRequestGate()
        let first = requests.begin()
        let second = requests.begin()
        expect(!requests.accepts(first), "Old stream response cannot present")
        expect(requests.accepts(second), "Current response can present")
        requests.cancel()
        expect(!requests.accepts(second), "Cancelled request cannot reopen playback")
        for _ in 0..<100 {
            let stale = requests.begin()
            requests.cancel()
            _ = requests.begin()
            expect(!requests.accepts(stale), "Late addon result is ignored after rapid back/retry")
        }

        let old = FakePlayer(), new = FakePlayer()
        var owner = PlaybackOwnership()
        owner.claim(old)
        owner.claim(new)
        expect(!owner.release(old), "Old player's teardown cannot deactivate new audio")
        expect(owner.contains(new), "New audio still owned")
        expect(owner.release(new), "Current player releases audio")
        expect(!owner.release(new), "Audio release is idempotent")

        let buttons: [PlaybackControl] = [.restart, .play, .next, .source, .subs]
        for button in buttons {
            expect(PlaybackControl.vertical(from: button, direction: 1, lastButton: button,
                                           buttons: buttons, action: .skip) == .scrub,
                   "Down always reaches the timeline")
            expect(PlaybackControl.vertical(from: .scrub, direction: -1, lastButton: button,
                                           buttons: buttons, action: .skip) == button,
                   "Up restores the button, not an unrelated focus target")
            expect(PlaybackControl.vertical(from: button, direction: -1, lastButton: button,
                                           buttons: buttons, action: .upNext) == .upNext,
                   "Next-episode action is reachable")
        }
        expect(PlaybackControl.vertical(from: .scrub, direction: -1, lastButton: .audio,
                                       buttons: buttons, action: nil) == .play,
               "Removed controls fall back to Play")

        let model = PlayerModel()
        model.controller = old
        expect(model.owns(old), "Controller owns its model")
        let firstStop = Task { @MainActor in await model.shutdown() }
        for _ in 0..<100 where old.stopCount == 0 { await Task.yield() }
        expect(old.stopCount == 1, "Native stop requested")
        expect(!model.owns(old), "Late callbacks are rejected as soon as exit begins")
        var secondFinished = false
        let secondStop = Task { @MainActor in
            await model.shutdown()
            secondFinished = true
        }
        for _ in 0..<10 { await Task.yield() }
        expect(!secondFinished, "Exit during an engine switch waits for that teardown")
        expect(old.stopCount == 1, "Exit and engine switch share one stop")
        old.finish()
        await firstStop.value
        await secondStop.value
        expect(secondFinished, "Waiters finish after the renderer is released")
        model.controller = new
        expect(!model.releaseController(old), "Late old dismantle cannot clear new controller")
        expect(model.owns(new), "Next episode keeps its controller")
        expect(model.releaseController(new), "Current controller can release")

        expect(PlayerModel.fmt(.nan) == "0:00", "NaN clock is safe")
        expect(PlayerModel.fmt(.infinity) == "0:00", "Infinite clock is safe")
        expect(PlayerModel.fmt(Double.greatestFiniteMagnitude) == "0:00", "Overflow clock is safe")
        expect(PlayerModel.fmt(-10) == "0:00", "Negative clock is safe")
        expect(PlayerModel.fmt(3661) == "1:01:01", "Long video clock formatting")
        model.duration = 60
        model.position = .nan
        expect(model.progress == 0, "Malformed progress cannot create a NaN frame")
        model.position = -5
        expect(model.progress == 0, "Negative progress cannot create a negative frame")
        model.position = 90
        expect(model.progress == 1, "Overshoot is clamped")

        func episode(_ season: Int, _ number: Int) -> MetaItem.Video {
            .init(id: "\(season):\(number)", title: nil, season: season, episode: number,
                  thumbnail: nil, overview: nil, released: nil)
        }
        let e1 = episode(1, 1), e2 = episode(1, 2), s2 = episode(2, 1)
        expect(EpisodeOrder.next(after: e1, in: [s2, e1, e1, e2]) == e2,
               "Unsorted and duplicated metadata advances exactly one episode")
        expect(EpisodeOrder.next(after: e2, in: [e1, s2, e2]) == s2,
               "Next crosses season boundary")
        expect(EpisodeOrder.next(after: s2, in: [s2, e1, e2]) == nil,
               "Last episode has no next target")
        expect(EpisodeOrder.next(after: e1, in: [episode(0, 100), s2]) == s2,
               "Specials do not interrupt regular episode succession")
        expect(EpisodeOrder.next(after: e1, in: []) == nil, "Empty episode list is safe")
        let malformed = Data(#"{"id":"bad","season":1e100,"episode":1}"#.utf8)
        let decoded = try? JSONDecoder().decode(MetaItem.Video.self, from: malformed)
        expect(decoded != nil && decoded?.season == nil, "Out-of-range addon numbers cannot crash decoding")
        func meta(_ type: String, _ id: String) -> MetaItem {
            .init(id: id, type: type, name: id, poster: nil, background: nil,
                  description: nil, releaseInfo: nil, imdbRating: nil,
                  genres: nil, runtime: nil, videos: nil)
        }
        let movie = meta("movie", "42"), series = meta("series", "42")
        expect(MetaItem.unique([movie, movie, series]).count == 2,
               "Catalog focus identities distinguish movie and series")
        expect(MetaItem.unique([movie, series, series], excluding: [movie]) == [series],
               "Pagination removes duplicates within and across pages")
        expect(MetaItem.unique([]).isEmpty, "Empty catalog page is safe")
        print("PASS: \(checks) playback lifecycle, stale-response, audio-ownership and remote-navigation checks")
    }
}

@MainActor
private final class FakePlayer: HarborPlayerController {
    var videoSizeMode = "original"
    var stopCount = 0
    private var completion: (@MainActor () -> Void)?
    func shutdown(completion: @escaping @MainActor () -> Void) {
        stopCount += 1
        self.completion = completion
    }
    func finish() { let done = completion; completion = nil; done?() }
    func togglePause() {}
    func seekRelative(_ delta: Double) {}
    func seekAbsolute(_ seconds: Double) {}
    func tracks(ofType type: String) -> [MPVTrack] { [] }
    func setAudioTrack(_ id: Int) {}
    func setSubtitleTrack(_ id: Int) {}
    func setSpeed(_ speed: Double) {}
    func setSubDelay(_ seconds: Double) {}
    func setAudioDelay(_ seconds: Double) {}
    func setAnime4K(_ enabled: Bool) {}
    func mediaSummary() -> (height: Int, audioCodec: String, audioOut: String) { (0, "", "") }
    func chapters() -> [MediaChapter] { [] }
    func recoverAudioOutput(forceStereo: Bool) {}
    func setVideoSize(_ mode: String) {}
    func applySubtitleStyle() {}
}
