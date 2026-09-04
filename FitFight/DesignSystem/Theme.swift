import SwiftUI

// The design system has one palette, not a tintable accent. Moss is you and winning,
// Ember is urgency and losing, Gold is progress only, Ink is every surface. Night is
// the primary theme; Day is the cream counterpart of the same names.
// Source: docs/design/source/kit/FitFight Design System.dc.html

enum Mode: String, CaseIterable, Identifiable {
    case night
    case day

    var id: String { rawValue }
    var label: String {
        self == .night ? String(localized: "Night") : String(localized: "Day")
    }
    var colorScheme: ColorScheme { self == .night ? .dark : .light }
}

// MARK: - Palette

/// Hexes are parsed once at load; every lookup after that is a dictionary hit.
struct Palette {
    private let resolvedColors: [String: Color]

    init(_ raw: [String: String]) {
        resolvedColors = raw.mapValues { Color(token: $0) }
    }

    /// Magenta means the token name is wrong — loud on purpose.
    private func value(for key: String) -> Color {
        resolvedColors[key] ?? Color(red: 1, green: 0, blue: 1)
    }

    var canvas: Color { value(for: "canvas") }
    var bg: Color { value(for: "bg") }
    var overlay: Color { value(for: "overlay") }
    var card: Color { value(for: "card") }
    var control: Color { value(for: "control") }
    var controlAlt: Color { value(for: "controlAlt") }

    var text: Color { value(for: "text") }
    var textDim: Color { value(for: "textDim") }
    var textSecondary: Color { value(for: "textSecondary") }
    var textTertiary: Color { value(for: "textTertiary") }
    var textFaint: Color { value(for: "textFaint") }

    var hairline: Color { value(for: "hairline") }
    var line: Color { value(for: "line") }
    var dash: Color { value(for: "dash") }
    var track: Color { value(for: "track") }
    var chip: Color { value(for: "chip") }
    var disabledBg: Color { value(for: "disabledBg") }
    var disabledLine: Color { value(for: "disabledLine") }
    var disabledText: Color { value(for: "disabledText") }
    var scrim: Color { value(for: "scrim") }

    var mossFill: Color { value(for: "mossFill") }
    var mossEdge: Color { value(for: "mossEdge") }
    var mossText: Color { value(for: "mossText") }
    var mossSoft: Color { value(for: "mossSoft") }
    var mossOn: Color { value(for: "mossOn") }
    var mossWash: Color { value(for: "mossWash") }

    var emberFill: Color { value(for: "emberFill") }
    var emberText: Color { value(for: "emberText") }
    var emberOn: Color { value(for: "emberOn") }
    var emberWash: Color { value(for: "emberWash") }

    var gold: Color { value(for: "gold") }
    var goldInk: Color { value(for: "goldInk") }

    var tabBar: Color { value(for: "tabBar") }
    var chipInk: Color { value(for: "chipInk") }
    var chipEdgeOn: Color { value(for: "chipEdgeOn") }
    /// The kit brightens the monogram on the 54 and 68pt avatars.
    var monogram: Color { value(for: "monogram") }

    // The kit paints these as literal white over ink. Deriving them from `text`
    // (bone) tinted them warm, so they are their own tokens.
    var overlayLine: Color { value(for: "overlayLine") }
    var switchOff: Color { value(for: "switchOff") }
    var dotIdle: Color { value(for: "dotIdle") }
    var chipEdge: Color { value(for: "chipEdge") }
    var skeleton: Color { value(for: "skeleton") }
    var skeletonHi: Color { value(for: "skeletonHi") }
    var handle: Color { value(for: "handle") }
    var heroTagFill: Color { value(for: "heroTagFill") }
    var heroAvatarPlate: Color { value(for: "heroAvatarPlate") }
    var heroAvatarLine: Color { value(for: "heroAvatarLine") }
    var heroProgressTrack: Color { value(for: "heroProgressTrack") }

    // TabBarDark.dc.html / TabBar.dc.html carry their own values in both bases.
    var tabBarLine: Color { value(for: "tabBarLine") }
    var tabPillOn: Color { value(for: "tabPillOn") }
    var tabInkOn: Color { value(for: "tabInkOn") }
    var tabInkOff: Color { value(for: "tabInkOff") }
    /// The kit alternates plate fills so overlapping avatars stay legible.
    var plateAlt: Color { value(for: "plateAlt") }
}

// MARK: - Type

enum TypeRole: String {
    case metric, title, heading, rowTitle
    case button, buttonLarge, buttonSmall
    case label, body, caption, micro
    case eyebrow, sectionEyebrow, tag
}

struct TypeSpec: Decodable {
    var size: CGFloat
    var weight: Int
    var tracking: CGFloat?
    var uppercase: Bool?
}

struct TypeScale: Decodable {
    var family: String
    var roles: [String: TypeSpec]

    func spec(_ role: TypeRole) -> TypeSpec {
        roles[role.rawValue] ?? TypeSpec(size: 14, weight: 700, tracking: nil, uppercase: nil)
    }
}

struct RadiusScale: Decodable {
    var pill: CGFloat
    var card: CGFloat
    var field: CGFloat
    var glyph: CGFloat
    var shell: CGFloat
}

struct SpaceScale: Decodable {
    var xs, sm, md, base, lg, xl: CGFloat
    var screenPadding, cardPadding: CGFloat
    var rowPaddingX, rowPaddingY: CGFloat
    var sectionGap, cardGap, tabBarClearance: CGFloat
}

struct MotionSpec: Decodable {
    var duration: Double
    var curve: String

    /// cubic-bezier(0.16, 1, 0.3, 1) is the kit's one easing curve.
    var animation: Animation {
        switch curve {
        case "expo": return .timingCurve(0.16, 1, 0.3, 1, duration: duration)
        case "easeOut": return .easeOut(duration: duration)
        default: return .linear(duration: duration)
        }
    }
}

struct MotionScale: Decodable {
    var instant, quick, sheet, count, celebrate, shimmer: MotionSpec
}

struct Swatch: Decodable {
    var name: String
    var value: String
    var use: String
}

struct SwatchGroup: Decodable {
    var title: String
    var items: [Swatch]
}

// MARK: - Theme

@dynamicMemberLookup
struct Theme {
    var mode: Mode
    var palette: Palette
    var type: TypeScale
    var radius: RadiusScale
    var space: SpaceScale
    var motion: MotionScale

    /// theme.card instead of theme.palette.card.
    subscript<T>(dynamicMember keyPath: KeyPath<Palette, T>) -> T {
        palette[keyPath: keyPath]
    }

    var colorScheme: ColorScheme { mode.colorScheme }

    func font(_ role: TypeRole) -> Font {
        let spec = type.spec(role)
        return .ff(spec.size, spec.weight)
    }

    /// CSS letter-spacing is em-relative; SwiftUI tracking is in points.
    func tracking(_ role: TypeRole) -> CGFloat {
        let spec = type.spec(role)
        return spec.size * (spec.tracking ?? 0)
    }

    func isUppercase(_ role: TypeRole) -> Bool {
        type.spec(role).uppercase ?? false
    }
}

// MARK: - Loading

struct TokenFile: Decodable {
    var swatches: [SwatchGroup]
    var palettes: [String: [String: String]]
    var type: TypeScale
    var radius: RadiusScale
    var space: SpaceScale
    var motion: MotionScale

    func theme(_ mode: Mode) -> Theme {
        Theme(
            mode: mode,
            palette: Palette(palettes[mode.rawValue] ?? [:]),
            type: type,
            radius: radius,
            space: space,
            motion: motion
        )
    }
}

enum ThemeCatalog {
    static func theme(_ mode: Mode) -> Theme { file.theme(mode) }
    static var swatches: [SwatchGroup] { file.swatches }

    /// tokens.json ships in the Resources build phase. A missing or malformed file is a
    /// packaging error, not a runtime condition — fail on first launch rather than
    /// silently render a second, drifted palette.
    private static let file: TokenFile = {
        guard let url = Bundle.main.url(forResource: "tokens", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("tokens.json missing from the app bundle — check the Resources build phase.")
        }
        do {
            return try JSONDecoder().decode(TokenFile.self, from: data)
        } catch {
            fatalError("tokens.json failed to decode: \(error)")
        }
    }()
}

final class ThemeStore: ObservableObject {
    @Published var mode: Mode {
        didSet { if persists { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) } }
    }

    var theme: Theme { ThemeCatalog.theme(mode) }

    private static let key = "ff.mode"
    private let persists: Bool

    init() {
        persists = true
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? Mode.night.rawValue
        mode = Mode(rawValue: raw) ?? .night
    }

    /// Previews and the screenshot export set a mode to render it, not to choose it —
    /// without this they would leave the real app in whichever base they rendered last.
    init(transient mode: Mode) {
        persists = false
        self.mode = mode
    }
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeCatalog.theme(.night)
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
            .tint(theme.mossFill)
            .preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - Colour parsing

extension Color {
    init(token raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("rgba") || value.hasPrefix("rgb") {
            self.init(rgba: value)
        } else {
            self.init(hex: value)
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
            (r, g, b, a) = (255, 0, 255, 255)
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
        func part(_ i: Int, _ fallback: Double) -> Double {
            guard parts.indices.contains(i), let v = Double(parts[i]) else { return fallback }
            return v
        }
        self.init(
            .sRGB,
            red: part(0, 0) / 255,
            green: part(1, 0) / 255,
            blue: part(2, 0) / 255,
            opacity: part(3, 1)
        )
    }
}
