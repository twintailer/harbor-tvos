import SwiftUI

/// Shared visual language for Harbor's ten-foot interface. The palette stays
/// deliberately restrained: artwork owns the colour, while focus and progress
/// use one cinema-red signal that is easy to see from across the room.
enum HarborTVDesign {
    static let canvas = Color(red: 0.018, green: 0.019, blue: 0.021)
    static let elevated = Color(red: 0.060, green: 0.062, blue: 0.068)
    static let panel = Color.white.opacity(0.075)
    static let cinemaRed = Color(red: 0.90, green: 0.035, blue: 0.075)
    static let success = Color(red: 0.25, green: 0.82, blue: 0.48)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.43)
    static let pageInset: CGFloat = 58
    static let cardRadius: CGFloat = 10

    static func accent(interfaceStyle: String, fallback: String) -> Color {
        interfaceStyle == "netflix" ? cinemaRed : HarborSettings.accentColor(fallback)
    }
}

struct HarborStageBackground: View {
    @AppStorage(SubtitleStyle.Key.background) private var background = "oled"

    private var base: Color {
        switch background {
        case "harbor": return Color(red: 0.032, green: 0.036, blue: 0.039)
        case "system": return Color(red: 0.024, green: 0.025, blue: 0.028)
        default: return .black
        }
    }

    var body: some View {
        ZStack {
            base
            RadialGradient(
                colors: [HarborTVDesign.cinemaRed.opacity(0.055), .clear],
                center: .topTrailing, startRadius: 40, endRadius: 880)
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.48)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct HarborPageHeader: View {
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil
    var count: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .tracking(2.1)
                    .foregroundStyle(HarborTVDesign.cinemaRed)
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(HarborTVDesign.primaryText)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(HarborTVDesign.tertiaryText)
                }
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(HarborTVDesign.secondaryText)
                    .lineLimit(2)
            }
        }
    }
}

struct HarborSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 29 * scale, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(HarborTVDesign.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

enum HarborActionTone: Equatable {
    case primary, secondary, quiet
}

struct HarborActionButtonStyle: ButtonStyle {
    var tone: HarborActionTone = .secondary

    func makeBody(configuration: Configuration) -> some View {
        HarborActionButtonBody(configuration: configuration, tone: tone)
    }
}

private struct HarborActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tone: HarborActionTone
    @Environment(\.isFocused) private var focused

    private var foreground: Color {
        if focused || tone == .primary { return .black }
        return .white
    }

    private var fill: Color {
        if focused { return .white }
        switch tone {
        case .primary: return .white.opacity(configuration.isPressed ? 0.76 : 0.96)
        case .secondary: return .white.opacity(configuration.isPressed ? 0.20 : 0.13)
        case .quiet: return .black.opacity(configuration.isPressed ? 0.62 : 0.44)
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 25)
            .frame(minHeight: 54)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(.white.opacity(focused ? 0.95 : 0.18), lineWidth: focused ? 3 : 1))
            .scaleEffect(focused ? 1.07 : (configuration.isPressed ? 0.98 : 1))
            .shadow(color: .black.opacity(focused ? 0.56 : 0), radius: 22, y: 10)
            .animation(.easeOut(duration: 0.14), value: focused)
    }
}

struct HarborFilterPillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HarborFilterPillBody(configuration: configuration, selected: selected)
    }
}

private struct HarborFilterPillBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(focused ? .black : .white.opacity(selected ? 1 : 0.72))
            .padding(.horizontal, 21)
            .frame(height: 48)
            .background(Capsule().fill(focused ? .white : (selected ? HarborTVDesign.cinemaRed : .white.opacity(0.075))))
            .overlay(Capsule().stroke(.white.opacity(focused ? 1 : 0.10), lineWidth: focused ? 2 : 1))
            .scaleEffect(focused ? 1.07 : (configuration.isPressed ? 0.98 : 1))
            .animation(.easeOut(duration: 0.13), value: focused)
    }
}

struct HarborCardFocusStyle: ButtonStyle {
    var radius: CGFloat = HarborTVDesign.cardRadius
    var accent: Color = HarborTVDesign.cinemaRed
    var scale: CGFloat = 1.065
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        HarborCardFocusBody(configuration: configuration, radius: radius,
                            accent: accent, scale: scale, reduceMotion: reduceMotion)
    }
}

struct HarborRowFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HarborRowFocusBody(configuration: configuration)
    }
}

private struct HarborRowFocusBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? .white.opacity(0.15) : .white.opacity(0.035)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focused ? .white.opacity(0.92) : .white.opacity(0.055),
                            lineWidth: focused ? 3 : 1))
            .scaleEffect(focused ? 1.018 : (configuration.isPressed ? 0.992 : 1))
            .shadow(color: .black.opacity(focused ? 0.48 : 0), radius: 18, y: 9)
            .animation(.easeOut(duration: 0.14), value: focused)
    }
}

private struct HarborCardFocusBody: View {
    let configuration: ButtonStyle.Configuration
    let radius: CGFloat
    let accent: Color
    let scale: CGFloat
    let reduceMotion: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(focused ? .white : .white.opacity(0.07), lineWidth: focused ? 3 : 1)
            }
            .overlay(alignment: .bottom) {
                if focused {
                    Capsule()
                        .fill(accent)
                        .frame(height: 5)
                        .padding(.horizontal, 6)
                }
            }
            .scaleEffect(focused ? scale : (configuration.isPressed ? 0.985 : 1))
            .shadow(color: .black.opacity(focused ? 0.72 : 0.18), radius: focused ? 26 : 8, y: focused ? 14 : 5)
            .zIndex(focused ? 5 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
    }
}

/// Wide artwork is easier to scan on a television and mirrors the home rails
/// users already understand from major streaming apps. Portrait posters remain
/// available on catalog grids, where density matters more than recognition speed.
struct HarborLandscapeCard: View {
    let item: MetaItem
    var width: CGFloat = 350
    @AppStorage(SubtitleStyle.Key.interfaceStyle) private var interfaceStyle = "netflix"
    @AppStorage(SubtitleStyle.Key.accent) private var accentID = "green"
    @AppStorage(SubtitleStyle.Key.reduceArtworkMotion) private var reduceMotion = false

    private var height: CGFloat { width * 9 / 16 }
    private var accent: Color { HarborTVDesign.accent(interfaceStyle: interfaceStyle, fallback: accentID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: item) {
                ZStack(alignment: .bottomLeading) {
                    HarborArtworkImage(url: item.background ?? item.poster,
                                       maxPixelSize: 900,
                                       fallbackText: item.name,
                                       showProgress: true)
                        .frame(width: width, height: height)

                    LinearGradient(colors: [.clear, .black.opacity(0.86)],
                                   startPoint: .center, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 5) {
                        if item.type == "series" || item.type == "anime" {
                            Text(item.type == "anime" ? "ANIME" : "SERIES")
                                .font(.system(size: 12, weight: .heavy))
                                .tracking(1.5)
                                .foregroundStyle(accent)
                        }
                        Text(item.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(14)

                    if let rating = item.imdbRating, !rating.isEmpty {
                        ImdbBadge(rating: rating).padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: HarborTVDesign.cardRadius, style: .continuous))
            }
            .buttonStyle(HarborCardFocusStyle(accent: accent, reduceMotion: reduceMotion))

            HStack(spacing: 8) {
                if let year = item.releaseInfo, !year.isEmpty {
                    Text(year)
                }
                if let runtime = item.runtime, !runtime.isEmpty {
                    Text("•")
                    Text(runtime)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(HarborTVDesign.tertiaryText)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
        }
    }
}

struct HarborEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(HarborTVDesign.tertiaryText)
            Text(title)
                .font(.system(size: 29, weight: .bold))
            Text(message)
                .font(.system(size: 20))
                .foregroundStyle(HarborTVDesign.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }
}
