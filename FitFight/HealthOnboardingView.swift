import SwiftUI

struct HealthOnboardingView: View {
    let showingResult: Bool
    let animal: StockCompanion
    @Binding var busy: Bool
    let onResult: () -> Void
    let onFinished: () -> Void
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var displayedSteps = 0.0

    private var todaySteps: Int? {
        if case .steps(let count) = steps.status { return count }
        return nil
    }

    var body: some View {
        OnboardingPage {
            if showingResult {
                OnboardingHeading(title: todaySteps != nil
                    ? String(appLocalized: "onboarding.steps.title", defaultValue: "Look at you,\nalready moving.")
                    : String(appLocalized: "onboarding.no-steps.title", defaultValue: "Your starting line\nis still here."))
                FFCard {
                    VStack(spacing: 12) {
                        Image(animal.image).resizable().scaledToFit().frame(height: 170)
                            .accessibilityHidden(true)
                        if let todaySteps {
                            OnboardingStepCount(value: reduceMotion || staticRender ? Double(todaySteps) : displayedSteps)
                                .font(.ff(48, 800)).monospacedDigit().foregroundStyle(theme.mossText)
                                .accessibilityLabel(todaySteps.formatted())
                            Text(String(appLocalized: "steps today"))
                                .font(.ff(15, 700)).foregroundStyle(theme.textSecondary)
                        } else {
                            Text(String(appLocalized: "No accessible step data"))
                                .ffType(.heading)
                            Text(String(appLocalized: "Connect later from You → Apple Health."))
                                .ffType(.body).foregroundStyle(theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                .modifier(OnboardingEntrance(order: 1))
                Text(String(appLocalized: "Only steps taken during the Fight count."))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                OnboardingHeading(
                    title: String(appLocalized: "onboarding.health.title", defaultValue: "Let your steps\ndo the talking."),
                    subtitle: String(appLocalized: "Connect Apple Health to count your steps in Fights."),
                    centered: false
                )
                HStack(spacing: 48) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40)).foregroundStyle(theme.emberText)
                    Image(animal.image).resizable().scaledToFit().frame(width: 140, height: 165)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                ForEach([
                    ["figure.walk", String(appLocalized: "Reads steps and movement data.")],
                    ["person.2", String(appLocalized: "Fight participants see your steps and standings.")],
                    ["lock", String(appLocalized: "You control access in Apple Health.")]
                ], id: \.first) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row[0]).frame(width: 24)
                        Text(row[1]).fixedSize(horizontal: false, vertical: true)
                    }
                    .ffType(.body).foregroundStyle(theme.textSecondary)
                }
            }
        } actions: {
            if showingResult {
                FFScreenCTA(title: String(appLocalized: "Find your first Fight")) { onFinished() }
            } else {
                FFScreenCTA(title: String(appLocalized: "Connect Apple Health"), enabled: !busy, busy: busy) {
                    Task {
                        guard !busy else { return }
                        busy = true
                        defer { busy = false }
                        await steps.refresh(requestAccess: true, trace: HealthKitSyncTrace(trigger: .manual))
                        guard !Task.isCancelled else { return }
                        onResult()
                    }
                }
                OnboardingSkip(title: String(appLocalized: "I'll do this later"), action: onResult)
                    .disabled(busy)
            }
        }
        .task(id: todaySteps) {
            guard showingResult, let todaySteps else { return }
            withAnimation(reduceMotion || staticRender ? nil : .easeOut(duration: 1)) {
                displayedSteps = Double(todaySteps)
            }
        }
    }
}

private struct OnboardingStepCount: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(Int(value.rounded()).formatted()) }
}
