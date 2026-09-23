import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var preferences: AccountPreferencesStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss
    @State private var showingNotifications = false
    @State private var showingBeta = false
    @State private var distribution: AppDistribution?

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Preferences")) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            if staticRender {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        settingsContent.fixedSize(horizontal: false, vertical: true)
                    }
                    .clipped()
            } else {
                ScrollView { settingsContent }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task {
            guard !staticRender else { return }
            await preferences.refresh(session: session)
        }
        .task {
            guard !staticRender else { return }
            distribution = await AppVersion.distribution()
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationSettingsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $showingBeta) {
            betaInfo
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: theme.space.sectionGap) {
            Text(String(appLocalized: "Language and appearance are saved to your account and follow you on your devices."))
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
            if let error = preferences.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                if !preferences.isAvailable {
                    FFButton(title: String(appLocalized: "Try again"), kind: .secondary) {
                        Task { await preferences.refresh(session: session) }
                    }
                }
            }
            if preferences.isLoading || preferences.isSaving {
                ProgressView(preferences.isSaving
                             ? String(appLocalized: "Saving…")
                             : String(appLocalized: "Loading…"))
                    .tint(theme.mossText)
            }
            FFSection(title: String(appLocalized: "Language")) {
                FFGroupedRows {
                    ForEach(AppLanguage.allCases) { language in
                        if language != .system { FFDivider() }
                        choiceRow(language.label, selected: preferences.value.language == language) {
                            Task { await preferences.save(.init(language: language), session: session) }
                        }
                    }
                }
                .disabled(!preferences.isAvailable || preferences.isSaving)
            }
            FFSection(title: String(appLocalized: "Appearance")) {
                FFGroupedRows {
                    ForEach(AppAppearance.allCases) { appearance in
                        if appearance != .system { FFDivider() }
                        choiceRow(appearance.label, selected: preferences.value.appearance == appearance) {
                            Task { await preferences.save(.init(appearance: appearance), session: session) }
                        }
                    }
                }
                .disabled(!preferences.isAvailable || preferences.isSaving)
            }
            FFGroupedRows {
                FFGroupedRow(title: String(appLocalized: "Notifications"), systemImage: "bell",
                             trailing: AnyView(Image(systemName: "chevron.right"))) {
                    showingNotifications = true
                }
                FFDivider()
                FFGroupedRow(title: String(appLocalized: "Beta testing"), systemImage: "flask",
                             trailing: AnyView(Image(systemName: "chevron.right"))) {
                    showingBeta = true
                }
            }
            FFSection(title: String(appLocalized: "This installation")) {
                FFGroupedRows {
                    FFGroupedRow(title: String(appLocalized: "Installed from"),
                                 subtitle: staticRender ? AppDistribution.development.label
                                         : (distribution?.label ?? String(appLocalized: "Loading…")),
                                 subtitleTone: .neutral)
                    FFDivider()
                    FFGroupedRow(title: String(appLocalized: "Version"),
                                 subtitle: String(appLocalized: "preferences.version", defaultValue: "\(AppVersion.marketing) · build \(AppVersion.build)"),
                                 subtitleTone: .neutral)
                    FFDivider()
                    FFGroupedRow(title: String(appLocalized: "Account environment"),
                                 subtitle: AppVersion.backend == "prod"
                                     ? String(appLocalized: "App Store account")
                                     : String(appLocalized: "Beta account"),
                                 subtitleTone: .neutral)
                }
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 24)
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        FFGroupedRow(title: title, trailing: AnyView(
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? theme.mossText : theme.textFaint)
        ), action: action)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var betaInfo: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Beta testing")) { showingBeta = false }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    Text(String(appLocalized: "Try upcoming features in TestFlight. Beta builds may have bugs."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    FFNotice(
                        text: String(appLocalized: "The beta uses a separate database. Accounts, fights, progress, and preferences do not sync automatically with the App Store version, even when you use the same Apple ID."),
                        tone: .ember,
                        systemImage: "exclamationmark.triangle"
                    )
                    Text(String(appLocalized: "Installing the beta replaces the App Store app on this device. To switch back, reinstall FitFight from the App Store."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    FFGroupedRows {
                        Link(destination: URL(string: "https://testflight.apple.com/join/wcZKdwVZ")!) {
                            FFGroupedRow(title: String(appLocalized: "Open TestFlight"),
                                         trailing: AnyView(Image(systemName: "arrow.up.right")))
                        }
                        FFDivider()
                        Link(destination: URL(string: "https://apps.apple.com/app/id6804230516")!) {
                            FFGroupedRow(title: String(appLocalized: "Return to the App Store"),
                                         trailing: AnyView(Image(systemName: "arrow.up.right")))
                        }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
