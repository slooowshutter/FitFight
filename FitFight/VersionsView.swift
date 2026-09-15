import SwiftUI

struct VersionsView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                Text("Versions")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Close") { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            Text(
                String(
                    localized: "version.current",
                    defaultValue: "You're on \(AppVersion.label)"
                )
            )
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Changelog.visible) { release in
                        ReleaseNoteRow(release: release)
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
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
        release.id == Changelog.current?.id
    }

    var body: some View {
        FFCard(padding: 16, stroke: isCurrent ? theme.mossEdge : nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(release.version)
                        .ffType(.heading)
                        .foregroundStyle(isCurrent ? theme.mossText : theme.text)
                    if isCurrent {
                        FFPill(String(localized: "this build"))
                    }
                    Spacer()
                    Text(release.date, format: .dateTime.month(.abbreviated).day().year())
                        .ffType(.caption)
                        .foregroundStyle(theme.textFaint)
                }
                Text(release.notes)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(3)
            }
        }
        .background(
            isCurrent ? theme.mossWash : .clear,
            in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        )
    }
}

#Preview {
    VersionsView()
        .fitFightTheme(ThemeCatalog.theme(.night))
}
