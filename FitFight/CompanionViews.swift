import SwiftUI

enum StockCompanion: String, CaseIterable, Identifiable {
    case badger, raccoon, redPanda = "red-panda", otter, rabbit, fox, bear, boar, sloth, dog, goat, turtle

    case limitedPangolin = "limited-pangolin"
    case limitedPlatypus = "limited-platypus"
    case limitedSpottedQuoll = "limited-spotted-quoll"
    case limitedFennecFox = "limited-fennec-fox"
    case limitedMuskOx = "limited-musk-ox"
    case limitedKookaburra = "limited-kookaburra"
    case limitedPorcupine = "limited-porcupine"
    case limitedBharal = "limited-bharal"
    case limitedGoldenSnubNosedMonkey = "limited-golden-snub-nosed-monkey"
    case limitedProboscisMonkey = "limited-proboscis-monkey"
    case limitedTreeKangaroo = "limited-tree-kangaroo"
    case limitedGilaMonster = "limited-gila-monster"
    case limitedTarsier = "limited-tarsier"
    case limitedManedWolf = "limited-maned-wolf"
    case limitedFireSalamander = "limited-fire-salamander"
    case limitedServalStroll = "limited-serval-stroll"
    case limitedPuffin = "limited-puffin"
    case limitedNumbatSprint = "limited-numbat-sprint"
    case limitedCoatiSnooze = "limited-coati-snooze"
    case limitedGalago = "limited-galago"
    case limitedFrilledLizard = "limited-frilled-lizard"
    case limitedOkapi = "limited-okapi"
    case limitedHoatzin = "limited-hoatzin"
    case limitedQuokka = "limited-quokka"
    case limitedNumbatStride = "limited-numbat-stride"
    case limitedSifaka = "limited-sifaka"
    case limitedSecretaryBirdStride = "limited-secretary-bird-stride"
    case limitedRockHyrax = "limited-rock-hyrax"
    case limitedServalSprint = "limited-serval-sprint"
    case limitedBandedMongoose = "limited-banded-mongoose"
    case limitedAxolotl = "limited-axolotl"
    case limitedThornyDevilStroll = "limited-thorny-devil-stroll"
    case limitedCoatiSprint = "limited-coati-sprint"
    case limitedTamandua = "limited-tamandua"
    case limitedPaca = "limited-paca"
    case limitedJerboa = "limited-jerboa"
    case limitedThornyDevilCoffee = "limited-thorny-devil-coffee"
    case limitedKakapo = "limited-kakapo"
    case limitedSecretaryBirdSnooze = "limited-secretary-bird-snooze"
    case limitedMarkhor = "limited-markhor"

    var isLimited: Bool { rawValue.hasPrefix("limited-") }
    var productId: String { "com.fitfight.mvp.special.\(rawValue.replacingOccurrences(of: "limited-", with: "").replacingOccurrences(of: "-", with: "_"))" }

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
        case .limitedPangolin: String(appLocalized: "Pangolin")
        case .limitedPlatypus: String(appLocalized: "Platypus")
        case .limitedSpottedQuoll: String(appLocalized: "Spotted Quoll")
        case .limitedFennecFox: String(appLocalized: "Fennec Fox")
        case .limitedMuskOx: String(appLocalized: "Musk Ox")
        case .limitedKookaburra: String(appLocalized: "Kookaburra")
        case .limitedPorcupine: String(appLocalized: "Porcupine")
        case .limitedBharal: String(appLocalized: "Bharal")
        case .limitedGoldenSnubNosedMonkey: String(appLocalized: "Golden Snub-Nosed Monkey")
        case .limitedProboscisMonkey: String(appLocalized: "Proboscis Monkey")
        case .limitedTreeKangaroo: String(appLocalized: "Tree Kangaroo")
        case .limitedGilaMonster: String(appLocalized: "Gila Monster")
        case .limitedTarsier: String(appLocalized: "Tarsier")
        case .limitedManedWolf: String(appLocalized: "Maned Wolf")
        case .limitedFireSalamander: String(appLocalized: "Fire Salamander")
        case .limitedServalStroll: String(appLocalized: "Serval, Easy Pace")
        case .limitedPuffin: String(appLocalized: "Puffin")
        case .limitedNumbatSprint: String(appLocalized: "Numbat, Sprint Mode")
        case .limitedCoatiSnooze: String(appLocalized: "Coati, Snooze Mode")
        case .limitedGalago: String(appLocalized: "Galago")
        case .limitedFrilledLizard: String(appLocalized: "Frilled Lizard")
        case .limitedOkapi: String(appLocalized: "Okapi")
        case .limitedHoatzin: String(appLocalized: "Hoatzin")
        case .limitedQuokka: String(appLocalized: "Quokka")
        case .limitedNumbatStride: String(appLocalized: "Numbat, Steady Stride")
        case .limitedSifaka: String(appLocalized: "Sifaka")
        case .limitedSecretaryBirdStride: String(appLocalized: "Secretary Bird, On Duty")
        case .limitedRockHyrax: String(appLocalized: "Rock Hyrax")
        case .limitedServalSprint: String(appLocalized: "Serval, Sprint Mode")
        case .limitedBandedMongoose: String(appLocalized: "Banded Mongoose")
        case .limitedAxolotl: String(appLocalized: "Axolotl")
        case .limitedThornyDevilStroll: String(appLocalized: "Thorny Devil, Easy Pace")
        case .limitedCoatiSprint: String(appLocalized: "Coati, Sprint Mode")
        case .limitedTamandua: String(appLocalized: "Tamandua")
        case .limitedPaca: String(appLocalized: "Paca")
        case .limitedJerboa: String(appLocalized: "Jerboa")
        case .limitedThornyDevilCoffee: String(appLocalized: "Thorny Devil, Coffee Break")
        case .limitedKakapo: String(appLocalized: "Kakapo")
        case .limitedSecretaryBirdSnooze: String(appLocalized: "Secretary Bird, Off Duty")
        case .limitedMarkhor: String(appLocalized: "Markhor")
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
        case .limitedPangolin: String(appLocalized: "Packed a snack. Called it endurance.")
        case .limitedPlatypus: String(appLocalized: "Built like a committee. Walks like a legend.")
        case .limitedSpottedQuoll: String(appLocalized: "Spots the finish line. Ignores the warm-up.")
        case .limitedFennecFox: String(appLocalized: "Heard you were skipping leg day.")
        case .limitedMuskOx: String(appLocalized: "Built for winter. Dressed for PE.")
        case .limitedKookaburra: String(appLocalized: "Laughs at your excuses. Then takes a break.")
        case .limitedPorcupine: String(appLocalized: "Personal space is part of the training plan.")
        case .limitedBharal: String(appLocalized: "Your hill is the warm-up.")
        case .limitedGoldenSnubNosedMonkey: String(appLocalized: "Golden fur. Questionable pacing.")
        case .limitedProboscisMonkey: String(appLocalized: "Wins every race by a nose.")
        case .limitedTreeKangaroo: String(appLocalized: "Took the stairs. All the way up the tree.")
        case .limitedGilaMonster: String(appLocalized: "A monster at taking it easy.")
        case .limitedTarsier: String(appLocalized: "Wide awake. Deeply suspicious of cardio.")
        case .limitedManedWolf: String(appLocalized: "All legs. No shortcuts.")
        case .limitedFireSalamander: String(appLocalized: "Warming up is a personal brand.")
        case .limitedServalStroll: String(appLocalized: "Long legs. Leisurely agenda.")
        case .limitedPuffin: String(appLocalized: "Flight mode off. Step count on.")
        case .limitedNumbatSprint: String(appLocalized: "Small stripes. Unreasonably big ambitions.")
        case .limitedCoatiSnooze: String(appLocalized: "Yawn first. Personal best later.")
        case .limitedGalago: String(appLocalized: "Night owl energy. Morning walk regrets.")
        case .limitedFrilledLizard: String(appLocalized: "Dressed for drama. Stayed for the steps.")
        case .limitedOkapi: String(appLocalized: "Half stripes. Full commitment to a nap.")
        case .limitedHoatzin: String(appLocalized: "Pre-workout is coffee and a long sit.")
        case .limitedQuokka: String(appLocalized: "Smiling through a very optional workout.")
        case .limitedNumbatStride: String(appLocalized: "Counts ants on rest days. Steps on the others.")
        case .limitedSifaka: String(appLocalized: "Sideways is still a direction.")
        case .limitedSecretaryBirdStride: String(appLocalized: "Booked your defeat between two meetings.")
        case .limitedRockHyrax: String(appLocalized: "Tiny legs. Elephant-sized confidence.")
        case .limitedServalSprint: String(appLocalized: "Already at the finish. Pretending to stretch.")
        case .limitedBandedMongoose: String(appLocalized: "Runs in a pack. Keeps a solo victory speech.")
        case .limitedAxolotl: String(appLocalized: "Regrows limbs. Still skips leg day.")
        case .limitedThornyDevilStroll: String(appLocalized: "Prickly about pace. Soft on rest days.")
        case .limitedCoatiSprint: String(appLocalized: "Sniffed out a shortcut. Took the long way.")
        case .limitedTamandua: String(appLocalized: "Long snout. Short list of excuses.")
        case .limitedPaca: String(appLocalized: "Times every lap. Rounds down the snack breaks.")
        case .limitedJerboa: String(appLocalized: "Tiny footprint. Dramatic entrance.")
        case .limitedThornyDevilCoffee: String(appLocalized: "Sharp outfit. Extremely soft schedule.")
        case .limitedKakapo: String(appLocalized: "Flight cancelled. Walking reluctantly.")
        case .limitedSecretaryBirdSnooze: String(appLocalized: "This meeting could have been a nap.")
        case .limitedMarkhor: String(appLocalized: "Spiralling horns. Perfectly level coffee.")
        }
    }

    func effortImage(stage: CompanionEffortStage?) -> String {
        // Specials have no effort forms yet.
        guard let stage, !isLimited else { return image }
        return "\(image)-effort-\(stage.rawValue)"
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
        switch todaySteps {
        case ..<3_000: return .rest
        case ..<6_000: return .headingOut
        case ..<10_000: return .onTheMove
        case ..<15_000: return .pushing
        default: return .peak
        }
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

    func loadSavedPrompts(session: SessionStore) async throws {
        guard !CompanionPreview.isEnabled, let ownerId,
              session.profile?.userId == ownerId else { return }
        let prompts = try await session.companionPrompts()
        try Task.checkCancellation()
        guard self.ownerId == ownerId, session.profile?.userId == ownerId else {
            throw CancellationError()
        }
        // Keep locally pending choices while refreshing the account's saved library.
        savedPrompts = prompts + savedPrompts.filter { !prompts.contains($0) }
        if customPrompt.isEmpty { customPrompt = savedPrompts.first ?? "" }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var greeting = false

    var body: some View {
        Button {
            guard !reduceMotion, !staticRender, !greeting else { return }
            withAnimation(.easeInOut(duration: 0.18)) { greeting = true }
        } label: {
            Image(animal.effortImage(stage: effort))
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(greeting ? -3 : 0), anchor: .bottom)
                .scaleEffect(greeting ? 1.025 : 1, anchor: .bottom)
                .padding(4)
                .contentShape(Rectangle())
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
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.ffTheme) private var theme

    init(
        personID: String? = nil,
        companionID: String? = nil,
        isYou: Bool = false,
        monogram: String = "?",
        photoURL: URL? = nil,
        size: CGFloat = 44,
        pending: Bool = false
    ) {
        self.personID = personID
        self.companionID = companionID
        self.isYou = isYou
        self.monogram = monogram
        self.photoURL = photoURL
        self.size = size
        self.pending = pending
    }

    init(_ person: Person?, size: CGFloat = 44, pending: Bool = false) {
        self.init(
            personID: person?.id,
            companionID: person?.companionId,
            isYou: person?.isYou ?? false,
            monogram: person?.initials ?? "?",
            photoURL: person?.photoURL,
            size: size,
            pending: pending
        )
    }

    var body: some View {
        if let animal = companions.animal(for: personID, companionID: companionID, isYou: isYou) {
            Image("\(animal.image)-avatar")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(theme.control, in: Circle())
                .clipShape(Circle())
                .contentShape(Circle())
                .opacity(pending ? 0.55 : 1)
                .accessibilityHidden(true)
        } else {
            FFAvatar(monogram: monogram, size: size, photoURL: photoURL, dimmed: pending)
        }
    }
}

struct CompanionAvatarStack: View {
    let people: [Person]
    var visible = 3
    var size: CGFloat = 36
    var ring: Color?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(people.prefix(visible).enumerated()), id: \.element.id) { offset, person in
                CompanionAvatar(person, size: size)
                    .overlay { Circle().strokeBorder(ring ?? theme.bg, lineWidth: 2) }
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

    var body: some View {
        Group {
            if surface == .fights {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fights")
                            .ffType(.title)
                            .foregroundStyle(theme.text)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("A little further.")
                                .foregroundStyle(theme.text)
                            Text("Together.")
                                .foregroundStyle(theme.mossText)
                        }
                        .font(.custom("Nunito-ExtraBold", size: 16, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
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
                Text("Good company.")
                    .font(.custom("Nunito-ExtraBold", size: 24, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Text("A good excuse to walk.")
                    .font(.custom("Nunito-ExtraBold", size: 24, relativeTo: .title2))
                    .foregroundStyle(theme.mossText)
            } else {
                if companions.isCustom {
                    Text("Custom")
                        .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text("Your own animal.")
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
        if companions.isCustom {
            RemotePhoto(url: fitnessImages[youEffort.fitnessImageStage] ?? session.profile?.photoURL, contentMode: .fit) { Color.clear }
        } else {
            CompanionCharacter(animal: companions.selection, effort: youEffort)
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
            case .reading, .idle where model.isRefreshingFights, .empty where model.isRefreshingFights:
                if staticRender {
                    Image(systemName: "arrow.clockwise").foregroundStyle(theme.gold)
                } else {
                    ProgressView().tint(theme.gold)
                }
                Text(steps.status == .reading ? String(appLocalized: "Reading today’s steps…") : String(appLocalized: "Syncing…"))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            case .idle, .empty:
                Text("-")
                    .ffType(.metric)
                    .foregroundStyle(theme.text)
                Text(steps.isConnected ? String(appLocalized: "Today’s steps unavailable") : String(appLocalized: "Connect Apple Health"))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CompanionScene: View {
    var name = "race"

    var body: some View {
        Image("Companion-\(name)")
            .resizable()
            .scaledToFit()
            .accessibilityLabel(name == "race"
                ? String(appLocalized: "Rabbit, Turtle, Fox and Badger running together")
                : String(appLocalized: "Rabbit, Fox, Badger and Turtle playing tennis"))
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
            if CompanionPreview.isEnabled && racing.count == 4 {
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
                // There is no saved group identity/art contract yet. Keep the real roster visible.
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
    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender

    /// Artwork sits in the middle of a wide transparent canvas, so pages overlap for the neighbours to show.
    private let overlap: CGFloat = -50

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { proxy in
                let width = proxy.size.width * 0.62
                if staticRender {
                    // ImageRenderer can't draw scroll views, so screenshots lay the pages out directly.
                    let index = CGFloat(animals.firstIndex { $0 == selection } ?? 0)
                    HStack(spacing: overlap) { ForEach(animals) { page($0, width: width) } }
                        .fixedSize()
                        .offset(x: (proxy.size.width - width) / 2 - index * (width + overlap))
                        .frame(width: proxy.size.width, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: overlap) { ForEach(animals) { page($0, width: width) } }
                            .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, (proxy.size.width - width) / 2, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $selection, anchor: .center)
                    .animation(reduceMotion ? nil : .snappy, value: selection)
                    .disabled(disabled)
                }
            }
            .frame(height: 320)
            .clipped()
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

    private func page(_ animal: StockCompanion, width: CGFloat) -> some View {
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
        .frame(width: width)
        .scaleEffect(selection == animal ? 1 : 0.9)
        .accessibilityElement(children: .combine)
        .id(animal)
    }
}

struct CompanionPicker: View {
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var purchases: SpecialPurchases
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ffStaticRender) private var staticRender
    @State private var draft: StockCompanion?
    @State private var pickingCustom: Bool
    @State private var customPrompt: String
    @State private var category: CompanionCategory
    @State private var isSaving = false
    @State private var error = ""
    @State private var libraryError = ""
    @State private var loadingLibrary = false
    @State private var loadingEditions = false
    @State private var editionsError = ""
    @State private var showingGeneration = false
    @State private var showingGrid = false
    @FocusState private var promptFocused: Bool

    private let promptLimit = 1000
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
                Spacer()
                if !animals(in: category).isEmpty {
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
            Text("This is how other people see you in fights and Feed. You can change your animal anytime.")
                .font(.custom("Nunito-Bold", size: 13, relativeTo: .body))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FFSegmented(items: CompanionCategory.allCases.filter { $0 != .limited || CompanionCategory.limited.animals.contains(where: shows) },
                        selection: $category, fill: true) { $0.name }
            .disabled(isSaving)
            if category == .limited || (category == .all && draft?.isLimited == true) {
                Text("One of each. One Special per account. Buy once and keep it, even when you change companions.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                FFButton(title: String(appLocalized: "Restore purchases"), kind: .secondary, enabled: !isSaving, busy: purchases.isBusy) {
                    Task { await purchases.restore(session: session) }
                }
                if purchases.canCancelCheckout {
                    FFButton(title: String(appLocalized: "Cancel checkout"), kind: .secondary, enabled: !isSaving, busy: purchases.isBusy) {
                        Task { await purchases.cancelCheckout(session: session) }
                    }
                }
                if !purchases.message.isEmpty {
                    Text(purchases.message).ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                if purchases.snapshot?.editions.contains(where: { $0.status == .reserved }) == true {
                    Text("A purchase is in progress. Your Special is held for 30 minutes. Restore purchases to check it.")
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
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
            if !visible.isEmpty && !showingGrid {
                CompanionStage(
                    animals: visible,
                    selection: Binding(get: { pickingCustom ? nil : draft }, set: { animal in
                        guard let animal else { return }
                        promptFocused = false
                        draft = animal
                        pickingCustom = false
                        error = ""
                    }),
                    label: specialLabel,
                    disabled: isSaving || purchases.isBusy
                )
            }
            if !visible.isEmpty && showingGrid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 10)], spacing: 10) {
                    ForEach(visible) { animal in
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
                        .disabled(isSaving || purchases.isBusy || (animal.isLimited && ![.available, .reserved, .yours].contains(edition)))
                        .accessibilityAddTraits(draft == animal && !pickingCustom ? .isSelected : [])
                    }
                }
            }
            if category == .yours {
                Text("Reuse a saved description or write a new one.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if loadingLibrary {
                    ProgressView().accessibilityLabel(String(appLocalized: "Loading saved descriptions"))
                }
                if !libraryError.isEmpty {
                    Text(libraryError)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                } else if !loadingLibrary && companions.savedPrompts.isEmpty {
                    Text("Your saved descriptions will appear here.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(companions.savedPrompts, id: \.self) { prompt in
                    Button {
                        customPrompt = prompt
                        Task { await saveCustom() }
                    } label: {
                        HStack(spacing: 12) {
                            Text(prompt)
                                .ffType(.body)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: companions.isCustom && companions.customPrompt == prompt
                                  ? "checkmark.circle.fill" : "arrow.uturn.backward")
                        }
                        .foregroundStyle(theme.mossText)
                        .padding(16)
                        .frame(minHeight: 44)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card))
                        .ffBorder(theme.hairline, radius: theme.radius.card)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(isSaving)
                    .accessibilityLabel(prompt)
                    .accessibilityHint(String(appLocalized: "Use this saved description"))
                    .accessibilityAddTraits(companions.isCustom && companions.customPrompt == prompt ? .isSelected : [])
                }
            }
            if category == .yours {
                FFField(
                    label: String(appLocalized: "Your animal"),
                    state: promptFocused ? .focused : .normal,
                    help: String(appLocalized: "Write the species, breed or race, accessories, colors, and anything else that should appear."),
                    counter: "\(customPrompt.count)/\(promptLimit)",
                    minHeight: 140
                ) {
                    if staticRender {
                        Text("Species, breed, accessories, colors…")
                            .foregroundStyle(theme.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                    } else {
                        TextField(
                            String(appLocalized: "Species, breed, accessories, colors…"),
                            text: $customPrompt,
                            axis: .vertical
                        )
                        .focused($promptFocused)
                        .accessibilityLabel(String(appLocalized: "Your animal"))
                        .lineLimit(5...12)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: customPrompt) { _, value in
                            if value.count > promptLimit { customPrompt = String(value.prefix(promptLimit)) }
                        }
                    }
                }
                if !error.isEmpty {
                    Text(error)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FFButton(
                    title: String(appLocalized: "Save companion"),
                    kind: .primary,
                    enabled: canSaveCustom,
                    busy: isSaving,
                    fullWidth: true,
                    action: { Task { await saveCustom() } }
                )
                FFButton(
                    title: String(localized: "Create character"),
                    kind: .secondary,
                    enabled: !isSaving && !CompanionPreview.isEnabled,
                    fullWidth: true
                ) {
                    promptFocused = false
                    showingGeneration = true
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled {
                FFSection(title: String(appLocalized: "Artwork study")) {
                    CompanionScene(name: "tennis")
                    Text("Fixed demo cast. Artwork study only; this is not a Feed post.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            #endif
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
                    let price = purchases.products[draft.productId]?.displayPrice
                    let canBuy = purchases.canBuy(draft)
                    FFButton(
                        title: paid && !owned ? price.map { String(appLocalized: "special.buy", defaultValue: "Buy for \($0)") } ?? String(appLocalized: "Purchases unavailable") : String(appLocalized: "Save companion"),
                        enabled: (!paid || owned || canBuy) && (!draft.isLimited || [.available, .reserved, .yours].contains(status(draft))),
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
            PaidCharacterView(initialDescription: customPrompt)
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
        .task(id: session.profile?.userId) {
            loadingLibrary = true
            libraryError = ""
            defer { loadingLibrary = false }
            do {
                try await companions.loadSavedPrompts(session: session)
                if customPrompt.isEmpty { customPrompt = companions.customPrompt }
            } catch is CancellationError {
                return
            } catch {
                libraryError = String(appLocalized: "Couldn’t load your saved descriptions.")
            }
        }
        .task(id: session.profile?.userId) { await loadLimitedEditions() }
        .onChange(of: category, initial: true) { _, category in
            promptFocused = false
            error = ""
            // The stage always shows an animal, so keep the draft on one from this tab.
            let visible = animals(in: category)
            if category != .yours, !pickingCustom, let first = visible.first, draft.map(visible.contains) != true {
                draft = first
                pickingCustom = false
            }
        }
        // Writing a description means picking custom, so the pinned stock save bar steps aside.
        .onChange(of: promptFocused) { _, focused in
            if focused {
                pickingCustom = true
                draft = nil
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
        if CompanionPreview.isEnabled { return animal == CompanionCategory.limited.animals[1] ? .taken : .available }
        #endif
        return purchases.snapshot?.editions.first { $0.id == animal.rawValue }?.status
    }

    /// Yours lists the Special this account owns and the current stock companion.
    private func animals(in category: CompanionCategory) -> [StockCompanion] {
        guard category == .yours else { return category.animals.filter(shows) }
        let owned = CompanionCategory.limited.animals.filter { status($0) == .yours }
        let current = companions.hasChosen && !companions.isCustom && !owned.contains(companions.selection) ? [companions.selection] : []
        return current + owned
    }

    private func specialLabel(_ animal: StockCompanion) -> String? {
        guard animal.isLimited else { return nil }
        return switch status(animal) {
        case .yours: String(appLocalized: "Your special")
        case .reserved: String(appLocalized: "Reserved for you")
        case .available: String(appLocalized: "Available")
        default: String(appLocalized: "Taken")
        }
    }

    /// Specials stay hidden while sales are off, except one this account already owns.
    /// Specials are hidden for now; an account that already owns one still sees it.
    private func shows(_ animal: StockCompanion) -> Bool {
        !animal.isLimited || status(animal) == .yours
    }

    private var canSaveCustom: Bool {
        !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveStock(_ animal: StockCompanion) async {
        error = ""
        pickingCustom = false
        draft = animal
        isSaving = true
        defer { isSaving = false }
        do {
            if animal.isLimited && !CompanionPreview.isEnabled,
               purchases.snapshot?.editions.first(where: { $0.id == animal.rawValue })?.status != .yours {
                guard await purchases.buy(animal, session: session) else {
                    self.error = purchases.message
                    await loadLimitedEditions()
                    return
                }
            }
            try await companions.choose(id: animal.rawValue, prompt: nil, session: session)
            companions.showingPicker = false
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            if animal.isLimited { await loadLimitedEditions() }
        }
    }

    private func saveCustom() async {
        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        error = ""
        pickingCustom = true
        draft = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await companions.choose(id: CompanionStore.customId, prompt: prompt, session: session)
            companions.showingPicker = false
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = String(appLocalized: "Couldn’t save your companion. Try again.")
        }
    }
}
