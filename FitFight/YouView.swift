import SwiftUI
import UIKit

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var preferences: AccountPreferencesStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var profileStore = ProfileScreenStore()
    @State private var showingEditProfile = false
    @State private var showingFriends = false
    @State private var showingProfileHistory = false
    @State private var incomingFriends = 0
    @State private var rivals: [ProfileRivalrySummary] = []
    @State private var profileLoadGeneration = 0
    @State private var socialError: String?
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var showingOnboardingPreview = false
    @State private var showingSlideHapticsLab = false
    @State private var showingBroadcastCompose = false
    @State private var showingHealthDetails = false
    @State private var showingCompanionPreviewControls = false

    var body: some View {
        FFScreen(top: AnyView(VersionBanner(onTap: versionBannerTap)), refresh: fightsRefresh) {
            profile
            CompanionIntroduction(surface: .you)
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled && !ScreenshotExport.isEnabled {
                Text("Companion design preview · this session only")
                    .ffType(.micro)
                    .foregroundStyle(theme.textSecondary)
            }
            #endif
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if let record = profileStore.profile?.record {
                ProfileRecordCard(record: record)
                FFButton(title: String(appLocalized: "Fight history"), kind: .ghost) { showingProfileHistory = true }
            }
            if let statistics = profileStore.profile?.stepStatistics {
                ProfileStepStatisticsView(statistics: statistics)
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
                FFGroupedRows {
                    FFGroupedRow(
                        title: String(appLocalized: "Friends"),
                        subtitle: incomingFriends > 0 ? String(format: String(appLocalized: "profile.requests-count"), incomingFriends) : nil,
                        systemImage: "person.2",
                        action: { showingFriends = true }
                    )
                }
            }

            FFSection(title: String(appLocalized: "Apple Health")) {
                health
            }

            FFSection(title: String(appLocalized: "Activity")) {
                FFGroupedRows {
                    navRow(String(appLocalized: "Notifications & activity")) { model.showingActivity = true }
                }
            }

            FFSection(title: String(appLocalized: "Bugs & requests")) {
                requests
            }

            FFSection(title: String(appLocalized: "Settings")) {
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

            if session.isFitFightAdmin {
                FFSection(title: String(appLocalized: "Developer")) {
                    developer
                }
            }
        }
        .task(id: session.authSession?.user.id) { await refreshOwnProfile() }
        .onChange(of: scenePhase) { _, phase in
            profileLoadGeneration += 1
            profileStore.clear()
            rivals = []
            incomingFriends = 0
            if phase == .active { Task { await refreshOwnProfile() } }
        }
        .sheet(isPresented: $showingEditProfile, onDismiss: { Task { await loadOwnProfile() } }) {
            EditProfileView().fitFightTheme(theme).presentationBackground(theme.bg)
        }
        .sheet(isPresented: $showingFriends, onDismiss: { Task { await loadOwnProfile() } }) {
            FriendsView().fitFightTheme(theme).presentationBackground(theme.bg)
        }
        .sheet(isPresented: $showingProfileHistory) {
            if let userID = session.authSession?.user.id {
                ProfileSheet(userID: userID, source: "friends").fitFightTheme(theme).presentationBackground(theme.bg)
            }
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
            Text("This permanently deletes your profile, photos, uploaded Steps, referrals, invitations, fights you created, and bugs or requests you posted; removes you from other fights; and signs you out. This can’t be undone.")
        }
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
            action: {
                await refreshOwnProfile(trigger: .manual)
            }
        )
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            HStack(alignment: .top, spacing: 14) {
                Button { showingProfileHistory = true } label: {
                    CompanionAvatar(
                        personID: session.profile?.userId.uuidString,
                        companionID: session.profile?.companionId, isYou: true,
                        monogram: session.profile?.initials ?? "FF", photoURL: session.profile?.photoURL, size: 68
                    )
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityLabel(String(appLocalized: "Open profile"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: session.profile?.displayName ?? String(appLocalized: "Signed in"))
                        .ffType(.heading).foregroundStyle(theme.text)
                    Text(verbatim: session.profile?.atHandle ?? String(appLocalized: "Profile isn’t ready yet"))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                    if session.profile != nil {
                        Button {
                            UIPasteboard.general.string = session.profile?.atHandle ?? ""
                            copied = true
                        } label: {
                            Text(copied ? String(appLocalized: "Copied") : String(appLocalized: "Copy username"))
                                .ffType(.micro).foregroundStyle(theme.mossText)
                        }.buttonStyle(FFHapticPlainStyle()).frame(minHeight: 44)
                    }
                }
                Spacer(minLength: 4)
                Button(String(appLocalized: "Edit profile")) { showingEditProfile = true }
                    .ffType(.label).foregroundStyle(theme.mossText).frame(minHeight: 44)
            }
        } else {
            SignInControls()
        }
    }

    private func refreshOwnProfile(trigger: HealthKitStepsStore.SyncTrigger = .foreground, requestAccess: Bool = false) async {
        guard !staticRender else { return }
        await model.refreshFights(session: session, steps: steps, trigger: trigger, requestAccess: requestAccess)
        guard !Task.isCancelled else { return }
        await loadOwnProfile()
    }

    private func loadOwnProfile() async {
        profileLoadGeneration += 1
        let requestGeneration = profileLoadGeneration
        rivals = []
        socialError = nil
        profileStore.clear()
        incomingFriends = 0
        guard !staticRender, let userID = session.authSession?.user.id else { return }
        await profileStore.load(userID: userID, session: session, includeHistory: false)
        do {
            let token = try await session.freshAccessToken()
            async let friendsRequest = FitFightAPI().profileFriends(kind: "incoming", accessToken: token)
            async let rivalsRequest = FitFightAPI().ownRivalries(accessToken: token)
            let (friends, loadedRivals) = try await (friendsRequest, rivalsRequest)
            try Task.checkCancellation()
            guard requestGeneration == profileLoadGeneration, session.authSession?.user.id == userID else { return }
            incomingFriends = friends.incomingCount
            rivals = loadedRivals
        } catch is CancellationError {
        } catch {
            guard requestGeneration == profileLoadGeneration, session.authSession?.user.id == userID else { return }
            socialError = error.localizedDescription
        }
    }

    private var health: some View {
        FFGroupedRows {
            Button {
                Task {
                    await refreshOwnProfile(trigger: .manual, requestAccess: !steps.hasAsked)
                }
            } label: {
                FFGroupedRow(
                    title: String(appLocalized: "Apple Health Steps"),
                    subtitle: steps.connection == .upToDate ? String(appLocalized: "Up to date") : steps.detailText,
                    systemImage: "heart",
                    enabled: steps.status != .reading && !model.isRefreshingFights,
                    subtitleTone: healthSubtitleTone,
                    trailing: AnyView(healthPill)
                )
            }
            .buttonStyle(FFHapticPlainStyle())
            .disabled(steps.status == .reading || model.isRefreshingFights)
            FFDivider()
            FFGroupedRow(
                title: showingHealthDetails ? String(appLocalized: "Fewer settings") : String(appLocalized: "More settings"),
                systemImage: "slider.horizontal.3",
                trailing: AnyView(
                    Image(systemName: showingHealthDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                ),
                action: { showingHealthDetails.toggle() }
            )
            if showingHealthDetails {
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Request Health access"),
                    subtitle: String(appLocalized: "Ask for access to Health types you haven’t reviewed yet. Fights use Steps only."),
                    systemImage: "heart.circle",
                    enabled: steps.status != .reading && !model.isRefreshingFights,
                    subtitleTone: .neutral,
                    trailing: AnyView(
                        FFPill(String(appLocalized: "Review"), style: .softMoss)
                    ),
                    action: {
                        Task {
                            await refreshOwnProfile(trigger: .manual, requestAccess: true)
                        }
                    }
                )
                .disabled(steps.status == .reading || model.isRefreshingFights)
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Change Health permissions"),
                    subtitle: String(appLocalized: "In Health, tap your profile → Apps → FitFight to turn each type of access on or off."),
                    systemImage: "hand.raised",
                    subtitleTone: .neutral
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Background App Refresh"),
                    subtitle: steps.backgroundRefreshText,
                    systemImage: "arrow.clockwise",
                    subtitleTone: steps.diagnostics.backgroundRefreshStatus == .available ? .moss : .neutral,
                    trailing: steps.diagnostics.backgroundRefreshStatus == .denied
                        ? AnyView(FFPill(String(appLocalized: "Open Settings"), style: .softMoss)) : nil,
                    action: steps.diagnostics.backgroundRefreshStatus == .denied
                        ? { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        : nil
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "HealthKit background delivery"),
                    subtitle: steps.backgroundDeliveryText,
                    systemImage: "heart.text.square",
                    subtitleTone: steps.diagnostics.deliveryRegistrationStatus == .enabled ? .moss : .neutral
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Last automatic sync"),
                    subtitle: diagnosticDate(steps.diagnostics.lastAutomaticSync),
                    systemImage: "bolt"
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Last manual or foreground sync"),
                    subtitle: diagnosticDate(steps.diagnostics.lastManualSync),
                    systemImage: "hand.tap"
                )
                if let failure = steps.currentFailureText {
                    FFDivider()
                    FFGroupedRow(
                        title: String(appLocalized: "Current sync issue"),
                        subtitle: failure,
                        systemImage: "exclamationmark.triangle",
                        subtitleTone: .ember
                    )
                }
                if let reference = steps.diagnostics.failureReference {
                    FFDivider()
                    FFGroupedRow(
                        title: String(appLocalized: "Sync error reference"),
                        subtitle: reference,
                        systemImage: "number",
                        subtitleTone: .neutral
                    )
                }
            }
        }
    }

    private var healthSubtitleTone: FFTone {
        switch steps.connection {
        case .syncFailed, .noAccessibleSteps: return .ember
        case .upToDate: return .moss
        case .syncing, .notConnected: return .neutral
        }
    }

    private var healthPill: FFPill {
        switch steps.connection {
        case .syncFailed:
            return FFPill(String(appLocalized: "Retry"), style: .softEmber)
        case .syncing:
            return FFPill(String(appLocalized: "Syncing"), style: .neutral)
        case .upToDate, .noAccessibleSteps:
            return FFPill(String(appLocalized: "Connected"), style: .softMoss)
        case .notConnected:
            return FFPill(String(appLocalized: "Connect"), style: .solidMoss)
        }
    }

    private func diagnosticDate(_ date: Date?) -> String {
        guard let date else { return String(appLocalized: "Not yet") }
        return date.formatted(.relative(presentation: .named).locale(AppLocalization.locale))
    }

    private var requests: some View {
        FFGroupedRows {
            FFGroupedRow(
                title: String(appLocalized: "Bugs & requests"),
                subtitle: String(appLocalized: "Post a bug or a feature request. Other people can upvote and comment with their username."),
                systemImage: "bubble.left.and.bubble.right",
                trailing: AnyView(FFChevron()),
                action: {
                    model.feedbackRequestFilter = RequestFilter()
                    model.tab = .feedback
                }
            )
            .disabled(session.isBusy)
        }
    }

    private var settings: some View {
        FFGroupedRows {
            if let code = session.profile?.referralCode {
                ShareLink(item: APIConfig.publicOrigin.appending(path: "r/\(code.uuidString.lowercased())")) {
                    rowLabel(title: String(appLocalized: "Refer a friend"), destructive: false)
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
