import SwiftUI

enum StockCompanion: String, CaseIterable, Identifiable {
    case badger, raccoon, redPanda = "red-panda", otter, rabbit, fox, bear, boar, sloth, dog, goat, turtle

    case limitedBlackPanther = "limited-black-panther"
    case limitedLoneWolf = "limited-lone-wolf"
    case limitedSnowLeopard = "limited-snow-leopard"
    case limitedTiger = "limited-tiger"
    case limitedNightOwl = "limited-night-owl"
    case limitedCrocodile = "limited-crocodile"
    case limitedPeacock = "limited-peacock"
    case limitedFlamingo = "limited-flamingo"
    case limitedPersianCat = "limited-persian-cat"
    case limitedOstrich = "limited-ostrich"
    case limitedCheetah = "limited-cheetah"
    case limitedBaldEagle = "limited-bald-eagle"
    case limitedSilverback = "limited-silverback"
    case limitedKangaroo = "limited-kangaroo"
    case limitedBull = "limited-bull"
    case limitedMoose = "limited-moose"
    case limitedBison = "limited-bison"
    case limitedCamel = "limited-camel"
    case limitedPanda = "limited-panda"
    case limitedCapybara = "limited-capybara"
    case limitedHedgehog = "limited-hedgehog"
    case limitedGingerCat = "limited-ginger-cat"
    case limitedAlpaca = "limited-alpaca"
    case limitedSeal = "limited-seal"
    case limitedHamster = "limited-hamster"
    case limitedTreeFrog = "limited-tree-frog"
    case limitedMouse = "limited-mouse"
    case limitedGuineaPig = "limited-guinea-pig"
    case limitedDuck = "limited-duck"
    case limitedDonkey = "limited-donkey"

    var isLimited: Bool { rawValue.hasPrefix("limited-") }

    var id: String { rawValue }
    var image: String { "Companion-\(rawValue)" }

    var name: String {
        switch self {
        case .badger: String(appLocalized: "Badger")
        case .raccoon: String(appLocalized: "Raccoon")
        case .redPanda: String(appLocalized: "Red Panda")
        case .otter: String(appLocalized: "Otter")
        case .rabbit: String(appLocalized: "Rabbit")
        case .fox: String(appLocalized: "Fox")
        case .bear: String(appLocalized: "Bear")
        case .boar: String(appLocalized: "Boar")
        case .sloth: String(appLocalized: "Sloth")
        case .dog: String(appLocalized: "Dog")
        case .goat: String(appLocalized: "Goat")
        case .turtle: String(appLocalized: "Turtle")
        case .limitedBlackPanther: String(appLocalized: "Black Panther")
        case .limitedLoneWolf: String(appLocalized: "Lone Wolf")
        case .limitedSnowLeopard: String(appLocalized: "Snow Leopard")
        case .limitedTiger: String(appLocalized: "Tiger")
        case .limitedNightOwl: String(appLocalized: "Night Owl")
        case .limitedCrocodile: String(appLocalized: "Crocodile")
        case .limitedPeacock: String(appLocalized: "Peacock")
        case .limitedFlamingo: String(appLocalized: "Flamingo")
        case .limitedPersianCat: String(appLocalized: "Persian Cat")
        case .limitedOstrich: String(appLocalized: "Ostrich")
        case .limitedCheetah: String(appLocalized: "Cheetah")
        case .limitedBaldEagle: String(appLocalized: "Bald Eagle")
        case .limitedSilverback: String(appLocalized: "Silverback")
        case .limitedKangaroo: String(appLocalized: "Kangaroo")
        case .limitedBull: String(appLocalized: "Bull")
        case .limitedMoose: String(appLocalized: "Moose")
        case .limitedBison: String(appLocalized: "Bison")
        case .limitedCamel: String(appLocalized: "Camel")
        case .limitedPanda: String(appLocalized: "Panda")
        case .limitedCapybara: String(appLocalized: "Capybara")
        case .limitedHedgehog: String(appLocalized: "Hedgehog")
        case .limitedGingerCat: String(appLocalized: "Ginger Cat")
        case .limitedAlpaca: String(appLocalized: "Alpaca")
        case .limitedSeal: String(appLocalized: "Seal")
        case .limitedHamster: String(appLocalized: "Hamster")
        case .limitedTreeFrog: String(appLocalized: "Tree Frog")
        case .limitedMouse: String(appLocalized: "Mouse")
        case .limitedGuineaPig: String(appLocalized: "Guinea Pig")
        case .limitedDuck: String(appLocalized: "Duck")
        case .limitedDonkey: String(appLocalized: "Donkey")
        }
    }

    var caption: String {
        switch self {
        case .badger: String(appLocalized: "Quietly competitive.")
        case .raccoon: String(appLocalized: "Always has a plan.")
        case .redPanda: String(appLocalized: "Looks relaxed. Isn’t.")
        case .otter: String(appLocalized: "Here for a good time.")
        case .rabbit: String(appLocalized: "Always one more lap.")
        case .fox: String(appLocalized: "Just a little smug.")
        case .bear: String(appLocalized: "Big strides. Soft heart.")
        case .boar: String(appLocalized: "A little unstoppable.")
        case .sloth: String(appLocalized: "Slow is still forward.")
        case .dog: String(appLocalized: "Always up for a walk.")
        case .goat: String(appLocalized: "Takes the uphill route.")
        case .turtle: String(appLocalized: "Never out of the race.")
        case .limitedBlackPanther: String(appLocalized: "Doesn't count steps. Steps count him.")
        case .limitedLoneWolf: String(appLocalized: "Runs alone. Finishes first.")
        case .limitedSnowLeopard: String(appLocalized: "Cold start. Hot finish.")
        case .limitedTiger: String(appLocalized: "Wraps on. Excuses off.")
        case .limitedNightOwl: String(appLocalized: "Up at 3 a.m. Still ahead of you.")
        case .limitedCrocodile: String(appLocalized: "Smiles at the finish line. Bad sign.")
        case .limitedPeacock: String(appLocalized: "Dressed to win. Also wins.")
        case .limitedFlamingo: String(appLocalized: "Stands on one leg. Still out-walks you.")
        case .limitedPersianCat: String(appLocalized: "Pearls on. Pinky up. Pace up.")
        case .limitedOstrich: String(appLocalized: "Never buries her head. Only the competition.")
        case .limitedCheetah: String(appLocalized: "Fashionably fast. Never fashionably late.")
        case .limitedBaldEagle: String(appLocalized: "Spotted your step count from up here.")
        case .limitedSilverback: String(appLocalized: "Skips nothing. Especially not leg day.")
        case .limitedKangaroo: String(appLocalized: "Counts jumps as steps. Nobody argues.")
        case .limitedBull: String(appLocalized: "Charges first. Asks questions never.")
        case .limitedMoose: String(appLocalized: "Coach says one more lap. Coach is me.")
        case .limitedBison: String(appLocalized: "Skipping rope. Never skipping cardio.")
        case .limitedCamel: String(appLocalized: "Hydrated in 2019. Still going.")
        case .limitedPanda: String(appLocalized: "Bubble tea first. Then domination.")
        case .limitedCapybara: String(appLocalized: "Unbothered. Undefeated.")
        case .limitedHedgehog: String(appLocalized: "Prickly before coffee. Fast after.")
        case .limitedGingerCat: String(appLocalized: "Woke up at noon. Won by dinner.")
        case .limitedAlpaca: String(appLocalized: "Spits on rest days only.")
        case .limitedSeal: String(appLocalized: "Warm flippers. Cold competition.")
        case .limitedHamster: String(appLocalized: "Small legs. Unreasonable cardio.")
        case .limitedTreeFrog: String(appLocalized: "Hops count double. Allegedly.")
        case .limitedMouse: String(appLocalized: "Small steps. So many of them.")
        case .limitedGuineaPig: String(appLocalized: "Squeaks politely. Walks relentlessly.")
        case .limitedDuck: String(appLocalized: "Small duck. Big lift. Bigger quack.")
        case .limitedDonkey: String(appLocalized: "Stubborn about cardio. In a good way.")
        }
    }

    var series: SpecialSeries? {
        switch self {
        case .limitedBlackPanther, .limitedLoneWolf, .limitedSnowLeopard, .limitedTiger, .limitedNightOwl, .limitedCrocodile: .nightHunters
        case .limitedPeacock, .limitedFlamingo, .limitedPersianCat, .limitedOstrich, .limitedCheetah, .limitedBaldEagle: .royals
        case .limitedSilverback, .limitedKangaroo, .limitedBull, .limitedMoose, .limitedBison, .limitedCamel: .gymBros
        case .limitedPanda, .limitedCapybara, .limitedHedgehog, .limitedGingerCat, .limitedAlpaca, .limitedSeal: .cozyClub
        case .limitedHamster, .limitedTreeFrog, .limitedMouse, .limitedGuineaPig, .limitedDuck, .limitedDonkey: .oddSquad
        default: nil
        }
    }

    func effortImage(stage: CompanionEffortStage?) -> String {
        guard let stage else { return image }
        return "\(image)-effort-\(stage.rawValue)"
    }
}

/// Specials come in series of six, shown in this order.
enum SpecialSeries: CaseIterable {
    case nightHunters, royals, gymBros, cozyClub, oddSquad

    var name: String {
        switch self {
        case .nightHunters: String(appLocalized: "Night Hunters")
        case .royals: String(appLocalized: "Royals")
        case .gymBros: String(appLocalized: "Gym Bros")
        case .cozyClub: String(appLocalized: "Cozy Club")
        case .oddSquad: String(appLocalized: "Odd Squad")
        }
    }
}

enum CompanionCategory: String, CaseIterable, Identifiable {
    case all, limited, yours

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: String(appLocalized: "All")
        case .limited: String(appLocalized: "Specials")
        case .yours: String(appLocalized: "Yours")
        }
    }

    var animals: [StockCompanion] {
        switch self {
        case .all: StockCompanion.allCases
        case .limited: StockCompanion.allCases.filter(\.isLimited)
        case .yours: []
        }
    }
}

enum CompanionEffortStage: Int, CaseIterable, Identifiable {
    case rest = 1, headingOut, onTheMove, pushing, peak

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .rest: String(appLocalized: "Rest")
        case .headingOut: String(appLocalized: "Heading out")
        case .onTheMove: String(appLocalized: "On the move")
        case .pushing: String(appLocalized: "Pushing")
        case .peak: String(appLocalized: "Peak")
        }
    }

    var minimumSteps: Int {
        switch self {
        case .rest: 0
        case .headingOut: 3_000
        case .onTheMove: 6_000
        case .pushing: 10_000
        case .peak: 15_000
        }
    }

    var fitnessImageStage: String {
        switch self {
        case .rest: "resting"
        case .headingOut: "soft"
        case .onTheMove: "average"
        case .pushing: "fit"
        case .peak: "strong"
        }
    }

    static func matching(todaySteps: Int?) -> CompanionEffortStage {
        guard let todaySteps else { return .rest }
        return allCases.last { todaySteps >= $0.minimumSteps } ?? .rest
    }

    static func matchingDaily(_ status: HealthKitStepsStore.Status) -> CompanionEffortStage {
        if case .steps(let count) = status { return matching(todaySteps: count) }
        return .rest
    }
}

/// Only restored from older builds that offered a sport picker.
enum CompanionSport: String {
    case hiking, running, football, ski, walking
}

private struct CompanionIdentityRecord: Codable {
    var animal: String
    var sport: String
    var isCustom: Bool?
}

/// Account-backed companion selection and reusable custom descriptions.
@MainActor
final class CompanionStore: ObservableObject {
    @Published var selection: StockCompanion = .badger
    @Published var sport: CompanionSport = .hiking { didSet { persist() } }
    @Published var isCustom = false
    @Published var customPrompt = ""
    @Published private(set) var savedPrompts: [String] = []
    @Published private(set) var hasChosen = false
    @Published var showingPicker = false
    @Published var pickerStartsWithCustom = false

    private var isRestoring = false
    private var ownerId: UUID?
    private static let pendingPrefix = "ff.companion.pending."
    private static let pendingPromptPrefix = "ff.companion.pendingPrompt."
    private static let storageKey = "ff.companion.identity"
    private static let libraryPrefix = "ff.companion.library."
    static let customId = "custom"

    init() {
        restore()
    }

    static func hasPendingChoice(for userId: UUID?) -> Bool {
        guard let userId else { return false }
        return UserDefaults.standard.string(forKey: pendingPrefix + userId.uuidString) != nil
    }

    static func deleteLocalLibrary(for userId: UUID) {
        UserDefaults.standard.removeObject(forKey: "ff.ai.pending." + userId.uuidString)
        UserDefaults.standard.removeObject(forKey: libraryPrefix + userId.uuidString)
        UserDefaults.standard.removeObject(forKey: pendingPrefix + userId.uuidString)
        UserDefaults.standard.removeObject(forKey: pendingPromptPrefix + userId.uuidString)
    }

    func apply(_ profile: FitFightProfile?) {
        guard !CompanionPreview.isEnabled else { return }
        if ownerId != profile?.userId {
            ownerId = profile?.userId
            savedPrompts = ownerId.flatMap {
                UserDefaults.standard.stringArray(forKey: Self.libraryPrefix + $0.uuidString)
            } ?? []
            customPrompt = savedPrompts.first ?? ""
            selection = .badger
            isCustom = false
            hasChosen = false
        }
        if let userId = profile?.userId,
           let pending = UserDefaults.standard.string(forKey: Self.pendingPrefix + userId.uuidString) {
            let pendingPrompt = UserDefaults.standard.string(forKey: Self.pendingPromptPrefix + userId.uuidString)
            applyChoice(id: pending, prompt: pendingPrompt)
            if pendingSaveLanded(on: profile, id: pending, prompt: pendingPrompt) {
                clearPending(for: userId)
            }
        } else if let id = profile?.companionId {
            applyChoice(id: id, prompt: profile?.companionPrompt)
        } else {
            hasChosen = false
            isCustom = false
            if profile == nil {
                customPrompt = ""
                savedPrompts = []
                selection = .badger
                showingPicker = false
            }
        }
        persist()
    }

    func choose(id: String, prompt: String?, session: SessionStore) async throws {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            applyChoice(id: id, prompt: prompt)
            return
        }
        #endif
        if StockCompanion(rawValue: id)?.isLimited == true {
            // A Special needs the server's ownership check, so it is never saved offline.
            let userId = session.profile?.userId
            try await session.setCompanion(id: id, prompt: nil)
            try Task.checkCancellation()
            guard session.profile?.userId == userId, ownerId == userId else { throw CancellationError() }
            if let userId { clearPending(for: userId) }
            applyChoice(id: id, prompt: prompt)
            persist()
            return
        }
        applyChoice(id: id, prompt: prompt)
        persist()
        if let userId = session.profile?.userId {
            UserDefaults.standard.set(id, forKey: Self.pendingPrefix + userId.uuidString)
            if id == Self.customId {
                UserDefaults.standard.set(customPrompt, forKey: Self.pendingPromptPrefix + userId.uuidString)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingPromptPrefix + userId.uuidString)
            }
        }
        do {
            try await session.setCompanion(id: id, prompt: isCustom ? customPrompt : nil)
            if let userId = session.profile?.userId {
                clearPending(for: userId)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Keep the local pick and the pending key until the server confirms.
        }
    }

    func publishPending(session: SessionStore) async {
        guard let userId = session.profile?.userId,
              let pending = UserDefaults.standard.string(forKey: Self.pendingPrefix + userId.uuidString)
        else { return }
        let prompt = UserDefaults.standard.string(forKey: Self.pendingPromptPrefix + userId.uuidString)
        do {
            try await session.setCompanion(id: pending, prompt: pending == Self.customId ? prompt : nil)
            if pendingSaveLanded(on: session.profile, id: pending, prompt: prompt) {
                clearPending(for: userId)
            }
        } catch {
            return
        }
    }

    func animal(for personID: String?, companionID: String? = nil, isYou: Bool = false) -> StockCompanion? {
        if isYou && hasChosen { return isCustom ? nil : selection }
        if let companionID, let animal = StockCompanion(rawValue: companionID) {
            return animal
        }
        #if DEBUG && targetEnvironment(simulator)
        guard CompanionPreview.isEnabled else { return nil }
        if isYou || personID?.lowercased() == CompanionPreview.people[0].id.lowercased() {
            return selection
        }
        return CompanionPreview.animals[personID?.lowercased() ?? ""]
        #else
        return nil
        #endif
    }

    /// Custom always uses companion_id `custom`, so an id match is not proof a prompt edit landed.
    private func pendingSaveLanded(on profile: FitFightProfile?, id: String, prompt: String?) -> Bool {
        guard profile?.companionId == id else { return false }
        guard id == Self.customId else { return true }
        let server = profile?.companionPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let local = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !local.isEmpty && server == local
    }

    private func applyChoice(id: String, prompt: String?) {
        if id == Self.customId {
            isCustom = true
            customPrompt = (prompt ?? customPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
            if !customPrompt.isEmpty {
                savedPrompts.removeAll { $0 == customPrompt }
                savedPrompts.insert(customPrompt, at: 0)
            }
            hasChosen = true
            return
        }
        guard let animal = StockCompanion(rawValue: id) else {
            hasChosen = false
            isCustom = false
            return
        }
        selection = animal
        isCustom = false
        hasChosen = true
    }

    private func clearPending(for userId: UUID) {
        UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userId.uuidString)
        UserDefaults.standard.removeObject(forKey: Self.pendingPromptPrefix + userId.uuidString)
    }

    private func restore() {
        if CompanionPreview.isEnabled || ScreenshotExport.isEnabled { return }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(CompanionIdentityRecord.self, from: data)
        else { return }
        isRestoring = true
        sport = CompanionSport(rawValue: saved.sport) ?? .hiking
        if saved.isCustom != true, let animal = StockCompanion(rawValue: saved.animal) {
            applyChoice(id: animal.rawValue, prompt: nil)
        }
        isRestoring = false
    }

    private func persist() {
        guard !isRestoring, !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
        let record = CompanionIdentityRecord(
            animal: selection.rawValue,
            sport: sport.rawValue,
            isCustom: isCustom
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: Self.storageKey)
        if let ownerId {
            UserDefaults.standard.set(savedPrompts, forKey: Self.libraryPrefix + ownerId.uuidString)
        }
    }
}

struct CompanionCharacter: View {
    let animal: StockCompanion
    var effort: CompanionEffortStage?
    /// Off when a parent button owns the tap, so the inner greeting cannot swallow it.
    var greets = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var greeting = false

    var body: some View {
        if greets {
            greetingButton
        } else {
            artwork
        }
    }

    private var artwork: some View {
        Image(animal.effortImage(stage: effort))
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(greeting ? -3 : 0), anchor: .bottom)
            .scaleEffect(greeting ? 1.025 : 1, anchor: .bottom)
            .padding(4)
            .contentShape(Rectangle())
    }

    private var greetingButton: some View {
        Button {
            guard !reduceMotion, !staticRender, !greeting else { return }
            withAnimation(.easeInOut(duration: 0.18)) { greeting = true }
        } label: {
            artwork
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(appLocalized: "companion.greet", defaultValue: "Say hello to \(animal.name)"))
        .task(id: greeting) {
            guard greeting else { return }
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { greeting = false }
        }
    }
}

/// Prefer a saved companion; fall back to the existing photo or initials.
struct CompanionAvatar: View {
    var personID: String?
    var companionID: String?
    var isYou = false
    var monogram = "?"
    var photoURL: URL?
    var size: CGFloat = 44
    var pending = false
    /// Drawn around photo and initials fallbacks only; companion art stands free.
    var ring: Color?
    /// Head to waist instead of full body, for the small stacks on Fights cards.
    var halfBody = false
    @EnvironmentObject private var companions: CompanionStore

    init(
        personID: String? = nil,
        companionID: String? = nil,
        isYou: Bool = false,
        monogram: String = "?",
        photoURL: URL? = nil,
        size: CGFloat = 44,
        pending: Bool = false,
        ring: Color? = nil,
        halfBody: Bool = false
    ) {
        self.personID = personID
        self.companionID = companionID
        self.isYou = isYou
        self.monogram = monogram
        self.photoURL = photoURL
        self.size = size
        self.pending = pending
        self.ring = ring
        self.halfBody = halfBody
    }

    init(_ person: Person?, size: CGFloat = 44, pending: Bool = false, ring: Color? = nil, halfBody: Bool = false) {
        self.init(
            personID: person?.id,
            companionID: person?.companionId,
            isYou: person?.isYou ?? false,
            monogram: person?.initials ?? "?",
            photoURL: person?.photoURL,
            size: size,
            pending: pending,
            ring: ring,
            halfBody: halfBody
        )
    }

    var body: some View {
        if let animal = companions.animal(for: personID, companionID: companionID, isYou: isYou) {
            Group {
                if halfBody {
                    // The 352x400 portrait scaled so its top 55% (head to waist) fills the square, then cropped.
                    Image(animal.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size / 0.55 * 352 / 400, height: size / 0.55)
                        .frame(width: size, height: size, alignment: .top)
                        .clipped()
                } else {
                    // Full body in the same square a head crop used, so rows and cards keep their size.
                    Image(animal.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                }
            }
            .contentShape(Rectangle())
            .opacity(pending ? 0.55 : 1)
            .accessibilityHidden(true)
        } else if let photoURL, (isYou && companions.hasChosen) ? companions.isCustom : companionID == CompanionStore.customId {
            // A custom character is transparent art like the stock animals, so it stands free in the same square, never in a photo circle.
            RemotePhoto(url: photoURL, kind: .avatar, contentMode: .fit) { Color.clear }
                .frame(width: halfBody ? size / 0.55 : size, height: halfBody ? size / 0.55 : size)
                .frame(width: size, height: size, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .opacity(pending ? 0.55 : 1)
                .accessibilityHidden(true)
        } else {
            FFAvatar(monogram: monogram, size: size, photoURL: photoURL, dimmed: pending)
                .overlay {
                    if let ring { Circle().strokeBorder(ring, lineWidth: 2) }
                }
        }
    }
}

struct CompanionAvatarStack: View {
    let people: [Person]
    var visible = 3
    var size: CGFloat = 36
    var ring: Color?
    var halfBody = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(people.prefix(visible).enumerated()), id: \.element.id) { offset, person in
                CompanionAvatar(person, size: size, ring: ring ?? theme.bg, halfBody: halfBody)
                    .zIndex(Double(visible - offset))
            }
            if people.count > visible {
                Text("+\(people.count - visible)")
                    .font(.ff(11, 800))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: size, height: size)
                    .background(theme.chip, in: Circle())
                    .overlay { Circle().strokeBorder(ring ?? theme.bg, lineWidth: 2) }
            }
        }
    }
}

struct CompanionIntroduction: View {
    enum Surface { case fights, newFight, you }
    let surface: Surface
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ffStaticRender) private var staticRender
    @State private var fitnessImages: [String: URL] = [:]
    @State private var showingLevels = false
    /// The picker lives on the root sheet, so it opens only after the levels drawer has dismissed.
    @State private var pickerAfterLevels = false

    var body: some View {
        Group {
            if surface == .fights {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text("Fights")
                                .ffType(.title)
                                .foregroundStyle(theme.text)
                            TenKStreakBadge()
                        }
                        .frame(minHeight: 44)
                        let live = model.fights.filter { $0.status == .live && !$0.isUpcoming }
                        if !live.isEmpty {
                            let leading = live.filter { $0.rank == 1 }.count
                            Text(String(appLocalized: "fights.hosted-leading", defaultValue: "Leading \(leading) of \(live.count)"))
                                .font(.custom("Nunito-ExtraBold", size: 16, relativeTo: .body))
                                .foregroundStyle(leading > 0 ? theme.mossText : theme.emberText)
                        }
                        dailySteps
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    youCharacter
                        .frame(width: typeSize.isAccessibilitySize ? 96 : 142, height: 156)
                        .clipped()
                        .contentShape(Rectangle())
                        .accessibilitySortPriority(-1)
                }
            } else if typeSize > .large {
                VStack(alignment: .leading, spacing: 12) {
                    copy
                    youCharacter
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                }
            } else if surface == .you {
                HStack(alignment: .top, spacing: 0) {
                    copy
                        .frame(maxWidth: .infinity, alignment: .leading)
                    youCharacter
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 24)
                        .clipped()
                        .contentShape(Rectangle())
                        .padding(.top, 24)
                }
                .frame(minHeight: height, alignment: .topLeading)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        youCharacter
                            .frame(width: proxy.size.width * 0.53, height: height - 24)
                            .clipped()
                            .contentShape(Rectangle())
                            .position(x: proxy.size.width * 0.735, y: height / 2 + 12)
                        copy
                            .frame(width: proxy.size.width * 0.52, height: height - 22, alignment: .topLeading)
                            .position(x: theme.space.screenPadding + proxy.size.width * 0.26, y: (height - 22) / 2)
                    }
                    .frame(width: proxy.size.width, height: height, alignment: .bottomLeading)
                }
                .frame(height: height)
                .padding(.horizontal, -theme.space.screenPadding)
                .clipped()
            }
        }
        .accessibilityElement(children: .contain)
        .task(id: [session.profile?.userId.uuidString, session.profile?.companionImageURL?.absoluteString]) {
            fitnessImages = [:]
            guard let profile = session.profile,
                  profile.companionId == CompanionStore.customId,
                  let selectedURL = profile.companionImageURL else { return }
            do {
                let entries = try await FitFightAPI().aiLibrary(accessToken: try await session.freshAccessToken())
                guard !Task.isCancelled,
                      session.profile?.userId == profile.userId,
                      session.profile?.companionImageURL == selectedURL else { return }
                if let entry = entries.first(where: {
                    $0.workflow == .fitness && $0.images.contains(where: { $0.url == selectedURL })
                }), entry.images.count == 5 {
                    fitnessImages = Dictionary(uniqueKeysWithValues: entry.images.map { ($0.stage, $0.url) })
                }
            } catch {
                return
            }
        }
        .sheet(isPresented: $showingLevels, onDismiss: {
            guard pickerAfterLevels else { return }
            pickerAfterLevels = false
            companions.pickerStartsWithCustom = false
            companions.showingPicker = true
        }) {
            CompanionLevelsSheet(status: steps.status, change: {
                pickerAfterLevels = true
                showingLevels = false
            }) { levelArt($0) }
                .fitFightTheme(theme)
                .presentationBackground(theme.overlay)
                .presentationCornerRadius(theme.radius.shell)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
    }

    private var height: CGFloat {
        switch surface {
        case .fights: 156
        case .newFight: 210
        case .you: 240
        }
    }

    @ViewBuilder
    private var copy: some View {
        VStack(alignment: .leading, spacing: 7) {
            if surface == .newFight {
                Text("Steps. Highest total wins.")
                    .font(.custom("Nunito-ExtraBold", size: 24, relativeTo: .title2))
                    .foregroundStyle(theme.text)
            } else {
                if companions.isCustom {
                    Text(session.profile?.companionName ?? String(appLocalized: "Custom"))
                        .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text(session.profile?.companionLine ?? String(appLocalized: "Your own animal."))
                        .font(.custom("Nunito-Bold", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text(companions.selection.name)
                        .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text(companions.selection.caption)
                        .font(.custom("Nunito-Bold", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.textSecondary)
                }
                Button(String(appLocalized: "Make it yours")) {
                    companions.pickerStartsWithCustom = true
                    companions.showingPicker = true
                }
                .ffType(.buttonSmall)
                .foregroundStyle(theme.mossText)
                .frame(minHeight: 44)
                .buttonStyle(FFHapticPlainStyle())
                Button(String(appLocalized: "Change animal")) {
                    companions.pickerStartsWithCustom = false
                    companions.showingPicker = true
                }
                .ffType(.buttonSmall)
                .foregroundStyle(theme.mossText)
                .frame(minHeight: 44)
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 28)
    }

    private var youEffort: CompanionEffortStage {
        CompanionEffortStage.matchingDaily(steps.status)
    }

    @ViewBuilder
    private var youCharacter: some View {
        // Every companion opens the drawer on Fights, so Change animal is always reachable.
        if surface == .fights {
            // The whole area is tappable, even when a custom companion has no image yet.
            Button { showingLevels = true } label: {
                youArt.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
                .buttonStyle(FFPressStyle())
                .accessibilityLabel(String(appLocalized: "Companion levels"))
        } else {
            youArt
        }
    }

    @ViewBuilder
    private var youArt: some View {
        if companions.isCustom {
            RemotePhoto(url: fitnessImages[youEffort.fitnessImageStage] ?? session.profile?.photoURL, contentMode: .fit) { Color.clear }
        } else {
            CompanionCharacter(animal: companions.selection, effort: youEffort, greets: surface != .fights)
        }
    }

    @ViewBuilder
    private func levelArt(_ stage: CompanionEffortStage) -> some View {
        if companions.isCustom {
            RemotePhoto(url: fitnessImages[stage.fitnessImageStage], contentMode: .fit) { Color.clear }
        } else {
            Image(companions.selection.effortImage(stage: stage))
                .resizable()
                .scaledToFit()
                .padding(4)
        }
    }

    private var dailySteps: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch steps.status {
            case .steps(let count):
                Text(count, format: .number)
                    .font(.custom("Nunito-ExtraBold", size: 34, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text("steps today")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            case .reading, .idle where steps.hasAsked, .empty where model.isRefreshingFights:
                if staticRender {
                    Image(systemName: "arrow.clockwise").foregroundStyle(theme.gold)
                } else {
                    ProgressView().tint(theme.gold)
                }
                Text(String(appLocalized: "Synchronizing your steps."))
                    .font(.custom("Nunito-ExtraBold", size: 16, relativeTo: .body))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .empty:
                Text("-")
                    .ffType(.metric)
                    .foregroundStyle(theme.text)
                Text(steps.hasAsked ? String(appLocalized: "Today’s steps unavailable") : String(appLocalized: "Connect Apple Health"))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Opened from the companion on Fights: every effort form, the steps it starts at, and what today's next one needs.
struct CompanionLevelsSheet<Art: View>: View {
    let status: HealthKitStepsStore.Status
    let change: () -> Void
    @ViewBuilder var art: (CompanionEffortStage) -> Art
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let current = CompanionEffortStage.matchingDaily(status)
        VStack(alignment: .leading, spacing: 16) {
            FFSheetHeader(title: String(appLocalized: "Levels")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(appLocalized: "Your companion changes with today’s steps."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(appLocalized: "Change animal"), action: change)
                    .ffType(.buttonSmall)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
                    .frame(minHeight: 44)
                    if let next = CompanionEffortStage(rawValue: current.rawValue + 1) {
                        FFCard {
                            HStack(spacing: 14) {
                                art(next)
                                    .frame(width: 88, height: 100)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(String(appLocalized: "Next level"))
                                        .ffType(.eyebrow)
                                        .foregroundStyle(theme.textSecondary)
                                    Text(next.name)
                                        .ffType(.heading)
                                        .foregroundStyle(theme.text)
                                    // Unknown steps leave the companion resting, but the gap can't be counted.
                                    if case .steps(let count) = status {
                                        Text(String(appLocalized: "companion.level-remaining", defaultValue: "\(next.minimumSteps - count) more steps today"))
                                            .ffType(.label)
                                            .foregroundStyle(theme.gold)
                                    } else {
                                        Text(String(appLocalized: "companion.level-minimum", defaultValue: "\(next.minimumSteps)+ steps"))
                                            .ffType(.caption)
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    FFGroupedRows {
                        ForEach(CompanionEffortStage.allCases) { stage in
                            if stage != .rest { FFDivider() }
                            HStack(spacing: 14) {
                                art(stage)
                                    .frame(width: 84, height: 96)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(stage.name)
                                        .ffType(.rowTitle)
                                        .foregroundStyle(theme.text)
                                    Text(stage == .rest
                                         ? String(appLocalized: "companion.level-under", defaultValue: "Under \(CompanionEffortStage.headingOut.minimumSteps) steps")
                                         : String(appLocalized: "companion.level-minimum", defaultValue: "\(stage.minimumSteps)+ steps"))
                                        .ffType(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                if stage == current {
                                    Text(String(appLocalized: "Today"))
                                        .ffType(.label)
                                        .foregroundStyle(theme.mossText)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(stage == current ? .isSelected : [])
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 16)
    }
}

struct CompanionScene: View {
    var body: some View {
        Image("Companion-race")
            .resizable()
            .scaledToFit()
            .accessibilityLabel(String(appLocalized: "Rabbit, Turtle, Fox and Badger running together"))
    }
}

struct CompanionFightSummary: View {
    let fight: Fight
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var racing: [Standing] { fight.standings.filter { !$0.invited && !$0.deferred } }
    private var mine: Standing? { racing.first { $0.person.isYou } }
    private var rival: Standing? { racing.first { !$0.person.isYou } }
    private var gap: Double? {
        guard !fight.isUpcoming, let mine, let best = racing.filter({ !$0.person.isYou }).map(\.score).max() else { return nil }
        return mine.score - best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let groupImageURL = fight.groupImageURL {
                // Transparent art straight on the screen, no box, 12 pt from the edges like the approved proposal.
                RemotePhoto(url: groupImageURL, kind: .photo, contentMode: .fit) { Color.clear }
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .padding(.horizontal, 12 - theme.space.screenPadding)
                    .accessibilityElement()
                    .accessibilityLabel(String(appLocalized: "Everyone in this fight running together"))
                    .accessibilityAddTraits(.isImage)
            } else if CompanionPreview.isEnabled && racing.count == 4 {
                CompanionScene()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    // Trim the scene's empty margins while retaining every character and its ground.
                    .frame(height: 168)
                    .clipped()
            } else if CompanionPreview.isEnabled {
                HStack(alignment: .bottom, spacing: 0) {
                    if mine != nil {
                        CompanionCharacter(
                            animal: companions.selection,
                            effort: CompanionEffortStage.matchingDaily(steps.status)
                        )
                    }
                    if let rival, let animal = companions.animal(for: rival.person.id, companionID: rival.person.companionId) {
                        CompanionCharacter(animal: animal)
                    }
                }
                .frame(height: 144)
                .frame(maxWidth: .infinity)
            } else {
                // Until the fight's group image is ready, keep the real roster visible.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(racing.prefix(6)) { row in
                            CompanionAvatar(row.person, size: 52)
                        }
                    }
                    CompanionAvatarStack(
                        people: racing.map(\.person),
                        visible: 4, size: 38, ring: theme.bg
                    )
                }
                .padding(.vertical, 18)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(fight.isUpcoming ? String(appLocalized: "Scheduled") : fight.isTiedForFirst && mine?.rank == 1 ? String(appLocalized: "Tied") : fight.status == .finished
                     ? String(appLocalized: "fight.finished-rank", defaultValue: "Finished #\(fight.rank)")
                     : String(appLocalized: "fight.rank-of-count", defaultValue: "#\(fight.rank) of \(racing.count)"))
                    .ffType(.label)
                    .foregroundStyle(!fight.isUpcoming && fight.rank == 1 ? theme.mossText : theme.textSecondary)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(fight.timeLeftLabel)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mine.map { $0.score.formatted(.number.precision(.fractionLength(0))) } ?? "-")
                        .font(.custom("Nunito-ExtraBold", size: 34, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                    Text(String(appLocalized: "companion.fight-total", defaultValue: "Your steps · \(fight.durationLabel)"))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let gap {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                        Text(gap == 0 ? String(appLocalized: "Tied")
                             : "\(gap > 0 ? "+" : "−")\(abs(gap).formatted(.number.precision(.fractionLength(0))))")
                            .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                            .monospacedDigit()
                        if gap != 0 {
                            Text(gap > 0 ? String(appLocalized: "steps ahead") : String(appLocalized: "steps behind"))
                                .ffType(.caption)
                        }
                    }
                    .foregroundStyle(gap < 0 ? theme.emberText : gap > 0 ? theme.mossText : theme.textSecondary)
                }
            }
            .padding(.bottom, 8)
            FFDivider(inset: 0)
        }
    }
}

/// One big animal at a time: swipe between them with the neighbours peeking in, or tap a thumbnail below.
struct CompanionStage: View {
    let animals: [StockCompanion]
    @Binding var selection: StockCompanion?
    var label: (StockCompanion) -> String? = { _ in nil }
    var disabled = false
    /// Height of everything else on the screen. When set, the stage takes the rest and centres the animal in it.
    var reserved: CGFloat?
    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender

    /// Artwork sits in the middle of a wide transparent canvas, so pages overlap for the neighbours to show.
    private let overlap: CGFloat = -50

    var body: some View {
        VStack(spacing: 14) {
            if let reserved {
                stage.containerRelativeFrame(.vertical) { height, _ in max(320, height - reserved) }
            } else {
                stage.frame(height: 320)
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    thumbnails
                }
                .onChange(of: selection, initial: true) { _, animal in
                    guard let animal else { return }
                    withAnimation(reduceMotion ? nil : .snappy) { reader.scrollTo(animal, anchor: .center) }
                }
            }
            .opacity(staticRender ? 0 : 1)
            .overlay(alignment: .leading) {
                if staticRender { thumbnails.fixedSize() }
            }
        }
        .padding(.horizontal, -20)
    }

    private var stage: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.62
            if staticRender {
                // ImageRenderer can't draw scroll views, so screenshots lay the pages out directly.
                let index = CGFloat(animals.firstIndex { $0 == selection } ?? 0)
                HStack(spacing: overlap) { ForEach(animals) { page($0, width: width, height: proxy.size.height) } }
                    .fixedSize()
                    .offset(x: (proxy.size.width - width) / 2 - index * (width + overlap))
                    .frame(width: proxy.size.width, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    // NOTE: Not lazy. A lazy stack rebuilds the page you scroll back to and slides it in
                    // from the far side of the screen. The thumbnails below already load every animal.
                    HStack(spacing: overlap) { ForEach(animals) { page($0, width: width, height: proxy.size.height) } }
                        .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (proxy.size.width - width) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selection, anchor: .center)
                .disabled(disabled)
            }
        }
        .clipped()
    }

    private var thumbnails: some View {
        HStack(spacing: 8) {
            ForEach(animals) { animal in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { selection = animal }
                } label: {
                    Image(animal.image)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .frame(width: 64, height: 76)
                        .background(selection == animal ? theme.mossWash : theme.card,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .ffBorder(selection == animal ? theme.mossEdge : theme.hairline, radius: 16)
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(disabled)
                .accessibilityLabel(animal.name)
                .accessibilityAddTraits(selection == animal ? .isSelected : [])
                .id(animal)
            }
        }
        .padding(.horizontal, 20)
    }

    private func page(_ animal: StockCompanion, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(animal.image)
                .resizable()
                .scaledToFit()
                .frame(height: 220)
                .opacity(selection == animal ? 1 : 0.55)
                .accessibilityHidden(true)
            Group {
                Text(animal.name)
                    .font(.ff(24, 800))
                    .foregroundStyle(theme.text)
                Text(animal.caption)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = label(animal) {
                    Text(text).ffType(.caption).foregroundStyle(theme.mossText)
                }
            }
            .opacity(selection == animal ? 1 : 0)
        }
        // The page fills the stage height, so the animal sits centred in any spare space.
        .frame(width: width, height: height)
        .scaleEffect(selection == animal ? 1 : 0.9)
        .animation(reduceMotion ? nil : .snappy, value: selection)
        .accessibilityElement(children: .combine)
        .id(animal)
    }
}

struct CompanionPicker: View {
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var purchases: SpecialPurchases
    @EnvironmentObject private var characterPurchases: CustomCharacterPurchases
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: StockCompanion?
    @State private var pickingCustom: Bool
    @State private var customPrompt: String
    @State private var category: CompanionCategory
    @State private var isSaving = false
    @State private var error = ""
    @State private var library: [FitFightAILibraryEntry] = []
    @State private var loadingEditions = false
    @State private var editionsError = ""
    @State private var showingGeneration = false
    /// The character the creation screen opens on; nil with "Create your own" starts a new one.
    @State private var generationCharacterID: UUID?
    @State private var showingGrid = false

    private let startWithCustom: Bool

    init(selection: StockCompanion, required: Bool = false, isCustom: Bool = false, prompt: String = "", startWithCustom: Bool = false) {
        self.startWithCustom = startWithCustom
        _category = State(initialValue: startWithCustom ? .yours : selection.isLimited && !required ? .limited : .all)
        if isCustom || startWithCustom {
            _draft = State(initialValue: nil)
            _pickingCustom = State(initialValue: true)
            _customPrompt = State(initialValue: prompt)
        } else {
            _draft = State(initialValue: required ? nil : selection)
            _pickingCustom = State(initialValue: false)
            _customPrompt = State(initialValue: prompt)
        }
    }

    var body: some View {
        FFScreen(clearance: false) {
            HStack(alignment: .top) {
                Text("Choose your companion")
                    .font(.custom("Nunito-ExtraBold", size: 26, relativeTo: .title))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                if category != .yours && !animals(in: category).isEmpty {
                    Button {
                        showingGrid.toggle()
                    } label: {
                        Image(systemName: showingGrid ? "rectangle.portrait" : "square.grid.2x2")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.mossText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(showingGrid ? String(appLocalized: "Show one at a time") : String(appLocalized: "Show all"))
                }
                if !session.needsCompanionSelection {
                    Button(String(appLocalized: "Close")) { dismiss() }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                        .frame(minHeight: 44)
                        .disabled(isSaving)
                }
            }
            Text("How others see you in fights and Feed. Change it anytime.")
                .font(.custom("Nunito-Bold", size: 13, relativeTo: .body))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if characterPurchases.freeCharacters > 0 {
                HStack(spacing: 10) {
                    FreeCharacterBadge(count: characterPurchases.freeCharacters)
                    Text(String(appLocalized: "Unlock any Special or create your own."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FFSegmented(items: CompanionCategory.allCases.filter { $0 != .limited || CompanionCategory.limited.animals.contains(where: shows) },
                        selection: $category, fill: true) { $0.name }
            .disabled(isSaving)
            if category == .limited || (category == .all && draft?.isLimited == true) {
                Text("Buy any Special once and keep it forever. Collect as many as you like.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                if !purchases.message.isEmpty {
                    Text(purchases.message).ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                ForEach(purchases.snapshot?.conflicts ?? [], id: \.transactionId) { claim in
                    FFButton(title: String(appLocalized: "Request a refund from Apple"), kind: .secondary) {
                        Task { await purchases.requestRefund(claim) }
                    }
                }
            }
            if category == .limited {
                if loadingEditions {
                    ProgressView(String(appLocalized: "Checking availability…"))
                        .ffType(.caption)
                } else if !editionsError.isEmpty {
                    Text(editionsError).ffType(.caption).foregroundStyle(theme.emberText)
                    FFButton(title: String(appLocalized: "Retry"), kind: .secondary) {
                        Task { await loadLimitedEditions() }
                    }
                }
            }
            let visible = animals(in: category)
            if category != .yours && !visible.isEmpty && !showingGrid {
                CompanionStage(
                    animals: visible,
                    selection: Binding(get: { pickingCustom ? nil : draft }, set: { animal in
                        guard let animal else { return }
                        draft = animal
                        pickingCustom = false
                        error = ""
                    }),
                    label: specialLabel,
                    disabled: isSaving || purchases.isBusy,
                    reserved: category == .limited || draft?.isLimited == true ? 280 : 240
                )
            }
            if category != .yours && !visible.isEmpty && showingGrid {
                // Specials are grouped under a small header per series; All stays one grid.
                let groups: [(title: String?, animals: [StockCompanion])] = category == .limited
                    ? SpecialSeries.allCases.map { series -> (title: String?, animals: [StockCompanion]) in (series.name, visible.filter { $0.series == series }) }.filter { !$0.animals.isEmpty }
                    : [(nil, visible)]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 10)], spacing: 10) {
                    ForEach(groups, id: \.animals) { group in
                        Section {
                            ForEach(group.animals) { animal in
                                let edition = status(animal)
                                Button {
                                    draft = animal
                                    pickingCustom = false
                                    error = ""
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(animal.image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 104)
                                            .clipped()
                                        Text(animal.name)
                                            .font(.custom("Nunito-ExtraBold", size: 12, relativeTo: .caption))
                                            .foregroundStyle(draft == animal && !pickingCustom ? theme.mossText : theme.text)
                                            .lineLimit(2, reservesSpace: true)
                                            .minimumScaleFactor(0.8)
                                        // Every tile reserves the status line so limited and regular animals stay the same size.
                                        Text(specialLabel(animal) ?? " ")
                                            .ffType(.caption)
                                            .foregroundStyle(theme.textSecondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .accessibilityHidden(!animal.isLimited)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .background(draft == animal && !pickingCustom ? theme.mossWash : theme.card,
                                                in: RoundedRectangle(cornerRadius: theme.radius.card))
                                    .ffBorder(draft == animal && !pickingCustom ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
                                    .contentShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                                }
                                .buttonStyle(FFHapticPlainStyle())
                                .disabled(isSaving || purchases.isBusy || (animal.isLimited && edition == nil))
                                .accessibilityAddTraits(draft == animal && !pickingCustom ? .isSelected : [])
                            }
                        } header: {
                            if let title = group.title {
                                Text(title)
                                    .ffType(.label)
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                }
            }
            if category == .yours {
                let owned = animals(in: .yours)
                let characters = characterPurchases.snapshot?.characters.filter { $0.status != .refunded } ?? []
                if characters.isEmpty && !owned.contains(where: \.isLimited) {
                    Text("Specials you buy and characters you create live here.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 10)], spacing: 10) {
                    ForEach(owned) { animal in
                        let selected = draft == animal && !pickingCustom
                        Button {
                            draft = animal
                            pickingCustom = false
                            error = ""
                        } label: {
                            collectionTile(
                                name: animal.name,
                                caption: equippedStock == animal ? String(appLocalized: "Equipped") : specialLabel(animal),
                                selected: selected
                            ) {
                                Image(animal.image).resizable().scaledToFit()
                            }
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(isSaving)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    ForEach(characters) { character in
                        let entry = library.first { $0.requestID == character.requestID && $0.workflow == .fitness }
                        let resting = entry?.images.first { $0.stage == "resting" }
                        let equipped = companions.isCustom && entry?.images.contains { $0.url == session.profile?.companionImageURL } == true
                        Button {
                            if character.status == .complete, let entry {
                                Task { await equip(entry) }
                            } else {
                                generationCharacterID = character.id
                                showingGeneration = true
                            }
                        } label: {
                            collectionTile(
                                name: character.name ?? character.suggestions?.first?.name
                                    ?? character.description ?? entry?.description ?? String(appLocalized: "Your character"),
                                caption: character.phase == .complete ? (equipped ? String(appLocalized: "Equipped") : nil)
                                    : character.phase == .choosing ? String(appLocalized: "Pick one")
                                    : [.portraits, .poses].contains(character.phase) ? String(appLocalized: "Being drawn")
                                    : String(appLocalized: "Finish it"),
                                selected: equipped && pickingCustom
                            ) {
                                if let resting {
                                    RemotePhoto(url: resting.url, contentMode: .fit) { theme.control }
                                } else if let portrait = character.portraitURL ?? character.candidateURLs.first {
                                    RemotePhoto(url: portrait, contentMode: .fit) { theme.control }
                                } else if character.status == .generating || character.status == .complete {
                                    ProgressView().tint(theme.gold)
                                } else {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(theme.mossText)
                                }
                            }
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(isSaving)
                        .accessibilityAddTraits(equipped ? .isSelected : [])
                        .contextMenu {
                            if character.status == .complete && character.suggestions != nil {
                                Button(String(appLocalized: "Name your companion"), systemImage: "pencil") {
                                    generationCharacterID = character.id
                                    showingGeneration = true
                                }
                            }
                        }
                    }
                    // Paid characters stay hidden while sales are off, except for an account that already bought one.
                    if CompanionPreview.isEnabled || characterPurchases.snapshot.map({ $0.purchasesEnabled || !$0.characters.isEmpty }) == true {
                        Button {
                            generationCharacterID = nil
                            showingGeneration = true
                        } label: {
                            collectionTile(
                                name: String(appLocalized: "Create your own"),
                                caption: characterPurchases.freeCharacters > 0
                                    ? String(appLocalized: "character.free-count", defaultValue: "\(characterPurchases.freeCharacters) free")
                                    : characterPurchases.product?.displayPrice,
                                selected: false
                            ) {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(theme.mossText)
                                    .frame(width: 64, height: 64)
                                    .background(theme.mossWash, in: Circle())
                            }
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(isSaving)
                    }
                }
                if !error.isEmpty && (draft == nil || pickingCustom) {
                    Text(error)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let draft, !pickingCustom, animals(in: category).contains(draft) {
                VStack(alignment: .leading, spacing: 8) {
                    if showingGrid {
                        HStack(alignment: .top, spacing: 12) {
                            Image(draft.image)
                                .resizable().scaledToFit().frame(width: 56, height: 72)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.name).ffType(.label).foregroundStyle(theme.text)
                                Text(draft.caption).ffType(.body).foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if companions.isCustom || !companions.hasChosen || draft != companions.selection {
                                    Text("Not saved yet").ffType(.caption).foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                    }
                    if !error.isEmpty {
                        Text(error).ffType(.caption).foregroundStyle(theme.emberText)
                    }
                    let paid = draft.isLimited && !CompanionPreview.isEnabled
                    let owned = status(draft) == .yours
                    let canBuy = purchases.canBuy(draft)
                    FFButton(
                        title: (paid || CompanionPreview.isEnabled && draft.isLimited) && !owned
                            ? purchases.hasUnclaimedCharge
                                ? String(appLocalized: "Unlock this Special")
                                : unlocksFree
                                    ? String(appLocalized: "Unlock with 1 free")
                                    : specialPrice.map { String(appLocalized: "special.buy", defaultValue: "Buy for \($0)") } ?? String(appLocalized: "Purchases unavailable")
                            : String(appLocalized: "Save companion"),
                        enabled: (!paid || owned || canBuy || unlocksFree) && (!draft.isLimited || status(draft) != nil),
                        busy: isSaving || purchases.isBusy, fullWidth: true
                    ) { Task { await saveStock(draft) } }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)
                .background(theme.bg)
            }
        }
        .interactiveDismissDisabled(session.needsCompanionSelection || isSaving || purchases.isBusy)
        .sheet(isPresented: $showingGeneration) {
            PaidCharacterView(initialDescription: customPrompt, characterID: generationCharacterID,
                              startNew: generationCharacterID == nil)
        }
        .onAppear {
            if customPrompt.isEmpty { customPrompt = companions.customPrompt }
            if companions.isCustom || startWithCustom {
                pickingCustom = true
                draft = nil
            } else if companions.hasChosen {
                pickingCustom = false
                draft = companions.selection
            }
        }
        .task(id: characterPurchases.snapshot?.characters.filter { $0.status == .complete }.compactMap(\.requestID)) {
            guard !CompanionPreview.isEnabled,
                  characterPurchases.snapshot?.characters.contains(where: { $0.status == .complete }) == true else { return }
            do {
                library = try await FitFightAPI().aiLibrary(accessToken: try await session.freshAccessToken())
            } catch {
                return
            }
        }
        .task(id: session.profile?.userId) {
            // A referral character can arrive while the app is open, so the balance is read again here.
            try? await characterPurchases.refresh(session: session)
            await loadLimitedEditions()
        }
        .onChange(of: category, initial: true) { _, category in
            error = ""
            // The stage always shows an animal, so keep the draft on one from this tab.
            let visible = animals(in: category)
            if category != .yours, !pickingCustom, let first = visible.first, draft.map(visible.contains) != true {
                draft = first
                pickingCustom = false
            }
        }
        .onChange(of: session.profile?.userId) { _, _ in dismiss() }
    }

    private func loadLimitedEditions() async {
        guard !CompanionPreview.isEnabled else { return }
        let userId = session.profile?.userId
        loadingEditions = true
        editionsError = ""
        defer { loadingEditions = false }
        do {
            try await purchases.refresh(session: session)
        } catch is CancellationError {
            return
        } catch {
            guard session.profile?.userId == userId else { return }
            editionsError = String(appLocalized: "Couldn’t load specials. Try again.")
        }
    }

    private func status(_ animal: StockCompanion) -> SpecialStoreSnapshot.Edition.Status? {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            return animal == CompanionCategory.limited.animals[0] || animal == CompanionCategory.limited.animals[1] ? .yours : .available
        }
        #endif
        return purchases.snapshot?.editions.first { $0.id == animal.rawValue }?.status
    }

    /// Yours lists every Special this account owns and the current stock companion.
    private func animals(in category: CompanionCategory) -> [StockCompanion] {
        guard category == .yours else { return category.animals.filter(shows) }
        let owned = CompanionCategory.limited.animals.filter { status($0) == .yours }
        let current = equippedStock.map { owned.contains($0) ? [] : [$0] } ?? []
        return current + owned
    }

    /// The preview never saves a choice, so its fixture animal counts as equipped.
    private var equippedStock: StockCompanion? {
        (companions.hasChosen || CompanionPreview.isEnabled) && !companions.isCustom ? companions.selection : nil
    }

    private func specialLabel(_ animal: StockCompanion) -> String? {
        guard animal.isLimited else { return nil }
        return status(animal) == .yours ? String(appLocalized: "Yours") : specialPrice ?? String(appLocalized: "Available")
    }

    /// Every Special costs the same consumable. The preview has no StoreKit, but it still shows the label a buyer sees.
    private var specialPrice: String? {
        purchases.product?.displayPrice ?? (CompanionPreview.isEnabled ? "€0.99" : nil)
    }

    /// A free character pays for a Special, unless an earlier paid charge is still waiting to unlock one.
    private var unlocksFree: Bool {
        characterPurchases.freeCharacters > 0 && !purchases.hasUnclaimedCharge
    }

    /// Specials stay hidden while sales are off, except one this account already owns.
    private func shows(_ animal: StockCompanion) -> Bool {
        !animal.isLimited || CompanionPreview.isEnabled || purchases.snapshot?.purchasesEnabled == true || status(animal) == .yours
    }

    private func saveStock(_ animal: StockCompanion) async {
        error = ""
        pickingCustom = false
        draft = animal
        isSaving = true
        defer { isSaving = false }
        do {
            var bought = false
            if animal.isLimited && !CompanionPreview.isEnabled,
               purchases.snapshot?.editions.first(where: { $0.id == animal.rawValue })?.status != .yours {
                let free = unlocksFree
                guard free ? await purchases.claimFree(animal, session: session) : await purchases.buy(animal, session: session) else {
                    self.error = purchases.message
                    if free { try? await characterPurchases.refresh(session: session) }
                    await loadLimitedEditions()
                    return
                }
                if free { try? await characterPurchases.refresh(session: session) }
                bought = true
            }
            try await companions.choose(id: animal.rawValue, prompt: nil, session: session)
            // After a purchase the picker stays open, so the buyer sees the Special marked as theirs.
            if bought {
                await loadLimitedEditions()
                return
            }
            // Closing through the binding only: a second dismiss() can hit the screen underneath and leave it untappable.
            companions.showingPicker = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            if animal.isLimited {
                try? await characterPurchases.refresh(session: session)
                await loadLimitedEditions()
            }
        }
    }

    private func equip(_ entry: FitFightAILibraryEntry) async {
        error = ""
        pickingCustom = true
        draft = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.setCompanion(image: .init(requestID: entry.requestID, stage: "resting"))
            companions.apply(session.profile)
            companions.showingPicker = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// One closet tile in Yours, matching the grid tiles on All and Specials.
    private func collectionTile<Art: View>(name: String, caption: String?, selected: Bool, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 3) {
            art()
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .clipped()
            Text(name)
                .font(.custom("Nunito-ExtraBold", size: 12, relativeTo: .caption))
                .foregroundStyle(selected ? theme.mossText : theme.text)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
            Text(caption ?? " ")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(selected ? theme.mossWash : theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card))
        .ffBorder(selected ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    }
}
