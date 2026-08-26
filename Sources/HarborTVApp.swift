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
    @State private var selection: HarborSection = .home
    @FocusState private var sidebarFocus: HarborSection?

    private var sidebarExpanded: Bool { sidebarFocus != nil }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            HStack(spacing: 0) {
                Color.clear.frame(width: 96)
                destination
                    .id(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if sidebarExpanded {
                LinearGradient(
                    stops: [
                        .init(color: backgroundColor.opacity(0.98), location: 0),
                        .init(color: backgroundColor.opacity(0.90), location: 0.22),
                        .init(color: .black.opacity(0.46), location: 0.48),
                        .init(color: .clear, location: 0.74),
                    ],
                    startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            HarborSidebar(selection: $selection, focus: $sidebarFocus,
                          accent: HarborSettings.accentColor(accent))
        }
        .tint(HarborSettings.accentColor(accent))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        case .home: HomeView()
        case .movies: MediaBrowseView(title: "Movies", type: "movie")
        case .series: MediaBrowseView(title: "Series", type: "series")
        case .anime: MediaBrowseView(title: "Anime", type: "anime", fallbackGenre: "Animation")
        case .discover: DiscoverView()
        case .catalogs: CatalogsView()
        case .library: LibraryView()
        case .addons: AddonsView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }

    private var backgroundColor: Color {
        switch background {
        case "oled": return .black
        case "system": return .black
        default: return Color(red: 0.035, green: 0.047, blue: 0.065)
        }
    }
}

private enum HarborSection: String, CaseIterable, Identifiable {
    case home, movies, series, anime, discover, catalogs, library, addons, search, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .anime: return "Anime"
        case .discover: return "Discover"
        case .catalogs: return "Catalogs"
        case .library: return "Library"
        case .addons: return "Add-ons"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "tv.fill"
        case .anime: return "sparkles"
        case .discover: return "safari.fill"
        case .catalogs: return "square.grid.2x2.fill"
        case .library: return "books.vertical.fill"
        case .addons: return "puzzlepiece.extension.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Collapsed icon rail that expands over the content when focus enters it. This keeps
/// Movies / Series / Anime permanently on the left instead of tvOS' top TabView bar.
private struct HarborSidebar: View {
    @Binding var selection: HarborSection
    var focus: FocusState<HarborSection?>.Binding
    let accent: Color

    private var expanded: Bool { focus.wrappedValue != nil }
    private var width: CGFloat { expanded ? 330 : 96 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 58)
                Text("Harbor")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .opacity(expanded ? 1 : 0)
            }
            .frame(height: 72)
            .padding(.leading, 18)
            .padding(.bottom, 12)

            ForEach(HarborSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HarborSidebarRow(section: section, selected: selection == section,
                                     expanded: expanded, accent: accent)
                }
                .buttonStyle(.plain)
                .focused(focus, equals: section)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .padding(.bottom, 26)
        .padding(.horizontal, expanded ? 12 : 8)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(expanded ? background.opacity(0.97) : Color.clear)
        .overlay(alignment: .trailing) {
            if expanded { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
        }
        .clipped()
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
    }

    private var background: Color { Color(red: 0.025, green: 0.032, blue: 0.044) }
}

private struct HarborSidebarRow: View {
    @Environment(\.isFocused) private var isFocused
    let section: HarborSection
    let selected: Bool
    let expanded: Bool
    let accent: Color

    private var highlighted: Bool { selected || isFocused }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.52))
                .frame(width: 56, height: 56)
            Text(section.label)
                .font(.system(size: 27, weight: selected ? .bold : .medium))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.64))
                .lineLimit(1)
                .opacity(expanded ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: expanded ? 306 : 80, height: 70, alignment: .leading)
        .background {
            Capsule(style: .continuous)
                .fill(expanded && highlighted ? .white.opacity(isFocused ? 0.18 : 0.10) : .clear)
        }
        .overlay(alignment: .leading) {
            if selected {
                Capsule().fill(accent).frame(width: 4, height: 34).padding(.leading, 2)
            }
        }
    }
}
