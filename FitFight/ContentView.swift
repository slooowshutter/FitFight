import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @State private var showingVersions = false
    @State private var showingDesign = false

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()

            ScrollView {
                VStack(spacing: theme.metrics.spaceLg) {
                    Spacer(minLength: theme.metrics.spaceXl)

                    VStack(spacing: 12) {
                        Text("FitFight")
                            .font(theme.displayFont())
                            .foregroundStyle(theme.colors.text)

                        Text("Challenge your friends.\nWinner takes the glory.")
                            .font(theme.bodyFont(17, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.colors.muted)
                    }

                    VStack(spacing: 10) {
                        FFButton(title: "Design") {
                            showingDesign = true
                        }
                        FFButton(title: "Versions", kind: .secondary) {
                            showingVersions = true
                        }
                    }
                    .padding(.horizontal, 8)

                    FFCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                FFChip(text: theme.name, emphasized: true)
                                FFChip(text: "sample")
                            }
                            Text("5K before Sunday")
                                .font(theme.bodyFont(20, weight: .bold))
                                .foregroundStyle(theme.colors.text)
                            Text("Placeholder card. Real fights come after we pick a look.")
                                .font(theme.bodyFont(15, weight: .regular))
                                .foregroundStyle(theme.colors.muted)
                        }
                    }

                    HStack(spacing: 8) {
                        FFStat(label: "Wins", value: "12")
                        FFStat(label: "Streak", value: "4")
                        FFStat(label: "Open", value: "2")
                    }

                    Spacer(minLength: theme.metrics.spaceXl)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(theme.colors.bg.ignoresSafeArea())
        .sheet(isPresented: $showingVersions) {
            VersionsView()
                .environmentObject(themeStore)
                .fitFightTheme(themeStore.current)
                .presentationBackground(themeStore.current.colors.bg)
        }
        .sheet(isPresented: $showingDesign) {
            DesignCatalogView()
                .environmentObject(themeStore)
                .fitFightTheme(themeStore.current)
                .presentationBackground(themeStore.current.colors.bg)
        }
    }
}

#Preview {
    let store = ThemeStore(preview: .arena)
    return ContentView()
        .environmentObject(store)
        .fitFightTheme(store.current)
}
