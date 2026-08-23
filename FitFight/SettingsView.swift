import SwiftUI
import UIKit

struct SettingsView: View {
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

                    Text("FitFight follows your iPhone language. Tap Language to pick English or French for this app only.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    Button(action: openAppSettings) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Language")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(verbatim: currentLanguageName)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("language-ios-settings")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    /// iOS’s choice for this app (QA1828 / Bundle.preferredLocalizations), not GPS/country.
    private var currentLanguageName: String {
        let identifier = Bundle.main.preferredLocalizations.first ?? "en"
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.localizedCapitalized
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("English") {
    SettingsView()
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("French") {
    SettingsView()
        .environment(\.locale, Locale(identifier: "fr"))
}
