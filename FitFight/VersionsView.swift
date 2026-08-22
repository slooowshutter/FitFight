import SwiftUI

struct VersionBanner: View {
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(AppVersion.label)
            .font(theme.monoFont(12, weight: .semibold))
            .foregroundStyle(theme.colors.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(theme.colors.bg)
            .accessibilityIdentifier("app-version")
    }
}

struct VersionsView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()

            HStack {
                Text("Versions")
                    .font(theme.bodyFont(22, weight: .bold))
                    .foregroundStyle(theme.colors.text)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .font(theme.bodyFont(17, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Text("You're on \(AppVersion.label)")
                .font(theme.monoFont(13, weight: .semibold))
                .foregroundStyle(theme.colors.muted)
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
        .background(theme.colors.bg.ignoresSafeArea())
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
                Text(release.version)
                    .font(theme.monoFont(16, weight: .semibold))
                    .foregroundStyle(isCurrent ? theme.colors.accent : theme.colors.text)
                if isCurrent {
                    Text("this build")
                        .font(theme.bodyFont(12, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }
                Spacer()
                Text(release.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(theme.bodyFont(15, weight: .regular))
                    .foregroundStyle(theme.colors.muted)
            }

            Text(release.notes)
                .font(theme.bodyFont(17, weight: .regular))
                .foregroundStyle(theme.colors.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.colors.surface,
            in: RoundedRectangle(cornerRadius: theme.metrics.radiusLg, style: theme.metrics.cornerStyle)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.metrics.radiusLg, style: theme.metrics.cornerStyle)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        }
    }
}

#Preview {
    let store = ThemeStore(preview: .arena)
    return VersionsView()
        .environmentObject(store)
        .fitFightTheme(store.current)
}
