import Foundation

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
        // episode list
        static let episodeSort = "harbor.pref.episodeSort"
        static let showEpisodeDesc = "harbor.pref.showEpisodeDesc"
    }

    static let defaultSize = "medium"
    static let defaultColor = "white"
    static let defaultStyle = "shadow"

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
    ]
    // Matches Harbor's subStyle: shadow / outline / box.
    static let styles: [Preset] = [
        .init(id: "shadow", label: "Shadow"),
        .init(id: "outline", label: "Outline"),
        .init(id: "box", label: "Box"),
    ]
    // Language options (code "" = system/auto). Audio "off" isn't offered.
    static let languages: [Preset] = [
        .init(id: "", label: "System / Auto"),
        .init(id: "eng", label: "English"),
        .init(id: "ger", label: "German"),
        .init(id: "spa", label: "Spanish"),
        .init(id: "fre", label: "French"),
        .init(id: "ita", label: "Italian"),
        .init(id: "jpn", label: "Japanese"),
    ]
    static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let seekSteps: [Int] = [5, 10, 15, 30]

    private static func str(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    /// The current subtitle appearance as mpv option name/value pairs.
    static var mpvOptions: [(String, String)] {
        let size = str(Key.size, defaultSize)
        let color = str(Key.color, defaultColor)
        let style = str(Key.style, defaultStyle)
        let bold = UserDefaults.standard.object(forKey: Key.bold) as? Bool ?? false

        var opts: [(String, String)] = []
        let fontSize: String
        switch size {
        case "small":  fontSize = "40"
        case "large":  fontSize = "64"
        case "xlarge": fontSize = "80"
        default:       fontSize = "52"
        }
        opts.append(("sub-font-size", fontSize))

        let hex: String
        switch color {
        case "yellow": hex = "#FFFF00"
        case "cyan":   hex = "#00FFFF"
        default:       hex = "#FFFFFF"
        }
        opts.append(("sub-color", hex))
        opts.append(("sub-bold", bold ? "yes" : "no"))
        opts.append(("sub-border-color", "#000000"))

        switch style {
        case "box":
            opts.append(("sub-back-color", "#90000000"))
            opts.append(("sub-border-size", "0"))
            opts.append(("sub-shadow-offset", "0"))
        case "outline":
            opts.append(("sub-back-color", "#00000000"))
            opts.append(("sub-border-size", "3"))
            opts.append(("sub-shadow-offset", "0"))
        default: // shadow
            opts.append(("sub-back-color", "#00000000"))
            opts.append(("sub-border-size", "2"))
            opts.append(("sub-shadow-offset", "1.5"))
        }
        return opts
    }
}
