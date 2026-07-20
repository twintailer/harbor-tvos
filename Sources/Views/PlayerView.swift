import SwiftUI

struct PlayerTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

// libmpv-backed player — plays MKV/HEVC/anything, unlike AVPlayer. Menu button
// exits, play/pause toggles.
struct PlayerView: View {
    let target: PlayerTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MPVPlayerView(url: target.url, onExit: { dismiss() })
            .ignoresSafeArea()
    }
}
