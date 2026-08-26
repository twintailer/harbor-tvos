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
        URLCache.shared.memoryCapacity = 96 * 1024 * 1024
        URLCache.shared.diskCapacity = 420 * 1024 * 1024
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
    @AppStorage(SubtitleStyle.Key.interfaceStyle) private var interfaceStyle = "harbor"
    @State private var selection: HarborSection = .home
    @State private var sidebarOpen = false
    @FocusState private var sidebarFocus: HarborSection?

    var body: some View {
        ZStack(alignment: .leading) {
            stageColor.ignoresSafeArea()
            HStack(spacing: 0) {
                Color.clear.frame(width: HarborSidebar.collapsedWidth)
                destination
                    .id(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(sidebarOpen)
            .allowsHitTesting(!sidebarOpen)
            .onExitCommand { openSidebar() }

            HarborSidebar(selection: $selection, focus: $sidebarFocus,
                          expanded: sidebarOpen, accent: sidebarAccent,
                          interfaceStyle: interfaceStyle) {
                closeSidebar()
            }
            .disabled(!sidebarOpen)
            .onExitCommand { closeSidebar() }
            .onMoveCommand { direction in
                if direction == .left || direction == .right { closeSidebar() }
            }
            .onChange(of: sidebarFocus) { old, new in
                guard sidebarOpen, old == nil, let new, new != selection else { return }
                sidebarFocus = selection
            }
        }
        .tint(sidebarAccent)
        .preferredColorScheme(.dark)
    }

    private func openSidebar() {
        guard !sidebarOpen else { return }
        sidebarOpen = true
        DispatchQueue.main.async { sidebarFocus = selection }
    }

    private func closeSidebar() {
        sidebarFocus = nil
        sidebarOpen = false
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

    private var stageColor: Color {
        if interfaceStyle == "max" { return .black }
        if interfaceStyle == "netflix" { return Color(red: 0.027, green: 0.027, blue: 0.027) }
        switch background {
        case "oled": return .black
        case "system": return .black
        default: return Color(red: 0.025, green: 0.032, blue: 0.044)
        }
    }

    private var sidebarAccent: Color {
        switch interfaceStyle {
        case "max": return .white
        case "netflix": return Color(red: 0.90, green: 0.035, blue: 0.075)
        default: return HarborSettings.accentColor(accent)
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
    let expanded: Bool
    let accent: Color
    let interfaceStyle: String
    let onSelected: () -> Void

    static let collapsedWidth: CGFloat = 116
    static let expandedWidth: CGFloat = 430
    private var width: CGFloat { expanded ? Self.expandedWidth : Self.collapsedWidth }

    var body: some View {
        ZStack(alignment: .leading) {
            if expanded {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.98), location: 0),
                    .init(color: .black.opacity(0.92), location: 0.28),
                    .init(color: .black.opacity(0.50), location: 0.48),
                    .init(color: .clear, location: 0.72),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 18) {
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 48)
                    if expanded {
                        Text("Harbor")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                }
                .padding(.leading, 34)
                .frame(height: 68)

                Spacer(minLength: 18)

                ForEach(HarborSection.allCases) { section in
                    Button {
                        if selection != section { selection = section }
                        onSelected()
                    } label: {
                        HarborSidebarRow(section: section, selected: selection == section,
                                         expanded: expanded, accent: accent,
                                         width: width, interfaceStyle: interfaceStyle)
                    }
                    .buttonStyle(.plain)
                    .focused(focus, equals: section)
                }

                Spacer(minLength: 18)
            }
            .defaultFocus(focus, selection)
            .padding(.vertical, 44)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: expanded)
    }
}

private struct HarborSidebarRow: View {
    @Environment(\.isFocused) private var isFocused
    let section: HarborSection
    let selected: Bool
    let expanded: Bool
    let accent: Color
    let width: CGFloat
    let interfaceStyle: String

    private var highlighted: Bool { selected || isFocused }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.system(size: 27, weight: selected ? .semibold : .regular))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.52))
                .frame(width: 44, height: 44)
            Text(section.label)
                .font(.system(size: 28, weight: selected ? .bold : .medium))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.64))
                .lineLimit(1)
                .opacity(expanded ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.leading, 38)
        .padding(.trailing, 22)
        .frame(width: width, height: 58, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(expanded && isFocused ? .white.opacity(interfaceStyle == "max" ? 0.18 : 0.14) : .clear)
                .padding(.horizontal, 18)
        }
        .overlay(alignment: .leading) {
            if expanded && selected {
                Rectangle().fill(accent).frame(width: 4, height: 30).padding(.leading, 18)
            }
        }
    }
}
