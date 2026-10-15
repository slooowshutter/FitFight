
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

        // A store from a server that cannot name companions yet: the character screen hides the name block.
        let character = #"{"id":"44444444-4444-4444-8444-444444444444","description":"a lazy panda in a hoodie","stage":"fitness","status":"complete","phase":"complete","request_id":"55555555-5555-4555-8555-555555555555","poll_after_seconds":null,"portrait_url":"https://example.com/portrait.png","candidates":[]"#
        let storeHead = #"{"app_account_token":"33333333-3333-4333-8333-333333333333","environment":"staging","purchases_enabled":true,"product_id":"com.fitfight.mvp.custom_character","free_characters":0,"characters":["#
        let older = try JSONDecoder().decode(CustomCharacterStoreSnapshot.self, from: Data((storeHead + character + "}]}").utf8))
        let olderCharacter = older.characters[0]
        precondition(olderCharacter.phase == .complete && olderCharacter.suggestions == nil)
        precondition(!olderCharacter.suggestionsPending && olderCharacter.moreSuggestionsLeft == 0)
        precondition(olderCharacter.name == nil && olderCharacter.line == nil)
        let labels = #","suggestions":[{"name":"Couch Panda","line":"Hoodie up. Steps up."},{"name":"Bao","line":"Naps hard. Walks harder."},{"name":"Sir Snooze","line":"Late start. Strong finish."},{"name":"Bamboo Bolt","line":"Fuelled by leaves and spite."}],"suggestions_pending":true,"more_suggestions_left":2,"name":"Couch Panda","line":null"#
        let current = try JSONDecoder().decode(CustomCharacterStoreSnapshot.self, from: Data((storeHead + character + labels + "}]}").utf8))
        let named = current.characters[0]
        precondition(named.suggestions?.count == 4 && named.suggestions?.first == .init(name: "Couch Panda", line: "Hoodie up. Steps up."))
        precondition(named.suggestionsPending && named.moreSuggestionsLeft == 2)
        precondition(named.name == "Couch Panda" && named.line == nil)

        // The backend's contract fixture decodes with the app's model.
        let fixture = try JSONDecoder().decode(CustomCharacterStoreSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let finished = fixture.characters[0]
        precondition(finished.suggestions?.count == 4 && finished.suggestions?.first == .init(name: "Street Strutter", line: "Struts like he owns the block. He does."))
        precondition(finished.suggestionsPending && finished.moreSuggestionsLeft == 2)
        precondition(finished.name == "Sir Waddles" && finished.line == "Slow start. Strong finish.")
        let drawing = fixture.characters[1]
        precondition(drawing.phase == .portraits && drawing.suggestions == [])
        precondition(!drawing.suggestionsPending && drawing.moreSuggestionsLeft == 0 && drawing.name == nil && drawing.line == nil)
        print("Companion retention, reuse, relaunch, account isolation, category filters, and character names passed")
    }
}
