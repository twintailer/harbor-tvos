import SwiftUI
import AVFoundation

// Harbor for Apple TV — a NATIVE SwiftUI rewrite of the Harbor Stremio
// client. The iOS/desktop app is a Tauri WebView (React); tvOS has no
// WebKit, so the UI here is built from scratch with SwiftUI + the tvOS
// focus engine. It reuses the same public data sources (Stremio addons /
// Cinemeta) the web app uses.
@main
struct HarborTVApp: App {
    @StateObject private var auth = AuthStore()

    init() {
        HarborSettings.registerDefaults()
        // Category only — no setActive. The audio output driver activates the session when
        // it starts; a long-form .playback/.moviePlayback category is what tvOS expects
        // from a media app and is safe to declare up front.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(auth)
        }
    }
}

struct RootView: View {
    @AppStorage(SubtitleStyle.Key.accent) private var accent = "green"
    @AppStorage(SubtitleStyle.Key.background) private var background = "harbor"

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                DiscoverView()
                    .tabItem { Label("Discover", systemImage: "safari.fill") }
                CatalogsView()
                    .tabItem { Label("Catalogs", systemImage: "square.grid.2x2.fill") }
                MediaBrowseView(title: "Movies", type: "movie")
                    .tabItem { Label("Movies", systemImage: "film.fill") }
                MediaBrowseView(title: "Series", type: "series")
                    .tabItem { Label("Series", systemImage: "tv.fill") }
                MediaBrowseView(title: "Anime", type: "anime", fallbackGenre: "Animation")
                    .tabItem { Label("Anime", systemImage: "sparkles") }
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                AddonsView()
                    .tabItem { Label("Add-ons", systemImage: "puzzlepiece.extension.fill") }
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(HarborSettings.accentColor(accent))
        }
        .preferredColorScheme(.dark)
    }

    private var backgroundColor: Color {
        switch background {
        case "oled": return .black
        case "system": return .black
        default: return Color(red: 0.035, green: 0.047, blue: 0.065)
        }
    }
}
