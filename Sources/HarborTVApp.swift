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
        // Keep enough headroom for VideoToolbox + Anime4K. Oversized artwork/network
        // caches can force tvOS memory pressure and turn focus animations into hitches.
        URLCache.shared.memoryCapacity = 32 * 1024 * 1024
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
    @AppStorage(SubtitleStyle.Key.interfaceStyle) private var interfaceStyle = "harbor"
    @State private var selection: HarborSection = .home
    @State private var sidebarEnabled = false
    @FocusState private var sidebarFocus: HarborSection?

    private var sidebarExpanded: Bool { sidebarFocus != nil }

    var body: some View {
        ZStack(alignment: .leading) {
            HarborStageBackground()
            destination
                .id(selection)
                .padding(.leading, HarborSidebar.collapsedWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: HarborTVDesign.canvas, location: 0),
                            .init(color: .black.opacity(0.76), location: 0.17),
                            .init(color: .black.opacity(0.56), location: 1),
                        ], startPoint: .leading, endPoint: .trailing
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(sidebarExpanded ? 1 : 0)
                }

            HarborSidebar(selection: $selection, focus: $sidebarFocus,
                          accent: sidebarAccent, interfaceStyle: interfaceStyle,
                          onSelected: select)
            .disabled(!sidebarEnabled)
            .focusSection()
            .onExitCommand { collapseSidebar() }
            .onMoveCommand { direction in
                if direction == .right { collapseSidebar() }
            }
            .task {
                // Let the first content card win cold-launch focus. This is the
                // same focus hand-off used by Orivio and prevents the rail from
                // opening before a row has rendered.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                sidebarEnabled = true
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sidebarExpanded)
        .tint(sidebarAccent)
        .preferredColorScheme(.dark)
    }

    private func openSidebar() {
        sidebarEnabled = true
        sidebarFocus = selection
    }

    private func collapseSidebar() {
        guard sidebarExpanded else { return }
        sidebarFocus = nil
        sidebarEnabled = false
        scheduleSidebarReenable()
    }

    private func select(_ section: HarborSection) {
        selection = section
        sidebarFocus = nil
        sidebarEnabled = false
        scheduleSidebarReenable()
    }

    private func scheduleSidebarReenable() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            sidebarEnabled = true
        }
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        case .home: HomeView(onRootBack: openSidebar, onSearch: { select(.search) })
        case .movies: MediaBrowseView(title: "Movies", type: "movie", onRootBack: openSidebar)
        case .series: MediaBrowseView(title: "Series", type: "series", onRootBack: openSidebar)
        case .anime: MediaBrowseView(title: "Anime", type: "anime", fallbackGenre: "Animation", onRootBack: openSidebar)
        case .discover: DiscoverView(onRootBack: openSidebar)
        case .catalogs: CatalogsView(onRootBack: openSidebar)
        case .library: LibraryView(onRootBack: openSidebar)
        case .addons: AddonsView(onRootBack: openSidebar)
        case .search: SearchView(onRootBack: openSidebar)
        case .settings: SettingsView(onRootBack: openSidebar)
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

    static let sidebarOrder: [HarborSection] = [
        .home, .discover, .catalogs, .movies, .series, .anime,
        .library, .addons, .search, .settings,
    ]

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
    let interfaceStyle: String
    let onSelected: (HarborSection) -> Void

    static let collapsedWidth: CGFloat = 82
    static let expandedWidth: CGFloat = 286
    private var expanded: Bool { focus.wrappedValue != nil }
    private var width: CGFloat { expanded ? Self.expandedWidth : Self.collapsedWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                HStack(spacing: 18) {
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: expanded ? 30 : 32, weight: .bold))
                        .foregroundStyle(interfaceStyle == "netflix" ? HarborTVDesign.cinemaRed : .white)
                        .frame(width: 46)
                    if expanded {
                        Text("Harbor")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .transition(.opacity)
                    }
                }
                .padding(.leading, expanded ? 18 : 20)
                .frame(height: 72, alignment: .leading)
            }
            .padding(.top, 30)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(HarborSection.sidebarOrder) { section in
                    if section == .library {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(height: 1)
                            .padding(.horizontal, expanded ? 16 : 23)
                            .padding(.vertical, 7)
                    }
                    Button {
                        onSelected(section)
                    } label: {
                        HarborSidebarRow(section: section, selected: selection == section,
                                         expanded: expanded, accent: accent,
                                         width: width, interfaceStyle: interfaceStyle)
                    }
                    .buttonStyle(.plain)
                    .focused(focus, equals: section)
                }
            }
            .defaultFocus(focus, selection)
            .padding(.horizontal, expanded ? 12 : 0)

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background((expanded ? HarborTVDesign.canvas.opacity(0.995) : .black.opacity(0.62)).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(expanded ? 0.08 : 0.045)).frame(width: 1)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focus.wrappedValue != selection { focus.wrappedValue = selection }
        }
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
                .font(.system(size: expanded ? 25 : 29, weight: selected ? .semibold : .regular))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.52))
                .frame(width: 42, height: 42)
            Text(section.label)
                .font(.system(size: 24, weight: selected ? .semibold : .medium))
                .foregroundStyle(highlighted ? .white : .white.opacity(0.64))
                .lineLimit(1)
                .opacity(expanded ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.leading, expanded ? 16 : 22)
        .padding(.trailing, 16)
        .frame(width: expanded ? width - 24 : width, height: 62, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(expanded && highlighted ? .white.opacity(interfaceStyle == "max" ? 0.18 : 0.13) : .clear)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(selected ? accent : .clear)
                .frame(width: 4, height: 30)
                .padding(.leading, expanded ? 3 : 7)
        }
        .scaleEffect(isFocused ? 1.025 : 1, anchor: .leading)
        .animation(.easeOut(duration: 0.13), value: isFocused)
    }
}
