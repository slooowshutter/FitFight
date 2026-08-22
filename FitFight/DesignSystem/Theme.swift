import SwiftUI

enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case arena
    case pulse
    case locker
    case rogue

    var id: String { rawValue }
}

enum FontRole: String, Codable {
    case rounded
    case `default`
    case condensed
    case serif
    case mono
}

enum FontWeightName: String, Codable {
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black
}

struct ThemeColors {
    var bg: Color
    var surface: Color
    var raised: Color
    var text: Color
    var muted: Color
    var accent: Color
    var accentText: Color
    var danger: Color
    var dangerText: Color
    var success: Color
    var border: Color
}

struct ThemeMetrics {
    var radiusSm: CGFloat
    var radiusMd: CGFloat
    var radiusLg: CGFloat
    var spaceXs: CGFloat
    var spaceSm: CGFloat
    var spaceMd: CGFloat
    var spaceLg: CGFloat
    var spaceXl: CGFloat
    var continuousCorners: Bool

    var cornerStyle: RoundedCornerStyle {
        continuousCorners ? .continuous : .circular
    }
}

struct ThemeTypography {
    var display: FontRole
    var body: FontRole
    var mono: FontRole
    var displaySize: CGFloat
    var displayWeight: FontWeightName
}

struct Theme: Identifiable {
    var id: ThemeID
    var name: String
    var blurb: String
    var dark: Bool
    var colors: ThemeColors
    var metrics: ThemeMetrics
    var type: ThemeTypography

    var colorScheme: ColorScheme {
        dark ? .dark : .light
    }

    func font(_ role: FontRole, size: CGFloat, weight: Font.Weight) -> Font {
        switch role {
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .default:
            return .system(size: size, weight: weight, design: .default)
        case .condensed:
            return .system(size: size, weight: weight, design: .default).width(.condensed)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    func displayFont() -> Font {
        font(type.display, size: type.displaySize, weight: type.displayWeight.weight)
    }

    func bodyFont(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        font(type.body, size: size, weight: weight)
    }

    func monoFont(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        font(type.mono, size: size, weight: weight)
    }
}

enum ThemeCatalog {
    static let all: [Theme] = load()

    static func named(_ id: ThemeID) -> Theme {
        all.first(where: { $0.id == id }) ?? missing
    }

    private static let missing = Theme(
        id: .arena,
        name: "Missing",
        blurb: "themes.json failed to load. Check the app bundle.",
        dark: true,
        colors: ThemeColors(
            bg: Color(hex: "#FF00AA"),
            surface: Color(hex: "#220011"),
            raised: Color(hex: "#330022"),
            text: .white,
            muted: Color.white.opacity(0.7),
            accent: .white,
            accentText: .black,
            danger: Color(hex: "#FF00AA"),
            dangerText: .white,
            success: .white,
            border: .white
        ),
        metrics: ThemeMetrics(
            radiusSm: 8,
            radiusMd: 12,
            radiusLg: 16,
            spaceXs: 4,
            spaceSm: 8,
            spaceMd: 16,
            spaceLg: 24,
            spaceXl: 40,
            continuousCorners: true
        ),
        type: ThemeTypography(
            display: .rounded,
            body: .rounded,
            mono: .mono,
            displaySize: 44,
            displayWeight: .heavy
        )
    )

    private static func load() -> [Theme] {
        let url = Bundle.main.url(forResource: "themes", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let file = data.flatMap { try? JSONDecoder().decode(ThemeFile.self, from: $0) }
        let decoded = file?.themes.map(\.theme) ?? []
        return decoded.isEmpty ? [missing] : decoded
    }
}

final class ThemeStore: ObservableObject {
    private static let defaultsKey = "ff.themeID"

    @Published var themeID: ThemeID {
        didSet {
            UserDefaults.standard.set(themeID.rawValue, forKey: Self.defaultsKey)
        }
    }

    var current: Theme {
        ThemeCatalog.named(themeID)
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ThemeID.arena.rawValue
        themeID = ThemeID(rawValue: raw) ?? .arena
    }

    init(preview themeID: ThemeID) {
        self.themeID = themeID
    }
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeCatalog.named(.arena)
}

extension EnvironmentValues {
    var ffTheme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func fitFightTheme(_ theme: Theme) -> some View {
        environment(\.ffTheme, theme)
            .tint(theme.colors.accent)
            .preferredColorScheme(theme.colorScheme)
    }
}

extension FontWeightName {
    var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r, g, b, a: UInt64
        switch raw.count {
        case 8:
            (r, g, b, a) = ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        case 6:
            (r, g, b, a) = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF, 255)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private struct ThemeFile: Decodable {
    var themes: [ThemeDTO]
}

private struct ThemeDTO: Decodable {
    var id: ThemeID
    var name: String
    var blurb: String
    var dark: Bool
    var continuousCorners: Bool
    var colors: ColorDTO
    var radius: RadiusDTO
    var space: SpaceDTO
    var type: TypeDTO

    var theme: Theme {
        Theme(
            id: id,
            name: name,
            blurb: blurb,
            dark: dark,
            colors: ThemeColors(
                bg: Color(hex: colors.bg),
                surface: Color(hex: colors.surface),
                raised: Color(hex: colors.raised),
                text: Color(hex: colors.text),
                muted: Color(hex: colors.muted),
                accent: Color(hex: colors.accent),
                accentText: Color(hex: colors.accentText),
                danger: Color(hex: colors.danger),
                dangerText: Color(hex: colors.dangerText),
                success: Color(hex: colors.success),
                border: Color(hex: colors.border)
            ),
            metrics: ThemeMetrics(
                radiusSm: radius.sm,
                radiusMd: radius.md,
                radiusLg: radius.lg,
                spaceXs: space.xs,
                spaceSm: space.sm,
                spaceMd: space.md,
                spaceLg: space.lg,
                spaceXl: space.xl,
                continuousCorners: continuousCorners
            ),
            type: ThemeTypography(
                display: type.display,
                body: type.body,
                mono: type.mono,
                displaySize: type.displaySize,
                displayWeight: type.displayWeight
            )
        )
    }
}

private struct ColorDTO: Decodable {
    var bg: String
    var surface: String
    var raised: String
    var text: String
    var muted: String
    var accent: String
    var accentText: String
    var danger: String
    var dangerText: String
    var success: String
    var border: String
}

private struct RadiusDTO: Decodable {
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
}

private struct SpaceDTO: Decodable {
    var xs: CGFloat
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
    var xl: CGFloat
}

private struct TypeDTO: Decodable {
    var display: FontRole
    var body: FontRole
    var mono: FontRole
    var displaySize: CGFloat
    var displayWeight: FontWeightName
}
