import CoreText
import SwiftUI
import UIKit

/// The design system was drawn in Nunito at 500/600/700/800 — the kit loads it from
/// Google Fonts. SF renders the same point sizes narrower and squarer, which is what
/// made the native build read as a different app, so the family ships in the bundle.
enum FFFont {
    static func uiFont(size: CGFloat, weight: Int) -> UIFont {
        _ = registered
        let named = UIFont(name: postScriptName(weight), size: size)
        return tabularFigures(named ?? .systemFont(ofSize: size, weight: systemWeight(weight)))
    }

    private static let registered: Bool = {
        for name in ["Medium", "SemiBold", "Bold", "ExtraBold"].map({ "Nunito-\($0)" }) {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

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
        Font(FFFont.uiFont(size: size, weight: weight))
    }
}
