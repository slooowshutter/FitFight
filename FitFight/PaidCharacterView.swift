import SwiftUI

/// "New companion": one character, one step per screen. Describe it, pick from the AI's rewrites, pay, pick a
/// portrait, then name it while the poses are drawn. Each step has one main button at the bottom.
struct PaidCharacterView: View {
    let initialDescription: String
    /// Opens on this character: a tile tapped on Yours, a push, or a finished character being renamed.
    var characterID: UUID? = nil
    /// Opened from "Create your own": characters that already exist stay out of the way.
    var startNew = false
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var companions: CompanionStore
    @EnvironmentObject private var purchases: CustomCharacterPurchases
    @EnvironmentObject private var push: PushNotificationService
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    /// The words to pick from after "Next": the owner's own first, then the AI's rewrites.
    @State private var options: [String]?
    @State private var note: String?
    @State private var chosen = 0
    /// The words being checked by the AI. Clearing it stops waiting for the answer.
    @State private var checkText: String?
    @State private var checking = false
    @State private var checkFailed = false
    @State private var restoring = false
    @State private var focusID: UUID?
    /// Characters that existed before "Create your own" or "Create another".
    @State private var ignored: Set<UUID> = []
    /// A character that finished while this screen was open, or was ready and unseen when it opened.
    @State private var finishedID: UUID?
    @State private var library: [FitFightAILibraryEntry] = []
    @State private var isSelecting = false
    @State private var picked: [UUID: UUID] = [:]
    @State private var choosingID: UUID?
    @State private var error = ""
    /// Typed names and lines, kept here so a draft survives the character moving from poses to finished.
    @State private var labelDrafts: [UUID: CompanionLabelEditor.Draft] = [:]
    @State private var playingSnake = false
    /// The last record the server sent, so the board shows it before the next answer.
    @AppStorage("ff.snake.record") private var snakeRecord = 0

    init(initialDescription: String, characterID: UUID? = nil, startNew: Bool = false) {
        self.initialDescription = initialDescription
        self.characterID = characterID
        self.startNew = startNew
        _description = State(initialValue: initialDescription)
        _focusID = State(initialValue: characterID)
    }

    private enum Step { case describe, review, portraits, choosing, poses, done, problem }

    private var focused: CustomCharacterProgress? {
        let characters = purchases.snapshot?.characters ?? []
        if let focusID, let character = characters.first(where: { $0.id == focusID }),
           character.phase != .ready, character.phase != .refunded {
            return character
        }
        return purchases.inProgress.first { !ignored.contains($0.id) } ?? characters.first { $0.id == finishedID }
    }

    private var step: Step {
        guard let focused else { return options == nil ? .describe : .review }
        return switch focused.phase {
        case .portraits: .portraits
        case .choosing: .choosing
        case .poses: .poses
        case .complete: .done
        case .ready, .retryable, .needsSupport, .refunded: .problem
        }
    }

    /// The server keeps drawing without the app; polling only makes progress visible sooner while open.
    private var pollingID: UUID? {
        guard let focused, focused.phase == .portraits || focused.phase == .poses else { return nil }
        return focused.id
    }

    var body: some View {
        let step = step
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // The header stays put, so Close is always in reach while the parts scroll.
                FFSheetHeader(title: String(appLocalized: "New companion")) { dismiss() }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        part(0, String(appLocalized: "Describe your animal"), later: "",
                             summary: "“\(options?.first ?? (description.isEmpty ? focused?.description ?? "" : description))”") {
                            describe
                        }
                        part(1, String(appLocalized: "Pick from our suggestions"),
                             later: String(appLocalized: "After you write, we suggest richer versions."),
                             summary: "“\(focused?.description ?? options?[chosen] ?? "")”") {
                            review
                        }
                        part(2, String(appLocalized: "Pick a portrait"), later: String(appLocalized: "Drawn after you pay. About a minute."),
                             summary: String(appLocalized: "Portrait chosen"), thumbnail: focused?.portraitURL) {
                            if let focused {
                                switch step {
                                case .choosing: choosing(focused)
                                case .problem: problem(focused)
                                default: portraits(focused)
                                }
                            }
                        }
                        part(3, String(appLocalized: "Name it"), later: String(appLocalized: "Five fitness poses, then a name."), summary: nil) {
                            if let focused {
                                switch step {
                                case .done: done(focused)
                                case .problem: problem(focused)
                                default: poses(focused)
                                }
                            }
                        }
                        if !error.isEmpty {
                            Text(error).ffType(.caption).foregroundStyle(theme.emberText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                }
                .scrollDisabled(playingSnake)
                // A down swipe in Snake must steer, not close the sheet.
                .interactiveDismissDisabled(playingSnake)
                // Scrolling stops during a game, so the whole board must be on screen first, even on a small iPhone.
                .onChange(of: playingSnake) { _, playing in
                    if playing { withAnimation(theme.motion.quick.animation) { proxy.scrollTo("snake", anchor: .bottom) } }
                }
                // The open part is always in view, finished parts fold above it.
                .onChange(of: currentPart, initial: true) { _, part in
                    withAnimation(theme.motion.quick.animation) { proxy.scrollTo("part-\(part)", anchor: .top) }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) { bottomBar(step) }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(theme.bg)
        }
        .animation(theme.motion.quick.animation, value: step)
        .onChange(of: step) { _, step in
            error = ""
            // Editing or paying stops waiting; the run itself finishes on the server either way.
            if step != .review { checkText = nil }
        }
        .task(id: checkText) {
            guard let checkText else { return }
            await check(checkText)
        }
        .onAppear {
            // Before the first frame, so a new character never flashes an older one.
            if startNew {
                ignored = Set(purchases.snapshot?.characters.map(\.id) ?? [])
            } else if let characterID {
                // A tapped character stays on screen even when another one is being drawn.
                ignored = Set(purchases.snapshot?.characters.map(\.id) ?? []).subtracting([characterID])
            } else {
                finishedID = purchases.unseenReady.first?.id
            }
        }
        .task {
            await push.refreshAuthorizationStatus()
            #if DEBUG && targetEnvironment(simulator)
            if let state = CompanionPreview.characterState {
                if ["describe", "checking", "review"].contains(state) { description = "A cowboy pig" }
                if state == "checking" || state == "review" { startCheck(description) }
            }
            #endif
            guard !CompanionPreview.isEnabled else { return }
            do { try await purchases.refresh(session: session) }
            catch { self.error = error.localizedDescription }
            if startNew {
                ignored.formUnion(purchases.snapshot?.characters.map(\.id) ?? [])
            } else if let characterID {
                ignored.formUnion(Set(purchases.snapshot?.characters.map(\.id) ?? []).subtracting([characterID]))
            } else if finishedID == nil {
                finishedID = purchases.unseenReady.first?.id
            }
            // A new character leaves the Fights card of a finished one for when its owner sees it.
            if !startNew { purchases.markReadySeen() }
            await loadLibrary()
        }
        .task {
            guard !CompanionPreview.isEnabled,
                  let saved = try? await FitFightAPI().snakeRecord(accessToken: try await session.freshAccessToken()) else { return }
            snakeRecord = saved.record
        }
        .task(id: pollingID) {
            guard let id = pollingID else { return }
            while !Task.isCancelled {
                do {
                    let progress = try await purchases.advance(id, session: session)
                    if progress.phase != .portraits && progress.phase != .poses {
                        // The finished snapshot clears pollingID, which cancels this task; finish outside it.
                        finishedID = progress.id
                        focusID = progress.id
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

    /// Describe, words, portrait, name: the part of the page that is open now.
    private var currentPart: Int {
        switch step {
        case .describe: 0
        case .review: 1
        case .portraits, .choosing: 2
        // A failed pose run has a chosen portrait; a failed portrait run does not.
        case .problem: focused?.portraitURL == nil ? 2 : 3
        case .poses, .done: 3
        }
    }

    /// One part of the page: open now, finished (folded to one line), or still to come (dashed).
    @ViewBuilder
    private func part<Content: View>(_ index: Int, _ title: String, later: String, summary: String?,
                                     thumbnail: URL? = nil, @ViewBuilder content: () -> Content) -> some View {
        let current = currentPart
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(index < current ? theme.mossFill : theme.control)
                    if index < current {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.mossOn)
                    } else {
                        Text(verbatim: "\(index + 1)").ffType(.label).foregroundStyle(index == current ? theme.text : theme.textSecondary)
                    }
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).ffType(.rowTitle).foregroundStyle(index > current ? theme.textSecondary : theme.text)
                    if index > current, !later.isEmpty {
                        Text(later).ffType(.caption).foregroundStyle(theme.textSecondary)
                    } else if index < current, let summary {
                        Text(verbatim: summary).ffType(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if index < current, let thumbnail {
                    RemotePhoto(url: thumbnail, contentMode: .fit) { Color.clear }
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            if index == current { content() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index > current ? Color.clear : theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(index > current ? theme.line : theme.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: index > current ? [4, 4] : []))
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .id("part-\(index)")
    }

    // MARK: Parts

    @ViewBuilder private var describe: some View {
        if purchases.freeCharacters > 0 {
            FreeCharacterBadge(count: purchases.freeCharacters)
        }
        FFField(label: "", counter: "\(description.count)/1000", minHeight: 88) {
            TextField(String(appLocalized: "Species, breed, accessories, colors…"), text: $description, axis: .vertical)
                .lineLimit(4...8)
                .onChange(of: description) { _, text in description = String(text.prefix(1000)) }
        }
        CharacterIdeas(description: $description)
        purchaseMessage
    }

    @ViewBuilder private var review: some View {
        if checking {
            FFCard {
                HStack(spacing: 12) {
                    ProgressView().tint(theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(appLocalized: "Reading your idea")).ffType(.heading).foregroundStyle(theme.text)
                        Text(String(appLocalized: "Better versions show up here in about a minute. You can also create it now with your words."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if let note {
            FFNotice(text: note, tone: .neutral, systemImage: "sparkles")
        } else if checkFailed {
            Text(String(appLocalized: "We could not check your idea. You can still create it as you wrote it."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(Array((options ?? []).enumerated()), id: \.offset) { index, text in
            let selected = chosen == index
            Button { chosen = index } label: {
                FFCard(fill: selected ? theme.mossWash : nil, stroke: selected ? theme.mossEdge : nil) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(index == 0 ? String(appLocalized: "Your words")
                                 : String(appLocalized: "character.idea-number", defaultValue: "Idea \(index)"))
                                .ffType(.micro).foregroundStyle(selected ? theme.mossText : theme.textTertiary)
                            Text(verbatim: text).ffType(.body).foregroundStyle(theme.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? theme.mossText : theme.textTertiary)
                    }
                }
            }
            .buttonStyle(FFHapticPlainStyle())
            .disabled(purchases.isBusy)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        // Words can change until paying; portraits are never redone.
        if !purchases.isBusy {
            Button(String(appLocalized: "Change my words")) {
                description = options?[chosen] ?? description
                options = nil
                note = nil
                error = ""
            }
            .ffType(.label).foregroundStyle(theme.mossText)
            .frame(minHeight: 44)
            .buttonStyle(FFHapticPlainStyle())
        }
        purchaseMessage
    }

    private func portraits(_ character: CustomCharacterProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { slot in
                    let candidate = character.candidates.first { $0.slot == slot + 1 }
                    portraitTile(candidate?.status == .completed ? candidate?.imageURL : nil,
                                 failed: candidate?.status == .failed || candidate?.status == .needsSupport, picked: false)
                }
            }
            Text(String(appLocalized: "Drawing three portraits. This takes about a minute."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
            snake
        }
    }

    private func choosing(_ character: CustomCharacterProgress) -> some View {
        let selection = picked[character.id] ?? character.candidates.first { $0.status == .completed }?.id
        let selected = character.candidates.first { $0.id == selection }
        return VStack(alignment: .leading, spacing: 16) {
            RemotePhoto(url: selected?.imageURL, contentMode: .fit) { theme.control }
                .frame(maxWidth: .infinity).frame(height: 260)
            HStack(spacing: 8) {
                ForEach(character.candidates) { candidate in
                    Button { picked[character.id] = candidate.id } label: {
                        portraitTile(candidate.imageURL, failed: candidate.status != .completed, picked: selection == candidate.id)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(candidate.status != .completed)
                    .accessibilityLabel(String(appLocalized: "character.portrait", defaultValue: "Portrait \(candidate.slot)"))
                    .accessibilityAddTraits(selection == candidate.id ? .isSelected : [])
                }
            }
            Text(String(appLocalized: "Pick your favourite. The other portraits stay saved in your account."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
            if character.candidates.contains(where: { $0.status == .failed }) {
                FFButton(title: String(appLocalized: "Redraw the failed portraits"), kind: .ghost, size: .small,
                         enabled: !purchases.isBusy, busy: purchases.isBusy, fullWidth: true) {
                    Task { await retry(character) }
                }
            }
        }
    }

    private func poses(_ character: CustomCharacterProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView().tint(theme.gold)
                Text(String(appLocalized: "Making five fitness poses. This takes a few minutes."))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
            }
            labelEditor(character)
            snake
        }
    }

    private func done(_ character: CustomCharacterProgress) -> some View {
        let entry = library.first { $0.requestID == character.requestID && $0.workflow == .fitness }
        return VStack(alignment: .leading, spacing: 16) {
            if let entry, let resting = entry.images.first(where: { $0.stage == "resting" }) {
                RemotePhoto(url: resting.url, contentMode: .fit) { theme.control }
                    .frame(maxWidth: .infinity).frame(height: 220)
                HStack(spacing: 6) {
                    ForEach(entry.images) { image in
                        RemotePhoto(url: image.url, contentMode: .fit) { theme.control }
                            .frame(maxWidth: .infinity).frame(height: 64)
                            .accessibilityLabel(image.stage)
                    }
                }
            } else if let portrait = character.portraitURL {
                RemotePhoto(url: portrait, contentMode: .fit) { theme.control }
                    .frame(maxWidth: .infinity).frame(height: 220)
            }
            labelEditor(character)
        }
    }

    @ViewBuilder
    private func problem(_ character: CustomCharacterProgress) -> some View {
        Text(character.phase == .needsSupport
             ? String(appLocalized: "We could not confirm whether this drawing started. Contact support and we will finish your character at no cost.")
             : String(appLocalized: "The images could not be completed. Retry this character without another purchase."))
            .ffType(.body).foregroundStyle(theme.emberText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private func bottomBar(_ step: Step) -> some View {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        switch step {
        case .describe:
            FFButton(title: String(appLocalized: "Next"), size: .large, enabled: !trimmed.isEmpty && !restoring,
                     fullWidth: true) {
                startCheck(trimmed)
            }
            FFButton(title: String(appLocalized: "Restore purchases"), kind: .ghost, size: .small,
                     enabled: !purchases.isBusy, busy: restoring, fullWidth: true) {
                Task {
                    restoring = true
                    await purchases.restore(session: session)
                    await loadLibrary()
                    restoring = false
                }
            }
        case .review:
            buyButton
            Text(String(appLocalized: "Three portraits in about a minute. You pick your favourite."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        case .portraits, .poses:
            FFButton(title: push.permissionStatus == .denied ? String(appLocalized: "Close") : String(appLocalized: "Notify me when it’s ready"),
                     kind: .secondary, size: .large, fullWidth: true) {
                Task {
                    if push.permissionStatus == .notDetermined { await push.requestSystemPermission() }
                    dismiss()
                }
            }
            Text(push.permissionStatus == .denied
                 ? String(appLocalized: "Notifications are off. The Fights tab shows when it is ready.")
                 : String(appLocalized: "You can close the app. We keep drawing."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        case .choosing:
            if let focused {
                let selection = picked[focused.id] ?? focused.candidates.first { $0.status == .completed }?.id
                FFButton(title: String(appLocalized: "Use this portrait"), size: .large,
                         enabled: selection != nil && choosingID == nil, busy: choosingID == focused.id, fullWidth: true) {
                    if let selection { Task { await choose(focused, candidate: selection) } }
                }
            }
        case .done:
            if let focused {
                let entry = library.first { $0.requestID == focused.requestID && $0.workflow == .fitness }
                let equipped = companions.isCustom && entry?.images.contains { $0.url == session.profile?.companionImageURL } == true
                if equipped || entry == nil {
                    FFButton(title: String(appLocalized: "Done"), size: .large, fullWidth: true) { dismiss() }
                } else if let entry {
                    FFButton(title: String(appLocalized: "Use as companion"), size: .large,
                             enabled: !isSelecting, busy: isSelecting, fullWidth: true) {
                        Task { await select(entry) }
                    }
                }
            }
        case .problem:
            if focused?.phase == .needsSupport {
                Link(destination: supportURL) {
                    Text(String(appLocalized: "Contact support")).ffType(.buttonLarge).foregroundStyle(theme.mossOn)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(theme.mossFill, in: Capsule())
                }
            } else if let focused {
                FFButton(title: String(appLocalized: "Try again"), size: .large, enabled: !purchases.isBusy,
                         busy: purchases.isBusy, fullWidth: true) {
                    Task { await retry(focused) }
                }
            }
        }
        // From any step of a paid character, so one stuck on a portrait pick or drawing never blocks the next.
        // ponytail: the old one stays on Yours and keeps drawing; hiding it needs a server column.
        if focused != nil {
            FFButton(title: String(appLocalized: "Create another"), kind: .ghost, size: .small, fullWidth: true) {
                ignored = Set(purchases.snapshot?.characters.map(\.id) ?? [])
                focusID = nil
                finishedID = nil
                options = nil
                note = nil
                description = ""
            }
        }
    }

    /// One button for every way to pay: a purchase made before descriptions existed, a free character, or Apple.
    @ViewBuilder private var buyButton: some View {
        let text = options?[chosen] ?? ""
        if let ready = purchases.snapshot?.characters.first(where: { $0.status == .ready }) {
            FFButton(title: String(appLocalized: "Create character"), size: .large, enabled: !purchases.isBusy,
                     busy: purchases.isBusy, fullWidth: true) {
                Task { await start(ready, description: text) }
            }
        } else if purchases.freeCharacters > 0 {
            FFButton(title: String(appLocalized: "Create for free"), size: .large, enabled: !purchases.isBusy,
                     busy: purchases.isBusy, fullWidth: true) {
                Task { await createFree(text) }
            }
        } else {
            let title = purchases.pendingPurchase
                ? String(appLocalized: "Purchase pending")
                // The preview has no StoreKit, but it still shows the label a buyer sees.
                : (purchases.product?.displayPrice ?? (CompanionPreview.isEnabled ? "€2.99" : nil))
                    .map { String(appLocalized: "character.buy", defaultValue: "Create for \($0)") }
                    ?? String(appLocalized: "Purchases unavailable")
            FFButton(title: title, size: .large,
                     enabled: (purchases.product != nil || CompanionPreview.isEnabled) && !purchases.pendingPurchase && !purchases.isBusy,
                     busy: purchases.isBusy, fullWidth: true) {
                Task { await purchases.buy(description: text, session: session) }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var purchaseMessage: some View {
        if !purchases.message.isEmpty && !CompanionPreview.isEnabled {
            Text(purchases.message).ffType(.caption).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var snake: some View {
        VStack(spacing: 8) {
            Text(String(appLocalized: "Play Snake while you wait")).ffType(.heading).foregroundStyle(theme.text)
            SnakeGame(playing: $playingSnake, record: snakeRecord) { score, milliseconds in
                snakeRecord = max(snakeRecord, score)
                guard !CompanionPreview.isEnabled else { return }
                Task {
                    // A lost or refused score only costs this game's place in the record.
                    if let saved = try? await FitFightAPI().recordSnakeScore(score, milliseconds: milliseconds,
                                                                             accessToken: try await session.freshAccessToken()) {
                        snakeRecord = saved.record
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .id("snake")
    }

    private func portraitTile(_ url: URL?, failed: Bool, picked: Bool) -> some View {
        ZStack {
            theme.control
            if let url {
                // The whole figure, feet included, so people judge the full character.
                RemotePhoto(url: url, contentMode: .fit) { theme.control }
                    .padding(4)
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.emberText)
            } else {
                ProgressView().tint(theme.gold)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                .strokeBorder(picked ? theme.mossEdge : theme.hairline, lineWidth: picked ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if picked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.mossOn, theme.mossFill)
                    .padding(6)
            }
        }
    }

    /// Nothing from a server that cannot name companions yet; it sends no suggestions.
    @ViewBuilder
    private func labelEditor(_ character: CustomCharacterProgress) -> some View {
        if character.suggestions != nil {
            CompanionLabelEditor(character: character, draft: Binding(
                get: { labelDrafts[character.id] ?? .init(name: character.name ?? "", line: character.line ?? "") },
                set: { labelDrafts[character.id] = $0 }
            ))
        }
    }

    private var supportURL: URL {
        let site = URL(string: AppVersion.backend == "prod" ? "https://fitfight.app" : "https://staging.fitfight.app")!
        return (AppLocalization.languageCode == "fr" ? site.appending(path: "fr") : site).appending(path: "support")
    }

    // MARK: Actions

    /// Opens "Pick from our suggestions" at once with the owner's words; the rewrites join them when the Blend run ends.
    private func startCheck(_ text: String) {
        options = [text]
        note = nil
        chosen = 0
        checkFailed = false
        checkText = text
    }

    /// Waits for the Blend prompt check, about a minute. If it fails, the owner can still buy their own words.
    private func check(_ text: String) async {
        checking = true
        defer { checking = false }
        do {
            var run: CharacterPromptCheckRun
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled {
                try await Task.sleep(for: .seconds(CompanionPreview.characterState == "checking" ? 3600 : 2))
                note = CompanionPreview.characterPromptCheck.note
                options = [text] + CompanionPreview.characterPromptCheck.variations
                return
            }
            #endif
            let api = FitFightAPI()
            run = try await api.startPromptCheck(
                description: text, language: AppLocalization.languageCode == "fr" ? "fr" : "en",
                idempotencyKey: UUID(), accessToken: try await session.freshAccessToken()
            )
            while run.check == nil && (run.status == "pending" || run.status == "running") {
                try await Task.sleep(for: .seconds(max(3, run.pollAfterSeconds ?? 5)))
                run = try await api.promptCheck(requestID: run.requestID, accessToken: try await session.freshAccessToken())
            }
            guard let result = run.check else {
                checkFailed = true
                return
            }
            note = result.note
            options = [text] + result.variations
        } catch is CancellationError {
        } catch {
            checkFailed = true
        }
    }

    private func loadLibrary() async {
        do { library = try await FitFightAPI().aiLibrary(accessToken: try await session.freshAccessToken()) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func start(_ character: CustomCharacterProgress, description: String) async {
        focusID = character.id
        do { _ = try await purchases.advance(character.id, description: description, session: session) }
        catch { self.error = error.localizedDescription }
    }

    private func createFree(_ text: String) async {
        error = ""
        do {
            try await purchases.claimFree(description: text, session: session)
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

/// "Name your companion": the written ideas as cards, then Name and Line fields to save either one or your own.
struct CompanionLabelEditor: View {
    struct Draft {
        var name: String
        var line: String
        /// Filled from a card at least once, so a changed card counts as edited rather than typed.
        var fromCard = false
    }

    let character: CustomCharacterProgress
    @Binding var draft: Draft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var purchases: CustomCharacterPurchases
    @Environment(\.ffTheme) private var theme
    @State private var saving = false
    @State private var asking = false
    @State private var error = ""

    var body: some View {
        let suggestions = character.suggestions ?? []
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = draft.line.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(appLocalized: "Name your companion")).ffType(.heading).foregroundStyle(theme.text)
                Spacer()
                if character.moreSuggestionsLeft > 0 && !character.suggestionsPending {
                    Button {
                        Task { await askForMore() }
                    } label: {
                        HStack(spacing: 6) {
                            if asking { ProgressView().controlSize(.small).tint(theme.mossText) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text(suggestions.isEmpty ? String(appLocalized: "Get four ideas") : String(appLocalized: "Four more"))
                        }
                        .ffType(.label).foregroundStyle(theme.mossText)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(asking)
                }
            }
            Text(suggestions.isEmpty && !character.suggestionsPending
                 ? String(appLocalized: "No ideas yet.")
                 : String(appLocalized: "Pick an idea, change it, or write your own."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                let picked = name == suggestion.name && line == suggestion.line
                Button {
                    draft = Draft(name: suggestion.name, line: suggestion.line, fromCard: true)
                } label: {
                    FFCard(fill: picked ? theme.mossWash : nil, stroke: picked ? theme.mossEdge : nil) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: suggestion.name).ffType(.heading).foregroundStyle(theme.text)
                            Text(verbatim: suggestion.line).ffType(.caption).foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
            if character.suggestionsPending {
                FFCard {
                    HStack(spacing: 10) {
                        ProgressView().tint(theme.gold)
                        Text(String(appLocalized: "Writing four ideas. This takes about a minute.")).ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            // The server counts UTF-16 units, so an emoji uses two of the 24 and 60.
            FFField(label: String(appLocalized: "Name"), counter: "\(draft.name.utf16.count)/24") {
                TextField(String(appLocalized: "Your companion’s name"), text: $draft.name)
                    .onChange(of: draft.name) { _, text in
                        var text = text
                        while text.utf16.count > 24 { text.removeLast() }
                        draft.name = text
                    }
            }
            FFField(label: String(appLocalized: "companion.line", defaultValue: "Line"), counter: "\(draft.line.utf16.count)/60") {
                TextField(String(appLocalized: "A short, funny line"), text: $draft.line)
                    .onChange(of: draft.line) { _, text in
                        var text = text
                        while text.utf16.count > 60 { text.removeLast() }
                        draft.line = text
                    }
            }
            // Secondary, so the step's own button at the bottom stays the one main action.
            FFButton(title: String(appLocalized: "Save"), kind: .secondary,
                     enabled: !name.isEmpty && !line.isEmpty && (name != character.name || line != character.line),
                     busy: saving, fullWidth: true) {
                Task { await save(name: name, line: line) }
            }
            if !error.isEmpty {
                Text(error).ffType(.caption).foregroundStyle(theme.emberText)
            }
        }
        .task(id: character.suggestionsPending) {
            // During poses the screen's own polling already advances this character.
            guard character.suggestionsPending, character.phase == .complete else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                    _ = try await purchases.advance(character.id, session: session)
                } catch is CancellationError { return }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save(name: String, line: String) async {
        saving = true
        defer { saving = false }
        error = ""
        let source = character.suggestions?.contains(.init(name: name, line: line)) == true
            ? "suggestion" : draft.fromCard ? "edited" : "own"
        do { try await purchases.saveLabel(character.id, name: name, line: line, source: source, session: session) }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }

    private func askForMore() async {
        asking = true
        defer { asking = false }
        error = ""
        do { try await purchases.suggestLabels(character.id, attemptID: UUID(), session: session) }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
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
/// The five portraits are runs of the published Animal Avatars workflow from these exact words (15 Oct 2026).
struct CharacterIdeas: View {
    @Binding var description: String
    var disabled = false
    @Environment(\.ffTheme) private var theme

    private var ideas: [(image: String, text: String)] {
        [
            ("CharacterIdea-orangutan", String(appLocalized: "character.idea.orangutan", defaultValue: "A 70s hippie orangutan with a tie-dye bandana, a peace sign necklace and round orange glasses.")),
            ("CharacterIdea-parrot", String(appLocalized: "character.idea.parrot", defaultValue: "A pirate parrot with an eye patch and a tricorn hat.")),
            ("CharacterIdea-flamingo", String(appLocalized: "character.idea.flamingo", defaultValue: "A diva flamingo with heart sunglasses and a pink feather boa.")),
            ("CharacterIdea-pig", String(appLocalized: "character.idea.pig", defaultValue: "A cowboy pig with a big hat and a sheriff star.")),
            ("CharacterIdea-chihuahua", String(appLocalized: "character.idea.chihuahua", defaultValue: "A tiny furious chihuahua wearing a huge gold chain.")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(appLocalized: "Need an idea? Tap one.")).ffType(.label).foregroundStyle(theme.textSecondary)
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
                                    .frame(height: 84)
                                    .accessibilityHidden(true)
                                Text(idea.text)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(8)
                            .frame(width: 122, alignment: .top)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(picked ? theme.mossWash : theme.card,
                                        in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                            .ffBorder(picked ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(disabled)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
                // Every card takes the tallest card's height.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A Fights card for a paid character that is being drawn, waits for a portrait choice, or is ready.
/// It shows nothing when there is no such character, and opens the character screen when tapped.
struct PaidCharacterProgressCard: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var purchases: CustomCharacterPurchases
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        // The container stays when the card hides, so an open sheet is not dismissed with it.
        VStack(spacing: 0) {
            if let character = purchases.inProgress.first ?? purchases.unseenReady.first {
                Button {
                    model.characterRouteID = nil
                    model.showingCharacter = true
                } label: {
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
        // A character push opens this sheet too, on the character it names.
        .sheet(isPresented: $model.showingCharacter) {
            PaidCharacterView(initialDescription: "", characterID: model.characterRouteID)
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
