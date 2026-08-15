import Foundation
import SwiftUI

// User-configurable playback preferences, persisted in UserDefaults and mapped to mpv.
// Mirrors the Harbor iPhone settings that actually apply to a tvOS player: subtitle
// appearance, preferred languages, audio, playback and episode-list behaviour.
enum SubtitleStyle {
    enum Key {
        // subtitle appearance
        static let size = "harbor.sub.size"
        static let color = "harbor.sub.color"
        static let style = "harbor.sub.style"
        static let bold = "harbor.sub.bold"
        static let borderSize = "harbor.sub.borderSize"
        static let margin = "harbor.sub.margin"
        static let opacity = "harbor.sub.opacity"
        static let alignment = "harbor.sub.alignment"
        static let font = "harbor.sub.font"
        static let fontSize = "harbor.sub.fontSize"
        static let fontColor = "harbor.sub.fontColor"
        static let borderColor = "harbor.sub.borderColor"
        static let boxColor = "harbor.sub.boxColor"
        static let boxOpacity = "harbor.sub.boxOpacity"
        static let assOverride = "harbor.sub.assOverride"
        static let lineSpacing = "harbor.sub.lineSpacing"
        static let preferEmbedded = "harbor.pref.preferEmbeddedSubs"
        // language + track prefs
        static let subLang = "harbor.pref.subLang"
        static let audioLang = "harbor.pref.audioLang"
        static let subsOff = "harbor.pref.subsOffByDefault"
        static let audioNormalize = "harbor.pref.audioNormalize"
        // playback
        static let videoSize = "harbor.videoSize"
        static let defaultSpeed = "harbor.pref.defaultSpeed"
        static let seekStep = "harbor.pref.seekStep"
        static let resume = "harbor.pref.resume"
        static let autoPlayNext = "harbor.pref.autoPlayNext"
        static let instantPlay = "harbor.pref.instantPlay"
        static let rememberStream = "harbor.pref.rememberStream"
        static let seekBackStep = "harbor.pref.seekBackStep"
        static let seekForwardStep = "harbor.pref.seekForwardStep"
        static let audioProfile = "harbor.pref.audioProfile"
        static let confirmLeave = "harbor.pref.confirmLeave"
        // episode list
        static let episodeSort = "harbor.pref.episodeSort"
        static let showEpisodeDesc = "harbor.pref.showEpisodeDesc"
        static let episodeLayout = "harbor.pref.episodeLayout"
        static let hideWatched = "harbor.library.hideWatched"
        static let hideUnreleased = "harbor.library.hideUnreleased"
        static let libraryBookmarkedOnly = "harbor.library.bookmarkedOnly"
        static let librarySort = "harbor.library.sort"
        static let homeShowAllRows = "harbor.home.showAllAddonRows"
        static let hideSpoilers = "harbor.library.hideSpoilers"
        static let spoilerThumbnails = "harbor.library.spoilerThumbnails"
        // stream picker
        static let streamSort = "harbor.stream.sort"
        static let streamFilter = "harbor.stream.filter"
        static let fullStreamDescription = "harbor.stream.fullDescription"
        static let pickerShowFilename = "harbor.stream.showFilename"
        static let bandwidthMbps = "harbor.stream.bandwidthMbps"
        // mpv / picture
        static let mpvQuality = "harbor.mpv.quality"
        static let mpvHWDec = "harbor.mpv.hwdec"
        static let mpvBufferBoost = "harbor.mpv.bufferBoost"
        static let mpvDownmix = "harbor.mpv.downmix"
        static let brightness = "harbor.mpv.brightness"
        static let contrast = "harbor.mpv.contrast"
        static let saturation = "harbor.mpv.saturation"
        static let gamma = "harbor.mpv.gamma"
        static let toneMapping = "harbor.mpv.toneMapping"
        static let motionInterpolation = "harbor.mpv.motionInterpolation"
        // Anime4K
        static let anime4KEnabled = "harbor.anime4k.enabled"
        static let anime4KAnimeOnly = "harbor.anime4k.animeOnly"
        static let anime4KIndicator = "harbor.anime4k.indicator"
        static let anime4KMode = "harbor.anime4k.mode"
        static let anime4KTier = "harbor.anime4k.tier"
        // player chrome
        static let controlsHideSeconds = "harbor.player.controlsHideSeconds"
        static let showQualityInfo = "harbor.player.showQualityInfo"
        static let playerTitleScale = "harbor.player.titleScale"
        // appearance
        static let accent = "harbor.theme.accent"
        static let background = "harbor.theme.background"
        static let posterScale = "harbor.theme.posterScale"
        static let posterRadius = "harbor.theme.posterRadius"
        static let rowTitleScale = "harbor.theme.rowTitleScale"
        static let reduceArtworkMotion = "harbor.theme.reduceArtworkMotion"
    }

    static let defaultSize = "medium"
    static let defaultColor = "white"
    static let defaultStyle = "shadow"
    static let defaultFontSize = 52.0
    static let defaultFontColor = "#FFFFFF"
    static let defaultBorderColor = "#000000"
    static let defaultBoxColor = "#000000"

    struct Preset: Identifiable, Hashable { let id: String; let label: String }

    static let sizes: [Preset] = [
        .init(id: "small", label: "Small"),
        .init(id: "medium", label: "Medium"),
        .init(id: "large", label: "Large"),
        .init(id: "xlarge", label: "Extra Large"),
    ]
    static let colors: [Preset] = [
        .init(id: "white", label: "White"),
        .init(id: "yellow", label: "Yellow"),
        .init(id: "cyan", label: "Cyan"),
        .init(id: "green", label: "Green"),
        .init(id: "pink", label: "Pink"),
    ]
    // Matches Harbor's subStyle: shadow / outline / box.
    static let styles: [Preset] = [
        .init(id: "shadow", label: "Drop shadow"),
        .init(id: "outline", label: "Outline"),
        .init(id: "box", label: "Black bar"),
    ]
    static let assOverrides: [Preset] = [
        .init(id: "no", label: "Keep original"),
        .init(id: "scale", label: "Resize only"),
        .init(id: "force", label: "Use my style"),
    ]
    static let fonts: [Preset] = [
        .init(id: "inter", label: "Inter / Sans serif"),
        .init(id: "system", label: "System"),
        .init(id: "rounded", label: "Rounded"),
        .init(id: "serif", label: "Serif"),
        .init(id: "arabic", label: "Arabic"),
    ]
    static let textColors: [Preset] = [
        .init(id: "#FFFFFF", label: "White"),
        .init(id: "#FFF36A", label: "Yellow"),
        .init(id: "#61E7FF", label: "Cyan"),
        .init(id: "#74E68A", label: "Green"),
        .init(id: "#FF9ED2", label: "Pink"),
    ]
    static let edgeColors: [Preset] = [
        .init(id: "#000000", label: "Black"),
        .init(id: "#20242C", label: "Charcoal"),
        .init(id: "#FFFFFF", label: "White"),
        .init(id: "#173C70", label: "Blue"),
        .init(id: "#5B173E", label: "Plum"),
    ]
    static let fontSizes: [Double] = [24, 32, 40, 48, 52, 56, 64, 72, 80, 96, 112]
    static let outlineSizes: [Double] = [0, 1, 2, 3, 4, 5, 6]
    static let margins: [Double] = [0, 6, 12, 18, 24, 32, 40, 50, 65, 80, 100]
    static let opacities: [Double] = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    static let lineSpacings: [Double] = [-4, -2, 0, 2, 4, 6, 8, 12]
    // Language options (code "" = system/auto). Audio "off" isn't offered.
    static let languages: [Preset] = [
        .init(id: "", label: "System / Auto"),
        .init(id: "eng", label: "English"),
        .init(id: "ger", label: "German"),
        .init(id: "spa", label: "Spanish"),
        .init(id: "fre", label: "French"),
        .init(id: "ita", label: "Italian"),
        .init(id: "jpn", label: "Japanese"),
        .init(id: "por", label: "Portuguese"),
        .init(id: "ara", label: "Arabic"),
        .init(id: "kor", label: "Korean"),
        .init(id: "chi", label: "Chinese"),
        .init(id: "dut", label: "Dutch"),
        .init(id: "pol", label: "Polish"),
        .init(id: "rus", label: "Russian"),
        .init(id: "tur", label: "Turkish"),
    ]
    static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let seekSteps: [Int] = [5, 10, 15, 30]

    private static func str(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    private static func number(_ key: String, _ fallback: Double) -> Double {
        (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
    }

    private static func legacyColor(_ id: String) -> String {
        switch id {
        case "yellow": return "#FFFF00"
        case "cyan": return "#00FFFF"
        case "green": return "#74E68A"
        case "pink": return "#FF9ED2"
        default: return defaultFontColor
        }
    }

    private static func legacySize(_ id: String) -> Double {
        switch id {
        case "small": return 40
        case "large": return 64
        case "xlarge": return 80
        default: return defaultFontSize
        }
    }

    private static func fontName(_ id: String) -> String {
        switch id {
        case "system": return "Helvetica Neue"
        case "rounded": return "Arial Rounded MT Bold"
        case "serif": return "New York"
        case "arabic": return "Geeza Pro"
        default: return "Arial"
        }
    }

    private static func mpvColor(_ raw: String, opacity: Double) -> String {
        let value = raw.uppercased()
        let rgb = value.hasPrefix("#") && value.count == 7 ? String(value.dropFirst()) : "FFFFFF"
        let alpha = Int(max(0, min(1, opacity)) * 255.0).clamped(to: 0...255)
        return String(format: "#%02X%@", alpha, rgb)
    }

    /// The current subtitle appearance as mpv option name/value pairs.
    static var mpvOptions: [(String, String)] {
        let size = str(Key.size, defaultSize)
        let legacyColorID = str(Key.color, defaultColor)
        let style = str(Key.style, defaultStyle)
        let bold = (UserDefaults.standard.object(forKey: Key.bold) as? Bool) ?? false
        let borderSize = number(Key.borderSize, 2.0)
        let margin = number(Key.margin, 12.0)
        let opacity = number(Key.opacity, 1.0)
        let boxOpacity = number(Key.boxOpacity, 0.6)
        let fontSize = number(Key.fontSize, legacySize(size))
        let lineSpacing = number(Key.lineSpacing, 0)
        let alignment = str(Key.alignment, "center")
        let font = str(Key.font, "inter")
        let fontColor = str(Key.fontColor, legacyColor(legacyColorID))
        let borderColor = str(Key.borderColor, defaultBorderColor)
        let boxColor = str(Key.boxColor, defaultBoxColor)
        let assOverride = str(Key.assOverride, "no")
        let forceMargins = assOverride == "no" ? "no" : "yes"

        var opts: [(String, String)] = []
        opts.append(("sub-font-size", "32"))
        opts.append(("sub-scale", String(format: "%.3f", max(0.4, min(4, fontSize / 32.0)))))
        opts.append(("sub-color", mpvColor(fontColor, opacity: opacity)))
        opts.append(("sub-bold", bold ? "yes" : "no"))
        opts.append(("sub-border-color", mpvColor(borderColor, opacity: opacity)))
        opts.append(("sub-margin-y", String(format: "%.0f", margin)))
        opts.append(("sub-pos", String(format: "%.0f", max(0, min(100, 100 - margin)))))
        opts.append(("sub-align-x", alignment))
        opts.append(("sub-font", fontName(font)))
        opts.append(("sub-ass-override", assOverride))
        opts.append(("sub-ass-force-margins", forceMargins))
        opts.append(("sub-use-margins", forceMargins))
        opts.append(("sub-line-spacing", String(format: "%.1f", lineSpacing)))

        switch style {
        case "box":
            opts.append(("sub-border-style", "background-box"))
            opts.append(("sub-back-color", mpvColor(boxColor, opacity: boxOpacity * opacity)))
            opts.append(("sub-border-size", "0"))
            opts.append(("sub-shadow-offset", "0"))
        case "outline":
            opts.append(("sub-border-style", "outline-and-shadow"))
            opts.append(("sub-back-color", "#00000000"))
            opts.append(("sub-border-size", String(format: "%.1f", max(1, borderSize))))
            opts.append(("sub-shadow-offset", "0"))
        default: // shadow
            opts.append(("sub-border-style", "outline-and-shadow"))
            opts.append(("sub-back-color", mpvColor("#000000", opacity: opacity)))
            opts.append(("sub-border-size", String(format: "%.1f", borderSize)))
            opts.append(("sub-shadow-offset", "1.4"))
        }
        return opts
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}

// Shared, tvOS-native settings catalog. It intentionally contains only switches that
// have a native consumer in this target; desktop window, tray and keyboard settings do
// not belong on a Siri Remote driven app.
enum HarborSettings {
    struct Choice: Identifiable, Hashable {
        let id: String
        let label: String
        var detail: String = ""
    }

    static let videoSizes = [
        Choice(id: "original", label: "Fit", detail: "Keep the full picture"),
        Choice(id: "fill", label: "Fill", detail: "Crop black bars"),
        Choice(id: "stretch", label: "Stretch", detail: "Fill and distort"),
    ]
    static let qualityPresets = [
        Choice(id: "performance", label: "Performance", detail: "Lowest GPU load"),
        Choice(id: "balanced", label: "Balanced", detail: "Recommended for Apple TV"),
        Choice(id: "quality", label: "Max quality", detail: "Sharper scaling, more GPU use"),
    ]
    static let hwdecModes = [
        Choice(id: "auto", label: "Automatic"),
        Choice(id: "on", label: "VideoToolbox"),
        Choice(id: "off", label: "Software"),
    ]
    static let toneMapModes = [
        Choice(id: "auto", label: "Automatic"),
        Choice(id: "bt.2390", label: "BT.2390"),
        Choice(id: "clip", label: "Clip"),
    ]
    static let audioProfiles = [
        Choice(id: "off", label: "Off"),
        Choice(id: "voice", label: "Clear dialogue"),
        Choice(id: "night", label: "Night mode"),
        Choice(id: "bass", label: "Bass boost"),
        Choice(id: "bass-reduce", label: "Reduce bass"),
    ]
    static let animeModes = [
        Choice(id: "A", label: "Mode A", detail: "Restore → upscale"),
        Choice(id: "B", label: "Mode B", detail: "Soft restore → upscale"),
        Choice(id: "C", label: "Mode C", detail: "Upscale → restore"),
        Choice(id: "A+A", label: "Mode A+A", detail: "Strong restore"),
        Choice(id: "B+B", label: "Mode B+B", detail: "Strong soft restore"),
        Choice(id: "C+A", label: "Mode C+A", detail: "Strong upscale and restore"),
    ]
    static let animeTiers = [
        Choice(id: "fast", label: "Performance", detail: "M shaders"),
        Choice(id: "hq", label: "High quality", detail: "VL shaders"),
    ]
    static let streamFilters = [
        Choice(id: "strict", label: "Strict", detail: "Hide suspicious and unsupported results"),
        Choice(id: "balanced", label: "Balanced", detail: "Hide only obvious mismatches"),
        Choice(id: "off", label: "Off", detail: "Show everything"),
    ]
    static let accents = [
        Choice(id: "green", label: "Harbor green"),
        Choice(id: "blue", label: "Ocean blue"),
        Choice(id: "purple", label: "Deep purple"),
        Choice(id: "orange", label: "Warm gold"),
        Choice(id: "pink", label: "Rose"),
        Choice(id: "white", label: "Monochrome"),
    ]

    static func accentColor(_ id: String) -> Color {
        switch id {
        case "blue": return Color(red: 0.22, green: 0.58, blue: 0.98)
        case "purple": return Color(red: 0.62, green: 0.42, blue: 0.96)
        case "orange": return Color(red: 0.95, green: 0.62, blue: 0.22)
        case "pink": return Color(red: 0.95, green: 0.38, blue: 0.65)
        case "white": return .white
        default: return Color(red: 0.25, green: 0.82, blue: 0.48)
        }
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: SubtitleStyle.Key.episodeSort) == "oldest" {
            defaults.set("aired", forKey: SubtitleStyle.Key.episodeSort)
        }
        if defaults.object(forKey: SubtitleStyle.Key.seekBackStep) == nil,
           let legacy = defaults.object(forKey: SubtitleStyle.Key.seekStep) as? Int {
            defaults.set(legacy, forKey: SubtitleStyle.Key.seekBackStep)
            defaults.set(legacy, forKey: SubtitleStyle.Key.seekForwardStep)
        }
        defaults.register(defaults: [
            SubtitleStyle.Key.resume: true,
            SubtitleStyle.Key.autoPlayNext: true,
            SubtitleStyle.Key.instantPlay: true,
            SubtitleStyle.Key.rememberStream: true,
            SubtitleStyle.Key.seekStep: 10,
            SubtitleStyle.Key.seekBackStep: 10,
            SubtitleStyle.Key.seekForwardStep: 10,
            SubtitleStyle.Key.confirmLeave: true,
            SubtitleStyle.Key.showEpisodeDesc: true,
            SubtitleStyle.Key.libraryBookmarkedOnly: true,
            SubtitleStyle.Key.homeShowAllRows: false,
            SubtitleStyle.Key.hideSpoilers: false,
            SubtitleStyle.Key.spoilerThumbnails: true,
            SubtitleStyle.Key.fullStreamDescription: true,
            SubtitleStyle.Key.pickerShowFilename: false,
            SubtitleStyle.Key.mpvBufferBoost: false,
            SubtitleStyle.Key.mpvDownmix: false,
            SubtitleStyle.Key.anime4KEnabled: false,
            SubtitleStyle.Key.anime4KAnimeOnly: true,
            SubtitleStyle.Key.anime4KIndicator: true,
            SubtitleStyle.Key.motionInterpolation: false,
            SubtitleStyle.Key.showQualityInfo: true,
            SubtitleStyle.Key.posterScale: 1.0,
            SubtitleStyle.Key.posterRadius: 12.0,
            SubtitleStyle.Key.rowTitleScale: 1.0,
            SubtitleStyle.Key.opacity: 1.0,
            SubtitleStyle.Key.borderSize: 2.0,
            SubtitleStyle.Key.margin: 12.0,
            SubtitleStyle.Key.fontSize: SubtitleStyle.defaultFontSize,
            SubtitleStyle.Key.fontColor: SubtitleStyle.defaultFontColor,
            SubtitleStyle.Key.borderColor: SubtitleStyle.defaultBorderColor,
            SubtitleStyle.Key.boxColor: SubtitleStyle.defaultBoxColor,
            SubtitleStyle.Key.boxOpacity: 0.6,
            SubtitleStyle.Key.assOverride: "no",
            SubtitleStyle.Key.lineSpacing: 0.0,
        ])
    }

    static func reset() {
        let prefix = "harbor."
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix(prefix) && !key.hasPrefix("harbor.stremio.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        registerDefaults()
    }
}
