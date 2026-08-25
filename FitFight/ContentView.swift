import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var designStore: DesignStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner {
                model.showingVersions = true
            }
            if session.isSignedIn {
                signedInApp
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(resolved)
                .presentationBackground(resolved.bg)
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

    /// The picked design's palette on top of the token theme.
    private var resolved: Theme {
        designStore.variant.theme(themeStore.theme)
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
        case .designs:
            DesignsTabView()
        case .you:
            YouView()
        }
    }

    private var fightsStack: some View {
        NavigationStack {
            designStore.variant.fightsScreen
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
    let designStore = DesignStore()
    return ContentView()
        .environmentObject(themeStore)
        .environmentObject(designStore)
        .environmentObject(AppModel())
        .environmentObject(SessionStore(preview: ()))
        .environmentObject(HealthKitStepsStore())
        .fitFightTheme(designStore.variant.theme(themeStore.theme))
}
