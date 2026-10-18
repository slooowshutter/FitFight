import SwiftUI

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var preferences: AccountPreferencesStore
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var purchases: SpecialPurchases
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var profileStore = ProfileScreenStore()
    @StateObject private var activity = YouActivityStore()
    @State private var showingEditProfile = false
    /// The last own profile this phone loaded, shown until a fresh one lands.
    @State private var cachedProfile: SharedProfile?
    @State private var rivals: [ProfileRivalrySummary] = []
    @State private var profileLoadGeneration = 0
    @State private var socialError: String?
    @State private var confirmDelete = false
    @State private var showingSettings = false
    @State private var showingDashboard = false
    @State private var showingOnboardingPreview = false
    @State private var showingSlideHapticsLab = false
    @State private var showingBroadcastCompose = false
    @State private var showingAppleHealth = false
    @State private var connector: Connector?
    @State private var showingCompanionPreviewControls = false
    @StateObject private var whoop = WhoopConnectionStore()
    static let profileCachePrefix = "fitfight.you."

    var body: some View {
        FFScreen(top: AnyView(VersionBanner(onTap: versionBannerTap)), refresh: fightsRefresh) {
            profile
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if session.isSignedIn {
                YouStatsCard(
                    todaySteps: todaySteps, statistics: ownProfile?.stepStatistics, record: ownProfile?.record,
                    results: results, todayWorkouts: activity.sports.dropFirst().filter { ($0.values.last ?? 0) > 0 },
                    eightWeekSteps: activity.eightWeekSteps
                )
                .padding(.top, 8)
                if !activity.sports.isEmpty {
                    YouSportList(sports: activity.sports)
                        .padding(.top, 12)
                }
            }
            ForEach(rivals) { rival in
                ProfileIdentityLink(userID: rival.id, source: "friends", onClosed: { Task { await loadOwnProfile() } }) {
                    FFCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: "@\(rival.identity.handle)").ffType(.label)
                            Text(String(format: String(appLocalized: "profile.rivalry-score"), rival.rivalry.wins, rival.rivalry.losses, rival.rivalry.draws))
                                .ffType(.heading)
                            Text(String(appLocalized: "Your rivalry")).ffType(.caption).foregroundStyle(theme.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let error = profileStore.error ?? socialError {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(appLocalized: "Retry"), kind: .secondary) { Task { await loadOwnProfile() } }
            }
            if session.isSignedIn {
                FriendsView(embedded: true)
                    .padding(.top, 12)
            }
        }
        .navigationDestination(isPresented: $showingSettings) { settingsScreen }
        .navigationDestination(isPresented: $showingDashboard) {
            DashboardView(
                sports: activity.sports, days: activity.days, statistics: ownProfile?.stepStatistics,
                results: results, record: ownProfile?.record
            )
        }
        .onChange(of: session.authSession?.user.id, initial: true) { _, userID in
            cachedProfile = userID
                .flatMap { UserDefaults.standard.data(forKey: Self.profileCachePrefix + $0.uuidString) }
                .flatMap { try? JSONDecoder().decode(SharedProfile.self, from: $0) }
        }
        .task(id: session.authSession?.user.id) { await loadOwnProfileAfterRefresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await loadOwnProfileAfterRefresh() } }
        }
        .sheet(isPresented: $showingEditProfile, onDismiss: { Task { await loadOwnProfile() } }) {
            EditProfileView().fitFightTheme(theme).presentationBackground(theme.bg)
        }
        .sheet(isPresented: $showingOnboardingPreview) {
            OnboardingPreviewView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $showingSlideHapticsLab) {
            SlideHapticsLabView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $showingBroadcastCompose) {
            FeedComposeSheet(broadcastOnly: true) {
                model.tab = .feed
            }
            .fitFightTheme(themeStore.theme)
            .presentationBackground(themeStore.theme.bg)
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    let userId = session.authSession?.user.id
                    if await session.deleteAccount(), let userId {
                        preferences.removeCache(for: userId)
                        model.removeCachedFights(for: userId)
                        UserDefaults.standard.removeObject(forKey: Self.profileCachePrefix + userId.uuidString)
                        if !(await steps.deleteLocalData(userId: userId)) {
                            let cleanupMessage = String(appLocalized: "Your account was deleted. FitFight will retry removing its local Health cache when you reopen the app.")
                            if let authError = session.authError {
                                session.authError = "\(authError) \(cleanupMessage)"
                            } else {
                                session.authError = cleanupMessage
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, photos, uploaded Apple Health activity, referrals, invitations, fights you created, and bugs or requests you posted; removes you from other fights; and signs you out. This can’t be undone.")
            Text("Deleting your account does not refund Apple purchases. Contact support for purchase recovery.")
        }
    }

    private var ownProfile: SharedProfile? { profileStore.profile ?? cachedProfile }

    /// Won, lost and drew from your record; group places below first count as lost.
    /// Nil when the backend predates draws and losses, so the card shows only won and lost.
    private var results: (won: Int, lost: Int, drew: Int)? {
        guard let record = ownProfile?.record, let drew = record.draws, let lost = record.losses else { return nil }
        return (record.wins, lost, drew)
    }

    private var todaySteps: Int? {
        if case .steps(let count) = steps.status { return count }
        return nil
    }

    private var versionBannerTap: (() -> Void)? {
        guard !CompanionPreview.isEnabled else { return nil }
        guard session.isFitFightAdmin else { return nil }
        return { model.showingDebugMenu = true }
    }

    private var fightsRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            error: model.refreshError,
            action: {
                await refreshOwnProfile(trigger: .manual)
            }
        )
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            HStack(alignment: .center, spacing: 12) {
                Button { showingEditProfile = true } label: {
                    CompanionAvatar(
                        personID: session.profile?.userId.uuidString,
                        companionID: session.profile?.companionId, isYou: true,
                        monogram: session.profile?.initials ?? "FF", photoURL: session.profile?.photoURL, size: 48
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.text)
                            .frame(width: 18, height: 18)
                            .background(theme.control, in: Circle())
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityLabel(String(appLocalized: "Edit profile"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.profile?.displayName ?? String(appLocalized: "Signed in"))
                        .ffType(.title).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: session.profile?.atHandle ?? String(appLocalized: "Profile isn’t ready yet"))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 4)
                headerButton(nil, label: String(appLocalized: "Dashboard")) { showingDashboard = true }
                headerButton("gearshape", label: String(appLocalized: "Settings")) { showingSettings = true }
            }
            .padding(.top, 12)
            // A stock or Special companion's words ship in the app; a custom one's come with the profile.
            let animal = companions.animal(for: session.profile?.userId.uuidString, companionID: session.profile?.companionId, isYou: true)
            if let name = animal?.name ?? session.profile?.companionName {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).ffType(.label).foregroundStyle(theme.text)
                    if let line = animal?.caption ?? session.profile?.companionLine {
                        Text(verbatim: line).ffType(.caption).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            SignInControls()
        }
    }

    /// A nil image draws the kit's thin three-line chart glyph.
    private func headerButton(_ systemImage: String?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .regular))
                } else {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach([8.0, 16.0, 12.0], id: \.self) { height in
                            Capsule().frame(width: 2, height: height)
                        }
                    }
                    .frame(height: 16)
                }
            }
                .foregroundStyle(theme.text)
                .frame(width: 44, height: 44)
                .background(theme.card, in: Circle())
                .overlay(Circle().stroke(theme.hairline))
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(label)
    }

    /// Everything that used to sit at the bottom of You: profile, app settings and Marc-only tools.
    private var settingsScreen: some View {
        FFScreen {
            FFSection(title: String(appLocalized: "Profile"), extraTop: false) {
                FFGroupedRows {
                    navRow(String(appLocalized: "Edit profile")) { showingEditProfile = true }
                    FFDivider()
                    navRow(String(appLocalized: "Your companion")) { companions.showingPicker = true }
                    FFDivider()
                    FFGroupedRow(
                        title: String(appLocalized: "Restore purchases"),
                        subtitle: purchases.message.isEmpty ? nil : purchases.message,
                        enabled: !purchases.isBusy,
                        subtitleTone: .neutral,
                        action: { Task { await purchases.restore(session: session) } }
                    )
                }
            }
            FFSection(title: String(appLocalized: "Connectors")) {
                FFGroupedRows {
                    AppleHealthRow { showingAppleHealth = true }
                    ForEach(Connector.allCases) { connector in
                        FFDivider()
                        ConnectorRow(
                            connector: connector,
                            status: connector == .whoop && whoop.connected
                                ? String(appLocalized: "Connected · Updates every hour") : nil
                        ) { self.connector = connector }
                    }
                }
                Text(String(appLocalized: "FitFight reads Apple Health. Connect your watch or app to Apple Health and it counts here too."))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 16)
            }
            FFSection(title: String(appLocalized: "Activity")) {
                FFGroupedRows {
                    navRow(String(appLocalized: "Notifications & activity")) { model.showingActivity = true }
                }
            }
            FFSection(title: String(appLocalized: "App")) {
                settings
            }
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled && !ScreenshotExport.isEnabled {
                FFButton(title: String(appLocalized: "Companion preview"), kind: .ghost, fullWidth: true) {
                    showingCompanionPreviewControls = true
                }
                .sheet(isPresented: $showingCompanionPreviewControls) {
                    CompanionPreviewControls()
                        .fitFightTheme(themeStore.theme)
                        .presentationBackground(themeStore.theme.bg)
                }
            }
            #endif

            if session.isFitFightAdmin || (CompanionPreview.isEnabled && !ScreenshotExport.isEnabled) {
                FFSection(title: String(appLocalized: "Developer")) {
                    developer
                }
            }
        }
        .navigationTitle(String(appLocalized: "Settings"))
        .task {
            if !staticRender { await whoop.refresh(session: session) }
        }
        .sheet(isPresented: $showingAppleHealth) {
            health
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(item: $connector) { connector in
            ConnectorGuideSheet(connector: connector, whoop: whoop, privacy: sitePage("privacy"))
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
    }

    private func refreshOwnProfile(trigger: HealthKitStepsStore.SyncTrigger, requestAccess: Bool = false) async {
        guard !staticRender else { return }
        // Local Apple Health first: Dashboard and the sport list must not wait for the server.
        await activity.load()
        await model.refreshFights(session: session, steps: steps, trigger: trigger, requestAccess: requestAccess)
        guard !Task.isCancelled else { return }
        if requestAccess { await activity.load() }
        await loadOwnProfile()
    }

    /// FitFightApp uploads Steps at launch and on return from background; appearing only waits for that upload.
    private func loadOwnProfileAfterRefresh() async {
        guard !staticRender else { return }
        await activity.load()
        await model.waitForRefresh()
        guard !Task.isCancelled else { return }
        await loadOwnProfile()
    }

    private func loadOwnProfile() async {
        profileLoadGeneration += 1
        let requestGeneration = profileLoadGeneration
        rivals = []
        socialError = nil
        profileStore.clear()
        guard !staticRender, let userID = session.authSession?.user.id ?? CompanionPreview.youID else { return }
        async let rivalsRequest = CompanionPreview.isEnabled ? [] : FitFightAPI().ownRivalries(accessToken: session.freshAccessToken())
        await profileStore.load(userID: userID, session: session, includeHistory: false)
        if requestGeneration == profileLoadGeneration, session.authSession?.user.id == userID,
           let loaded = profileStore.profile, let data = try? JSONEncoder().encode(loaded) {
            UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userID.uuidString)
            cachedProfile = loaded
        }
        do {
            let loadedRivals = try await rivalsRequest
            try Task.checkCancellation()
            guard requestGeneration == profileLoadGeneration, session.authSession?.user.id == userID else { return }
            rivals = loadedRivals
        } catch is CancellationError {
        } catch {
            guard requestGeneration == profileLoadGeneration, session.authSession?.user.id == userID else { return }
            socialError = error.localizedDescription
        }
    }

    /// The Apple Health sheet. Its syncs run here so Profile reloads after the upload.
    private var health: AppleHealthSheet {
        AppleHealthSheet(
            sync: {
                Task {
                    await refreshOwnProfile(trigger: .manual, requestAccess: !steps.hasAsked)
                }
            },
            review: {
                Task {
                    await refreshOwnProfile(trigger: .manual, requestAccess: true)
                }
            }
        )
    }

    private var settings: some View {
        FFGroupedRows {
            if let code = session.profile?.referralCode {
                ShareLink(item: APIConfig.publicOrigin.appending(path: "r/\(code.uuidString.lowercased())")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(appLocalized: "Refer a friend"))
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text(String(appLocalized: "When they connect Apple Health, you each get a free character."))
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        FFChevron()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                FFDivider()
            }
            navRow(String(appLocalized: "Preferences")) { model.showingPreferences = true }
            FFDivider()
            linkRow(String(appLocalized: "Privacy"), destination: sitePage("privacy"))
            FFDivider()
            linkRow(String(appLocalized: "Support"), destination: sitePage("support"))
            FFDivider()
            navRow(String(appLocalized: "Versions")) { model.showingVersions = true }
            if session.isSignedIn {
                FFDivider()
                navRow(String(appLocalized: "Sign out")) {
                    Task { await session.signOut() }
                }
                FFDivider()
                navRow(String(appLocalized: "Delete account"), destructive: true) {
                    confirmDelete = true
                }
            }
        }
    }

    private var developer: some View {
        FFGroupedRows {
            if !CompanionPreview.isEnabled {
                FFGroupedRow(
                    title: String(appLocalized: "Replay onboarding"),
                    subtitle: String(appLocalized: "Health, challenge reminders, and Bugs & requests. Your account and fights stay."),
                    systemImage: "arrow.counterclockwise",
                    subtitleTone: .neutral,
                    trailing: AnyView(FFChevron()),
                    action: { showingOnboardingPreview = true }
                )
                FFDivider()
                FFGroupedRow(
                    title: "Slide haptics",
                    subtitle: "Twenty Slide to start vibrations. This page is only on your account.",
                    systemImage: "iphone.radiowaves.left.and.right",
                    subtitleTone: .neutral,
                    trailing: AnyView(FFChevron()),
                    action: { showingSlideHapticsLab = true }
                )
                FFDivider()
            }
            FFGroupedRow(
                title: String(appLocalized: "Preview update card"),
                subtitle: String(appLocalized: "Large notice at the top."),
                systemImage: "rectangle",
                action: { model.showingUpdateToastPreview = true }
            )
            if !CompanionPreview.isEnabled {
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Broadcast"),
                    subtitle: String(appLocalized: "Write one post. Everyone signed in sees it on Feed."),
                    systemImage: "megaphone",
                    subtitleTone: .neutral,
                    trailing: AnyView(FFChevron()),
                    action: { showingBroadcastCompose = true }
                )
            }
        }
    }

    private var siteURL: URL {
        URL(string: AppVersion.backend == "prod" ? "https://fitfight.app" : "https://staging.fitfight.app")!
    }

    private func sitePage(_ path: String) -> URL {
        let root = AppLocalization.languageCode == "fr"
            ? siteURL.appending(path: "fr")
            : siteURL
        return root.appending(path: path)
    }

    private func linkRow(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            rowLabel(title: title, destructive: false)
        }
        .buttonStyle(FFHapticPlainStyle())
    }

    private func navRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(title: title, destructive: destructive)
        }
        .buttonStyle(FFHapticPlainStyle())
        .disabled(session.isBusy)
    }

    private func rowLabel(title: String, destructive: Bool) -> some View {
        HStack {
            Text(title)
                .ffType(.rowTitle)
                .foregroundStyle(destructive ? theme.emberText : theme.text)
            Spacer()
            FFChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
