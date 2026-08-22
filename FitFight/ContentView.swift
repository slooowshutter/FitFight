import SwiftUI

struct ContentView: View {
    @State private var showingVersions = false

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
    }
}

#Preview {
    ContentView()
}
