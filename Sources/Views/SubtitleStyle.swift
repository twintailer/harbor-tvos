import Foundation

// User-configurable subtitle appearance + video-size, persisted in UserDefaults
// and translated to mpv options. Kept deliberately small: a few sensible presets
// the Settings screen and the in-player panel both drive.
enum SubtitleStyle {
    enum Key {
        static let size = "harbor.sub.size"
        static let color = "harbor.sub.color"
        static let background = "harbor.sub.background"
        static let videoSize = "harbor.videoSize"
    }

    static let defaultSize = "medium"
    static let defaultColor = "white"
    static let defaultBackground = "shadow"

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
    static let backgrounds: [Preset] = [
        .init(id: "shadow", label: "Shadow"),
        .init(id: "box", label: "Box"),
        .init(id: "none", label: "None"),
    ]

    private static func value(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    /// The current appearance as mpv option name/value pairs.
    static var mpvOptions: [(String, String)] {
        let size = value(Key.size, defaultSize)
        let color = value(Key.color, defaultColor)
        let background = value(Key.background, defaultBackground)

        var opts: [(String, String)] = []
        // Font size (mpv sub-font-size is relative to a 720p window height).
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

        switch background {
        case "box":
            opts.append(("sub-back-color", "#80000000"))
            opts.append(("sub-border-size", "0"))
            opts.append(("sub-shadow-offset", "0"))
        case "none":
            opts.append(("sub-back-color", "#00000000"))
            opts.append(("sub-border-size", "1"))
            opts.append(("sub-shadow-offset", "0"))
        default: // shadow
            opts.append(("sub-back-color", "#00000000"))
            opts.append(("sub-border-size", "2.5"))
            opts.append(("sub-shadow-offset", "1.5"))
        }
        opts.append(("sub-border-color", "#000000"))
        return opts
    }
}
