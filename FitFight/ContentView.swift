import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appUpdate: AppUpdateChecker
    @EnvironmentObject private var push: PushNotificationService
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            appContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .overlay(alignment: .top) {
            if model.showingUpdateToastPreview || appUpdate.pendingToastRelease != nil {
                FFToast(
                    systemImage: "arrow.down.app",
                    title: String(appLocalized: "New FitFight version"),
                    message: appUpdate.isTestFlight
                        ? String(appLocalized: "Ready in TestFlight.")
                        : String(appLocalized: "Ready in the App Store."),
                    tone: .neutral,
                    action: FFToastAction(
                        title: String(appLocalized: "Update FitFight"),
                        buttonHeight: 48,
                        perform: {
                            if model.showingUpdateToastPreview {
                                model.showingUpdateToastPreview = false
                            } else if let release = appUpdate.pendingToastRelease {
                                appUpdate.dismissToast()
                                openURL(release.updateURL)
                            }
                        }
                    ),
                    onClose: {
                        if model.showingUpdateToastPreview {
                            model.showingUpdateToastPreview = false
                        } else {
                            appUpdate.dismissToast()
                        }
                    },
                    raised: false
                )
                .accessibilityIdentifier("update-toast-card")
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.top, 8)
            }
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            themeStore.systemMode = scheme == .dark ? .night : .day
        }
        .task(id: scenePhase == .background) {
            guard scenePhase != .background, !ScreenshotExport.isEnabled, !CompanionPreview.isEnabled else { return }
            await appUpdate.check()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await appUpdate.check()
            }
        }
        .task(id: appUpdate.pendingToastRelease) {
            guard let release = appUpdate.pendingToastRelease, !UIAccessibility.isVoiceOverRunning else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            if appUpdate.pendingToastRelease == release { appUpdate.dismissToast() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                appUpdate.dismissToast()
                model.showingUpdateToastPreview = false
            }
        }
        .onChange(of: appUpdate.status) { _, status in
            guard !CompanionPreview.isEnabled else { return }
            if status == .current, session.isSignedIn, session.profile == nil {
                Task { await session.loadProfile() }
            }
        }
    }

    private var appContent: some View {
        Group {
            if session.isRestoringSession {
                FFLoadingBlock()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isSignedIn {
                signedInRoot
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: Binding(
            get: { companions.showingPicker || session.needsCompanionSelection },
            set: { presented in
                if session.needsCompanionSelection {
                    companions.showingPicker = true
                } else {
                    companions.showingPicker = presented
                }
            }
        ), onDismiss: {
            companions.pickerStartsWithCustom = false
        }) {
            CompanionPicker(
                selection: companions.selection,
                required: session.needsCompanionSelection,
                isCustom: companions.isCustom,
                prompt: companions.customPrompt,
                startWithCustom: companions.pickerStartsWithCustom
            )
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
                .interactiveDismissDisabled(session.needsCompanionSelection)
        }
        .onChange(of: session.profile, initial: true) { _, profile in
            companions.apply(profile)
            Task { await companions.publishPending(session: session) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            companions.apply(session.profile)
            Task { await companions.publishPending(session: session) }
        }
        .alert(String(appLocalized: "Companion preview"), isPresented: Binding(
            get: { model.companionPreviewNotice != nil },
            set: { if !$0 { model.companionPreviewNotice = nil } }
        )) {
            Button(String(appLocalized: "OK"), role: .cancel) { model.companionPreviewNotice = nil }
        } message: {
            Text(model.companionPreviewNotice ?? "")
        }
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $model.showingPreferences) {
            PreferencesView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $model.showingBetaTesting) {
            BetaTestingView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $model.showingDebugMenu) {
            DebugMenuView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .onChange(of: session.isFitFightAdmin) { _, isAdmin in
            if !isAdmin {
                model.showingDebugMenu = false
                if !CompanionPreview.isEnabled { model.showingUpdateToastPreview = false }
            }
        }
        .sheet(item: $model.dailyStatusRecap) { recap in
            DailyStatusRecapView(recap: recap) {
                model.dailyStatusRecap = nil
            }
            .fitFightTheme(themeStore.theme)
            .presentationBackground(themeStore.theme.bg)
            .presentationDetents([.medium])
        }
        .alert("Couldn’t save referral", isPresented: Binding(
            get: { model.pendingReferralError != nil },
            set: { if !$0 { model.pendingReferralError = nil } }
        )) {
            Button("Try again") {
                Task { await model.consumePendingLinks(session: session) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(model.pendingReferralError ?? "")
        }
        .alert(
            String(appLocalized: "Get fight-end reminders?"),
            isPresented: Binding(
                get: {
                    push.showPrePrompt
                        && session.firstFightOnboarding == nil
                        && !session.needsOnboarding
                        && !session.needsHealthOnboarding
                        && !session.needsNotificationOnboarding
                        && !session.needsRequestsOnboarding
                        && !session.needsCompanionSelection
                },
                set: { if !$0 { push.markPromptHandledThisSession() } }
            )
        ) {
            Button(String(appLocalized: "Allow notifications")) {
                Task { await push.requestSystemPermission() }
            }
            Button(String(appLocalized: "Not now"), role: .cancel) {
                push.markPromptHandledThisSession()
            }
        } message: {
            Text(String(appLocalized: "FitFight can remind you when a fight ends and when to sync your steps. Lock-screen alerts never show scores or fight titles."))
        }
    }

    @ViewBuilder
    private var signedInRoot: some View {
        if session.profile == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    session.profileUnavailable
                        ? String(appLocalized: "Couldn't load your account")
                        : String(appLocalized: "Loading your account…")
                )
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                if session.profileUnavailable {
                    Text("Your profile is missing or the account was deleted. Sign out and start again.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let authError = session.authError {
                    Text(authError)
                        .ffType(.body)
                        .foregroundStyle(theme.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.profileUnavailable {
                    // Without this the screen is a dead end — you cannot get back to
                    // the welcome screen to sign in as anyone else.
                    FFButton(title: String(appLocalized: "Sign out"), kind: .secondary) {
                        Task { await session.signOut() }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if session.firstFightOnboarding != nil {
            OnboardingView()
                .id(session.profile?.userId)
        } else {
            signedInApp
                .id(session.authSession?.user.id)
        }
    }

    private var signedInApp: some View {
        // The strip takes layout space: a top safeAreaInset does not reach screens inside a NavigationStack.
        VStack(spacing: 0) {
            if model.environment == "beta" || (model.environment == "production" && session.isFitFightAdmin) {
                environmentStrip
            }
            ZStack {
                tabBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FFTabBar(tab: $model.tab, onReselect: {
                    if model.tab == .feedback {
                        model.feedbackRequestFilter = RequestFilter()
                    }
                    model.openFightID = nil
                })
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.tabBarHeight = $0 }
            }
        }
    }

    /// Everyone on the beta sees it. The admin also sees it on the App Store version, both with the
    /// build, to tell installs apart. It opens Profile's Beta testing setting, which links to both.
    private var environmentStrip: some View {
        let beta = model.environment == "beta"
        let name = beta ? String(appLocalized: "Beta") : "App Store"
        let version = String(appLocalized: "preferences.version", defaultValue: "\(AppVersion.marketing) · build \(AppVersion.build)")
        return Button {
            model.tab = .you
            model.showingBetaTesting = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: beta ? "flask.fill" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(verbatim: session.isFitFightAdmin ? "\(name) · \(version)" : name)
                    .ffType(.label)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(beta ? theme.emberText : theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            // A color background would otherwise also fill the status bar.
            .background(beta ? theme.emberWash : theme.control, ignoresSafeAreaEdges: [])
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityIdentifier("environment-strip")
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.tab {
        case .fights:
            fightsStack
        case .newFight:
            NewFightView()
        case .feed:
            NavigationStack {
                FeedView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(item: $model.openPost) { target in
                        FightPostDetailView(target: target)
                            .id(target)
                    }
            }
        case .feedback:
            FeedbackTabView()
        case .you:
            NavigationStack {
                YouView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(isPresented: $model.showingActivity) {
                        FeedActivityView()
                    }
            }
        }
    }

    private var fightsPath: Binding<[String]> {
        Binding(
            get: { model.openFightID.map { [$0] } ?? [] },
            set: { model.openFightID = $0.last }
        )
    }

    private var fightsStack: some View {
        NavigationStack(path: fightsPath) {
            FightsListView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    Group {
                        if let fight = model.detailFight(for: id) {
                            FightDetailView(fight: fight)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(String(appLocalized: "That fight isn’t on your list."))
                                    .ffType(.heading)
                                    .foregroundStyle(theme.text)
                                FFButton(title: String(appLocalized: "Close"), kind: .secondary) {
                                    model.openFightID = nil
                                }
                            }
                            .padding(.horizontal, theme.space.screenPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                    .background(InteractivePopGestureEnabler(canPop: true, ownsDelegate: false))
                }
                .background(InteractivePopGestureEnabler(canPop: model.openFightID != nil, ownsDelegate: true))
        }
    }
}

/// Hidden nav bars disable edge-swipe back. The Fights stack owns the gesture
/// delegate so the list cannot freeze after a pop. `canPop` (not the list's
/// window) decides whether swipe is on, because NavigationStack detaches the
/// list view while a fight is open.
private struct InteractivePopGestureEnabler: UIViewRepresentable {
    var canPop: Bool
    var ownsDelegate: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(canPop: canPop, ownsDelegate: ownsDelegate)
    }

    func makeUIView(context: Context) -> SentinelView {
        let view = SentinelView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: SentinelView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.canPop = canPop
        context.coordinator.ownsDelegate = ownsDelegate
        context.coordinator.sync(from: uiView)
    }

    final class SentinelView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.sync(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.sync(from: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canPop: Bool
        var ownsDelegate: Bool
        weak var navigationController: UINavigationController?

        init(canPop: Bool, ownsDelegate: Bool) {
            self.canPop = canPop
            self.ownsDelegate = ownsDelegate
        }

        func sync(from view: UIView) {
            var responder: UIResponder? = view
            while let current = responder {
                if let found = current as? UINavigationController {
                    navigationController = found
                    break
                }
                if let controller = current as? UIViewController, let found = controller.navigationController {
                    navigationController = found
                    break
                }
                responder = current.next
            }
            guard let nav = navigationController else { return }
            if ownsDelegate {
                nav.interactivePopGestureRecognizer?.delegate = self
                nav.interactivePopGestureRecognizer?.isEnabled = canPop
            } else if canPop {
                nav.interactivePopGestureRecognizer?.isEnabled = true
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            canPop && (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            canPop && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}

#Preview {
    let themeStore = ThemeStore()
    let session = SessionStore(preview: ())
    return ContentView()
        .environmentObject(themeStore)
        .environmentObject(AppModel())
        .environmentObject(CompanionStore())
        .environmentObject(AccountPreferencesStore())
        .environmentObject(session)
        .environmentObject(HealthKitStepsStore())
        .environmentObject(FeedStore())
        .environmentObject(AppUpdateChecker.shared)
        .environmentObject(PushNotificationService.shared)
        .fitFightTheme(themeStore.theme)
}
