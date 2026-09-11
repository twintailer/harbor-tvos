import Foundation

enum HarborSection: String, CaseIterable, Identifiable {
    case home, movies, series, anime, discover, catalogs, library, addons, search, settings
    var id: String { rawValue }
    static let topTabs: [Self] = [.search, .home, .series, .movies, .anime, .catalogs, .library]

    /// nil means leave the Menu/Back event to tvOS, not terminate the process.
    var backDestination: Self? { self == .home ? nil : .home }

    var label: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .anime: return "Anime"
        case .discover: return "Discover"
        case .catalogs: return "Catalogs"
        case .library: return "My Harbor"
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

/// The More menu is a focus target, but it is not a destination page.
enum HarborNavigationItem: Hashable {
    case section(HarborSection)
    case more

    var destination: HarborSection? {
        guard case let .section(section) = self else { return nil }
        return section
    }
}

enum TVFocusPresentation {
    /// Call with a settled focus to select a title; nil preserves the last title
    /// while focus moves into navigation, another rail or a detail page.
    static func previewID(focused: String?, previous: String?, available: [String]) -> String? {
        if let focused, available.contains(focused) { return focused }
        if let previous, available.contains(previous) { return previous }
        return available.first
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case quick, playback, subtitles, library, streaming, account, appearance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: return "Quick access"
        case .playback: return "Playback"
        case .subtitles: return "Languages & subtitles"
        case .library: return "Library & tracking"
        case .streaming: return "Streaming"
        case .account: return "Account & system"
        case .appearance: return "Appearance"
        }
    }
    var icon: String {
        switch self {
        case .quick: return "star"
        case .playback: return "play.rectangle"
        case .subtitles: return "captions.bubble"
        case .library: return "books.vertical"
        case .streaming: return "antenna.radiowaves.left.and.right"
        case .account: return "person.crop.circle"
        case .appearance: return "paintpalette"
        }
    }
    var routes: [SettingsRoute] {
        switch self {
        case .quick: return [.player, .languages, .anime, .skip, .theme, .account]
        case .playback: return [.player, .skip, .video, .anime, .layout]
        case .subtitles: return [.languages, .subtitleBehavior, .subtitleStyle, .subtitleFont, .subtitlePosition, .subtitleColors]
        case .library: return [.library, .trakt, .anilist, .mal, .simkl, .letterboxd]
        case .streaming: return [.sources, .filters, .relay, .p2p]
        case .account: return [.account, .getStarted, .advanced]
        case .appearance: return [.theme, .layout, .advanced]
        }
    }
}

enum SettingsRoute: String, CaseIterable, Identifiable {
    case getStarted, account, library, trakt, anilist, mal, simkl, letterboxd
    case relay, sources, filters, p2p, player, skip, video, anime, layout
    case languages, subtitleBehavior, subtitleStyle, subtitleFont, subtitlePosition, subtitleColors, theme, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .getStarted: return "Get started"
        case .account: return "Account"
        case .library: return "Library & metadata"
        case .trakt: return "Trakt"
        case .anilist: return "AniList"
        case .mal: return "MyAnimeList"
        case .simkl: return "Simkl"
        case .letterboxd: return "Letterboxd"
        case .relay: return "Harbor Relay"
        case .sources: return "Streaming sources"
        case .filters: return "Stream filters"
        case .p2p: return "P2P & servers"
        case .player: return "Player & quality"
        case .skip: return "Intro skip & next episode"
        case .video: return "Video tuning"
        case .anime: return "Anime4K"
        case .layout: return "Player controls"
        case .languages: return "Playback languages"
        case .subtitleBehavior: return "Subtitle behaviour"
        case .subtitleStyle: return "Subtitle style"
        case .subtitleFont: return "Font & size"
        case .subtitlePosition: return "Subtitle position"
        case .subtitleColors: return "Subtitle colours"
        case .theme: return "Theme & appearance"
        case .advanced: return "Storage & system"
        }
    }
    var subtitle: String {
        switch self {
        case .getStarted: return "Set up Harbor in a few steps"
        case .account: return "Sign-in and account sync"
        case .library: return "Catalogs, episodes and watch history"
        case .trakt, .anilist, .mal, .simkl, .letterboxd: return "Connected tracking add-on"
        case .relay: return "Connect your Harbor Relay"
        case .sources: return "Providers and stream selection"
        case .filters: return "Quality, languages and source safety"
        case .p2p: return "TorrServer and network playback"
        case .player: return "Engine, playback and audio"
        case .skip: return "Intros, credits and automatic next episode"
        case .video: return "Acceleration, HDR and picture adjustments"
        case .anime: return "Upscaling presets and automatic activation"
        case .layout: return "Visible buttons and control-bar behaviour"
        case .languages: return "Audio, primary and fallback subtitles"
        case .subtitleBehavior: return "Defaults, embedded subtitles and signs"
        case .subtitleStyle: return "Background, outline and ASS overrides"
        case .subtitleFont: return "Typeface, weight, size and opacity"
        case .subtitlePosition: return "Alignment, bottom margin and spacing"
        case .subtitleColors: return "Text, outline and background colours"
        case .theme: return "Colours, artwork and accessibility"
        case .advanced: return "Cache, reset and app version"
        }
    }
    var icon: String {
        switch self {
        case .getStarted: return "safari"
        case .account: return "person.crop.circle"
        case .library: return "books.vertical"
        case .trakt, .anilist, .mal, .simkl, .letterboxd: return "arrow.triangle.2.circlepath"
        case .relay, .sources: return "antenna.radiowaves.left.and.right"
        case .filters: return "line.3.horizontal.decrease.circle"
        case .p2p: return "server.rack"
        case .player: return "play.rectangle"
        case .skip: return "forward.end"
        case .video: return "slider.horizontal.3"
        case .anime: return "sparkles"
        case .layout: return "rectangle.bottomthird.inset.filled"
        case .languages: return "globe"
        case .subtitleStyle, .subtitleBehavior: return "captions.bubble"
        case .subtitleFont: return "textformat.size"
        case .subtitlePosition: return "arrow.up.and.down.text.horizontal"
        case .subtitleColors, .theme: return "paintpalette"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}
