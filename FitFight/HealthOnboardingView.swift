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
            message: "FitFight reads your steps and other movement from Apple Health. Fights still use steps. We’ll ask iPhone for permission next. You can change this later in You.",
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
