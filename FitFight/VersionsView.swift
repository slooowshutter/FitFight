import SwiftUI

struct VersionsView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                FFLabel(text: "Versions", role: .title)
                Spacer()
                Button("Close") { dismiss() }
                    .font(theme.font(.bodyStrong))
                    .foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            FFLabel(text: "You're on \(AppVersion.label)", role: .caption, color: theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Changelog.newestFirst) { release in
                        ReleaseNoteRow(release: release)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

private struct ReleaseNoteRow: View {
    let release: ReleaseNote
    @Environment(\.ffTheme) private var theme

    private var isCurrent: Bool {
        release.version == AppVersion.marketing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                FFLabel(text: release.version, role: .headline, color: isCurrent ? theme.accent : theme.text)
                if isCurrent {
                    FFLabel(text: "this build", role: .caption, color: theme.accent)
                }
                Spacer()
                Text(release.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.muted)
            }
            FFLabel(text: release.notes, role: .body, color: theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }
}

#Preview {
    VersionsView()
        .fitFightTheme(ThemeCatalog.theme(base: .dark, accent: .blue))
}
