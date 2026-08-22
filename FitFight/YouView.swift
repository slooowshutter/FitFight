import SwiftUI

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                profile
                stats
                history
                sources
                appearance
                settings
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, theme.space.xl)
        }
        .background(theme.bg)
    }

    private var profile: some View {
        HStack(alignment: .center, spacing: 12) {
            FFAvatar(initials: "MM", size: 56, ring: true)
            VStack(alignment: .leading, spacing: 4) {
                FFLabel(text: "Maya Moves", role: .title)
                FFLabel(text: "@maya.moves · joined Mar 2026", role: .caption, color: theme.muted)
            }
            Spacer()
            Text("Edit")
                .font(theme.font(.bodyStrong))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            tile("12", "Fights")
            tile("5", "Wins")
            tile("62%", "Win rate")
            tile("$140", "Won")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            FFLabel(text: value, role: .rank)
            FFLabel(text: label, role: .tiny, color: theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Fight history", action: "All 12") {
                model.tab = .fights
            }
            FFGroup {
                ForEach(model.history) { item in
                    Button {
                        model.tab = .fights
                        model.openFightID = item.id
                    } label: {
                        HStack(spacing: 12) {
                            Text(item.won ? "W" : "L")
                                .font(theme.font(.bodyStrong))
                                .foregroundStyle(theme.onPhoto)
                                .frame(width: 32, height: 32)
                                .background(item.won ? theme.green : theme.red, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                FFLabel(text: item.name, role: .bodyStrong)
                                FFLabel(text: item.detail, role: .caption, color: theme.muted)
                            }
                            Spacer()
                            FFMoney(dollars: item.net)
                        }
                        .padding(.horizontal, theme.space.rowPaddingX)
                        .padding(.vertical, theme.space.rowPaddingY)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Data sources")
            FFGroup {
                sourceRow("Apple Health", "8,240 steps today", "Synced 9:32")
                FFHairline()
                sourceRow("Strava", "Morning ride synced", "Synced 8:05")
            }
        }
    }

    private func sourceRow(_ name: String, _ detail: String, _ time: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(theme.green).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                FFLabel(text: name, role: .bodyStrong)
                FFLabel(text: detail, role: .caption, color: theme.muted)
            }
            Spacer()
            FFLabel(text: time, role: .micro, color: theme.faint)
        }
        .padding(.horizontal, theme.space.rowPaddingX)
        .padding(.vertical, theme.space.rowPaddingY)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Look")
            HStack(spacing: 8) {
                ForEach(BaseID.allCases) { base in
                    Button {
                        themeStore.baseID = base
                    } label: {
                        Text(base.rawValue.capitalized)
                            .font(theme.font(.bodyStrong))
                            .foregroundStyle(themeStore.baseID == base ? theme.bg : theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                themeStore.baseID == base ? theme.text : theme.surface,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(FFPressStyle(scale: 0.97))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(AccentID.allCases) { accent in
                    let color = ThemeCatalog.theme(base: themeStore.baseID, accent: accent).accent
                    Button {
                        themeStore.accentID = accent
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if themeStore.accentID == accent {
                                    Circle().strokeBorder(theme.text, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.rawValue)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Settings")
            FFGroup {
                navRow("Versions") { model.showingVersions = true }
                FFHairline()
                navRow("Units & goals") {}
                FFHairline()
                navRow("Notifications") {}
                FFHairline()
                navRow("Privacy") {}
                FFHairline()
                navRow("Payouts") {}
            }
        }
    }

    private func navRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                FFLabel(text: title, role: .bodyStrong)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, theme.space.rowPaddingX)
            .padding(.vertical, theme.space.rowPaddingY)
        }
        .buttonStyle(.plain)
    }
}
