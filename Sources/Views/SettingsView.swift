import SwiftUI

// Settings mirroring the Harbor iPhone app's structure: a category list (one pane
// at a time, same names and order as the phone shell) that pushes detail panels.
// Only the categories that exist in the native tvOS build are shown; each option
// keeps Harbor's naming. Values live in UserDefaults under SubtitleStyle.Key and
// are read live by the player / episode list.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AccountPanel() } label: {
                        row("Account", icon: "person.crop.circle")
                    }
                    NavigationLink { LibraryPanel() } label: {
                        row("Library & metadata", icon: "books.vertical")
                    }
                }
                Section {
                    NavigationLink { PlayerPanel() } label: {
                        row("Player & quality", icon: "play.rectangle")
                    }
                    NavigationLink { LanguagesPanel() } label: {
                        row("Languages", icon: "globe")
                    }
                }
                Section {
                    NavigationLink { AboutPanel() } label: {
                        row("Advanced", icon: "wrench.and.screwdriver")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func row(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.system(size: 28))
            .padding(.vertical, 8)
    }
}

// MARK: - Account

private struct AccountPanel: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        List {
            if auth.isSignedIn {
                Section("Stremio account") {
                    LabeledContent("Signed in as", value: auth.email ?? "—")
                    LabeledContent("Add-ons", value: "\(auth.addons.count)")
                    LabeledContent("Stream sources", value: "\(auth.addons.filter { $0.hasStream }.count)")
                }
                Section {
                    Button("Sign Out", role: .destructive) { auth.logout() }
                }
            } else {
                Section {
                    Text("Sign in on the Account tab to load your add-ons, catalogs and Continue Watching.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Account")
    }
}

// MARK: - Library & metadata

private struct LibraryPanel: View {
    @AppStorage(SubtitleStyle.Key.episodeSort) private var episodeSort = "oldest"
    @AppStorage(SubtitleStyle.Key.showEpisodeDesc) private var showEpisodeDesc = true

    var body: some View {
        List {
            Section("Episodes") {
                Picker("Episode order", selection: $episodeSort) {
                    Text("Oldest first").tag("oldest")
                    Text("Newest first").tag("newest")
                }
                Toggle("Show episode descriptions", isOn: $showEpisodeDesc)
            }
        }
        .navigationTitle("Library & metadata")
    }
}

// MARK: - Player & quality

private struct PlayerPanel: View {
    @AppStorage(SubtitleStyle.Key.videoSize) private var videoSize = "original"
    @AppStorage(SubtitleStyle.Key.defaultSpeed) private var defaultSpeed = 1.0
    @AppStorage(SubtitleStyle.Key.seekStep) private var seekStep = 10
    @AppStorage(SubtitleStyle.Key.audioNormalize) private var audioNormalize = false

    var body: some View {
        List {
            Section("Aspect ratio") {
                Picker("Video size", selection: $videoSize) {
                    Text("Fit").tag("original")
                    Text("Fill").tag("fill")
                    Text("Stretch").tag("stretch")
                }
            }
            Section("Playback") {
                Picker("Default speed", selection: $defaultSpeed) {
                    ForEach(SubtitleStyle.speeds, id: \.self) { s in
                        Text(s == 1.0 ? "Normal" : String(format: "%gx", s)).tag(s)
                    }
                }
                Picker("Skip step", selection: $seekStep) {
                    ForEach(SubtitleStyle.seekSteps, id: \.self) { s in
                        Text("\(s) seconds").tag(s)
                    }
                }
            }
            Section {
                Toggle("Normalize loudness", isOn: $audioNormalize)
            } header: {
                Text("Audio")
            } footer: {
                Text("Evens out quiet dialogue and loud action. Applies on next playback.")
            }
        }
        .navigationTitle("Player & quality")
    }
}

// MARK: - Languages (audio/sub preferences + subtitle style, like Harbor)

private struct LanguagesPanel: View {
    @AppStorage(SubtitleStyle.Key.audioLang) private var audioLang = ""
    @AppStorage(SubtitleStyle.Key.subLang) private var subLang = ""
    @AppStorage(SubtitleStyle.Key.subsOff) private var subsOff = false
    @AppStorage(SubtitleStyle.Key.size) private var subSize = SubtitleStyle.defaultSize
    @AppStorage(SubtitleStyle.Key.color) private var subColor = SubtitleStyle.defaultColor
    @AppStorage(SubtitleStyle.Key.style) private var subStyle = SubtitleStyle.defaultStyle
    @AppStorage(SubtitleStyle.Key.bold) private var subBold = false

    var body: some View {
        List {
            Section("Preferred languages") {
                Picker("Audio language", selection: $audioLang) {
                    ForEach(SubtitleStyle.languages) { l in Text(l.label).tag(l.id) }
                }
                Picker("Subtitle language", selection: $subLang) {
                    ForEach(SubtitleStyle.languages) { l in Text(l.label).tag(l.id) }
                }
                Toggle("Subtitles off by default", isOn: $subsOff)
            }
            Section {
                Picker("Size", selection: $subSize) {
                    ForEach(SubtitleStyle.sizes) { s in Text(s.label).tag(s.id) }
                }
                Picker("Text color", selection: $subColor) {
                    ForEach(SubtitleStyle.colors) { c in Text(c.label).tag(c.id) }
                }
                Picker("Style", selection: $subStyle) {
                    ForEach(SubtitleStyle.styles) { s in Text(s.label).tag(s.id) }
                }
                Toggle("Bold", isOn: $subBold)
            } header: {
                Text("Subtitle style")
            } footer: {
                Text("Style changes apply on next playback, or immediately via the player's subtitle menu.")
            }
        }
        .navigationTitle("Languages")
    }
}

// MARK: - Advanced / about

private struct AboutPanel: View {
    var body: some View {
        List {
            Section("About") {
                LabeledContent("App", value: "Harbor for Apple TV")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Player", value: "mpv (MPVKit)")
            }
        }
        .navigationTitle("Advanced")
    }
}
