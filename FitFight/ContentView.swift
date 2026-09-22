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
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if !appUpdate.showsUpdate || ScreenshotExport.isEnabled || CompanionPreview.isEnabled {
                appContent
            } else {
                updateScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .onChange(of: colorScheme, initial: true) { _, scheme in
            themeStore.systemMode = scheme == .dark ? .night : .day
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !ScreenshotExport.isEnabled, !CompanionPreview.isEnabled else { return }
            await appUpdate.check()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await appUpdate.check()
            }
        }
        .onChange(of: appUpdate.status) { _, status in
            guard !CompanionPreview.isEnabled else { return }
            if appUpdate.showsUpdate {
                model.showingVersions = false
                model.showingDebugMenu = false
            } else if status == .current, session.isSignedIn, session.profile == nil {
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
        .onChange(of: session.profile) { _, _ in
            companions.apply(session.profile)
            Task { await companions.publishPending(session: session) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            companions.apply(session.profile)
            Task { await companions.publishPending(session: session) }
        }
        .onAppear {
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
        .sheet(isPresented: $model.showingDebugMenu) {
            DebugMenuView()
                .environmentObject(themeStore)
                .environmentObject(steps)
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .onChange(of: session.isFitFightAdmin) { _, isAdmin in
            if !isAdmin { model.showingDebugMenu = false }
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
                set: { if !$0 { push.declinePrePrompt() } }
            )
        ) {
            Button(String(appLocalized: "Allow notifications")) {
                Task { await push.requestSystemPermission() }
            }
            Button(String(appLocalized: "Not now"), role: .cancel) {
                push.declinePrePrompt()
            }
        } message: {
            Text(String(appLocalized: "FitFight can remind you when a fight ends and when to sync your steps. Lock-screen alerts never show scores or fight titles."))
        }
    }

    private var updateScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            updateCard
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("required-update-screen")
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appUpdate.isTestFlight
                 ? String(appLocalized: "A FitFight update is available")
                 : String(appLocalized: "Update FitFight to continue"))
                .font(.ff(18, 800))
                .tracking(18 * -0.015)
                .foregroundStyle(theme.text)
            Text(appUpdate.isTestFlight
                 ? String(appLocalized: "Open TestFlight to check for the update. If it isn’t available yet, cancel and keep using FitFight.")
                 : String(appLocalized: "You can’t use FitFight until you install the latest version."))
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            HStack(spacing: 9) {
                if appUpdate.isTestFlight {
                    FFButton(title: String(appLocalized: "Cancel"), kind: .secondary, fullWidth: true) {
                        appUpdate.dismissUpdate()
                    }
                    .accessibilityIdentifier("cancel-update-button")
                } else {
                    FFButton(
                        title: String(appLocalized: "Check again"),
                        kind: appUpdate.offeredRelease != nil ? .secondary : .primary,
                        fullWidth: true
                    ) {
                        Task { await appUpdate.check() }
                    }
                    .disabled(appUpdate.isChecking)
                }
                if let release = appUpdate.offeredRelease {
                    FFButton(title: String(appLocalized: "Update FitFight"), kind: .primary, fullWidth: true) {
                        openURL(release.updateURL)
                    }
                    .accessibilityIdentifier("required-update-button")
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.overlayLine, radius: theme.radius.card)
        .padding(24)
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
        }
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
