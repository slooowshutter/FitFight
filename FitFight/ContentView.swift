import SwiftUI

struct ContentView: View {
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

                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(AppVersion.label)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .background(Color.black)
                .accessibilityIdentifier("app-version")
        }
    }
}

#Preview {
    ContentView()
}
