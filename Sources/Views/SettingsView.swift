import Foundation
import SwiftUI

// Native tvOS counterpart of Harbor's settings shell. The category order follows
// desktop/Android, while desktop-only window, tray and keyboard sections are omitted.
// Every control in this file is backed by a consumer in the tvOS UI, stream picker or mpv.
struct SettingsView: View {
    var onRootBack: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { GetStartedPanel() } label: {
                        settingsRow("Get started", icon: "safari")
                    }
                }

                Section("Account") {
                    NavigationLink { AccountPanel() } label: {
                        settingsRow("Account", icon: "person.crop.circle")
                    }
                    NavigationLink { LibraryPanel() } label: {
                        settingsRow("Library & metadata", icon: "books.vertical")
                    }
                    NavigationLink { AddonIntegrationPanel(service: "Trakt", aliases: ["trakt"]) } label: {
                        settingsRow("Trakt", icon: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink { AddonIntegrationPanel(service: "AniList", aliases: ["anilist"]) } label: {
                        settingsRow("AniList", icon: "a.square")
                    }
                    NavigationLink { AddonIntegrationPanel(service: "MyAnimeList", aliases: ["myanimelist", "mal"]) } label: {
                        settingsRow("MyAnimeList", icon: "m.square")
                    }
                    NavigationLink { AddonIntegrationPanel(service: "Simkl", aliases: ["simkl"]) } label: {
                        settingsRow("Simkl", icon: "s.square")
                    }
                    NavigationLink { AddonIntegrationPanel(service: "Letterboxd", aliases: ["letterboxd", "stremboxd"]) } label: {
                        settingsRow("Letterboxd", icon: "ellipsis")
                    }
                }

                Section("Streaming") {
                    NavigationLink { RelayPanel() } label: {
                        settingsRow("Harbor Relay", icon: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink { StreamingSourcesPanel() } label: {
                        settingsRow("Streaming sources", icon: "play.square.stack")
                    }
                    NavigationLink { StreamFiltersPanel() } label: {
                        settingsRow("Stream filters", icon: "line.3.horizontal.decrease.circle")
                    }
                    NavigationLink { P2PPanel() } label: {
                        settingsRow("P2P & servers", icon: "server.rack")
                    }
                }

                Section("Playback") {
                    NavigationLink { PlayerPanel() } label: {
                        settingsRow("Player & quality", icon: "play.rectangle")
                    }
                    NavigationLink { VideoTuningPanel() } label: {
                        settingsRow("Video tuning", icon: "slider.horizontal.3")
                    }
                    NavigationLink { AnimePanel() } label: {
                        settingsRow("Anime tweaks", icon: "sparkles")
                    }
                    NavigationLink { PlayerLayoutPanel() } label: {
                        settingsRow("Player layout", icon: "rectangle.bottomthird.inset.filled")
                    }
                    NavigationLink { LanguagesPanel() } label: {
                        settingsRow("Languages", icon: "globe")
                    }
                }

                Section("Appearance") {
                    NavigationLink { ThemePanel() } label: {
                        settingsRow("Theme & appearance", icon: "paintpalette")
                    }
                }

                Section("System") {
                    NavigationLink { AdvancedPanel() } label: {
                        settingsRow("Advanced", icon: "wrench.and.screwdriver")
                    }
                }
            }
            .navigationTitle("Settings")
            .onExitCommand(perform: onRootBack)
        }
    }
}

private func settingsRow(_ label: String, icon: String) -> some View {
    Label(label, systemImage: icon)
        .font(.system(size: 28))
        .padding(.vertical, 8)
}

private struct SettingsHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 19))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Get started

private struct GetStartedPanel: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage(SubtitleStyle.Key.instantPlay) private var instantPlay = true
    @AppStorage(SubtitleStyle.Key.videoSize) private var videoSize = "original"
    @AppStorage(SubtitleStyle.Key.accent) private var accent = "green"

    var body: some View {
        List {
            Section("Account") {
                if auth.isSignedIn {
                    LabeledContent("Signed in as", value: auth.email ?? "—")
                    LabeledContent("Ready stream sources", value: "\(auth.addons.filter { $0.hasStream }.count)")
                } else {
                    NavigationLink("Sign in to Stremio") { LoginView() }
                    SettingsHint("Sign in once to sync your add-ons, library and Continue Watching.")
                }
            }
            Section("Play button behavior") {
                Picker("When Play is pressed", selection: $instantPlay) {
                    Text("Start the best stream").tag(true)
                    Text("Always show sources").tag(false)
                }
            }
            Section("Picture") {
                Picker("Aspect ratio", selection: $videoSize) {
                    ForEach(HarborSettings.videoSizes) { Text($0.label).tag($0.id) }
                }
            }
            Section("Look") {
                Picker("Accent", selection: $accent) {
                    ForEach(HarborSettings.accents) { Text($0.label).tag($0.id) }
                }
            }
        }
        .navigationTitle("Get started")
    }
}

// MARK: - Account

private struct AccountPanel: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var refreshing = false

    var body: some View {
        List {
            if auth.isSignedIn {
                Section("Stremio account") {
                    LabeledContent("Signed in as", value: auth.email ?? "—")
                    LabeledContent("Add-ons", value: "\(auth.addons.count)")
                    LabeledContent("Stream sources", value: "\(auth.addons.filter { $0.hasStream }.count)")
                    Button {
                        refreshing = true
                        Task { await auth.refreshAccountData(); refreshing = false }
                    } label: {
                        Label(refreshing ? "Refreshing…" : "Refresh account data", systemImage: "arrow.clockwise")
                    }
                    .disabled(refreshing)
                }
                Section {
                    Button("Sign Out", role: .destructive) { auth.logout() }
                }
            } else {
                Section {
                    NavigationLink("Sign in to Stremio") { LoginView() }
                    SettingsHint("Harbor stores the session token on this Apple TV; your password is sent only to Stremio during sign-in.")
                }
            }
        }
        .navigationTitle("Account")
    }
}

private struct AddonIntegrationPanel: View {
    @EnvironmentObject private var auth: AuthStore
    let service: String
    let aliases: [String]

    private var matches: [Addon] {
        auth.addons.filter { addon in
            let value = [addon.manifest?.id, addon.manifest?.name, addon.transportUrl]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            return aliases.contains(where: { value.contains($0) })
        }
    }

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Status", value: matches.isEmpty ? "Not connected" : "Connected")
                ForEach(matches, id: \.transportUrl) { addon in
                    Label(addon.manifest?.name ?? service, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                NavigationLink("Manage Stremio add-ons") { AddonsView() }
            }
            Section("How it works on Apple TV") {
                SettingsHint("Harbor uses the account-enabled \(service) provider exposed through your synced Stremio add-ons. Connect or configure it once in Harbor desktop or its add-on page, then refresh Account on Apple TV.")
            }
        }
        .navigationTitle(service)
    }
}

private struct RelayPanel: View {
    @AppStorage("harbor.relay.url") private var relayURL = "https://harbor.site"
    @AppStorage("harbor.relay.nickname") private var nickname = "Apple TV"
    @State private var result: String?

    var body: some View {
        List {
            Section("Harbor Relay") {
                TextField("Relay URL", text: $relayURL)
                    .textContentType(.URL)
                TextField("Display name", text: $nickname)
                Button("Test relay") {
                    result = nil
                    Task {
                        guard let url = URL(string: relayURL) else { result = "Invalid URL"; return }
                        var request = URLRequest(url: url); request.httpMethod = "HEAD"
                        do {
                            let (_, rawResponse) = try await URLSession.shared.data(for: request)
                            let response = rawResponse as? HTTPURLResponse
                            result = response.map { (200..<500).contains($0.statusCode) ? "Reachable" : "Unavailable" } ?? "Unavailable"
                        } catch {
                            result = "Unavailable"
                        }
                    }
                }
                if let result { LabeledContent("Status", value: result) }
            }
            Section {
                SettingsHint("Relay connection details are shared by Harbor's Watch Together workflow. Playback itself never depends on Relay.")
            }
        }
        .navigationTitle("Harbor Relay")
    }
}

// MARK: - Library & metadata

private struct LibraryPanel: View {
    @AppStorage(SubtitleStyle.Key.episodeLayout) private var episodeLayout = "list"
    @AppStorage(SubtitleStyle.Key.episodeSort) private var episodeSort = "aired"
    @AppStorage(SubtitleStyle.Key.showEpisodeDesc) private var showEpisodeDesc = true
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false
    @AppStorage(SubtitleStyle.Key.libraryBookmarkedOnly) private var bookmarkedOnly = true
    @AppStorage(SubtitleStyle.Key.librarySort) private var librarySort = "recent"
    @AppStorage(SubtitleStyle.Key.homeShowAllRows) private var showAllRows = false
    @AppStorage(SubtitleStyle.Key.hideSpoilers) private var hideSpoilers = false
    @AppStorage(SubtitleStyle.Key.spoilerThumbnails) private var spoilerThumbnails = true

    var body: some View {
        List {
            Section("Home layout") {
                Toggle("Show every add-on catalog", isOn: $showAllRows)
                Toggle("Hide watched titles in catalogs", isOn: $hideWatched)
                Toggle("Hide unreleased titles", isOn: $hideUnreleased)
            }
            Section("Library") {
                Toggle("Only show bookmarked titles", isOn: $bookmarkedOnly)
                Picker("Sort", selection: $librarySort) {
                    Text("Recently updated").tag("recent")
                    Text("Title").tag("title")
                    Text("Year").tag("year")
                }
            }
            Section("Episodes") {
                Picker("Layout", selection: $episodeLayout) {
                    Text("List").tag("list")
                    Text("Strip").tag("strip")
                }
                Picker("Episode order", selection: $episodeSort) {
                    Text("Aired order").tag("aired")
                    Text("Absolute order").tag("absolute")
                    Text("Newest first").tag("newest")
                }
                SettingsHint("Absolute order combines every regular season into one continuous release sequence.")
                Toggle("Show episode descriptions", isOn: $showEpisodeDesc)
            }
            Section("Spoilers") {
                Toggle("Hide spoilers", isOn: $hideSpoilers)
                if hideSpoilers {
                    Toggle("Blur episode thumbnails", isOn: $spoilerThumbnails)
                }
            }
        }
        .navigationTitle("Library & metadata")
    }
}

// MARK: - Streaming

private struct StreamingSourcesPanel: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage(SubtitleStyle.Key.instantPlay) private var instantPlay = true
    @AppStorage(SubtitleStyle.Key.rememberStream) private var rememberStream = true
    @AppStorage(SubtitleStyle.Key.streamSort) private var streamSort = "harbor"
    @AppStorage(SubtitleStyle.Key.fullStreamDescription) private var fullDescription = true
    @AppStorage(SubtitleStyle.Key.pickerShowFilename) private var showFilename = false
    @AppStorage(SubtitleStyle.Key.bandwidthMbps) private var bandwidth = 0.0

    var body: some View {
        List {
            Section("Play button behavior") {
                Picker("When Play is pressed", selection: $instantPlay) {
                    Text("Start the best stream").tag(true)
                    Text("Show source picker").tag(false)
                }
                Toggle("Remember the last source", isOn: $rememberStream)
            }
            Section("Source picker") {
                Picker("Result order", selection: $streamSort) {
                    Text("Harbor ranking").tag("harbor")
                    Text("Add-on order").tag("addon")
                }
                Toggle("Show full stream descriptions", isOn: $fullDescription)
                Toggle("Show filenames", isOn: $showFilename)
            }
            Section("Internet speed") {
                Picker("Bandwidth limit", selection: $bandwidth) {
                    Text("Automatic").tag(0.0)
                    Text("25 Mbps").tag(25.0)
                    Text("50 Mbps").tag(50.0)
                    Text("100 Mbps").tag(100.0)
                    Text("250 Mbps").tag(250.0)
                    Text("1 Gbps").tag(1000.0)
                }
            }
            Section("Installed Stremio add-ons") {
                LabeledContent("Available", value: "\(auth.addons.count)")
                LabeledContent("Provide streams", value: "\(auth.addons.filter { $0.hasStream }.count)")
                NavigationLink("View installed add-ons") { AddonsView() }
                SettingsHint("Install add-ons by manifest URL on the Add-ons screen. Configure debrid services in the add-on first; Harbor then uses the synced configuration directly.")
            }
        }
        .navigationTitle("Streaming sources")
    }
}

private struct StreamFiltersPanel: View {
    @AppStorage(SubtitleStyle.Key.streamFilter) private var filter = "strict"

    var body: some View {
        List {
            Section("Stream safety filter") {
                Picker("Filter level", selection: $filter) {
                    ForEach(HarborSettings.streamFilters) { Text($0.label).tag($0.id) }
                }
                if let choice = HarborSettings.streamFilters.first(where: { $0.id == filter }) {
                    SettingsHint(choice.detail)
                }
            }
            Section("Unsupported sources") {
                SettingsHint("Apple TV plays direct HTTP, HTTPS, HLS and debrid links. Raw magnet and torrent-only results stay visible but disabled so the source list remains honest.")
            }
        }
        .navigationTitle("Stream filters")
    }
}

private struct P2PPanel: View {
    @AppStorage(SubtitleStyle.Key.torrServerEnabled) private var enabled = false
    @AppStorage(SubtitleStyle.Key.torrServerURL) private var serverURL = "http://192.168.1.10:8090"
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        List {
            Section("TorrServer") {
                Toggle("Enable P2P through TorrServer", isOn: $enabled)
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .disabled(!enabled)
                Button(testing ? "Testing…" : "Test connection") {
                    testing = true; testResult = nil
                    Task {
                        let okay = await TorrServerService.ping()
                        await MainActor.run {
                            testing = false
                            testResult = okay ? "Connected" : "Couldn't reach TorrServer"
                        }
                    }
                }
                .disabled(!enabled || testing)
                if let testResult {
                    LabeledContent("Status", value: testResult)
                }
            }
            Section("Apple TV P2P") {
                SettingsHint("Apple TV cannot run a torrent engine locally. Harbor sends magnet sources to TorrServer on your computer, NAS or Raspberry Pi, selects the matching episode, then plays its HTTP stream through mpv. Debrid/direct sources remain preferred.")
            }
        }
        .navigationTitle("P2P & servers")
    }
}

// MARK: - Player & quality

private struct PlayerPanel: View {
    @AppStorage(SubtitleStyle.Key.playerEngine) private var playerEngine = "auto"
    @AppStorage(SubtitleStyle.Key.videoSize) private var videoSize = "original"
    @AppStorage(SubtitleStyle.Key.defaultSpeed) private var defaultSpeed = 1.0
    @AppStorage(SubtitleStyle.Key.seekBackStep) private var seekBack = 10
    @AppStorage(SubtitleStyle.Key.seekForwardStep) private var seekForward = 10
    @AppStorage(SubtitleStyle.Key.resume) private var resume = true
    @AppStorage(SubtitleStyle.Key.autoPlayNext) private var autoPlayNext = true
    @AppStorage(SubtitleStyle.Key.audioNormalize) private var audioNormalize = false
    @AppStorage(SubtitleStyle.Key.audioProfile) private var audioProfile = "off"
    @AppStorage(SubtitleStyle.Key.confirmLeave) private var confirmLeave = true
    @AppStorage(SubtitleStyle.Key.mpvHWDec) private var hwdec = "auto"
    @AppStorage(SubtitleStyle.Key.showSkipButton) private var showSkipButton = true
    @AppStorage(SubtitleStyle.Key.autoSkipIntro) private var autoSkipIntro = false
    @AppStorage(SubtitleStyle.Key.autoSkipRecap) private var autoSkipRecap = false
    @AppStorage(SubtitleStyle.Key.autoSkipOutro) private var autoSkipOutro = false
    @AppStorage(SubtitleStyle.Key.skipButtonHideSec) private var skipButtonHideSec = 10
    @AppStorage(SubtitleStyle.Key.nextEpisodeLeadSec) private var nextEpisodeLeadSec = -1

    var body: some View {
        List {
            Section("Player engine") {
                Picker("Preferred engine", selection: $playerEngine) {
                    Text("Auto · MPV recommended").tag("auto")
                    Text("MPV · best features").tag("mpv")
                    Text("VLC · compatibility fallback").tag("vlc")
                }
                LabeledContent("Active on next video", value: engineLabel)
                LabeledContent("Hardware video decode", value: hwdec == "off" ? "Software" : "VideoToolbox")
                SettingsHint(playerEngine == "vlc"
                    ? "VLC is useful for streams that stutter or fail in MPV. VLC manages its own subtitle rendering; Anime4K and Harbor's advanced subtitle styling remain MPV-only."
                    : "MPV provides Harbor's complete feature set: Anime4K, detailed subtitle styling, chapters and the tvOS 26 HDMI audio path. Auto currently prefers MPV.")
            }
            Section("Aspect ratio") {
                Picker("Video size", selection: $videoSize) {
                    ForEach(HarborSettings.videoSizes) { Text($0.label).tag($0.id) }
                }
            }
            Section("Playback") {
                Toggle("Resume playback", isOn: $resume)
                Toggle("Confirm before leaving playback", isOn: $confirmLeave)
                Picker("Default speed", selection: $defaultSpeed) {
                    ForEach(SubtitleStyle.speeds, id: \.self) { speed in
                        Text(speed == 1.0 ? "Normal" : String(format: "%gx", speed)).tag(speed)
                    }
                }
                Picker("Skip backward", selection: $seekBack) {
                    ForEach(SubtitleStyle.seekSteps, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("Skip forward", selection: $seekForward) {
                    ForEach(SubtitleStyle.seekSteps, id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }
            Section("Audio") {
                Toggle("Normalize loudness", isOn: $audioNormalize)
                Picker("Audio profile", selection: $audioProfile) {
                    ForEach(HarborSettings.audioProfiles) { Text($0.label).tag($0.id) }
                }
                SettingsHint("Audio filters apply when the next video starts.")
            }
            Section("Skip intros & credits") {
                Toggle("Show the Skip button", isOn: $showSkipButton)
                Toggle("Auto-skip intros", isOn: $autoSkipIntro)
                Toggle("Auto-skip recaps", isOn: $autoSkipRecap)
                Toggle("Auto-skip credit outros", isOn: $autoSkipOutro)
                if showSkipButton {
                    Picker("Auto-hide Skip button", selection: $skipButtonHideSec) {
                        Text("Off").tag(0)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                    }
                }
                SettingsHint("Harbor combines AniSkip, TheIntroDB and named chapters in the video. Auto-skip runs once per segment; seeking back lets it play normally.")
            }
            Section("Next episode prompt") {
                Picker("Show Up Next", selection: $nextEpisodeLeadSec) {
                    Text("Automatic").tag(-1)
                    Text("Off").tag(0)
                    Text("30 seconds before end").tag(30)
                    Text("45 seconds before end").tag(45)
                    Text("1 minute before end").tag(60)
                    Text("1.5 minutes before end").tag(90)
                    Text("2 minutes before end").tag(120)
                }
                Toggle("Auto-play next episode", isOn: $autoPlayNext)
            }
        }
        .navigationTitle("Player & quality")
    }

    private var engineLabel: String {
        switch playerEngine {
        case "vlc": return "VLC · TVVLCKit"
        case "mpv": return "MPV · MPVKit"
        default: return "Auto · MPV"
        }
    }
}

private struct VideoTuningPanel: View {
    @AppStorage(SubtitleStyle.Key.mpvQuality) private var quality = "balanced"
    @AppStorage(SubtitleStyle.Key.mpvHWDec) private var hwdec = "auto"
    @AppStorage(SubtitleStyle.Key.mpvBufferBoost) private var bufferBoost = false
    @AppStorage(SubtitleStyle.Key.mpvDownmix) private var downmix = false
    @AppStorage(SubtitleStyle.Key.brightness) private var brightness = 0.0
    @AppStorage(SubtitleStyle.Key.contrast) private var contrast = 0.0
    @AppStorage(SubtitleStyle.Key.saturation) private var saturation = 0.0
    @AppStorage(SubtitleStyle.Key.gamma) private var gamma = 0.0
    @AppStorage(SubtitleStyle.Key.toneMapping) private var toneMapping = "auto"
    @AppStorage(SubtitleStyle.Key.motionInterpolation) private var motionInterpolation = false

    var body: some View {
        List {
            Section("Picture quality") {
                Picker("Preset", selection: $quality) {
                    ForEach(HarborSettings.qualityPresets) { Text($0.label).tag($0.id) }
                }
                Picker("Hardware acceleration", selection: $hwdec) {
                    ForEach(HarborSettings.hwdecModes) { Text($0.label).tag($0.id) }
                }
            }
            Section("Picture adjustments") {
                valuePicker("Brightness", value: $brightness)
                valuePicker("Contrast", value: $contrast)
                valuePicker("Saturation", value: $saturation)
                valuePicker("Gamma", value: $gamma)
                Button("Reset picture adjustments") {
                    brightness = 0; contrast = 0; saturation = 0; gamma = 0
                }
            }
            Section("Color & HDR") {
                Picker("Tone mapping", selection: $toneMapping) {
                    ForEach(HarborSettings.toneMapModes) { Text($0.label).tag($0.id) }
                }
            }
            Section("Motion") {
                Toggle("Smooth motion", isOn: $motionInterpolation)
                SettingsHint("Uses display-resample interpolation in mpv. It is not SVP frame generation and can increase GPU usage.")
            }
            Section("Connection & audio") {
                Toggle("Bigger buffer for unstable Wi-Fi", isOn: $bufferBoost)
                Toggle("Downmix surround to stereo", isOn: $downmix)
            }
        }
        .navigationTitle("Video tuning")
    }

    private func valuePicker(_ label: String, value: Binding<Double>) -> some View {
        Picker(label, selection: value) {
            ForEach([-20.0, -10.0, -5.0, 0.0, 5.0, 10.0, 20.0], id: \.self) { option in
                Text(String(format: "%+.0f", option)).tag(option)
            }
        }
    }
}

private struct AnimePanel: View {
    @AppStorage(SubtitleStyle.Key.anime4KEnabled) private var enabled = false
    @AppStorage(SubtitleStyle.Key.anime4KAnimeOnly) private var animeOnly = true
    @AppStorage(SubtitleStyle.Key.anime4KIndicator) private var indicator = true
    @AppStorage(SubtitleStyle.Key.anime4KMode) private var mode = "A"
    @AppStorage(SubtitleStyle.Key.anime4KTier) private var tier = "fast"

    private var shaderCount: Int {
        let nested = Bundle.main.urls(forResourcesWithExtension: "glsl", subdirectory: "Anime4K") ?? []
        let root = Bundle.main.urls(forResourcesWithExtension: "glsl", subdirectory: nil) ?? []
        return Set(nested + root).count
    }

    var body: some View {
        List {
            Section("Anime4K upscaling") {
                Toggle("Enable Anime4K", isOn: $enabled)
                    .disabled(shaderCount < 15)
                Toggle("Apply to anime only", isOn: $animeOnly)
                    .disabled(!enabled)
                Toggle("Show Anime4K indicator", isOn: $indicator)
                    .disabled(!enabled)
                LabeledContent("Bundled shaders", value: shaderCount >= 15 ? "15 ready" : "\(shaderCount)/15")
                if shaderCount < 15 {
                    SettingsHint("This build does not contain the Anime4K shader pack. The release workflow bundles it automatically.")
                }
            }
            Section("Anime4K presets") {
                Picker("Mode", selection: $mode) {
                    ForEach(HarborSettings.animeModes) { Text($0.label).tag($0.id) }
                }
                Picker("GPU tier", selection: $tier) {
                    ForEach(HarborSettings.animeTiers) { Text($0.label).tag($0.id) }
                }
                if let choice = HarborSettings.animeTiers.first(where: { $0.id == tier }) {
                    SettingsHint(choice.detail)
                }
                SettingsHint("Anime4K uses a dedicated GPU pipeline. Smooth motion and expensive mpv scaling are suspended while it is active so the Apple TV can spend its frame budget on the Anime4K shaders.")
            }
        }
        .navigationTitle("Anime tweaks")
    }
}

private struct PlayerLayoutPanel: View {
    @AppStorage(SubtitleStyle.Key.controlsHideSeconds) private var hideSeconds = 5
    @AppStorage(SubtitleStyle.Key.showQualityInfo) private var showQuality = true
    @AppStorage(SubtitleStyle.Key.playerTitleScale) private var titleScale = 1.0
    @AppStorage(SubtitleStyle.Key.showRestartButton) private var showStop = true
    @AppStorage(SubtitleStyle.Key.showSeekButtons) private var showSeek = true
    @AppStorage(SubtitleStyle.Key.showNextButton) private var showNext = true
    @AppStorage(SubtitleStyle.Key.showSpeedButton) private var showSpeed = true
    @AppStorage(SubtitleStyle.Key.showSubtitleButton) private var showSubtitles = true
    @AppStorage(SubtitleStyle.Key.showAudioButton) private var showAudio = true
    @AppStorage(SubtitleStyle.Key.showAspectButton) private var showAspect = true
    @AppStorage(SubtitleStyle.Key.showAnimeButton) private var showAnime = true

    var body: some View {
        List {
            Section("Controls") {
                Picker("Hide controls after", selection: $hideSeconds) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("8 seconds").tag(8)
                    Text("Never").tag(0)
                }
                Toggle("Show codec and quality info", isOn: $showQuality)
            }
            Section("Title text") {
                Picker("Player title size", selection: $titleScale) {
                    Text("Small").tag(0.85)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.2)
                }
            }
            Section("Transport buttons") {
                Toggle("Stop", isOn: $showStop)
                Toggle("Skip backward / forward", isOn: $showSeek)
                Toggle("Next episode", isOn: $showNext)
            }
            Section("Utility buttons") {
                Toggle("Playback speed", isOn: $showSpeed)
                Toggle("Subtitles", isOn: $showSubtitles)
                Toggle("Audio tracks", isOn: $showAudio)
                Toggle("Aspect ratio", isOn: $showAspect)
                Toggle("Anime4K", isOn: $showAnime)
            }
            Section {
                SettingsHint("The Apple TV layout follows Harbor desktop: transport controls on the left, speed/subtitle/audio and picture tools on the right, with the timeline below. Siri Remote navigation replaces desktop hotkeys.")
            }
        }
        .navigationTitle("Player layout")
    }
}

// MARK: - Languages

private struct LanguagesPanel: View {
    @AppStorage(SubtitleStyle.Key.audioLang) private var audioLang = ""
    @AppStorage(SubtitleStyle.Key.subLang) private var subLang = ""
    @AppStorage(SubtitleStyle.Key.secondarySubLang) private var secondarySubLang = ""
    @AppStorage(SubtitleStyle.Key.subsOff) private var subsOff = false
    @AppStorage(SubtitleStyle.Key.preferEmbedded) private var preferEmbedded = false
    @AppStorage(SubtitleStyle.Key.preferForcedSubs) private var preferForced = false
    @AppStorage(SubtitleStyle.Key.style) private var subStyle = SubtitleStyle.defaultStyle
    @AppStorage(SubtitleStyle.Key.bold) private var subBold = false
    @AppStorage(SubtitleStyle.Key.borderSize) private var borderSize = 2.0
    @AppStorage(SubtitleStyle.Key.margin) private var margin = 12.0
    @AppStorage(SubtitleStyle.Key.opacity) private var opacity = 1.0
    @AppStorage(SubtitleStyle.Key.alignment) private var alignment = "center"
    @AppStorage(SubtitleStyle.Key.font) private var font = "inter"
    @AppStorage(SubtitleStyle.Key.fontSize) private var fontSize = SubtitleStyle.defaultFontSize
    @AppStorage(SubtitleStyle.Key.fontColor) private var fontColor = SubtitleStyle.defaultFontColor
    @AppStorage(SubtitleStyle.Key.borderColor) private var borderColor = SubtitleStyle.defaultBorderColor
    @AppStorage(SubtitleStyle.Key.boxColor) private var boxColor = SubtitleStyle.defaultBoxColor
    @AppStorage(SubtitleStyle.Key.boxOpacity) private var boxOpacity = 0.6
    @AppStorage(SubtitleStyle.Key.assOverride) private var assOverride = "no"
    @AppStorage(SubtitleStyle.Key.lineSpacing) private var lineSpacing = 0.0

    var body: some View {
        List {
            Section("Playback languages") {
                NavigationLink {
                    LanguageSelectionPanel(
                        title: "Audio language",
                        explanation: "Harbor selects this spoken language when a matching audio track is available.",
                        selection: $audioLang)
                } label: {
                    LanguagePreferenceRow(
                        icon: "waveform",
                        title: "Audio language",
                        detail: "Preferred spoken track",
                        selected: languageLabel(audioLang))
                }
                NavigationLink {
                    LanguageSelectionPanel(
                        title: "Primary subtitles",
                        explanation: "This is the first subtitle language Harbor tries for every stream.",
                        selection: $subLang)
                } label: {
                    LanguagePreferenceRow(
                        icon: "captions.bubble",
                        title: "Primary subtitles",
                        detail: "First subtitle choice",
                        selected: languageLabel(subLang))
                }
                NavigationLink {
                    LanguageSelectionPanel(
                        title: "Fallback subtitles",
                        explanation: "Harbor tries this language when no primary-language subtitle is available.",
                        selection: $secondarySubLang)
                } label: {
                    LanguagePreferenceRow(
                        icon: "captions.bubble.fill",
                        title: "Fallback subtitles",
                        detail: "Used if the first choice is unavailable",
                        selected: languageLabel(secondarySubLang))
                }
                SettingsHint("Open a row to choose one language. “System / Auto” follows the stream and Apple TV language instead of forcing a specific track.")
            }
            Section("Subtitle behavior") {
                Toggle("Subtitles off by default", isOn: $subsOff)
                Toggle("Prefer embedded subtitles", isOn: $preferEmbedded)
                Toggle("Prefer forced / signs tracks", isOn: $preferForced)
            }
            Section("Live preview") {
                SubtitlePreviewCard(style: subStyle, fontSize: fontSize, bold: subBold,
                                    opacity: opacity, boxOpacity: boxOpacity,
                                    fontColor: fontColor, boxColor: boxColor)
            }
            Section("Subtitle style") {
                Picker("Background", selection: $subStyle) {
                    ForEach(SubtitleStyle.styles) { Text($0.label).tag($0.id) }
                }
                Picker("Styled (ASS) subtitles", selection: $assOverride) {
                    ForEach(SubtitleStyle.assOverrides) { Text($0.label).tag($0.id) }
                }
                if subStyle == "box" {
                    Picker("Background opacity", selection: $boxOpacity) {
                        ForEach(SubtitleStyle.opacities, id: \.self) { value in
                            Text("\(Int(value * 100))%").tag(value)
                        }
                    }
                }
                if subStyle == "outline" {
                    Picker("Outline thickness", selection: $borderSize) {
                        ForEach(SubtitleStyle.outlineSizes.dropFirst(), id: \.self) { value in
                            Text(String(format: "%.0f px", value)).tag(value)
                        }
                    }
                }
                Picker("Font", selection: $font) {
                    ForEach(SubtitleStyle.fonts) { Text($0.label).tag($0.id) }
                }
                Toggle("Bold text", isOn: $subBold)
                Picker("Size", selection: $fontSize) {
                    ForEach(SubtitleStyle.fontSizes, id: \.self) { value in
                        Text(String(format: "%.0f px", value)).tag(value)
                    }
                }
                Picker("Opacity", selection: $opacity) {
                    ForEach(SubtitleStyle.opacities, id: \.self) { value in
                        Text("\(Int(value * 100))%").tag(value)
                    }
                }
                Picker("Distance from bottom", selection: $margin) {
                    ForEach(SubtitleStyle.margins, id: \.self) { value in
                        Text(String(format: "%.0f%%", value)).tag(value)
                    }
                }
                Picker("Alignment", selection: $alignment) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                Picker("Line spacing", selection: $lineSpacing) {
                    ForEach(SubtitleStyle.lineSpacings, id: \.self) { value in
                        Text(String(format: "%+.0f px", value)).tag(value)
                    }
                }
            }
            Section("Subtitle colours") {
                Picker("Text color", selection: $fontColor) {
                    ForEach(SubtitleStyle.textColors) { Text($0.label).tag($0.id) }
                }
                Picker("Outline color", selection: $borderColor) {
                    ForEach(SubtitleStyle.edgeColors) { Text($0.label).tag($0.id) }
                }
                if subStyle == "box" {
                    Picker("Box color", selection: $boxColor) {
                        ForEach(SubtitleStyle.edgeColors) { Text($0.label).tag($0.id) }
                    }
                }
            }
            Section {
                Button("Reset subtitle appearance", role: .destructive) {
                    subStyle = SubtitleStyle.defaultStyle
                    assOverride = "no"
                    boxOpacity = 0.6
                    borderSize = 2
                    font = "inter"
                    subBold = false
                    fontSize = SubtitleStyle.defaultFontSize
                    opacity = 1
                    margin = 12
                    alignment = "center"
                    lineSpacing = 0
                    fontColor = SubtitleStyle.defaultFontColor
                    borderColor = SubtitleStyle.defaultBorderColor
                    boxColor = SubtitleStyle.defaultBoxColor
                }
            }
        }
        .navigationTitle("Languages")
    }

    private func languageLabel(_ id: String) -> String {
        SubtitleStyle.languages.first(where: { $0.id == id })?.label ?? "System / Auto"
    }
}

private struct LanguagePreferenceRow: View {
    let icon: String
    let title: String
    let detail: String
    let selected: String

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 42)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 27, weight: .semibold))
                Text(detail)
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 30)
            Text(selected)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
    }
}

private struct LanguageSelectionPanel: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let explanation: String
    @Binding var selection: String

    var body: some View {
        List {
            Section {
                SettingsHint(explanation)
            }
            Section("Choose language") {
                ForEach(SubtitleStyle.languages) { language in
                    Button {
                        selection = language.id
                        dismiss()
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: language.id.isEmpty ? "wand.and.stars" : "character.bubble")
                                .font(.system(size: 23, weight: .semibold))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.label)
                                    .font(.system(size: 27, weight: .semibold))
                                if language.id.isEmpty {
                                    Text("Let Apple TV and the stream decide")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(language.id.uppercased())
                                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selection == language.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28, weight: .semibold))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct SubtitlePreviewCard: View {
    let style: String
    let fontSize: Double
    let bold: Bool
    let opacity: Double
    let boxOpacity: Double
    let fontColor: String
    let boxColor: String

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.17, green: 0.22, blue: 0.29),
                                    Color(red: 0.04, green: 0.055, blue: 0.075)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 28) {
                Circle().fill(.white.opacity(0.14)).frame(width: 130, height: 130)
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.10))
                    .frame(width: 380, height: 120)
            }
            Text("I'm gonna make him an offer he can't refuse.")
                .font(.system(size: min(42, max(22, fontSize * 0.62)), weight: bold ? .bold : .semibold))
                .foregroundStyle(Color.harborHex(fontColor).opacity(opacity))
                .padding(.horizontal, 16).padding(.vertical, style == "box" ? 8 : 2)
                .background(style == "box" ? Color.harborHex(boxColor).opacity(boxOpacity) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(style == "shadow" ? 0.95 : 0.55), radius: style == "outline" ? 1 : 5,
                        x: style == "shadow" ? 3 : 0, y: style == "shadow" ? 3 : 0)
                .padding(.bottom, 32)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private extension Color {
    static func harborHex(_ value: String) -> Color {
        let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let number = UInt64(clean, radix: 16) else { return .white }
        return Color(red: Double((number >> 16) & 0xFF) / 255,
                     green: Double((number >> 8) & 0xFF) / 255,
                     blue: Double(number & 0xFF) / 255)
    }
}

// MARK: - Theme

private struct ThemePanel: View {
    @AppStorage(SubtitleStyle.Key.accent) private var accent = "green"
    @AppStorage(SubtitleStyle.Key.background) private var background = "harbor"
    @AppStorage(SubtitleStyle.Key.posterScale) private var posterScale = 1.0
    @AppStorage(SubtitleStyle.Key.posterRadius) private var posterRadius = 12.0
    @AppStorage(SubtitleStyle.Key.rowTitleScale) private var rowTitleScale = 1.0
    @AppStorage(SubtitleStyle.Key.reduceArtworkMotion) private var reduceMotion = false
    @AppStorage(SubtitleStyle.Key.interfaceStyle) private var interfaceStyle = "harbor"

    var body: some View {
        List {
            Section("Theme") {
                Picker("Interface style", selection: $interfaceStyle) {
                    Text("Harbor").tag("harbor")
                    Text("Midnight · Orivio Max").tag("max")
                    Text("Cinema · Orivio Netflix").tag("netflix")
                }
                Picker("Accent", selection: $accent) {
                    ForEach(HarborSettings.accents) { Text($0.label).tag($0.id) }
                }
                Picker("Background", selection: $background) {
                    Text("Harbor").tag("harbor")
                    Text("OLED black").tag("oled")
                    Text("System dark").tag("system")
                }
            }
            Section("Posters") {
                Picker("Poster size", selection: $posterScale) {
                    Text("Compact").tag(0.85)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                }
                Picker("Corner radius", selection: $posterRadius) {
                    Text("Square").tag(0.0)
                    Text("Soft").tag(12.0)
                    Text("Round").tag(24.0)
                }
                Picker("Row title size", selection: $rowTitleScale) {
                    Text("Small").tag(0.85)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.2)
                }
            }
            Section("Accessibility") {
                Toggle("Reduce artwork motion", isOn: $reduceMotion)
            }
        }
        .navigationTitle("Theme & appearance")
    }
}

// MARK: - Advanced

private struct AdvancedPanel: View {
    @State private var cacheMessage: String?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("Storage") {
                Button("Clear image and network cache") {
                    URLCache.shared.removeAllCachedResponses()
                    cacheMessage = "Cache cleared"
                }
                if let cacheMessage { Text(cacheMessage).foregroundStyle(.secondary) }
            }
            Section("Reset") {
                Button("Reset all tvOS settings", role: .destructive) { confirmReset = true }
            }
            Section("About") {
                LabeledContent("App", value: "Harbor for Apple TV")
                LabeledContent("Version", value: version)
                LabeledContent("Player", value: "mpv · MPVKit-GPL")
                LabeledContent("Platform", value: "tvOS 17+")
            }
        }
        .navigationTitle("Advanced")
        .confirmationDialog("Reset every Harbor setting on this Apple TV?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Settings", role: .destructive) { HarborSettings.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}
