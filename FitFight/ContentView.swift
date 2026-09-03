import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var testFlightUpdate = TestFlightUpdateChecker()

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner {
                model.showingVersions = true
            }
            if session.isSignedIn {
                signedInRoot
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let build = testFlightUpdate.newerBuild {
                FFToast(
                    glyph: "↑",
                    title: "New version on TestFlight",
                    message: "Build \(build) is ready. Open TestFlight and tap Update.",
                    tone: .moss,
                    onClose: { testFlightUpdate.dismiss() }
                )
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, toastBottomPadding)
                .onTapGesture { testFlightUpdate.openTestFlight() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(theme.motion.sheet.animation, value: testFlightUpdate.newerBuild)
        .task {
            await testFlightUpdate.check()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await testFlightUpdate.check() }
        }
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
    }

    private var toastBottomPadding: CGFloat {
        if session.isSignedIn, session.profile != nil, !session.needsOnboarding {
            return 64
        }
        return theme.space.screenPadding
    }

    @ViewBuilder
    private var signedInRoot: some View {
        if session.profile == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.profileUnavailable ? "Couldn't load your account" : "Loading your account…")
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
                    FFButton(title: "Sign out", kind: .secondary) {
                        Task { await session.signOut() }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if session.needsOnboarding {
            OnboardingView()
        } else {
            signedInApp
        }
    }

    private var signedInApp: some View {
        ZStack {
            tabBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FFTabBar(tab: $model.tab, onReselect: {
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
        case .you:
            YouView()
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
                    if let fight = model.fight(id: id) {
                        FightDetailView(fight: fight)
                    }
                }
        }
    }
}

#Preview {
    let themeStore = ThemeStore()
    let session = SessionStore(preview: ())
    return ContentView()
        .environmentObject(themeStore)
        .environmentObject(AppModel())
        .environmentObject(session)
        .environmentObject(HealthKitStepsStore())
        .fitFightTheme(themeStore.theme)
}
