import NaturalLanguage
import SwiftUI
import Translation

struct TextTranslationButton: View {
    let text: String

    @Environment(\.ffTheme) private var theme
    @State private var showingTranslation = false

    var body: some View {
        if #available(iOS 17.4, *), isDifferentLanguage {
            Button {
                showingTranslation = true
            } label: {
                Image(systemName: "character.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.mossText)
                    .frame(height: 20)
                    .frame(width: 44, height: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FFHapticPlainStyle())
            .accessibilityLabel(String(localized: "Translate"))
            .translationPresentation(isPresented: $showingTranslation, text: text)
        }
    }

    private var isDifferentLanguage: Bool {
        guard text.rangeOfCharacter(from: .letters) != nil,
              let detectedLanguage = NLLanguageRecognizer.dominantLanguage(for: text),
              detectedLanguage != .undetermined,
              let preferredLanguage = Locale.preferredLanguages.first,
              let source = Locale.Language(identifier: detectedLanguage.rawValue).languageCode,
              let target = Locale.Language(identifier: preferredLanguage).languageCode else { return false }
        return source != target
    }
}
