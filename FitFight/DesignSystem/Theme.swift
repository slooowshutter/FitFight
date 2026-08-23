import SwiftUI

enum BaseID: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum AccentID: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case graphite

    var id: String { rawValue }
}

enum TypeRole: String {
    case heroNumber
    case display
    case title
    case headline
    case rank
    case bodyStrong
    case body
    case label
    case caption
    case micro
    case eyebrow
    case tiny
}

struct Theme {
    var baseID: BaseID
    var accentID: AccentID
    var lookID: LookID

    var bg: Color
    var surface: Color
    var surface2: Color
    var line: Color
    var hair: Color
    var text: Color
    var muted: Color
    var faint: Color
    var chip: Color
    var track: Color
    var scrim: Color

    var accent: Color
    var accentDim: Color
    var ink: Color
    var onPhoto: Color

    var green: Color
    var blue: Color
    var amber: Color
    var red: Color

    var type: TypeTokens
    var space: SpaceTokens
    var radius: RadiusTokens

    /// Measured card corner. Classic is 22, not `radius.xl` (24).
    var cardRadius: CGFloat
    var tightCardRadius: CGFloat
    var chipRadius: CGFloat
    var buttonRadius: CGFloat
    var segmentRadius: CGFloat
    var segmentThumbRadius: CGFloat
    var cornerStyle: RoundedCornerStyle

    var colorScheme: ColorScheme { baseID.colorScheme }

    func font(_ role: TypeRole) -> Font {
        let spec = type.spec(role)
        return .ff(spec.size, spec.weight)
    }

    func tracking(_ role: TypeRole) -> CGFloat {
        let spec = type.spec(role)
        return spec.size * spec.letterSpacing
    }

    func rounded(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: cornerStyle)
    }

    /// Bars that aren't first place and aren't you.
    func otherBar() -> Color { text.opacity(0.45) }

    func selectedRow() -> Color { accent.opacity(0.07) }
    func selectedOption() -> Color { accent.opacity(0.08) }
    func badgeFill() -> Color { accent.opacity(0.12) }
    func focusRing() -> Color { accent.opacity(0.20) }
}

struct TypeSpec {
    var size: CGFloat
    var weight: Font.Weight
    var letterSpacing: CGFloat
    var uppercase: Bool
}

struct TypeTokens {
    var roles: [TypeRole: TypeSpec]

    func spec(_ role: TypeRole) -> TypeSpec {
        roles[role] ?? TypeSpec(size: 14, weight: .regular, letterSpacing: 0, uppercase: false)
    }
}

struct SpaceTokens {
    var xs: CGFloat
    var sm: CGFloat
    var md: CGFloat
    var base: CGFloat
    var lg: CGFloat
    var xl: CGFloat
    var screenPadding: CGFloat
    var cardPadding: CGFloat
    var rowPaddingX: CGFloat
    var rowPaddingY: CGFloat
    var sectionGap: CGFloat
    var cardGap: CGFloat
    var tabBarClearance: CGFloat
}

struct RadiusTokens {
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
    var xl: CGFloat
    var full: CGFloat
}

enum ThemeCatalog {
    static let file: TokenFile = load()

    static func theme(base: BaseID, accent: AccentID, look: LookID = .classic) -> Theme {
        var theme = file.theme(base: base, accent: accent)
        LookCatalog.apply(look, base: base, to: &theme)
        return theme
    }

    private static func load() -> TokenFile {
        let url = Bundle.main.url(forResource: "tokens", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        if let data, let decoded = try? JSONDecoder().decode(TokenFile.self, from: data) {
            return decoded
        }
        return .fallback
    }
}

final class ThemeStore: ObservableObject {
    @Published var baseID: BaseID {
        didSet { UserDefaults.standard.set(baseID.rawValue, forKey: Self.baseKey) }
    }

    @Published var accentID: AccentID {
        didSet { UserDefaults.standard.set(accentID.rawValue, forKey: Self.accentKey) }
    }

    @Published var lookID: LookID {
        didSet { UserDefaults.standard.set(lookID.rawValue, forKey: Self.lookKey) }
    }

    var theme: Theme {
        ThemeCatalog.theme(base: baseID, accent: accentID, look: lookID)
    }

    private static let baseKey = "ff.baseID"
    private static let accentKey = "ff.accentID"
    private static let lookKey = "ff.lookID"

    init() {
        let baseRaw = UserDefaults.standard.string(forKey: Self.baseKey) ?? BaseID.dark.rawValue
        let accentRaw = UserDefaults.standard.string(forKey: Self.accentKey) ?? AccentID.blue.rawValue
        let lookRaw = UserDefaults.standard.string(forKey: Self.lookKey) ?? LookID.classic.rawValue
        baseID = BaseID(rawValue: baseRaw) ?? .dark
        accentID = AccentID(rawValue: accentRaw) ?? .blue
        lookID = LookID(rawValue: lookRaw) ?? .classic
    }

    func selectLook(_ look: LookID) {
        guard look != lookID else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            lookID = look
        }
    }
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeCatalog.theme(base: .dark, accent: .blue)
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
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
    }
}

struct TokenFile: Decodable {
    var colors: ColorFile
    var type: TypeFile
    var space: SpaceFile
    var radius: RadiusFile

    func theme(base: BaseID, accent: AccentID) -> Theme {
        let baseColors = colors.bases[base.rawValue] ?? colors.bases["dark"]!
        let accentColors = colors.accents[accent.rawValue] ?? colors.accents["blue"]!
        return Theme(
            baseID: base,
            accentID: accent,
            lookID: .classic,
            bg: Color(token: baseColors.bg),
            surface: Color(token: baseColors.surface),
            surface2: Color(token: baseColors.surface2),
            line: Color(token: baseColors.line),
            hair: Color(token: baseColors.hair),
            text: Color(token: baseColors.text),
            muted: Color(token: baseColors.muted),
            faint: Color(token: baseColors.faint),
            chip: Color(token: baseColors.chip),
            track: Color(token: baseColors.track),
            scrim: Color(scrim: baseColors.scrim).opacity(0.6),
            accent: Color(token: accentColors.accent),
            accentDim: Color(token: accentColors.accentDim),
            ink: Color(token: accentColors.ink),
            onPhoto: Color(token: colors.onPhoto),
            green: Color(token: colors.data.green),
            blue: Color(token: colors.data.blue),
            amber: Color(token: colors.data.amber),
            red: Color(token: colors.data.red),
            type: type.tokens,
            space: space.tokens,
            radius: radius.tokens,
            cardRadius: 22,
            tightCardRadius: 15,
            chipRadius: 10,
            buttonRadius: 9999,
            segmentRadius: 11,
            segmentThumbRadius: 8,
            cornerStyle: .continuous
        )
    }

    static let fallback: TokenFile = {
        let json = """
        {"colors":{"bases":{"dark":{"bg":"#101114","surface":"#191b1f","surface2":"#212429","line":"rgba(255,255,255,0.10)","hair":"rgba(255,255,255,0.06)","text":"#ffffff","muted":"rgba(255,255,255,0.62)","faint":"rgba(255,255,255,0.40)","scrim":"16,17,20","chip":"rgba(255,255,255,0.055)","track":"rgba(255,255,255,0.09)"},"light":{"bg":"#f4f4f6","surface":"#ffffff","surface2":"#eaeaee","line":"rgba(0,0,0,0.10)","hair":"rgba(0,0,0,0.065)","text":"#15171a","muted":"rgba(0,0,0,0.58)","faint":"rgba(0,0,0,0.42)","scrim":"21,23,26","chip":"rgba(0,0,0,0.045)","track":"rgba(0,0,0,0.08)"}},"accents":{"blue":{"name":"Blue","accent":"#1a6ef5","accentDim":"#114db3","ink":"#ffffff"}},"data":{"green":"#16a34a","blue":"#2f86e0","amber":"#e0a010","red":"#e0483f"},"onPhoto":"#ffffff"},"type":{"roles":{"heroNumber":{"size":34,"weight":700},"display":{"size":26,"weight":700,"letterSpacing":-0.02},"title":{"size":23,"weight":700,"letterSpacing":-0.02},"headline":{"size":19,"weight":700},"rank":{"size":17,"weight":700},"bodyStrong":{"size":15,"weight":600},"body":{"size":14,"weight":400},"label":{"size":13,"weight":700},"caption":{"size":12,"weight":400},"micro":{"size":11,"weight":400},"eyebrow":{"size":10,"weight":600,"letterSpacing":0.16,"transform":"uppercase"},"tiny":{"size":9,"weight":600,"transform":"uppercase"}}},"space":{"scale":{"xs":4,"sm":8,"md":12,"base":16,"lg":20,"xl":28},"rules":{"screenPadding":16,"cardPadding":20,"rowPaddingX":16,"rowPaddingY":14,"sectionGap":28,"cardGap":14,"tabBarClearance":128}},"radius":{"sm":8,"md":12,"lg":16,"xl":24,"full":9999}}
        """
        return try! JSONDecoder().decode(TokenFile.self, from: Data(json.utf8))
    }()
}

struct ColorFile: Decodable {
    var bases: [String: BaseColors]
    var accents: [String: AccentColors]
    var data: DataColors
    var onPhoto: String
}

struct BaseColors: Decodable {
    var bg: String
    var surface: String
    var surface2: String
    var line: String
    var hair: String
    var text: String
    var muted: String
    var faint: String
    var scrim: String
    var chip: String
    var track: String
}

struct AccentColors: Decodable {
    var name: String
    var accent: String
    var accentDim: String
    var ink: String
}

struct DataColors: Decodable {
    var green: String
    var blue: String
    var amber: String
    var red: String
}

struct TypeFile: Decodable {
    var roles: [String: RoleFile]

    var tokens: TypeTokens {
        var map: [TypeRole: TypeSpec] = [:]
        for (key, role) in roles {
            guard let typeRole = TypeRole(rawValue: key) else { continue }
            map[typeRole] = TypeSpec(
                size: role.size,
                weight: Font.Weight(token: role.weight),
                letterSpacing: role.letterSpacing ?? 0,
                uppercase: role.transform == "uppercase"
            )
        }
        return TypeTokens(roles: map)
    }
}

struct RoleFile: Decodable {
    var size: CGFloat
    var weight: Int
    var letterSpacing: CGFloat?
    var transform: String?
}

struct SpaceFile: Decodable {
    var scale: ScaleFile
    var rules: RulesFile

    var tokens: SpaceTokens {
        SpaceTokens(
            xs: scale.xs,
            sm: scale.sm,
            md: scale.md,
            base: scale.base,
            lg: scale.lg,
            xl: scale.xl,
            screenPadding: rules.screenPadding,
            cardPadding: rules.cardPadding,
            rowPaddingX: rules.rowPaddingX,
            rowPaddingY: rules.rowPaddingY,
            sectionGap: rules.sectionGap,
            cardGap: rules.cardGap,
            tabBarClearance: rules.tabBarClearance
        )
    }
}

struct ScaleFile: Decodable {
    var xs: CGFloat
    var sm: CGFloat
    var md: CGFloat
    var base: CGFloat
    var lg: CGFloat
    var xl: CGFloat
}

struct RulesFile: Decodable {
    var screenPadding: CGFloat
    var cardPadding: CGFloat
    var rowPaddingX: CGFloat
    var rowPaddingY: CGFloat
    var sectionGap: CGFloat
    var cardGap: CGFloat
    var tabBarClearance: CGFloat
}

struct RadiusFile: Decodable {
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
    var xl: CGFloat
    var full: CGFloat

    var tokens: RadiusTokens {
        RadiusTokens(sm: sm, md: md, lg: lg, xl: xl, full: full)
    }
}

extension Font.Weight {
    init(token value: Int) {
        switch value {
        case ...450: self = .regular
        case ...550: self = .medium
        case ...650: self = .semibold
        default: self = .bold
        }
    }
}

extension Color {
    init(token raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            self.init(hex: value)
        } else if value.hasPrefix("rgba") {
            self.init(rgba: value)
        } else {
            self.init(hex: "#000000")
        }
    }

    init(scrim raw: String) {
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            self.init(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: 1)
        } else {
            self.init(hex: "#101114")
        }
    }

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

    init(rgba: String) {
        let inner = rgba.drop { $0 != "(" }.dropFirst().dropLast()
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let r = Double(parts[safe: 0] ?? "0") ?? 0
        let g = Double(parts[safe: 1] ?? "0") ?? 0
        let b = Double(parts[safe: 2] ?? "0") ?? 0
        let a = Double(parts[safe: 3] ?? "1") ?? 1
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
