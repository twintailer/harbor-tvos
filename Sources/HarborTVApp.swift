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
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "square.grid.2x2") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            ProfileView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
