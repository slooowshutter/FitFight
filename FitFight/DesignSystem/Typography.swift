import SwiftUI
import UIKit

/// The design system was drawn in Nunito at 500/600/700/800 — the kit loads it from
/// Google Fonts. SF renders the same point sizes narrower and squarer, which is what
/// made the native build read as a different app, so the family ships in the bundle
/// and is registered through UIAppFonts in Info.plist.
enum FFFont {
    private static let lock = NSLock()
    private static var fonts: [Key: Font] = [:]

    private struct Key: Hashable {
        let size: CGFloat
        let weight: Int
    }

    /// Every body re-evaluation asks for fonts, so each size and weight is built once.
    static func font(size: CGFloat, weight: Int) -> Font {
        let key = Key(size: size, weight: weight)
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[key] { return font }
        let named = UIFont(name: postScriptName(weight), size: size)
        let font = Font(tabularFigures(named ?? .systemFont(ofSize: size, weight: systemWeight(weight))))
        fonts[key] = font
        return font
    }

    private static func postScriptName(_ weight: Int) -> String {
        switch weight {
        case ...550: return "Nunito-Medium"
        case ...650: return "Nunito-SemiBold"
        case ...750: return "Nunito-Bold"
        default: return "Nunito-ExtraBold"
        }
    }

    private static func systemWeight(_ weight: Int) -> UIFont.Weight {
        switch weight {
        case ...550: return .medium
        case ...650: return .semibold
        case ...750: return .bold
        default: return .heavy
        }
    }

    /// Scores, ranks, targets and dates all sit in columns, so figures are always tabular.
    private static func tabularFigures(_ font: UIFont) -> UIFont {
        let settings: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

extension Font {
    static func ff(_ size: CGFloat, _ weight: Int = 700) -> Font {
        FFFont.font(size: size, weight: weight)
    }
}
