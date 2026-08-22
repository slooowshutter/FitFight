import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner {
                model.showingVersions = true
            }
            ZStack(alignment: .bottom) {
                Group {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                FFTabBar(tab: $model.tab)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
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
    return ContentView()
        .environmentObject(themeStore)
        .environmentObject(AppModel())
        .fitFightTheme(themeStore.theme)
}
