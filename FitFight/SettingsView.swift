import SwiftUI

struct SettingsView: View {
    @Environment(LanguageSettings.self) private var languageSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()

            HStack {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Language")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)

                    Text("Follows your iPhone language. Pick another here if you prefer.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases) { language in
                            if language != .system {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                            languageRow(language)
                        }
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.locale, languageSettings.locale)
        .environment(\.layoutDirection, languageSettings.layoutDirection)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let selected = languageSettings.selection == language
        return Button {
            languageSettings.selection = language
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if language == .system {
                        Text("System")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(systemLanguageName)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Text(verbatim: language.nativeDisplayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("language-\(language.rawValue)")
    }

    private var systemLanguageName: String {
        let code = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
        let name = languageSettings.locale.localizedString(forLanguageCode: code) ?? code
        return name.localizedCapitalized
    }
}

#Preview("English") {
    SettingsView()
        .environment(LanguageSettings(selection: .english))
}

#Preview("French") {
    SettingsView()
        .environment(LanguageSettings(selection: .french))
}
