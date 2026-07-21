import SwiftUI

// Playback + account preferences. Subtitle appearance and video-size mirror the
// in-player panel; the values are shared via @AppStorage / UserDefaults so a change
// here applies to the next playback and vice-versa.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore

    @AppStorage(SubtitleStyle.Key.size) private var subSize = SubtitleStyle.defaultSize
    @AppStorage(SubtitleStyle.Key.color) private var subColor = SubtitleStyle.defaultColor
    @AppStorage(SubtitleStyle.Key.background) private var subBackground = SubtitleStyle.defaultBackground
    @AppStorage(SubtitleStyle.Key.videoSize) private var videoSize = "original"

    private let videoSizes: [SubtitleStyle.Preset] = [
        .init(id: "original", label: "Fit"),
        .init(id: "fill", label: "Fill"),
        .init(id: "stretch", label: "Stretch"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("Settings")
                        .font(.system(size: 56, weight: .bold))
                        .padding(.horizontal, 60).padding(.top, 40)

                    section("Account") {
                        if auth.isSignedIn {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(auth.email ?? "Signed in")
                                    .font(.system(size: 26)).foregroundStyle(.white.opacity(0.85))
                                Text("\(auth.addons.count) add-ons · \(auth.addons.filter { $0.hasStream }.count) stream sources")
                                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.55))
                                Button("Sign Out", role: .destructive) { auth.logout() }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Text("Sign in on the Account tab to load your add-ons, catalogs and Continue Watching.")
                                .font(.system(size: 22)).foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    section("Video Size") {
                        chips(videoSizes, selected: videoSize) { videoSize = $0 }
                    }

                    section("Subtitle Size") {
                        chips(SubtitleStyle.sizes, selected: subSize) { subSize = $0 }
                    }
                    section("Subtitle Colour") {
                        chips(SubtitleStyle.colors, selected: subColor) { subColor = $0 }
                    }
                    section("Subtitle Background") {
                        chips(SubtitleStyle.backgrounds, selected: subBackground) { subBackground = $0 }
                    }

                    Text("Harbor for Apple TV")
                        .font(.system(size: 18)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 60).padding(.top, 20)
                }
                .padding(.bottom, 80)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
            content()
        }
        .padding(.horizontal, 60)
    }

    private func chips(_ options: [SubtitleStyle.Preset], selected: String, _ pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 16) {
            ForEach(options) { o in
                Button(o.label) { pick(o.id) }
                    .buttonStyle(.bordered)
                    .tint(selected == o.id ? .green : .gray)
            }
        }
    }
}
