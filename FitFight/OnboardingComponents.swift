import SwiftUI

private struct OnboardingDirectionKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var onboardingDirection: CGFloat {
        get { self[OnboardingDirectionKey.self] }
        set { self[OnboardingDirectionKey.self] = newValue }
    }
}

struct OnboardingHeader: View {
    let step: Int?
    var onBack: (() -> Void)? = nil
    var busy = false
    @Environment(\.ffTheme) private var theme

    private var label: String {
        switch step {
        case 1: String(appLocalized: "Your account")
        case 2: String(appLocalized: "Your username")
        case 3: String(appLocalized: "Your companion")
        case 4: String(appLocalized: "Apple Health")
        case 5: String(appLocalized: "Your first Fight")
        case 6: String(appLocalized: "Reminders")
        default: "FitFight"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(theme.card, in: Circle())
                        .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel(String(appLocalized: "Back"))
            }
            VStack(spacing: 8) {
                HStack {
                    Text(label)
                    Spacer()
                    if let step {
                        Text(String(appLocalized: "onboarding.progress", defaultValue: "\(step) of 6"))
                            .foregroundStyle(theme.textSecondary)
                            .monospacedDigit()
                    }
                }
                .font(.ff(13, 800))
                if let step {
                    HStack(spacing: 5) {
                        ForEach(1...6, id: \.self) { index in
                            Capsule().fill(index <= step ? theme.gold : theme.track)
                                .frame(height: 4)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 20)
        .frame(minHeight: 60)
    }
}

struct OnboardingPage<Content: View, Actions: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .modifier(OnboardingEntrance(horizontal: true))
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) { actions }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(theme.bg)
        }
        .background(theme.bg)
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}

struct OnboardingHeading: View {
    let title: String
    var subtitle: String? = nil
    var centered = true
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            Text(title)
                .font(.ff(centered ? 33 : 30, 800))
                .tracking(-0.8)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(OnboardingEntrance())
            if let subtitle {
                Text(subtitle)
                    .font(.ff(16, 700))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(OnboardingEntrance(order: 1))
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Entry state belongs to the mounted element, so selecting an animal cannot replay the surrounding UI.
struct OnboardingEntrance: ViewModifier {
    var order = 0
    var horizontal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.onboardingDirection) private var direction
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived || reduceMotion || staticRender ? 1 : 0)
            .offset(x: !arrived && !reduceMotion && !staticRender && horizontal ? 18 * direction : 0,
                    y: !arrived && !reduceMotion && !staticRender && !horizontal ? 7 : 0)
            .onAppear {
                withAnimation(reduceMotion || staticRender ? nil : .timingCurve(0.19, 1, 0.22, 1, duration: 0.32).delay(Double(min(order, 5)) * 0.065)) {
                    arrived = true
                }
            }
    }
}

struct OnboardingAnimal: View {
    let animal: StockCompanion
    var duration = 0.7
    var delay = 0.0
    var selectionReaction = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var greeted = false

    private struct Pose {
        var height: CGFloat = 0
        var scale: CGFloat = 1
    }

    var body: some View {
        Image(animal.image)
            .resizable()
            .scaledToFit()
            .keyframeAnimator(initialValue: Pose(), trigger: greeted) { image, pose in
                image.offset(y: reduceMotion || staticRender ? 0 : pose.height)
                    .scaleEffect(reduceMotion || staticRender ? 1 : pose.scale)
            } keyframes: { _ in
                KeyframeTrack(\.height) {
                    CubicKeyframe(selectionReaction ? -3 : -12, duration: duration * 0.3)
                    CubicKeyframe(0, duration: duration * 0.28)
                    CubicKeyframe(selectionReaction ? 0 : -4, duration: duration * 0.2)
                    CubicKeyframe(0, duration: duration * 0.22)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(selectionReaction ? 0.98 : 1, duration: 0)
                    CubicKeyframe(selectionReaction ? 1.025 : 1, duration: duration * 0.55)
                    CubicKeyframe(1, duration: duration * 0.45)
                }
            }
            .task {
                guard !reduceMotion, !staticRender else { return }
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
                greeted = true
            }
            .accessibilityHidden(true)
    }
}

struct OnboardingSpeech: View {
    let animal: StockCompanion
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 13) {
            Image(animal.image).resizable().scaledToFit().frame(width: 61, height: 69)
                .accessibilityHidden(true)
            Text(text)
                .font(.ff(15, 700))
                .foregroundStyle(theme.text)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(theme.line, lineWidth: 1) }
        }
    }
}

struct OnboardingSkip: View {
    let title: String
    let action: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title).font(.ff(14, 800))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingCelebration: View {
    let animal: StockCompanion
    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var burst = false

    var body: some View {
        ZStack {
            OnboardingAnimal(animal: animal, duration: 0.9)
                .frame(width: 236, height: 254)
            if !reduceMotion && !staticRender {
                ForEach(0..<18, id: \.self) { index in
                    let angle = Double(index) * .pi * 2 / 18
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index % 3 == 0 ? theme.emberText : index % 3 == 1 ? theme.mossText : theme.textSecondary)
                        .frame(width: 4, height: 8)
                        .offset(x: burst ? cos(angle) * 140 : 0, y: burst ? sin(angle) * 112 : 10)
                        .opacity(burst ? 0 : 1)
                        .animation(.easeOut(duration: 0.95).delay(Double(index) * 0.014), value: burst)
                }
            }
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.mossOn)
                .frame(width: 48, height: 48)
                .background(theme.mossFill, in: Circle())
                .offset(x: 85, y: 75)
        }
        .frame(maxWidth: .infinity).frame(height: 275)
        .accessibilityHidden(true)
        .onAppear { burst = true }
    }
}
