import SwiftUI

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @State private var showingDesign = false

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
        .sheet(isPresented: $showingDesign) {
            DesignPickerSheet()
                .environmentObject(themeStore)
                .presentationDetents([.medium, .large])
        }
    }

    private func sectionHeader(_ title: String, action: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        FFSectionHeader(title: title, action: action, onAction: onAction)
            .padding(.top, theme.space.sectionGap)
            .padding(.bottom, 10)
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
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button {} label: {
                Text("Edit")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .overlay { theme.rounded(theme.buttonRadius).strokeBorder(theme.line, lineWidth: 1) }
            }
            .buttonStyle(FFPressStyle(scale: 0.97))
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            FFStatTile(value: "12", label: "Fights", onSurface: true, height: 60)
            FFStatTile(value: "5", label: "Wins", onSurface: true, height: 60)
            FFStatTile(value: "62%", label: "Win rate", onSurface: true, height: 60)
            FFStatTile(value: "$140", label: "Won", onSurface: true, height: 60)
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
                            .frame(width: 36, height: 36)
                            .background(
                                (item.won ? theme.green : theme.red).opacity(0.12),
                                in: theme.rounded(theme.radius.md)
                            )
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
                    .foregroundStyle(theme.faint)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.ff(11))
                .foregroundStyle(theme.faint)
        }
        .padding(.horizontal, FFMetric.rowPaddingX)
        .frame(height: 61)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Classic is the original. The others keep Dark/Light and your accent.")
                .font(.ff(12))
                .foregroundStyle(theme.faint)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(LookID.allCases) { look in
                    LookChoice(look: look)
                }
            }
            .sensoryFeedback(.selection, trigger: themeStore.lookID)

            HStack(spacing: 10) {
                ForEach(BaseID.allCases) { base in
                    let on = themeStore.baseID == base
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            themeStore.baseID = base
                        }
                    } label: {
                        Text(base.rawValue.capitalized)
                            .font(.ff(13, .semibold))
                            .foregroundStyle(on ? theme.ink : theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                on ? theme.accent : theme.surface,
                                in: theme.rounded(theme.radius.lg)
                            )
                            .overlay {
                                if !on {
                                    theme.rounded(theme.radius.lg)
                                        .strokeBorder(theme.line, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(FFPressStyle(scale: 0.97))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(AccentID.allCases) { accent in
                    let color = ThemeCatalog.theme(
                        base: themeStore.baseID,
                        accent: accent,
                        look: themeStore.lookID
                    ).accent
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
            Button { showingDesign = true } label: {
                HStack {
                    Text("Design")
                        .font(.ff(13, .semibold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(themeStore.lookID.name)
                        .font(.ff(13, .semibold))
                        .foregroundStyle(theme.faint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.faint)
                }
                .padding(.horizontal, FFMetric.rowPaddingX)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Design")
            .accessibilityValue(themeStore.lookID.name)
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

private struct LookChoice: View {
    let look: LookID
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let on = themeStore.lookID == look
        let sample = ThemeCatalog.theme(base: themeStore.baseID, accent: themeStore.accentID, look: look)
        Button {
            themeStore.selectLook(look)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LookThumbnail(theme: sample)
                    .frame(height: 64)
                    .clipShape(sample.rounded(10))
                    .overlay {
                        sample.rounded(10).strokeBorder(sample.line, lineWidth: 1)
                    }
                Text(look.name)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Text(look.blurb)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: theme.rounded(theme.chipRadius + 6))
            .overlay {
                theme.rounded(theme.chipRadius + 6)
                    .strokeBorder(on ? theme.accent : theme.line, lineWidth: on ? 2 : 1)
            }
        }
        .buttonStyle(FFPressStyle(scale: 0.98))
        .accessibilityLabel(look.name)
        .accessibilityValue(look.blurb)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct LookThumbnail: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.bg
            VStack(spacing: 6) {
                HStack {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 22, height: 4)
                    Spacer()
                    Circle()
                        .fill(theme.chip)
                        .frame(width: 8, height: 8)
                }
                theme.rounded(min(12, theme.cardRadius * 0.55))
                    .fill(theme.surface)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 5) {
                            Circle().fill(theme.accent).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(theme.text.opacity(0.55)).frame(width: 44, height: 3)
                                Capsule().fill(theme.faint.opacity(0.7)).frame(width: 28, height: 2)
                            }
                            Spacer(minLength: 0)
                            Capsule().fill(theme.green.opacity(0.85)).frame(width: 16, height: 3)
                        }
                        .padding(.horizontal, 8)
                    }
                    .overlay {
                        theme.rounded(min(12, theme.cardRadius * 0.55))
                            .strokeBorder(theme.line, lineWidth: 1)
                    }
                    .frame(height: 30)
            }
            .padding(8)
        }
    }
}

private struct DesignPickerSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = themeStore.theme
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                FFLabel(text: "Design", role: .title)
                Spacer()
                Button("Close") { dismiss() }
                    .font(theme.font(.bodyStrong))
                    .foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Text("Classic is the original. Tap another and the app shifts behind this sheet.")
                .font(.ff(13))
                .foregroundStyle(theme.faint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(LookID.allCases) { look in
                        LookChoice(look: look)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .sensoryFeedback(.selection, trigger: themeStore.lookID)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .fitFightTheme(theme)
        .presentationBackground(theme.bg)
    }
}
