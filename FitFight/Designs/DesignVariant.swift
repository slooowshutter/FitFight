import SwiftUI

/// A design direction. Each one owns a palette, a shape/type treatment and its own
/// take on the Fights screen. Every variant reads the same `AppModel` — the fights,
/// the names, the numbers and the copy never change between them, only the look.
///
/// `original` is the approved design in `docs/design/source`; the other ten are
/// experiments you can flip between from the Design tab.
enum DesignVariant: String, CaseIterable, Identifiable {
    case original
    case ring
    case ledger
    case arena
    case soft
    case terminal
    case stack
    case podium
    case pulse
    case bento
    case zine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .ring: return "Ring"
        case .ledger: return "Ledger"
        case .arena: return "Arena"
        case .soft: return "Soft"
        case .terminal: return "Terminal"
        case .stack: return "Stack"
        case .podium: return "Podium"
        case .pulse: return "Pulse"
        case .bento: return "Bento"
        case .zine: return "Zine"
        }
    }

    var blurb: String {
        switch self {
        case .original: return "The approved design. Cards, blue accent, dark."
        case .ring: return "Closed-ring fitness. Acid lime on black, rank inside the ring."
        case .ledger: return "A betting statement. Bone paper, mono figures, no cards."
        case .arena: return "Fight-night poster. Condensed caps, you versus the leader."
        case .soft: return "Calm and roomy. Warm paper, big radii, one sentence per fight."
        case .terminal: return "Monospace readout. Block bars, zero radius, green on black."
        case .stack: return "Frosted glass over colour. Layered depth, floating status pill."
        case .podium: return "Leaderboard first. A gold podium up top, then compact rows."
        case .pulse: return "Share of the pot as one stacked bar. Teal, chart-forward."
        case .bento: return "Asymmetric tiles. Light, deep rose accent, mixed sizes."
        case .zine: return "Editorial print. Huge figures, thick rules, ink and one red."
        }
    }
}

// MARK: - Palette

/// A variant's colour and shape overrides. The base `Theme` supplies everything
/// else (type scale, spacing), so a variant only states what it actually changes.
struct DesignPalette {
    var scheme: ColorScheme
    var bg: String
    var surface: String
    var surface2: String
    var line: String
    var hair: String
    var text: String
    var muted: String
    var faint: String
    var chip: String
    var track: String
    var accent: String
    var accentDim: String
    var ink: String
    var green: String = "#16a34a"
    var red: String = "#e0483f"
    var amber: String = "#e0a010"
    /// Card corner. Every other radius is derived from it, so a variant is round
    /// or square in one number instead of twelve.
    var cardRadius: CGFloat = 22

    func apply(to base: Theme) -> Theme {
        var theme = base
        theme.baseID = scheme == .dark ? .dark : .light
        theme.bg = Color(token: bg)
        theme.surface = Color(token: surface)
        theme.surface2 = Color(token: surface2)
        theme.line = Color(token: line)
        theme.hair = Color(token: hair)
        theme.text = Color(token: text)
        theme.muted = Color(token: muted)
        theme.faint = Color(token: faint)
        theme.chip = Color(token: chip)
        theme.track = Color(token: track)
        theme.accent = Color(token: accent)
        theme.accentDim = Color(token: accentDim)
        theme.ink = Color(token: ink)
        theme.green = Color(token: green)
        theme.red = Color(token: red)
        theme.amber = Color(token: amber)
        theme.scrim = Color(token: bg).opacity(0.6)
        theme.radius = RadiusTokens(
            sm: cardRadius * 0.36,
            md: cardRadius * 0.55,
            lg: cardRadius * 0.73,
            xl: cardRadius,
            full: 9999
        )
        return theme
    }
}

extension DesignVariant {
    /// nil means "leave the token theme alone" — that is what makes `original` original.
    var palette: DesignPalette? {
        switch self {
        case .original:
            return nil
        case .ring:
            return DesignPalette(
                scheme: .dark,
                bg: "#0b0b0d", surface: "#151517", surface2: "#1e1e21",
                line: "rgba(255,255,255,0.09)", hair: "rgba(255,255,255,0.05)",
                text: "#ffffff", muted: "rgba(255,255,255,0.60)", faint: "rgba(255,255,255,0.38)",
                chip: "rgba(255,255,255,0.05)", track: "rgba(255,255,255,0.10)",
                accent: "#d6ff3f", accentDim: "#8fae1f", ink: "#14170a",
                green: "#3ddc84", red: "#ff4d5a", amber: "#ffc857",
                cardRadius: 20
            )
        case .ledger:
            return DesignPalette(
                scheme: .light,
                bg: "#f2f0ea", surface: "#fbfaf7", surface2: "#e9e6de",
                line: "rgba(23,21,15,0.14)", hair: "rgba(23,21,15,0.09)",
                text: "#17150f", muted: "rgba(23,21,15,0.62)", faint: "rgba(23,21,15,0.42)",
                chip: "rgba(23,21,15,0.05)", track: "rgba(23,21,15,0.10)",
                accent: "#0b6e4f", accentDim: "#08543c", ink: "#ffffff",
                green: "#0b6e4f", red: "#b3261e", amber: "#9a6b00",
                cardRadius: 6
            )
        case .arena:
            return DesignPalette(
                scheme: .dark,
                bg: "#0c0a0a", surface: "#171212", surface2: "#221919",
                line: "rgba(255,236,232,0.11)", hair: "rgba(255,236,232,0.06)",
                text: "#fff8f5", muted: "rgba(255,248,245,0.60)", faint: "rgba(255,248,245,0.38)",
                chip: "rgba(229,52,42,0.10)", track: "rgba(255,248,245,0.10)",
                accent: "#e5342a", accentDim: "#a11f18", ink: "#ffffff",
                green: "#4ac26b", red: "#e5342a", amber: "#e8a33a",
                cardRadius: 4
            )
        case .soft:
            return DesignPalette(
                scheme: .light,
                bg: "#f5f1eb", surface: "#ffffff", surface2: "#efeae2",
                line: "rgba(42,39,36,0.08)", hair: "rgba(42,39,36,0.06)",
                text: "#2a2724", muted: "rgba(42,39,36,0.60)", faint: "rgba(42,39,36,0.40)",
                chip: "rgba(124,143,95,0.10)", track: "rgba(42,39,36,0.08)",
                accent: "#6f8455", accentDim: "#556740", ink: "#ffffff",
                green: "#4f7a4a", red: "#b8524a", amber: "#c08a3e",
                cardRadius: 28
            )
        case .terminal:
            return DesignPalette(
                scheme: .dark,
                bg: "#0d0f0d", surface: "#121512", surface2: "#171b17",
                line: "rgba(110,231,135,0.20)", hair: "rgba(110,231,135,0.11)",
                text: "#d9e6d9", muted: "rgba(217,230,217,0.58)", faint: "rgba(217,230,217,0.36)",
                chip: "rgba(110,231,135,0.07)", track: "rgba(217,230,217,0.10)",
                accent: "#6ee787", accentDim: "#3fa658", ink: "#0d0f0d",
                green: "#6ee787", red: "#ff6b6b", amber: "#e8c33c",
                cardRadius: 0
            )
        case .stack:
            return DesignPalette(
                scheme: .dark,
                bg: "#0e1020", surface: "#1a1d33", surface2: "#232742",
                line: "rgba(255,255,255,0.10)", hair: "rgba(255,255,255,0.06)",
                text: "#f2f4ff", muted: "rgba(242,244,255,0.62)", faint: "rgba(242,244,255,0.40)",
                chip: "rgba(255,255,255,0.07)", track: "rgba(255,255,255,0.10)",
                accent: "#5b8cff", accentDim: "#3a5fc0", ink: "#0a0d1c",
                green: "#4ad6a0", red: "#ff6b81", amber: "#ffc16b",
                cardRadius: 26
            )
        case .podium:
            return DesignPalette(
                scheme: .dark,
                bg: "#0b1220", surface: "#131c2e", surface2: "#1b2740",
                line: "rgba(232,185,72,0.16)", hair: "rgba(255,255,255,0.06)",
                text: "#f4f7ff", muted: "rgba(244,247,255,0.60)", faint: "rgba(244,247,255,0.38)",
                chip: "rgba(232,185,72,0.09)", track: "rgba(255,255,255,0.10)",
                accent: "#e8b948", accentDim: "#a8811f", ink: "#20180a",
                green: "#48c98a", red: "#e35d5d", amber: "#e8b948",
                cardRadius: 18
            )
        case .pulse:
            return DesignPalette(
                scheme: .dark,
                bg: "#07100f", surface: "#0e1918", surface2: "#142322",
                line: "rgba(45,212,191,0.16)", hair: "rgba(230,244,241,0.06)",
                text: "#e6f4f1", muted: "rgba(230,244,241,0.60)", faint: "rgba(230,244,241,0.38)",
                chip: "rgba(45,212,191,0.08)", track: "rgba(230,244,241,0.08)",
                accent: "#2dd4bf", accentDim: "#17958a", ink: "#06201d",
                green: "#2dd4bf", red: "#f2637e", amber: "#f0b429",
                cardRadius: 14
            )
        case .bento:
            return DesignPalette(
                scheme: .light,
                bg: "#eeedf1", surface: "#ffffff", surface2: "#e4e3e9",
                line: "rgba(20,20,22,0.08)", hair: "rgba(20,20,22,0.06)",
                text: "#141416", muted: "rgba(20,20,22,0.58)", faint: "rgba(20,20,22,0.40)",
                chip: "rgba(20,20,22,0.05)", track: "rgba(20,20,22,0.08)",
                accent: "#d6355a", accentDim: "#a11f40", ink: "#ffffff",
                green: "#1f7a4d", red: "#d6355a", amber: "#b57a00",
                cardRadius: 24
            )
        case .zine:
            return DesignPalette(
                scheme: .light,
                bg: "#ece8df", surface: "#ece8df", surface2: "#e1dcd0",
                line: "rgba(17,17,17,0.88)", hair: "rgba(17,17,17,0.22)",
                text: "#111111", muted: "rgba(17,17,17,0.66)", faint: "rgba(17,17,17,0.45)",
                chip: "rgba(17,17,17,0.06)", track: "rgba(17,17,17,0.14)",
                accent: "#d22b1f", accentDim: "#9c1c13", ink: "#ece8df",
                green: "#1f6b3a", red: "#d22b1f", amber: "#8a6a00",
                cardRadius: 0
            )
        }
    }

    func theme(_ base: Theme) -> Theme {
        palette?.apply(to: base) ?? base
    }

    /// The Fights screen, in this design's language.
    @ViewBuilder
    var fightsScreen: some View {
        switch self {
        case .original: FightsListView()
        case .ring: RingFightsView()
        case .ledger: LedgerFightsView()
        case .arena: ArenaFightsView()
        case .soft: SoftFightsView()
        case .terminal: TerminalFightsView()
        case .stack: StackFightsView()
        case .podium: PodiumFightsView()
        case .pulse: PulseFightsView()
        case .bento: BentoFightsView()
        case .zine: ZineFightsView()
        }
    }
}

// MARK: - Store

final class DesignStore: ObservableObject {
    @Published var variant: DesignVariant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.key) }
    }

    private static let key = "ff.design"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        variant = DesignVariant(rawValue: raw) ?? .original
    }
}

// MARK: - Shared helpers

extension Fight {
    /// Standings without the people who have not accepted yet, best first.
    var ranked: [Standing] {
        standings.filter { !$0.invited }.sorted { $0.score > $1.score }
    }

    var leader: Standing? { ranked.first }

    var yours: Standing? { standings.first { $0.person.isYou } }

    /// Where you sit among the people who actually joined.
    var yourPlace: Int? {
        ranked.firstIndex { $0.person.isYou }.map { $0 + 1 }
    }

    var notJoined: Int { standings.filter(\.invited).count }
}

extension View {
    /// Theme without `preferredColorScheme`. The full `fitFightTheme` sets the
    /// scheme for the whole window, which would let a gallery tile repaint the
    /// app behind it, so previews use this instead.
    func ffThemeOnly(_ theme: Theme) -> some View {
        environment(\.ffTheme, theme)
            .environment(\.colorScheme, theme.colorScheme)
            .tint(theme.accent)
    }
}

/// Monospaced figures, for the variants whose whole personality is the numbers.
extension Font {
    static func ffMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
