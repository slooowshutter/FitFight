import SwiftUI

struct DesignCatalogView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var sampleName = "Alex"

    private var theme: Theme { themeStore.current }

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            header
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.spaceLg) {
                    themePicker
                    colorSection
                    typeSection
                    buttonSection
                    cardSection
                    rowSection
                    statSection
                    inputSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 32)
            }
        }
        .background(theme.colors.bg.ignoresSafeArea())
        .fitFightTheme(themeStore.current)
    }

    private var header: some View {
        HStack {
            Text("Design")
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
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Theme")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ThemeID.allCases) { id in
                        let selected = themeStore.themeID == id
                        Button {
                            themeStore.themeID = id
                        } label: {
                            Text(ThemeCatalog.named(id).name)
                                .font(theme.bodyFont(15, weight: .semibold))
                                .foregroundStyle(selected ? theme.colors.accentText : theme.colors.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? theme.colors.accent : theme.colors.surface,
                                    in: RoundedRectangle(
                                        cornerRadius: theme.metrics.radiusSm,
                                        style: theme.metrics.cornerStyle
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(theme.blurb)
                .font(theme.bodyFont(15, weight: .regular))
                .foregroundStyle(theme.colors.muted)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Color")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                swatch("bg", theme.colors.bg)
                swatch("surface", theme.colors.surface)
                swatch("raised", theme.colors.raised)
                swatch("text", theme.colors.text)
                swatch("muted", theme.colors.muted)
                swatch("accent", theme.colors.accent)
                swatch("accentText", theme.colors.accentText)
                swatch("danger", theme.colors.danger)
                swatch("dangerText", theme.colors.dangerText)
                swatch("success", theme.colors.success)
                swatch("border", theme.colors.border)
            }
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: theme.metrics.radiusSm, style: theme.metrics.cornerStyle)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.metrics.radiusSm, style: theme.metrics.cornerStyle)
                        .strokeBorder(theme.colors.border, lineWidth: 1)
                }
                .frame(height: 44)
            Text(name)
                .font(theme.monoFont(10, weight: .medium))
                .foregroundStyle(theme.colors.muted)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FFSectionHeader(title: "Type")
            Text("FitFight")
                .font(theme.displayFont())
                .foregroundStyle(theme.colors.text)
            Text("Challenge your friends. Winner takes the glory.")
                .font(theme.bodyFont(17, weight: .regular))
                .foregroundStyle(theme.colors.muted)
            Text(AppVersion.label)
                .font(theme.monoFont(13, weight: .semibold))
                .foregroundStyle(theme.colors.muted)
        }
    }

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Buttons")
            FFButton(title: "Start a fight", kind: .primary, action: {})
            FFButton(title: "See versions", kind: .secondary, action: {})
            FFButton(title: "Not now", kind: .ghost, action: {})
            FFButton(title: "Give up", kind: .danger, action: {})
        }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Challenge")
            FFCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        FFChip(text: "Open", emphasized: true)
                        FFChip(text: "5 days left")
                    }
                    Text("5K before Sunday")
                        .font(theme.bodyFont(20, weight: .bold))
                        .foregroundStyle(theme.colors.text)
                    Text("You vs Alex. First to finish a 5K this week wins.")
                        .font(theme.bodyFont(15, weight: .regular))
                        .foregroundStyle(theme.colors.muted)
                }
            }
        }
    }

    private var rowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "People")
            FFRow(title: "Alex", subtitle: "3 wins this week", trailing: "+2")
            FFRow(title: "Sam", subtitle: "Waiting on you", trailing: "due")
        }
    }

    private var statSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Stats")
            HStack(spacing: 8) {
                FFStat(label: "Wins", value: "12")
                FFStat(label: "Streak", value: "4")
                FFStat(label: "Open", value: "2")
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Input")
            FFField(placeholder: "Friend’s name", text: $sampleName)
        }
    }
}

#Preview("Catalog") {
    let store = ThemeStore(preview: .arena)
    return DesignCatalogView()
        .environmentObject(store)
        .fitFightTheme(store.current)
}
