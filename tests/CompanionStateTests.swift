
enum CompanionPreview { static let isEnabled = false }
enum ScreenshotExport { static let isEnabled = false }
enum HealthKitStepsStore {
    enum Status { case steps(Int), unavailable }
}

@MainActor
final class SessionStore {
    var profile: FitFightProfile?
    var prompts: [String] = []
    var suspendLoad = false
    var pendingLoad: CheckedContinuation<[String], Error>?
    var rejectSave = false

    func companionPrompts() async throws -> [String] {
        if suspendLoad {
            return try await withCheckedThrowingContinuation { pendingLoad = $0 }
        }
        return prompts
    }

    func setCompanion(id: String, prompt: String?) async throws {
        if rejectSave { throw URLError(.cannotConnectToHost) }
        profile?.companionId = id
        profile?.companionPrompt = prompt
        if let prompt {
            prompts.removeAll { $0 == prompt }
            prompts.insert(prompt, at: 0)
        }
    }
}

@main
enum CompanionStateTests {
    @MainActor
    static func main() async throws {
        let userId = UUID()
        defer {
            UserDefaults.standard.removeObject(forKey: "ff.companion.library." + userId.uuidString)
            UserDefaults.standard.removeObject(forKey: "ff.companion.identity")
        }
        let session = SessionStore()
        session.profile = FitFightProfile(
            userId: userId, handle: "companion_test", displayName: "Test",
            handleSetAt: nil, companionId: "badger"
        )
        let store = CompanionStore()
        store.apply(session.profile)
        let prompt = "A cream frenchie with gold sunglasses"
        try await store.choose(id: "custom", prompt: prompt, session: session)
        try await store.choose(id: "fox", prompt: nil, session: session)
        guard store.customPrompt == prompt else {
            print("FAIL: selecting a stock animal erased the saved custom prompt")
            exit(1)
        }
        store.apply(session.profile)
        precondition(store.customPrompt == prompt, "Profile refresh must preserve the prompt")
        precondition(!store.isCustom && store.selection == .fox)
        precondition(store.savedPrompts == [prompt])

        session.rejectSave = true
        do {
            try await store.choose(id: "limited-black-panther", prompt: nil, session: session)
            preconditionFailure("A rejected claim must reach the picker")
        } catch { }
        precondition(store.selection == .fox && session.profile?.companionId == "fox")
        precondition(!CompanionStore.hasPendingChoice(for: userId), "A failed claim must never be replayed offline")
        session.rejectSave = false
        try await store.choose(id: "limited-black-panther", prompt: nil, session: session)
        precondition(store.selection == .limitedBlackPanther)
        precondition(store.animal(for: userId.uuidString, companionID: "limited-black-panther") == .limitedBlackPanther)
        session.rejectSave = true
        try await store.choose(id: "fox", prompt: nil, session: session)
        precondition(store.selection == .fox && CompanionStore.hasPendingChoice(for: userId), "Stock picks still save offline")
        session.rejectSave = false
        await store.publishPending(session: session)
        precondition(session.profile?.companionId == "fox" && !CompanionStore.hasPendingChoice(for: userId))

        let restored = CompanionStore()
        restored.apply(session.profile)
        precondition(restored.customPrompt == prompt, "Relaunch must restore a stock user's saved prompt")
        precondition(restored.savedPrompts == [prompt])
        let second = "An otter with a blue scarf"
        try await restored.choose(id: "custom", prompt: second, session: session)
        try await restored.choose(id: "custom", prompt: prompt, session: session)
        precondition(restored.savedPrompts == [prompt, second], "Reusing a description must not duplicate it")
        try await restored.choose(id: "goat", prompt: nil, session: session)
        restored.apply(nil)
        precondition(restored.savedPrompts.isEmpty && restored.customPrompt.isEmpty)
        restored.apply(FitFightProfile(userId: UUID(), handle: "other", displayName: "Other", handleSetAt: nil))
        precondition(restored.savedPrompts.isEmpty && restored.customPrompt.isEmpty, "Accounts must not share a library")

        CompanionStore.deleteLocalLibrary(for: userId)
        precondition(UserDefaults.standard.stringArray(forKey: "ff.companion.library." + userId.uuidString) == nil)

        precondition(Set(CompanionCategory.all.animals) == Set(StockCompanion.allCases))
        precondition(CompanionCategory.allCases == [.all, .limited, .yours])
        precondition(CompanionCategory.yours.animals.isEmpty)
        precondition(CompanionCategory.limited.animals.count == 30)
        precondition(CompanionCategory.limited.animals.allSatisfy { $0.isLimited && !$0.caption.isEmpty })
        precondition(SpecialSeries.allCases.allSatisfy { series in StockCompanion.allCases.filter { $0.series == series }.count == 6 })
        precondition(CompanionCategory.limited.animals.map(\.series) == CompanionCategory.limited.animals.compactMap(\.series).sorted {
            SpecialSeries.allCases.firstIndex(of: $0)! < SpecialSeries.allCases.firstIndex(of: $1)!
        }, "The Specials carousel is ordered by series")
        precondition(StockCompanion.limitedTiger.effortImage(stage: .peak) == "Companion-limited-tiger-effort-5", "Specials have effort poses")
        precondition(StockCompanion.limitedTiger.productId == "com.fitfight.mvp.special.tiger")

        // A retired Special id from the first roster stays on its profile and is simply unknown here.
        let retired = FitFightProfile(userId: UUID(), handle: "retired", displayName: "Retired", handleSetAt: nil, companionId: "limited-pangolin")
        let retiredStore = CompanionStore()
        retiredStore.apply(retired)
        precondition(!retiredStore.hasChosen && retiredStore.animal(for: nil, companionID: "limited-pangolin") == nil)
        let stages = [(0, "resting"), (2_999, "resting"), (3_000, "soft"), (5_999, "soft"),
                      (6_000, "average"), (9_999, "average"), (10_000, "fit"), (14_999, "fit"),
                      (15_000, "strong")]
        for (steps, stage) in stages {
            precondition(CompanionEffortStage.matching(todaySteps: steps).fitnessImageStage == stage)
        }
        print("Companion retention, reuse, relaunch, account isolation, and category filters passed")
    }
}
