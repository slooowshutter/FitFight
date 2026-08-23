import SwiftUI

struct ContentView: View {
    @State private var showingVersions = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("FitFight")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Challenge your friends.\nWinner takes the glory.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))

                Button("Versions") {
                    showingVersions = true
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                Button("Settings") {
                    showingSettings = true
                }
                .font(.headline)
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            VersionBanner()
        }
        .sheet(isPresented: $showingVersions) {
            VersionsView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#Preview("English") {
    ContentView()
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("French") {
    ContentView()
        .environment(\.locale, Locale(identifier: "fr"))
}
