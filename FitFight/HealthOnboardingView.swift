import SwiftUI

/// First-run Apple Health ask, right after the username. Permission stays on this phone.
struct HealthOnboardingView: View {
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore

    @State private var isConnecting = false

    var body: some View {
        OnboardingPage(
            title: "Connect Apple Health",
            message: "FitFight imports the Apple Health activity history you allow, including daily totals and workouts. Only Steps score Fights. Individual Health samples stay on your iPhone. We’ll ask for permission next.",
            actionTitle: isConnecting ? String(appLocalized: "Connecting…") : String(appLocalized: "Continue"),
            working: isConnecting,
            onSkip: finish
        ) {
            Task { await connect() }
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        let trace = HealthKitSyncTrace(trigger: .manual)
        await steps.refresh(requestAccess: true, trace: trace)
        finish()
        // Upload right away; returning from the permission sheet no longer triggers a refresh.
        Task { await model.refreshFights(session: session, steps: steps, trigger: .manual) }
    }

    private func finish() {
        session.finishHealthOnboarding()
        onFinished?()
    }
}
