import CoreText
import SwiftUI
import UIKit

/// The design system was drawn in Manrope. SF renders the same point sizes noticeably
/// narrower and rounder, which is what made the native build read as a different app,
/// so the family ships in the bundle. The TTFs carry SF Pro's vertical metrics, so a
/// line box is the same height it was on the system font.
enum FFFont {
    static func uiFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        _ = registered
        let named = UIFont(name: postScriptName(weight), size: size)
        return tabularFigures(named ?? .systemFont(ofSize: size, weight: uiWeight(weight)))
    }

    private static let registered: Bool = {
        let names = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"].map { "Manrope-\($0)" }
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    private static func postScriptName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "Manrope-Regular"
        case .medium: return "Manrope-Medium"
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        case .heavy, .black: return "Manrope-ExtraBold"
        default: return "Manrope-Regular"
        }
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy, .black: return .heavy
        default: return .regular
        }
    }

    /// Scores, money, ranks and dates all sit in columns, so figures are always tabular.
    private static func tabularFigures(_ font: UIFont) -> UIFont {
        let settings: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

extension Font {
    static func ff(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font(FFFont.uiFont(size: size, weight: weight))
    }
}
