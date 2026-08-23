import SwiftUI

/// A shape system on top of the same base × accent colours.
/// Classic is the approved kit. The others keep those colours and change the geometry.
enum LookID: String, CaseIterable, Identifiable {
    case classic
    case sharp
    case pill
    case slab
    case rail
    case frame

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .sharp: return "Sharp"
        case .pill: return "Pill"
        case .slab: return "Slab"
        case .rail: return "Rail"
        case .frame: return "Frame"
        }
    }

    var blurb: String {
        switch self {
        case .classic: return "The original."
        case .sharp: return "Squares. Tight corners."
        case .pill: return "Everything round."
        case .slab: return "Edge to edge. No curves."
        case .rail: return "A bar on the left."
        case .frame: return "Outline only."
        }
    }

    static func resolved(_ raw: String) -> LookID {
        switch raw {
        case "sharp", "grid": return .sharp
        case "pill", "dusk": return .pill
        case "slab": return .slab
        case "rail": return .rail
        case "frame": return .frame
        default: return .classic
        }
    }
}

enum CardChrome: Equatable {
    case filledStroke
    case filled
    case strokeOnly
    case rail
}

enum TabChrome: Equatable {
    case classic
    case flush
    case pill
    case boxed
}

enum TabMarker: Equatable {
    case dot
    case bar
    case none
}

enum LookCatalog {
    static func apply(_ look: LookID, to theme: inout Theme) {
        theme.lookID = look
        guard look != .classic else { return }
        recipe(look).apply(to: &theme)
    }

    private static func recipe(_ look: LookID) -> LookRecipe {
        switch look {
        case .classic:
            preconditionFailure("Classic uses tokens.json as-is")
        case .sharp:
            return LookRecipe(
                cardRadius: 4,
                tightCardRadius: 3,
                chipRadius: 3,
                buttonRadius: 4,
                segmentRadius: 4,
                segmentThumbRadius: 2,
                avatarRadius: 6,
                progressRadius: 2,
                iconButtonRadius: 6,
                railWidth: 0,
                strokeWidth: 1,
                cardChrome: .filledStroke,
                tabChrome: .flush,
                tabMarker: .bar,
                ringSquircle: true,
                cornerStyle: .circular,
                radius: RadiusTokens(sm: 3, md: 4, lg: 6, xl: 8, full: 9999),
                screenPadding: 16,
                cardGap: 10,
                sectionGap: 24
            )
        case .pill:
            return LookRecipe(
                cardRadius: 32,
                tightCardRadius: 24,
                chipRadius: 9999,
                buttonRadius: 9999,
                segmentRadius: 9999,
                segmentThumbRadius: 9999,
                avatarRadius: 9999,
                progressRadius: 9999,
                iconButtonRadius: 9999,
                railWidth: 0,
                strokeWidth: 1,
                cardChrome: .filledStroke,
                tabChrome: .pill,
                tabMarker: .dot,
                ringSquircle: false,
                cornerStyle: .continuous,
                radius: RadiusTokens(sm: 16, md: 20, lg: 24, xl: 32, full: 9999),
                screenPadding: 20,
                cardGap: 18,
                sectionGap: 32
            )
        case .slab:
            return LookRecipe(
                cardRadius: 0,
                tightCardRadius: 0,
                chipRadius: 0,
                buttonRadius: 0,
                segmentRadius: 0,
                segmentThumbRadius: 0,
                avatarRadius: 4,
                progressRadius: 0,
                iconButtonRadius: 0,
                railWidth: 0,
                strokeWidth: 1,
                cardChrome: .filled,
                tabChrome: .flush,
                tabMarker: .bar,
                ringSquircle: true,
                cornerStyle: .circular,
                radius: RadiusTokens(sm: 0, md: 0, lg: 0, xl: 0, full: 0),
                screenPadding: 0,
                cardGap: 3,
                sectionGap: 20
            )
        case .rail:
            return LookRecipe(
                cardRadius: 14,
                tightCardRadius: 10,
                chipRadius: 8,
                buttonRadius: 10,
                segmentRadius: 10,
                segmentThumbRadius: 6,
                avatarRadius: 9999,
                progressRadius: 9999,
                iconButtonRadius: 10,
                railWidth: 4,
                strokeWidth: 1,
                cardChrome: .rail,
                tabChrome: .classic,
                tabMarker: .dot,
                ringSquircle: false,
                cornerStyle: .continuous,
                radius: RadiusTokens(sm: 6, md: 10, lg: 12, xl: 16, full: 9999),
                screenPadding: 16,
                cardGap: 12,
                sectionGap: 26
            )
        case .frame:
            return LookRecipe(
                cardRadius: 8,
                tightCardRadius: 6,
                chipRadius: 6,
                buttonRadius: 8,
                segmentRadius: 8,
                segmentThumbRadius: 5,
                avatarRadius: 8,
                progressRadius: 3,
                iconButtonRadius: 8,
                railWidth: 0,
                strokeWidth: 1.5,
                cardChrome: .strokeOnly,
                tabChrome: .boxed,
                tabMarker: .none,
                ringSquircle: true,
                cornerStyle: .circular,
                radius: RadiusTokens(sm: 4, md: 6, lg: 8, xl: 10, full: 9999),
                screenPadding: 18,
                cardGap: 16,
                sectionGap: 28
            )
        }
    }
}

private struct LookRecipe {
    var cardRadius: CGFloat
    var tightCardRadius: CGFloat
    var chipRadius: CGFloat
    var buttonRadius: CGFloat
    var segmentRadius: CGFloat
    var segmentThumbRadius: CGFloat
    var avatarRadius: CGFloat
    var progressRadius: CGFloat
    var iconButtonRadius: CGFloat
    var railWidth: CGFloat
    var strokeWidth: CGFloat
    var cardChrome: CardChrome
    var tabChrome: TabChrome
    var tabMarker: TabMarker
    var ringSquircle: Bool
    var cornerStyle: RoundedCornerStyle
    var radius: RadiusTokens
    var screenPadding: CGFloat
    var cardGap: CGFloat
    var sectionGap: CGFloat

    func apply(to theme: inout Theme) {
        theme.cardRadius = cardRadius
        theme.tightCardRadius = tightCardRadius
        theme.chipRadius = chipRadius
        theme.buttonRadius = buttonRadius
        theme.segmentRadius = segmentRadius
        theme.segmentThumbRadius = segmentThumbRadius
        theme.avatarRadius = avatarRadius
        theme.progressRadius = progressRadius
        theme.iconButtonRadius = iconButtonRadius
        theme.railWidth = railWidth
        theme.strokeWidth = strokeWidth
        theme.cardChrome = cardChrome
        theme.tabChrome = tabChrome
        theme.tabMarker = tabMarker
        theme.ringSquircle = ringSquircle
        theme.cornerStyle = cornerStyle
        theme.radius = radius
        theme.space.screenPadding = screenPadding
        theme.space.cardGap = cardGap
        theme.space.sectionGap = sectionGap
    }
}
