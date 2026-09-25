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
    @State private var error = ""

    private var incomplete: [CustomCharacterProgress] {
        purchases.snapshot?.characters.filter({
            $0.status == .generating || $0.status == .retryable || $0.status == .needsSupport
        }) ?? []
    }

    private var pollingID: UUID? { incomplete.first(where: { $0.status == .generating })?.id }

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
            Text("One purchase creates one character and five fitness images that change with your daily Steps.")
                .ffType(.body).foregroundStyle(theme.textSecondary)

            ForEach(incomplete) { active in
                FFSection(title: String(localized: "Your character")) {
                    Text(active.description ?? description).ffType(.body).foregroundStyle(theme.text)
                    if active.status == .generating {
                        ProgressView().tint(theme.gold)
                        Text(active.stage == .fitness ? "Creating five fitness images…" : "Creating your portrait…")
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        Text("You can close this screen. Your character keeps generating.")
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    } else if active.status == .retryable {
                        Text("The images could not be completed. Retry this character without another purchase.")
                            .ffType(.caption).foregroundStyle(theme.emberText)
                        FFButton(title: String(localized: "Try again"), kind: .secondary, enabled: !purchases.isBusy, busy: purchases.isBusy, fullWidth: true) {
                            Task { await retry(active) }
                        }
                    } else {
                        Text("We could not confirm whether this generation started. Contact support before retrying.")
                            .ffType(.caption).foregroundStyle(theme.emberText)
                    }
                }
            }
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
            } else {
                let title = purchases.pendingPurchase
                    ? String(appLocalized: "Purchase pending")
                    : purchases.product.map { String(appLocalized: "character.buy", defaultValue: "Create for \($0.displayPrice)") }
                        ?? String(appLocalized: "Purchases unavailable")
                FFButton(title: title, kind: .primary,
                         enabled: purchases.product != nil && !purchases.pendingPurchase && !purchases.isBusy && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
            if !purchases.message.isEmpty {
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
            await loadLibrary()
        }
        .task(id: pollingID) {
            guard let id = pollingID else { return }
            while !Task.isCancelled {
                do {
                    let progress = try await purchases.advance(id, session: session)
                    if progress.status != .generating {
                        await loadLibrary()
                        if progress.status == .complete,
                           let entry = library.first(where: { $0.requestID == progress.requestID && $0.workflow == .fitness }) {
                            await select(entry)
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

    private func loadLibrary() async {
        do { library = try await FitFightAPI().aiLibrary(accessToken: try await session.freshAccessToken()) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func start(_ character: CustomCharacterProgress) async {
        do { _ = try await purchases.advance(character.id, description: description.trimmingCharacters(in: .whitespacesAndNewlines), session: session) }
        catch { self.error = error.localizedDescription }
    }

    private func retry(_ character: CustomCharacterProgress) async {
        do { _ = try await purchases.advance(character.id, retry: true, session: session) }
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
