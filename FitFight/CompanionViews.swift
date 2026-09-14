import SwiftUI

enum StockCompanion: String, CaseIterable, Identifiable {
    case badger, raccoon, redPanda = "red-panda", otter, rabbit, fox, bear, boar, sloth, dog, goat, turtle

    var id: String { rawValue }
    var image: String { "Companion-\(rawValue)" }

    var name: String {
        switch self {
        case .badger: String(localized: "Badger")
        case .raccoon: String(localized: "Raccoon")
        case .redPanda: String(localized: "Red Panda")
        case .otter: String(localized: "Otter")
        case .rabbit: String(localized: "Rabbit")
        case .fox: String(localized: "Fox")
        case .bear: String(localized: "Bear")
        case .boar: String(localized: "Boar")
        case .sloth: String(localized: "Sloth")
        case .dog: String(localized: "Dog")
        case .goat: String(localized: "Goat")
        case .turtle: String(localized: "Turtle")
        }
    }

    var caption: String {
        switch self {
        case .badger: String(localized: "Quietly competitive.")
        case .raccoon: String(localized: "Always has a plan.")
        case .redPanda: String(localized: "Looks relaxed. Isn’t.")
        case .otter: String(localized: "Here for a good time.")
        case .rabbit: String(localized: "Always one more lap.")
        case .fox: String(localized: "Just a little smug.")
        case .bear: String(localized: "Big strides. Soft heart.")
        case .boar: String(localized: "A little unstoppable.")
        case .sloth: String(localized: "Slow is still forward.")
        case .dog: String(localized: "Always up for a walk.")
        case .goat: String(localized: "Takes the uphill route.")
        case .turtle: String(localized: "Never out of the race.")
        }
    }
}

/// Account-backed stock companion. Preview keeps a local choice.
@MainActor
final class CompanionStore: ObservableObject {
    @Published var selection: StockCompanion = .badger
    @Published private(set) var hasChosen = false
    @Published var showingPicker = false

    private static let pendingPrefix = "ff.companion.pending."

    static func hasPendingChoice(for userId: UUID?) -> Bool {
        guard let userId else { return false }
        return UserDefaults.standard.string(forKey: pendingPrefix + userId.uuidString) != nil
    }

    func apply(_ profile: FitFightProfile?) {
        guard !CompanionPreview.isEnabled else { return }
        if let id = profile?.companionId, let animal = StockCompanion(rawValue: id) {
            selection = animal
            hasChosen = true
            if let userId = profile?.userId,
               UserDefaults.standard.string(forKey: Self.pendingPrefix + userId.uuidString) == id {
                UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userId.uuidString)
            }
        } else if let userId = profile?.userId,
                  let pending = UserDefaults.standard.string(forKey: Self.pendingPrefix + userId.uuidString),
                  let animal = StockCompanion(rawValue: pending) {
            selection = animal
            hasChosen = true
        } else {
            hasChosen = false
            if profile == nil {
                selection = .badger
                showingPicker = false
            }
        }
    }

    func choose(_ animal: StockCompanion, session: SessionStore) async throws {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            selection = animal
            hasChosen = true
            showingPicker = false
            return
        }
        #endif
        selection = animal
        hasChosen = true
        showingPicker = false
        if let userId = session.profile?.userId {
            UserDefaults.standard.set(animal.rawValue, forKey: Self.pendingPrefix + userId.uuidString)
        }
        do {
            try await session.setCompanion(animal)
            if let userId = session.profile?.userId {
                UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userId.uuidString)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Keep the local pick so the app stays usable if the save is offline.
        }
    }

    func publishPending(session: SessionStore) async {
        guard let userId = session.profile?.userId,
              let pending = UserDefaults.standard.string(forKey: Self.pendingPrefix + userId.uuidString),
              let animal = StockCompanion(rawValue: pending) else { return }
        if session.profile?.companionId == pending {
            UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userId.uuidString)
            return
        }
        do {
            try await session.setCompanion(animal)
            UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userId.uuidString)
        } catch {
            return
        }
    }

    func animal(for personID: String?, companionID: String? = nil, isYou: Bool = false) -> StockCompanion? {
        if isYou && hasChosen { return selection }
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
}

struct CompanionCharacter: View {
    let animal: StockCompanion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ffStaticRender) private var staticRender
    @State private var greeting = false

    var body: some View {
        Button {
            guard !reduceMotion, !staticRender, !greeting else { return }
            withAnimation(.easeInOut(duration: 0.18)) { greeting = true }
        } label: {
            Image(animal.image)
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(greeting ? -3 : 0), anchor: .bottom)
                .scaleEffect(greeting ? 1.025 : 1, anchor: .bottom)
                .padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "companion.greet", defaultValue: "Say hello to \(animal.name)"))
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
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ffStaticRender) private var staticRender

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
                    CompanionCharacter(animal: companions.selection)
                        .frame(width: typeSize.isAccessibilitySize ? 96 : 142, height: 156)
                        .accessibilitySortPriority(-1)
                }
            } else if typeSize > .large {
                VStack(alignment: .leading, spacing: 12) {
                    copy
                    CompanionCharacter(animal: companions.selection)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        CompanionCharacter(animal: companions.selection)
                            .frame(width: proxy.size.width * 0.53, height: height - 24)
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
    }

    private var height: CGFloat {
        switch surface {
        case .fights: 156
        case .newFight: 210
        case .you: 190
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
                Text(companions.selection.name)
                    .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Text(companions.selection.caption)
                    .font(.custom("Nunito-Bold", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.textSecondary)
                Button(String(localized: "Try another companion")) {
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
            case .reading:
                if staticRender {
                    Image(systemName: "arrow.clockwise").foregroundStyle(theme.gold)
                } else {
                    ProgressView().tint(theme.gold)
                }
                Text("Reading today’s steps…")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            case .idle, .empty:
                Text("-")
                    .ffType(.metric)
                    .foregroundStyle(theme.text)
                Text(steps.isConnected ? String(localized: "Today’s steps unavailable") : String(localized: "Connect Apple Health"))
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
                ? String(localized: "Rabbit, Turtle, Fox and Badger running together")
                : String(localized: "Rabbit, Fox, Badger and Turtle playing tennis"))
    }
}

struct CompanionFightSummary: View {
    let fight: Fight
    @EnvironmentObject private var companions: CompanionStore
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
                        CompanionCharacter(animal: companions.selection)
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
                Text(fight.isUpcoming ? String(localized: "Scheduled") : fight.isTiedForFirst && mine?.rank == 1 ? String(localized: "Tied") : fight.status == .finished
                     ? String(localized: "fight.finished-rank", defaultValue: "Finished #\(fight.rank)")
                     : String(localized: "fight.rank-of-count", defaultValue: "#\(fight.rank) of \(racing.count)"))
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
                    Text(String(localized: "companion.fight-total", defaultValue: "Your steps · \(fight.durationLabel)"))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let gap {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                        Text(gap == 0 ? String(localized: "Tied")
                             : "\(gap > 0 ? "+" : "−")\(abs(gap).formatted(.number.precision(.fractionLength(0))))")
                            .font(.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2))
                            .monospacedDigit()
                        if gap != 0 {
                            Text(gap > 0 ? String(localized: "steps ahead") : String(localized: "steps behind"))
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

struct CompanionPicker: View {
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: StockCompanion?
    @State private var isSaving = false
    @State private var error = ""
    var required: Bool

    init(selection: StockCompanion, required: Bool = false) {
        self.required = required
        _draft = State(initialValue: required ? nil : selection)
    }

    var body: some View {
        FFScreen(clearance: false) {
            HStack(alignment: .top) {
                Text("Choose your companion")
                    .font(.custom("Nunito-ExtraBold", size: 26, relativeTo: .title))
                    .foregroundStyle(theme.text)
                Spacer()
                if !required {
                    Button(String(localized: "Close")) { dismiss() }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                        .frame(minHeight: 44)
                }
            }
            Text("This is how other people see you in fights and Feed.")
                .font(.custom("Nunito-Bold", size: 13, relativeTo: .body))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 10)], spacing: 10) {
                ForEach(StockCompanion.allCases) { animal in
                    Button {
                        Task { await save(animal) }
                    } label: {
                        VStack(spacing: 3) {
                            Image(animal.image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 104)
                            Text(animal.name)
                                .font(.custom("Nunito-ExtraBold", size: 12, relativeTo: .caption))
                                .foregroundStyle(draft == animal ? theme.mossText : theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(draft == animal ? theme.mossWash : theme.card,
                                    in: RoundedRectangle(cornerRadius: theme.radius.card))
                        .ffBorder(draft == animal ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(isSaving)
                    .accessibilityAddTraits(draft == animal ? .isSelected : [])
                }
            }
            if let draft {
                Text(isSaving ? String(localized: "Saving…") : draft.caption)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled {
                FFSection(title: String(localized: "Artwork study")) {
                    CompanionScene(name: "tennis")
                    Text("Fixed demo cast. Artwork study only; this is not a Feed post.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            #endif
        }
        .interactiveDismissDisabled(required)
    }

    private func save(_ animal: StockCompanion) async {
        error = ""
        draft = animal
        isSaving = true
        defer { isSaving = false }
        do {
            try await companions.choose(animal, session: session)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = String(localized: "Couldn’t save your companion. Try again.")
        }
    }
}
