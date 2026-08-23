import SwiftUI

struct VersionBanner: View {
    var body: some View {
        Text(AppVersion.label)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Color.black)
            .accessibilityIdentifier("app-version")
    }
}

struct VersionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()

            HStack {
                Text("Versions")
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

            Text("You're on \(AppVersion.label)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
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
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct ReleaseNoteRow: View {
    let release: ReleaseNote

    private var isCurrent: Bool {
        release.id == Changelog.currentRelease?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(release.version)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(isCurrent ? Color.accentColor : .white)
                if isCurrent {
                    Text("this build")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(release.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(LocalizedStringKey(release.notes))
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("English") {
    VersionsView()
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("French") {
    VersionsView()
        .environment(\.locale, Locale(identifier: "fr"))
}
