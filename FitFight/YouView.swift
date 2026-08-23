import SwiftUI

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                profile
                    .padding(.bottom, 15)
                stats
                sectionHeader("Fight history", action: "All 12") { model.tab = .fights }
                history
                sectionHeader("Data sources")
                sources
                sectionHeader("Settings")
                settings
                sectionHeader("Look")
                appearance
                sectionHeader("This build")
                buildPanel
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 2)
            .padding(.bottom, theme.space.xl)
        }
    }

    private func sectionHeader(_ title: String, action: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        FFSectionHeader(title: title, action: action, onAction: onAction)
            .padding(.top, theme.space.sectionGap)
            .padding(.bottom, 12)
    }

    private var profile: some View {
        HStack(spacing: 12) {
            FFAvatar(model.you, size: 56, ring: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Maya Moves")
                    .font(.ff(17, .bold))
                    .foregroundStyle(theme.text)
                Text("@maya.moves · joined Mar 2026")
                    .font(.ff(12))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button {} label: {
                Text("Edit")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(theme.chip, in: Capsule())
                    .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }
            .buttonStyle(FFPressStyle(scale: 0.97))
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            FFStatTile(value: "12", label: "Fights", onSurface: true)
            FFStatTile(value: "5", label: "Wins", onSurface: true)
            FFStatTile(value: "62%", label: "Win rate", onSurface: true)
            FFStatTile(value: "$140", label: "Won", onSurface: true)
        }
    }

    private var history: some View {
        FFPanel {
            ForEach(Array(model.history.enumerated()), id: \.element.id) { index, item in
                if index > 0 { FFHairline() }
                Button {
                    model.tab = .fights
                    model.openFightID = item.id
                } label: {
                    HStack(spacing: 12) {
                        Text(item.won ? "W" : "L")
                            .font(.ff(13, .bold))
                            .foregroundStyle(item.won ? theme.green : theme.red)
                            .frame(width: 40, height: 40)
                            .background((item.won ? theme.green : theme.red).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.ff(13, .bold))
                                .foregroundStyle(theme.text)
                            Text(item.detail)
                                .font(.ff(11))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer(minLength: 8)
                        FFMoney(dollars: item.net, size: 13)
                    }
                    .padding(.horizontal, FFMetric.rowPaddingX)
                    .frame(height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sources: some View {
        FFPanel {
            sourceRow("Apple Health", "8,240 steps today", "Synced 9:32")
            FFHairline()
            sourceRow("Strava", "Morning ride synced", "Synced 8:05")
        }
    }

    private func sourceRow(_ name: String, _ detail: String, _ time: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(theme.green).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.ff(11))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.ff(11))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, FFMetric.rowPaddingX)
        .frame(height: 61)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(BaseID.allCases) { base in
                    let on = themeStore.baseID == base
                    Button {
                        themeStore.baseID = base
                    } label: {
                        Text(base.rawValue.capitalized)
                            .font(.ff(13, .semibold))
                            .foregroundStyle(on ? theme.ink : theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                on ? theme.accent : theme.surface,
                                in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                            )
                            .overlay {
                                if !on {
                                    RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                                        .strokeBorder(theme.line, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(FFPressStyle(scale: 0.97))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(AccentID.allCases) { accent in
                    let color = ThemeCatalog.theme(base: themeStore.baseID, accent: accent).accent
                    Button {
                        themeStore.accentID = accent
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
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

    private var buildPanel: some View {
        FFPanel {
            navRow("Versions") { model.showingVersions = true }
        }
    }

    private var settings: some View {
        FFPanel {
            navRow("Units & goals") {}
            FFHairline()
            navRow("Notifications") {}
            FFHairline()
            navRow("Privacy") {}
            FFHairline()
            navRow("Payouts") {}
        }
    }

    private func navRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, FFMetric.rowPaddingX)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
