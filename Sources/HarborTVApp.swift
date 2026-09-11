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
        Task.detached(priority: .utility) { MetadataText.prepare() }
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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task {
                        await HarborArtworkCache.shared.purge()
                        await AddonService.purgeCatalogCache()
                    }
                }
        }
    }
}

struct RootView: View {
    @AppStorage(SubtitleStyle.Key.accent) private var accent = "green"
    @AppStorage(SubtitleStyle.Key.interfaceStyle) private var interfaceStyle = "harbor"
    @State private var selection: HarborSection = .home
    @State private var detailIsOpen = false
    @FocusState private var navigationFocus: HarborNavigationItem?

    var body: some View {
        ZStack {
            HarborStageBackground()
            destination
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
        }
        // Keep the navigation outside the replaced destination. Moving between
        // tabs must not destroy the currently focused button.
        .safeAreaInset(edge: .top, spacing: 0) {
            if !detailIsOpen {
                HarborTopNavigation(selection: selection, focus: $navigationFocus, onSelected: select)
                    .focusSection()
                    .onExitCommand(perform: rootBackAction)
            }
        }
        .onPreferenceChange(HarborDetailNavigationKey.self) { detailIsOpen = $0 }
        .tint(HarborTVDesign.accent(interfaceStyle: interfaceStyle, fallback: accent))
        .preferredColorScheme(.dark)
        .defaultFocus($navigationFocus, .section(.home))
        .onChange(of: navigationFocus) { _, item in
            guard !detailIsOpen, let section = item?.destination else { return }
            select(section)
        }
    }

    private var rootBackAction: (() -> Void)? {
        guard let parent = selection.backDestination else { return nil }
        return {
            select(parent)
            navigationFocus = .section(parent)
        }
    }

    private func select(_ section: HarborSection) {
        guard selection != section else { return }
        detailIsOpen = false
        selection = section
        // Keep the selected tab focused. Down moves naturally into its content;
        // disabling the bar on a timer can steal focus during a remote gesture.
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        // Home deliberately installs NO exit-command handler. The unhandled
        // Back/Menu press reaches tvOS and returns to the system Home screen.
        case .home: HomeView(onSearch: { select(.search) })
        case .movies: MediaBrowseView(title: "Movies", type: "movie", onRootBack: { select(.home) })
        case .series: MediaBrowseView(title: "Series", type: "series", onRootBack: { select(.home) })
        case .anime: MediaBrowseView(title: "Anime", type: "anime", fallbackGenre: "Animation", onRootBack: { select(.home) })
        case .discover: DiscoverView(onRootBack: { select(.home) })
        case .catalogs: CatalogsView(onRootBack: { select(.home) })
        case .library: LibraryView(onRootBack: { select(.home) })
        case .addons: AddonsView(onRootBack: { select(.home) })
        case .search: SearchView(onRootBack: { select(.home) })
        case .settings: SettingsView(onRootBack: { select(.home) })
        }
    }
}

/// Hide the global navigation on pushed details/settings pages. Their own
/// NavigationStack then owns Back, including nested language pickers.
struct HarborDetailNavigationKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct HarborTopNavigation: View {
    let selection: HarborSection
    var focus: FocusState<HarborNavigationItem?>.Binding
    let onSelected: (HarborSection) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            navigationBar(compact: false)
            navigationBar(compact: true)
        }
        .padding(.horizontal, 48).padding(.top, 12).padding(.bottom, 20)
    }

    private func navigationBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 12 : 22) {
            Label("Harbor", systemImage: "sailboat.fill")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                ForEach(HarborSection.topTabs) { section in
                    Button { onSelected(section) } label: {
                        if section == .search {
                            Image(systemName: section.icon).frame(width: 24)
                        } else { Text(section.label).lineLimit(1).fixedSize() }
                    }
                    .buttonStyle(HarborNavigationTabStyle(selected: selection == section, compact: compact))
                    .focused(focus, equals: .section(section))
                    .accessibilityLabel(section.label)
                    .accessibilityIdentifier("navigation.\(section.rawValue)")
                }
            }
            Spacer(minLength: 12)
            Menu {
                Button { onSelected(.discover) } label: { Label("Discover", systemImage: "safari") }
                Button { onSelected(.addons) } label: { Label("Add-ons", systemImage: "puzzlepiece.extension") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24)
            }
            .buttonStyle(HarborNavigationTabStyle(selected: selection == .discover || selection == .addons, compact: compact))
            .focused(focus, equals: .more)
            .accessibilityLabel("More: Discover and Add-ons")
            .accessibilityIdentifier("navigation.more")
            Button { onSelected(.settings) } label: {
                Image(systemName: "gearshape").frame(width: 24)
            }
            .buttonStyle(HarborNavigationTabStyle(selected: selection == .settings, compact: compact))
            .focused(focus, equals: .section(.settings))
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("navigation.settings")
        }
        .padding(.horizontal, 26).padding(.vertical, 12)
        .harborGlass(cornerRadius: 32, tint: .black.opacity(0.32))
    }
}

struct HarborNavigationTabStyle: ButtonStyle {
    var selected = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        HarborNavigationTabBody(configuration: configuration, selected: selected, compact: compact)
    }
}

private struct HarborNavigationTabBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let compact: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 19 : 22, weight: selected || focused ? .bold : .medium))
            .foregroundStyle(focused ? .black : .white.opacity(selected ? 1 : 0.70))
            .padding(.horizontal, compact ? 13 : 21).frame(height: 50)
            .background(Capsule().fill(focused ? .white : (selected ? .white.opacity(0.16) : .clear)))
            .overlay(Capsule().strokeBorder(.white.opacity(selected && !focused ? 0.18 : 0), lineWidth: 1))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: focused)
    }
}
