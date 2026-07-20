import AVKit
import SwiftUI

struct PlayerTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

// v1 player: native AVKit. tvOS gets AVPlayer + the system transport controls
// (Siri Remote scrubbing, PiP) for free. This is the surface that later rounds
// will feed real resolved streams into (addon/debrid pipeline); for now it
// proves end-to-end playback works with a public HLS test stream.
struct PlayerView: View {
    let target: PlayerTarget
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: target.url))
                player.play()
            }
            .onDisappear { player.pause() }
    }
}

// Apple's public test HLS stream — a stand-in until the stream resolver lands.
enum DemoStream {
    static let url = URL(string:
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")!
}
