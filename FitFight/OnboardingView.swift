import SwiftUI

/// The signed-in part of the selected Full of life flow. Only page changes replace the screen.
struct OnboardingView: View {
    var isReplay = false
    var onFinished: (() -> Void)? = nil
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var progress = FirstFightOnboarding()
    @State private var ownerID: UUID?
    @State private var handle = ""
    @State private var selected: StockCompanion = .goat
    @State private var busy = false
    @State private var error: String?
    @State private var backwards = false
    @FocusState private var usernameFocused: Bool
    private let animals: [StockCompanion] = [.goat, .fox, .otter, .bear, .rabbit, .sloth, .badger, .raccoon, .redPanda, .boar, .dog, .turtle]

    private var previous: FirstFightOnboarding.Page? {
        isReplay && progress.page == .health ? nil : progress.page.previous
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: progress.page.step, onBack: previous.map { page in
                { go(page, backwards: true) }
            }, busy: busy)
            Group {
                switch progress.page {
                case .username: username
                case .companion: companion
                case .health, .healthResult:
                    HealthOnboardingView(
                        showingResult: progress.page == .healthResult,
                        animal: selected, busy: $busy,
                        onResult: { go(.healthResult) },
                        onFinished: { go(.firstFight) }
                    )
                case .firstFight:
                    SuggestedFightsOnboardingView(
                        onFinished: { go(.reminders) },
                        onJoined: { id, name in
                            progress.joinedFightID = id
                            progress.joinedFightName = name
                            go(.reminders)
                        },
                        joinedFightID: progress.joinedFightID,
                        joinedFightName: progress.joinedFightName,
                        busy: $busy
                    )
                case .reminders:
                    NotificationOnboardingView(animal: selected, busy: $busy) {
                        if let page = progress.pageAfterReminders { go(page) } else { finish() }
                    }
                case .celebration: celebration
                }
            }
            .id(progress.page)
            .environment(\.onboardingDirection, backwards ? -1 : 1)
        }
        .background(theme.bg.ignoresSafeArea())
        .onAppear {
            ownerID = session.profile?.userId
            progress = isReplay ? FirstFightOnboarding(page: .health) : session.firstFightOnboarding ?? FirstFightOnboarding()
            handle = session.needsOnboarding ? "" : session.profile?.handle ?? ""
            selected = companions.hasChosen ? companions.selection : .goat
        }
    }

    private var username: some View {
        OnboardingPage {
            OnboardingHeading(title: String(appLocalized: "onboarding.username.title", defaultValue: "What should your\nopponents call you?"))
            OnboardingSpeech(animal: selected, text: String(appLocalized: "A name for the leaderboard."))
            FFField(label: String(appLocalized: "Your username"), state: error == nil ? .normal : .error, help: error) {
                TextField("your_name", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.continue)
                    .focused($usernameFocused)
                    .onSubmit { if SessionStore.isValidHandle(handle) && !busy { Task { await saveUsername() } } }
            }
            .modifier(OnboardingEntrance(order: 2))
            Text(String(appLocalized: "2 to 30 characters. Letters, numbers and underscores."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        } actions: {
            FFScreenCTA(title: String(appLocalized: "That's me"), enabled: SessionStore.isValidHandle(handle) && !busy, busy: busy) {
                Task { await saveUsername() }
            }
        }
    }

    private var companion: some View {
        OnboardingPage {
            OnboardingHeading(title: String(appLocalized: "onboarding.companion.title", defaultValue: "Find your kind\nof competitive."))
            CompanionStage(
                animals: animals,
                selection: Binding(get: { selected }, set: { if let animal = $0 { selected = animal } }),
                disabled: busy
            )
            .modifier(OnboardingEntrance(order: 2))
            if let error { FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle") }
        } actions: {
            FFScreenCTA(title: String(appLocalized: "onboarding.go-with", defaultValue: "Go with \(selected.name)"), enabled: !busy, busy: busy) {
                Task {
                    guard !busy, let ownerID else { return }
                    busy = true
                    error = nil
                    defer { busy = false }
                    do {
                        try await session.setCompanion(id: selected.id, prompt: nil)
                        try Task.checkCancellation()
                        guard session.profile?.userId == ownerID else { return }
                        companions.apply(session.profile)
                        go(.health)
                    } catch is CancellationError {
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private var celebration: some View {
        OnboardingPage {
            OnboardingCelebration(animal: selected)
            OnboardingHeading(
                title: String(appLocalized: "onboarding.youre-in", defaultValue: "You're in,\n\(session.profile?.handle ?? handle)."),
                subtitle: progress.joinedFightName
            )
        } actions: {
            FFScreenCTA(title: String(appLocalized: "Continue")) { finish() }
        }
    }

    private func go(_ page: FirstFightOnboarding.Page, backwards: Bool = false) {
        usernameFocused = false
        error = nil
        self.backwards = backwards
        progress.page = page
        if !isReplay, let ownerID { session.saveFirstFightOnboarding(progress, userID: ownerID) }
    }

    private func saveUsername() async {
        guard !busy, let ownerID else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.setHandle(handle)
            try Task.checkCancellation()
            guard session.profile?.userId == ownerID else { return }
            go(.companion)
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func finish() {
        if !isReplay, let ownerID, session.profile?.userId == ownerID {
            model.tab = .fights
            session.finishFirstFightOnboarding(userID: ownerID)
        }
        onFinished?()
    }
}
