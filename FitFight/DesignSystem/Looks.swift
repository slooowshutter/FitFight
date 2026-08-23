import SwiftUI

/// A full visual system on top of base × accent.
/// Classic is the approved kit in `tokens.json`. The other five are alternatives
/// you can try in You → Look; they keep your accent and Dark/Light.
enum LookID: String, CaseIterable, Identifiable {
    case classic
    case ink
    case paper
    case harbor
    case grid
    case dusk

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .ink: return "Ink"
        case .paper: return "Paper"
        case .harbor: return "Harbor"
        case .grid: return "Grid"
        case .dusk: return "Dusk"
        }
    }

    var blurb: String {
        switch self {
        case .classic: return "The original."
        case .ink: return "True black. Tighter."
        case .paper: return "Warm, printed."
        case .harbor: return "Navy. Night game."
        case .grid: return "Sharp. High contrast."
        case .dusk: return "Softer, rounder."
        }
    }
}

enum LookCatalog {
    static func apply(_ look: LookID, base: BaseID, to theme: inout Theme) {
        theme.lookID = look
        guard look != .classic else { return }
        let recipe = recipe(look)
        paint(base == .dark ? recipe.dark : recipe.light, onto: &theme)
        theme.cardRadius = recipe.cardRadius
        theme.tightCardRadius = recipe.tightCardRadius
        theme.chipRadius = recipe.chipRadius
        theme.buttonRadius = recipe.buttonRadius
        theme.segmentRadius = recipe.segmentRadius
        theme.segmentThumbRadius = recipe.segmentThumbRadius
        theme.radius = recipe.radius
        theme.cornerStyle = recipe.cornerStyle
    }

    private static func paint(_ palette: LookPalette, onto theme: inout Theme) {
        theme.bg = Color(token: palette.bg)
        theme.surface = Color(token: palette.surface)
        theme.surface2 = Color(token: palette.surface2)
        theme.line = Color(token: palette.line)
        theme.hair = Color(token: palette.hair)
        theme.text = Color(token: palette.text)
        theme.muted = Color(token: palette.muted)
        theme.faint = Color(token: palette.faint)
        theme.chip = Color(token: palette.chip)
        theme.track = Color(token: palette.track)
        theme.scrim = Color(scrim: palette.scrim).opacity(0.6)
    }

    private static func recipe(_ look: LookID) -> LookRecipe {
        switch look {
        case .classic:
            preconditionFailure("Classic uses tokens.json as-is")
        case .ink:
            return LookRecipe(
                dark: LookPalette(
                    bg: "#050505",
                    surface: "#111111",
                    surface2: "#1a1a1a",
                    line: "rgba(255,255,255,0.14)",
                    hair: "rgba(255,255,255,0.08)",
                    text: "#ffffff",
                    muted: "rgba(255,255,255,0.58)",
                    faint: "rgba(255,255,255,0.38)",
                    scrim: "5,5,5",
                    chip: "rgba(255,255,255,0.07)",
                    track: "rgba(255,255,255,0.12)"
                ),
                light: LookPalette(
                    bg: "#e8e6e1",
                    surface: "#ffffff",
                    surface2: "#ddd9d2",
                    line: "rgba(0,0,0,0.12)",
                    hair: "rgba(0,0,0,0.07)",
                    text: "#111111",
                    muted: "rgba(0,0,0,0.56)",
                    faint: "rgba(0,0,0,0.40)",
                    scrim: "17,17,17",
                    chip: "rgba(0,0,0,0.05)",
                    track: "rgba(0,0,0,0.10)"
                ),
                cardRadius: 14,
                tightCardRadius: 10,
                chipRadius: 8,
                buttonRadius: 9999,
                segmentRadius: 9,
                segmentThumbRadius: 6,
                radius: RadiusTokens(sm: 6, md: 10, lg: 12, xl: 16, full: 9999),
                cornerStyle: .continuous
            )
        case .paper:
            return LookRecipe(
                dark: LookPalette(
                    bg: "#16110c",
                    surface: "#211b14",
                    surface2: "#2c241b",
                    line: "rgba(232,210,180,0.14)",
                    hair: "rgba(232,210,180,0.08)",
                    text: "#f6efe4",
                    muted: "rgba(246,239,228,0.62)",
                    faint: "rgba(246,239,228,0.40)",
                    scrim: "22,17,12",
                    chip: "rgba(246,239,228,0.06)",
                    track: "rgba(246,239,228,0.10)"
                ),
                light: LookPalette(
                    bg: "#f2ebe1",
                    surface: "#fbf7f1",
                    surface2: "#e6d9c8",
                    line: "rgba(60,40,20,0.10)",
                    hair: "rgba(60,40,20,0.06)",
                    text: "#1a140e",
                    muted: "rgba(26,20,14,0.58)",
                    faint: "rgba(26,20,14,0.40)",
                    scrim: "26,20,14",
                    chip: "rgba(60,40,20,0.05)",
                    track: "rgba(60,40,20,0.09)"
                ),
                cardRadius: 18,
                tightCardRadius: 14,
                chipRadius: 10,
                buttonRadius: 9999,
                segmentRadius: 12,
                segmentThumbRadius: 8,
                radius: RadiusTokens(sm: 8, md: 12, lg: 16, xl: 22, full: 9999),
                cornerStyle: .continuous
            )
        case .harbor:
            return LookRecipe(
                dark: LookPalette(
                    bg: "#0b1220",
                    surface: "#121c2e",
                    surface2: "#1a2740",
                    line: "rgba(160,190,255,0.14)",
                    hair: "rgba(160,190,255,0.07)",
                    text: "#f0f5ff",
                    muted: "rgba(240,245,255,0.62)",
                    faint: "rgba(240,245,255,0.40)",
                    scrim: "11,18,32",
                    chip: "rgba(160,190,255,0.07)",
                    track: "rgba(160,190,255,0.12)"
                ),
                light: LookPalette(
                    bg: "#e7eef8",
                    surface: "#f7f9fd",
                    surface2: "#d4deec",
                    line: "rgba(20,40,80,0.10)",
                    hair: "rgba(20,40,80,0.06)",
                    text: "#0e1726",
                    muted: "rgba(14,23,38,0.58)",
                    faint: "rgba(14,23,38,0.40)",
                    scrim: "14,23,38",
                    chip: "rgba(20,40,80,0.05)",
                    track: "rgba(20,40,80,0.08)"
                ),
                cardRadius: 16,
                tightCardRadius: 12,
                chipRadius: 10,
                buttonRadius: 9999,
                segmentRadius: 10,
                segmentThumbRadius: 7,
                radius: RadiusTokens(sm: 7, md: 11, lg: 14, xl: 20, full: 9999),
                cornerStyle: .continuous
            )
        case .grid:
            return LookRecipe(
                dark: LookPalette(
                    bg: "#0c0c0e",
                    surface: "#161618",
                    surface2: "#202024",
                    line: "rgba(255,255,255,0.18)",
                    hair: "rgba(255,255,255,0.10)",
                    text: "#fafafa",
                    muted: "rgba(250,250,250,0.64)",
                    faint: "rgba(250,250,250,0.42)",
                    scrim: "12,12,14",
                    chip: "rgba(255,255,255,0.06)",
                    track: "rgba(255,255,255,0.14)"
                ),
                light: LookPalette(
                    bg: "#ffffff",
                    surface: "#f3f3f4",
                    surface2: "#e6e6e8",
                    line: "rgba(0,0,0,0.16)",
                    hair: "rgba(0,0,0,0.08)",
                    text: "#0a0a0b",
                    muted: "rgba(10,10,11,0.58)",
                    faint: "rgba(10,10,11,0.42)",
                    scrim: "10,10,11",
                    chip: "rgba(0,0,0,0.04)",
                    track: "rgba(0,0,0,0.10)"
                ),
                cardRadius: 6,
                tightCardRadius: 4,
                chipRadius: 4,
                buttonRadius: 8,
                segmentRadius: 6,
                segmentThumbRadius: 3,
                radius: RadiusTokens(sm: 3, md: 4, lg: 6, xl: 8, full: 9999),
                cornerStyle: .circular
            )
        case .dusk:
            return LookRecipe(
                dark: LookPalette(
                    bg: "#13111a",
                    surface: "#1d1a26",
                    surface2: "#282433",
                    line: "rgba(200,180,255,0.12)",
                    hair: "rgba(200,180,255,0.06)",
                    text: "#f5f2fb",
                    muted: "rgba(245,242,251,0.62)",
                    faint: "rgba(245,242,251,0.40)",
                    scrim: "19,17,26",
                    chip: "rgba(200,180,255,0.07)",
                    track: "rgba(200,180,255,0.11)"
                ),
                light: LookPalette(
                    bg: "#f4f0f8",
                    surface: "#fcfaff",
                    surface2: "#e8e0f0",
                    line: "rgba(40,20,70,0.10)",
                    hair: "rgba(40,20,70,0.06)",
                    text: "#17141f",
                    muted: "rgba(23,20,31,0.58)",
                    faint: "rgba(23,20,31,0.40)",
                    scrim: "23,20,31",
                    chip: "rgba(40,20,70,0.045)",
                    track: "rgba(40,20,70,0.08)"
                ),
                cardRadius: 26,
                tightCardRadius: 18,
                chipRadius: 14,
                buttonRadius: 9999,
                segmentRadius: 14,
                segmentThumbRadius: 10,
                radius: RadiusTokens(sm: 12, md: 16, lg: 20, xl: 28, full: 9999),
                cornerStyle: .continuous
            )
        }
    }
}

private struct LookPalette {
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

private struct LookRecipe {
    var dark: LookPalette
    var light: LookPalette
    var cardRadius: CGFloat
    var tightCardRadius: CGFloat
    var chipRadius: CGFloat
    var buttonRadius: CGFloat
    var segmentRadius: CGFloat
    var segmentThumbRadius: CGFloat
    var radius: RadiusTokens
    var cornerStyle: RoundedCornerStyle
}
