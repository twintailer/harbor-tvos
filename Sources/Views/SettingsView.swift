import SwiftUI

// Playback / subtitle / audio / episode preferences, mirroring the Harbor iPhone
// settings that apply to a tvOS player. Values are stored via @AppStorage under the
// same keys the player and episode list read, so a change here takes effect
// immediately on the next playback.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore

    @AppStorage(SubtitleStyle.Key.videoSize) private var videoSize = "original"
    @AppStorage(SubtitleStyle.Key.defaultSpeed) private var defaultSpeed = 1.0
    @AppStorage(SubtitleStyle.Key.seekStep) private var seekStep = 10

    @AppStorage(SubtitleStyle.Key.size) private var subSize = SubtitleStyle.defaultSize
    @AppStorage(SubtitleStyle.Key.color) private var subColor = SubtitleStyle.defaultColor
    @AppStorage(SubtitleStyle.Key.style) private var subStyle = SubtitleStyle.defaultStyle
    @AppStorage(SubtitleStyle.Key.bold) private var subBold = false
    @AppStorage(SubtitleStyle.Key.subLang) private var subLang = ""
    @AppStorage(SubtitleStyle.Key.subsOff) private var subsOff = false

    @AppStorage(SubtitleStyle.Key.audioLang) private var audioLang = ""
    @AppStorage(SubtitleStyle.Key.audioNormalize) private var audioNormalize = false

    @AppStorage(SubtitleStyle.Key.episodeSort) private var episodeSort = "oldest"
    @AppStorage(SubtitleStyle.Key.showEpisodeDesc) private var showEpisodeDesc = true

    private let videoSizes: [SubtitleStyle.Preset] = [
        .init(id: "original", label: "Fit"),
        .init(id: "fill", label: "Fill"),
        .init(id: "stretch", label: "Stretch"),
    ]
    private let sortOptions: [SubtitleStyle.Preset] = [
        .init(id: "oldest", label: "Oldest first"),
        .init(id: "newest", label: "Newest first"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("Settings")
                        .font(.system(size: 56, weight: .bold))
                        .padding(.horizontal, 60).padding(.top, 40)

                    section("Account") {
                        if auth.isSignedIn {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(auth.email ?? "Signed in")
                                    .font(.system(size: 24)).foregroundStyle(.white.opacity(0.85))
                                Text("\(auth.addons.count) add-ons · \(auth.addons.filter { $0.hasStream }.count) stream sources")
                                    .font(.system(size: 19)).foregroundStyle(.white.opacity(0.5))
                                Button("Sign Out", role: .destructive) { auth.logout() }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Text("Sign in on the Account tab to load your add-ons, catalogs and Continue Watching.")
                                .font(.system(size: 21)).foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    section("Playback") {
                        row("Video Size") { chips(videoSizes, sel: videoSize) { videoSize = $0 } }
                        row("Default Speed") {
                            chips(SubtitleStyle.speeds.map { .init(id: String($0), label: $0 == 1 ? "Normal" : "\($0.clean)x") },
                                  sel: String(defaultSpeed)) { defaultSpeed = Double($0) ?? 1.0 }
                        }
                        row("Skip Step") {
                            chips(SubtitleStyle.seekSteps.map { .init(id: String($0), label: "\($0)s") },
                                  sel: String(seekStep)) { seekStep = Int($0) ?? 10 }
                        }
                    }

                    section("Subtitles") {
                        row("Size") { chips(SubtitleStyle.sizes, sel: subSize) { subSize = $0 } }
                        row("Colour") { chips(SubtitleStyle.colors, sel: subColor) { subColor = $0 } }
                        row("Style") { chips(SubtitleStyle.styles, sel: subStyle) { subStyle = $0 } }
                        row("Bold") { toggle(subBold) { subBold.toggle() } }
                        row("Preferred Language") { chips(SubtitleStyle.languages, sel: subLang) { subLang = $0 } }
                        row("Off by Default") { toggle(subsOff) { subsOff.toggle() } }
                    }

                    section("Audio") {
                        row("Preferred Language") { chips(SubtitleStyle.languages, sel: audioLang) { audioLang = $0 } }
                        row("Normalize Loudness") { toggle(audioNormalize) { audioNormalize.toggle() } }
                    }

                    section("Episodes") {
                        row("Order") { chips(sortOptions, sel: episodeSort) { episodeSort = $0 } }
                        row("Show Descriptions") { toggle(showEpisodeDesc) { showEpisodeDesc.toggle() } }
                    }

                    Text("Harbor for Apple TV — settings apply on next playback")
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 60).padding(.top, 8)
                }
                .padding(.bottom, 80)
            }
        }
    }

    // MARK: - building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
            content()
        }
        .padding(.horizontal, 60)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 30) {
            Text(label).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 340, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }

    private func chips(_ options: [SubtitleStyle.Preset], sel: String, _ pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 14) {
            ForEach(options) { o in
                Button(o.label) { pick(o.id) }
                    .buttonStyle(.bordered)
                    .tint(sel == o.id ? .green : .gray)
            }
        }
    }

    private func toggle(_ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(on ? "On" : "Off") { act() }
            .buttonStyle(.bordered)
            .tint(on ? .green : .gray)
    }
}

private extension Double {
    // "1.5" not "1.50", "0.75" as-is — for speed chip labels.
    var clean: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}
