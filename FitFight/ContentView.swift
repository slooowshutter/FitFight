import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

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
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
    }

    @ViewBuilder
    private var signedInRoot: some View {
        if session.profile == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading your account…")
                    .font(.ff(17, .semibold))
                    .foregroundStyle(theme.text)
                if let authError = session.authError {
                    Text(authError)
                        .font(.ff(13))
                        .foregroundStyle(theme.red)
                }
                if session.authError != nil {
                    Button(session.isBusy ? "Loading…" : "Try again") {
                        Task { await session.retryLoadProfile() }
                    }
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.accent)
                    .disabled(session.isBusy)
                    .buttonStyle(.plain)
                }
                Button("Sign out") {
                    Task { await session.signOut() }
                }
                .font(.ff(13, .semibold))
                .foregroundStyle(theme.muted)
                .buttonStyle(.plain)
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
            FFTabBar(tab: $model.tab)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.tab {
        case .fights:
            fightsStack
        case .newFight:
            NewFightView()
        case .requests:
            RequestsView()
        case .you:
            YouView()
        }
    }

    private var fightsStack: some View {
        NavigationStack {
            FightsListView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $model.openFightID) { id in
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
        .environmentObject(FriendshipStore(client: session.client))
        .environmentObject(HealthKitStepsStore())
        .fitFightTheme(themeStore.theme)
}
