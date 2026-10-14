import SwiftUI

struct PaidCharacterView: View {
    let initialDescription: String
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var purchases: CustomCharacterPurchases
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var library: [FitFightAILibraryEntry] = []
    @State private var isSelecting = false
    @State private var picked: [UUID: UUID] = [:]
    @State private var choosingID: UUID?
    @State private var error = ""

    /// The server keeps drawing without the app; polling only makes progress visible sooner while open.
    private var pollingID: UUID? {
        purchases.inProgress.first(where: { $0.phase == .portraits || $0.phase == .poses })?.id
    }

    var body: some View {
        FFScreen(clearance: false) {
            HStack {
                Text("Create your companion").ffType(.title).foregroundStyle(theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "Close"))
                .foregroundStyle(theme.textSecondary)
            }
            Text(String(appLocalized: "Each character draws three portraits. Pick your favourite, then we create five fitness images from it that change with your daily Steps."))
                .ffType(.body).foregroundStyle(theme.textSecondary)
            if purchases.freeCharacters > 0 {
                FreeCharacterBadge(count: purchases.freeCharacters)
            }

            ForEach(purchases.inProgress) { active in
                FFSection(title: String(localized: "Your character")) {
                    Text(active.description ?? description).ffType(.body).foregroundStyle(theme.text)
                    steps(active)
                    progress(active)
                }
            }
            CharacterIdeas(description: $description, disabled: purchases.isBusy)
            FFField(label: String(localized: "Your animal"), counter: "\(description.count)/1000", minHeight: 120) {
                TextField(String(localized: "Species, breed, accessories, colors…"), text: $description, axis: .vertical)
                    .lineLimit(4...8)
                    .onChange(of: description) { _, text in description = String(text.prefix(1000)) }
            }
            if let ready = purchases.snapshot?.characters.first(where: { $0.status == .ready }) {
                FFButton(title: String(localized: "Create character"), kind: .primary,
                         enabled: !purchases.isBusy && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         busy: purchases.isBusy, fullWidth: true) {
                    Task { await start(ready) }
                }
            } else if purchases.freeCharacters > 0 {
                FFButton(title: String(appLocalized: "Create for free"), kind: .primary,
                         enabled: !purchases.isBusy && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         busy: purchases.isBusy, fullWidth: true) {
                    Task { await createFree() }
                }
            } else {
                let title = purchases.pendingPurchase
                    ? String(appLocalized: "Purchase pending")
                    // The preview has no StoreKit, but it still shows the label a buyer sees.
                    : (purchases.product?.displayPrice ?? (CompanionPreview.isEnabled ? "€2.99" : nil))
                        .map { String(appLocalized: "character.buy", defaultValue: "Create for \($0)") }
                        ?? String(appLocalized: "Purchases unavailable")
                FFButton(title: title, kind: .primary,
                         enabled: (purchases.product != nil || CompanionPreview.isEnabled) && !purchases.pendingPurchase && !purchases.isBusy && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         busy: purchases.isBusy, fullWidth: true) {
                    Task { await purchases.buy(description: description, session: session) }
                }
            }

            FFButton(title: String(localized: "Restore purchases"), kind: .ghost,
                     enabled: !purchases.isBusy, busy: purchases.isBusy, fullWidth: true) {
                Task {
                    await purchases.restore(session: session)
                    await loadLibrary()
                }
            }
            if !purchases.message.isEmpty && !CompanionPreview.isEnabled {
                Text(purchases.message).ffType(.caption).foregroundStyle(theme.textSecondary)
            }
            if !error.isEmpty {
                Text(error).ffType(.caption).foregroundStyle(theme.emberText)
            }

            let completed = purchases.snapshot?.characters.filter { $0.status == .complete } ?? []
            if !completed.isEmpty {
                FFSection(title: String(localized: "Your characters")) {
                    ForEach(completed) { character in
                        if let entry = library.first(where: { $0.requestID == character.requestID && $0.workflow == .fitness }),
                           let resting = entry.images.first(where: { $0.stage == "resting" }) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(character.description ?? entry.description).ffType(.body).foregroundStyle(theme.text)
                                RemotePhoto(url: resting.url, contentMode: .fit) { theme.control }
                                    .frame(height: 220)
                                HStack(spacing: 6) {
                                    ForEach(entry.images) { image in
                                        RemotePhoto(url: image.url, contentMode: .fit) { theme.control }
                                            .frame(maxWidth: .infinity).frame(height: 64)
                                            .accessibilityLabel(image.stage)
                                    }
                                }
                                FFButton(title: String(localized: "Use as companion"), kind: .secondary,
                                         enabled: !isSelecting, busy: isSelecting, fullWidth: true) {
                                    Task { await select(entry) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if description.isEmpty { description = initialDescription }
            do { try await purchases.refresh(session: session) }
            catch { self.error = error.localizedDescription }
            purchases.markReadySeen()
            await loadLibrary()
        }
        .task(id: pollingID) {
            guard let id = pollingID else { return }
            while !Task.isCancelled {
                do {
                    let progress = try await purchases.advance(id, session: session)
                    if progress.phase != .portraits && progress.phase != .poses {
                        // The finished snapshot clears pollingID, which cancels this task; finish outside it.
                        Task {
                            await loadLibrary()
                            purchases.markReadySeen()
                            if progress.status == .complete,
                               let entry = library.first(where: { $0.requestID == progress.requestID && $0.workflow == .fitness }) {
                                await select(entry)
                            }
                        }
                        return
                    }
                    try await Task.sleep(for: .seconds(max(3, progress.pollAfterSeconds ?? 3)))
                } catch is CancellationError { return }
                catch {
                    self.error = error.localizedDescription
                    return
                }
            }
        }
    }

    /// Portraits, choice, poses: the three steps every new character goes through.
    private func steps(_ character: CustomCharacterProgress) -> some View {
        let current: Int = switch character.phase {
        case .ready, .portraits: 0
        case .choosing: 1
        case .poses: 2
        case .complete: 3
        case .retryable, .needsSupport, .refunded: character.stage == .fitness ? 2 : 0
        }
        let titles = [String(localized: "Portraits"), String(localized: "Choose"), String(localized: "Poses")]
        return HStack(spacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 6) {
                    Image(systemName: index < current ? "checkmark.circle.fill" : index == current ? "circle.dotted" : "circle")
                        .foregroundStyle(index < current ? theme.mossText : index == current ? theme.gold : theme.textTertiary)
                    Text(title).ffType(.caption)
                        .foregroundStyle(index <= current ? theme.text : theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func progress(_ active: CustomCharacterProgress) -> some View {
        let selection = picked[active.id]
        switch active.phase {
        case .portraits where active.candidates.isEmpty:
            ProgressView().tint(theme.gold)
            Text("Creating your portrait…").ffType(.caption).foregroundStyle(theme.textSecondary)
            closeHint
        case .portraits, .choosing:
            HStack(spacing: 8) {
                ForEach(active.candidates) { candidate in
                    candidateTile(candidate, picked: selection == candidate.id) {
                        picked[active.id] = candidate.id
                    }
                }
            }
            if active.phase == .portraits {
                Text("Drawing three portraits. This takes about a minute.")
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                closeHint
            } else {
                Text("Pick your favourite. The other portraits stay saved in your account.")
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
            }
            if active.candidates.contains(where: { $0.status == .completed }) {
                FFButton(title: String(localized: "Use this portrait"), kind: .primary,
                         enabled: selection != nil && choosingID == nil, busy: choosingID == active.id, fullWidth: true) {
                    if let selection { Task { await choose(active, candidate: selection) } }
                }
            }
            if active.phase == .choosing, active.candidates.contains(where: { $0.status == .failed }) {
                FFButton(title: String(localized: "Redraw the failed portraits"), kind: .ghost,
                         enabled: !purchases.isBusy, busy: purchases.isBusy, fullWidth: true) {
                    Task { await retry(active) }
                }
            }
        case .poses:
            if let portrait = active.portraitURL {
                RemotePhoto(url: portrait, contentMode: .fit) { theme.control }
                    .frame(height: 160)
            }
            ProgressView().tint(theme.gold)
            Text("Creating five fitness images…").ffType(.caption).foregroundStyle(theme.textSecondary)
            closeHint
        case .retryable:
            Text("The images could not be completed. Retry this character without another purchase.")
                .ffType(.caption).foregroundStyle(theme.emberText)
            FFButton(title: String(localized: "Try again"), kind: .secondary, enabled: !purchases.isBusy, busy: purchases.isBusy, fullWidth: true) {
                Task { await retry(active) }
            }
        case .needsSupport:
            Text("We could not confirm whether this drawing started. Contact support and we will finish your character at no cost.")
                .ffType(.caption).foregroundStyle(theme.emberText)
            Link(destination: supportURL) {
                Text("Contact support").ffType(.button).foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(theme.control, in: Capsule())
                    .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }
        case .ready, .complete, .refunded:
            EmptyView()
        }
    }

    private var closeHint: some View {
        Text("You can close the app. We will send a notification when your character is ready.")
            .ffType(.caption).foregroundStyle(theme.textSecondary)
    }

    private var supportURL: URL {
        let site = URL(string: AppVersion.backend == "prod" ? "https://fitfight.app" : "https://staging.fitfight.app")!
        return (AppLocalization.languageCode == "fr" ? site.appending(path: "fr") : site).appending(path: "support")
    }

    private func candidateTile(_ candidate: CustomCharacterProgress.Candidate, picked: Bool, onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            ZStack {
                theme.control
                switch candidate.status {
                case .completed:
                    RemotePhoto(url: candidate.imageURL, contentMode: .fill) { theme.control }
                case .pending:
                    ProgressView().tint(theme.gold)
                case .failed, .needsSupport:
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.emberText)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                    .strokeBorder(picked ? theme.mossText : theme.hairline, lineWidth: picked ? 3 : 1)
            }
        }
        .buttonStyle(FFHapticPlainStyle())
        .disabled(candidate.status != .completed)
        .accessibilityLabel(String(appLocalized: "character.portrait", defaultValue: "Portrait \(candidate.slot)"))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func loadLibrary() async {
        do { library = try await FitFightAPI().aiLibrary(accessToken: try await session.freshAccessToken()) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func start(_ character: CustomCharacterProgress) async {
        do { _ = try await purchases.advance(character.id, description: description.trimmingCharacters(in: .whitespacesAndNewlines), session: session) }
        catch { self.error = error.localizedDescription }
    }

    private func createFree() async {
        error = ""
        do {
            try await purchases.claimFree(description: description, session: session)
            description = ""
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func retry(_ character: CustomCharacterProgress) async {
        do { _ = try await purchases.advance(character.id, retry: true, session: session) }
        catch { self.error = error.localizedDescription }
    }

    private func choose(_ character: CustomCharacterProgress, candidate: UUID) async {
        choosingID = character.id
        defer { choosingID = nil }
        do { _ = try await purchases.choose(character.id, candidate: candidate, session: session) }
        catch { self.error = error.localizedDescription }
    }

    private func select(_ entry: FitFightAILibraryEntry) async {
        guard !isSelecting else { return }
        isSelecting = true
        defer { isSelecting = false }
        do {
            try await session.setCompanion(image: .init(requestID: entry.requestID, stage: "resting"))
            companions.apply(session.profile)
        } catch { self.error = error.localizedDescription }
    }
}

/// "1 free": the characters this person can still create without paying.
struct FreeCharacterBadge: View {
    let count: Int
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Label(String(appLocalized: "character.free-count", defaultValue: "\(count) free"), systemImage: "gift")
            .ffType(.label)
            .foregroundStyle(theme.mossText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.mossWash, in: Capsule())
    }
}

/// Real descriptions next to the portrait the same drawing made from them, so people see what their words give.
/// The four portraits are unused runs of the Specials work (11 Oct 2026) on the pinned Animal Avatars workflow.
struct CharacterIdeas: View {
    @Binding var description: String
    var disabled = false
    @Environment(\.ffTheme) private var theme

    private var ideas: [(image: String, text: String)] {
        [
            ("CharacterIdea-pigeon", String(appLocalized: "character.idea.pigeon", defaultValue: "A plump grey city pigeon with an iridescent green-purple neck and orange eyes, wings used as arms. Nothing held in the hands or wings, no headband. One worn signature detail only: a small fanny pack worn across the chest. Strutting, nosy, weirdly confident.")),
            ("CharacterIdea-opossum", String(appLocalized: "character.idea.opossum", defaultValue: "A small scruffy grey opossum with a white face, pink nose and a bare pink tail. Nothing held in the hands or wings, no headband. One worn signature detail only: a tiny propeller beanie hat. Wide-eyed, slightly panicked, trying his best.")),
            ("CharacterIdea-seagull", String(appLocalized: "character.idea.seagull", defaultValue: "A scrappy white and grey seagull with a yellow beak, wings used as arms. Nothing held in the hands or wings, no headband. One worn signature detail only: small dark sunglasses. Shifty, opportunistic, totally guilty.")),
            ("CharacterIdea-mole", String(appLocalized: "character.idea.mole", defaultValue: "A small velvety dark grey mole with a pink star-like nose and big pink digging paws. Nothing held in the hands or wings, no headband. One worn signature detail only: tiny thick round glasses. Squinting, determined, a bit lost.")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(appLocalized: "Ideas")).ffType(.label).foregroundStyle(theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(ideas.enumerated()), id: \.offset) { _, idea in
                        let picked = description == idea.text
                        Button {
                            description = idea.text
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(idea.image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 120)
                                    .accessibilityHidden(true)
                                Text(idea.text)
                                    .ffType(.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(8)
                            .frame(width: 150, alignment: .top)
                            .background(picked ? theme.mossWash : theme.card,
                                        in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            .ffBorder(picked ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(disabled)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
            Text(String(appLocalized: "Real portraits drawn from these words. Tap one to start from it."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        }
    }
}

/// A Fights card for a paid character that is being drawn, waits for a portrait choice, or is ready.
/// It shows nothing when there is no such character, and opens the character screen when tapped.
struct PaidCharacterProgressCard: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var purchases: CustomCharacterPurchases
    @Environment(\.ffTheme) private var theme
    @State private var showing = false

    var body: some View {
        // The container stays when the card hides, so an open sheet is not dismissed with it.
        VStack(spacing: 0) {
            if let character = purchases.inProgress.first ?? purchases.unseenReady.first {
                Button { showing = true } label: {
                    FFCard {
                        HStack(spacing: 13) {
                            ZStack {
                                theme.control
                                if let url = character.portraitURL ?? character.candidateURLs.first {
                                    RemotePhoto(url: url, contentMode: .fill) { theme.control }
                                } else {
                                    ProgressView().tint(theme.gold)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(character)).ffType(.heading).foregroundStyle(theme.text)
                                Text(subtitle(character)).ffType(.caption).foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .sheet(isPresented: $showing) {
            PaidCharacterView(initialDescription: "")
        }
        .task {
            // The server advances on its own; this only keeps the card current while it is on screen.
            while !Task.isCancelled {
                try? await purchases.refresh(session: session)
                guard purchases.inProgress.contains(where: { $0.phase == .portraits || $0.phase == .poses }) else { return }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func title(_ character: CustomCharacterProgress) -> String {
        switch character.phase {
        case .choosing: String(localized: "Pick your favourite")
        case .complete: String(localized: "Your character is ready")
        case .retryable, .needsSupport: String(localized: "Your character needs attention")
        default: String(localized: "Your character is being drawn")
        }
    }

    private func subtitle(_ character: CustomCharacterProgress) -> String {
        switch character.phase {
        case .choosing: String(localized: "Three portraits are ready.")
        case .complete: String(localized: "Make it your companion.")
        case .poses: String(localized: "Creating five fitness images.")
        case .retryable: String(localized: "Try again at no cost.")
        case .needsSupport: String(localized: "Contact support.")
        default: String(localized: "Three portraits are on the way.")
        }
    }
}
