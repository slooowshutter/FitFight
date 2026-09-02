import SwiftUI

private struct BoardItem: Identifiable, Hashable {
    var request: FitFightRequest
    var ago: String
    var id: UUID { request.id }
}

struct RequestsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss

    @State private var filter: Filter = .top
    @State private var items: [BoardItem] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingCompose = false
    @State private var showingModerate = false
    @State private var moderateItem: BoardItem?

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case top = "Top"
        case features = "Features"
        case bugs = "Bugs"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack(spacing: 12) {
                Text("Requests")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                FFIconButton(systemName: "plus", size: 38) {
                    showingCompose = true
                }
                Button("Close") { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            FFScreen(clearance: false) {
                Text("Vote on what gets built next.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.bottom, 2)

                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { option in
                        FFChip(
                            title: option.rawValue,
                            count: count(option),
                            selected: filter == option
                        ) { filter = option }
                    }
                    Spacer(minLength: 0)
                }

                if let errorText, !errorText.isEmpty {
                    FFNotice(text: errorText, tone: .ember, systemImage: "exclamationmark.triangle")
                }

                if filtered.isEmpty, !loading {
                    FFEmptyState(
                        systemImage: "bubble.left",
                        title: "No requests yet",
                        message: "Post a feature or a bug. Everyone signed in can vote.",
                        actionTitle: "New request",
                        action: { showingCompose = true }
                    )
                }

                ForEach(filtered) { item in
                    RequestCard(
                        item: item,
                        canModerate: item.request.author.userId != session.authSession?.user.id
                    ) {
                        Task { await toggleVote(item) }
                    } onModerate: {
                        moderateItem = item
                        showingModerate = true
                    }
                }

                Text("Posts are public to everyone signed in to FitFight. Report or block anything that shouldn’t be here.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, theme.space.lg)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task {
            if staticRender {
                items = Self.previewItems
                return
            }
            await load()
        }
        .refreshable {
            await load()
        }
        .sheet(isPresented: $showingCompose) {
            RequestsComposeView { created in
                items.insert(
                    BoardItem(request: created, ago: relativeTime(from: created.createdAt)),
                    at: 0
                )
            }
            .environmentObject(session)
            .fitFightTheme(themeStore.theme)
            .presentationBackground(theme.bg)
        }
        .confirmationDialog(
            "This post",
            isPresented: $showingModerate,
            titleVisibility: .visible
        ) {
            Button("Report", role: .destructive) {
                if let item = moderateItem {
                    Task { await report(item) }
                }
            }
            Button("Block this person", role: .destructive) {
                if let item = moderateItem {
                    Task { await blockAuthor(item) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reported posts are hidden from you. Three reports hide them for everyone. Blocking hides that person’s posts from you.")
        }
    }

    private func count(_ option: Filter) -> Int {
        switch option {
        case .top: return items.count
        case .features: return items.filter { $0.request.kind == "feature" }.count
        case .bugs: return items.filter { $0.request.kind == "bug" }.count
        }
    }

    private var filtered: [BoardItem] {
        switch filter {
        case .top:
            return items.sorted { $0.request.voteCount > $1.request.voteCount }
        case .features:
            return items.filter { $0.request.kind == "feature" }
        case .bugs:
            return items.filter { $0.request.kind == "bug" }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let token = try await session.freshAccessToken()
            let list = try await FitFightAPI().listRequests(accessToken: token)
            items = list.items.map { BoardItem(request: $0, ago: relativeTime(from: $0.createdAt)) }
            errorText = nil
        } catch {
            errorText = displayError(error)
        }
    }

    private func toggleVote(_ item: BoardItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let current = items[index].request
        items[index].request.voted.toggle()
        items[index].request.voteCount += items[index].request.voted ? 1 : -1
        do {
            let token = try await session.freshAccessToken()
            let updated = try await FitFightAPI().toggleRequestVote(
                requestID: current.id,
                accessToken: token
            )
            items[index] = BoardItem(request: updated, ago: items[index].ago)
            errorText = nil
        } catch {
            items[index].request = current
            errorText = displayError(error)
        }
    }

    private func report(_ item: BoardItem) async {
        do {
            let token = try await session.freshAccessToken()
            _ = try await FitFightAPI().reportRequest(requestID: item.id, accessToken: token)
            items.removeAll { $0.id == item.id }
            errorText = nil
        } catch {
            errorText = displayError(error)
        }
    }

    private func blockAuthor(_ item: BoardItem) async {
        let authorID = item.request.author.userId
        do {
            let token = try await session.freshAccessToken()
            _ = try await FitFightAPI().blockRequestAuthor(requestID: item.id, accessToken: token)
            items.removeAll { $0.request.author.userId == authorID }
            errorText = nil
        } catch {
            errorText = displayError(error)
        }
    }

    private static let previewItems: [BoardItem] = [
        BoardItem(
            request: FitFightRequest(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                kind: "feature",
                status: "planned",
                title: "Custom challenge length",
                body: "Let me pick any number of days, not just 3 / 7 / 14 / 30.",
                voteCount: 84,
                voted: true,
                createdAt: "2026-08-30T12:00:00.000Z",
                author: FitFightRequestAuthor(userId: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, handle: "leo", displayName: "Leo")
            ),
            ago: "3d ago"
        ),
        BoardItem(
            request: FitFightRequest(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                kind: "feature",
                status: "open",
                title: "Team fights, 2 v 2",
                body: "Me and my wife against another couple. Scores add up per team.",
                voteCount: 71,
                voted: false,
                createdAt: "2026-08-28T12:00:00.000Z",
                author: FitFightRequestAuthor(userId: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, handle: "nina", displayName: "Nina")
            ),
            ago: "5d ago"
        ),
        BoardItem(
            request: FitFightRequest(
                id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
                kind: "bug",
                status: "open",
                title: "Chart days stay empty after refresh",
                body: "Pull to refresh updates the total, but the day-by-day block stays blank until I reopen the fight.",
                voteCount: 41,
                voted: false,
                createdAt: "2026-08-31T12:00:00.000Z",
                author: FitFightRequestAuthor(userId: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!, handle: "theo", displayName: "Theo")
            ),
            ago: "1d ago"
        ),
        BoardItem(
            request: FitFightRequest(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                kind: "feature",
                status: "open",
                title: "Apple Watch live standings",
                body: "A complication showing my position without opening the phone.",
                voteCount: 39,
                voted: false,
                createdAt: "2026-08-26T12:00:00.000Z",
                author: FitFightRequestAuthor(userId: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!, handle: "sam", displayName: "Sam")
            ),
            ago: "1w ago"
        ),
    ]
}

private struct RequestCard: View {
    let item: BoardItem
    var canModerate: Bool
    var onVote: () -> Void
    var onModerate: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let voted = item.request.voted
        return HStack(alignment: .top, spacing: 12) {
            Button(action: onVote) {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .heavy))
                    Text("\(item.request.voteCount)")
                        .ffType(.button)
                }
                .foregroundStyle(voted ? theme.mossOn : theme.textDim)
                .padding(.vertical, 10)
                .frame(width: 44)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    voted ? theme.mossFill : theme.control,
                    in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                )
                .ffBorder(voted ? theme.mossEdge : theme.line, radius: theme.radius.glyph)
            }
            .buttonStyle(FFPressStyle())
            .accessibilityLabel(voted ? "Remove upvote" : "Upvote")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    FFTag(
                        item.request.kind == "feature" ? "Feature" : "Bug",
                        tone: item.request.kind == "feature" ? .moss : .ember
                    )
                    FFTag(statusText, tone: statusTone)
                    Spacer(minLength: 0)
                    if canModerate {
                        Button(action: onModerate) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.textFaint)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Report or block")
                    }
                }
                .padding(.bottom, 8)
                Text(item.request.title)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .padding(.bottom, 4)
                Text(item.request.body)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 11)
                HStack(spacing: 8) {
                    FFAvatar(monogram: initials(item.request.author.displayName, handle: item.request.author.handle), size: 22)
                    Text("\(item.request.author.displayName) · \(item.ago)")
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private var statusText: String {
        switch item.request.status {
        case "planned": return "Planned"
        case "shipped": return "Shipped"
        default: return "Open"
        }
    }

    private var statusTone: FFTone {
        switch item.request.status {
        case "planned": return .gold
        case "shipped": return .moss
        default: return .neutral
        }
    }
}

struct RequestsComposeView: View {
    var onCreated: (FitFightRequest) -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "feature"
    @State private var title = ""
    @State private var bodyText = ""
    @State private var busy = false
    @State private var errorText: String?

    private var canPost: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !busy
            && !trimmedTitle.isEmpty
            && trimmedTitle.count <= 80
            && !trimmedBody.isEmpty
            && trimmedBody.count <= 500
    }

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                Text("New request")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Close") { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            FFScreen(clearance: false) {
                Text("Features and bugs are public. Keep it about FitFight.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: 8) {
                    FFChip(title: "Feature", selected: kind == "feature") { kind = "feature" }
                    FFChip(title: "Bug", selected: kind == "bug") { kind = "bug" }
                    Spacer(minLength: 0)
                }

                FFField(
                    label: "Title",
                    state: title.count > 80 ? .error : .normal,
                    counter: "\(title.count)/80"
                ) {
                    if staticRender {
                        Text(title.isEmpty ? "What should we build or fix?" : title)
                            .foregroundStyle(title.isEmpty ? theme.textFaint : theme.text)
                    } else {
                        TextField("What should we build or fix?", text: $title)
                            .foregroundStyle(theme.text)
                    }
                }

                FFField(
                    label: "Details",
                    state: bodyText.count > 500 ? .error : .normal,
                    counter: "\(bodyText.count)/500",
                    minHeight: 120
                ) {
                    if staticRender {
                        Text(bodyText.isEmpty ? "A short, specific description." : bodyText)
                            .foregroundStyle(bodyText.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        TextEditor(text: $bodyText)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(theme.text)
                    }
                }

                if let errorText, !errorText.isEmpty {
                    FFNotice(text: errorText, tone: .ember, systemImage: "exclamationmark.triangle")
                }

                FFScreenCTA(
                    title: busy ? "Posting…" : "Post request",
                    enabled: canPost,
                    busy: busy
                ) {
                    Task { await post() }
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func post() async {
        let payload = FitFightCreateRequest(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        busy = true
        defer { busy = false }
        do {
            let token = try await session.freshAccessToken()
            let created = try await FitFightAPI().createRequest(payload, accessToken: token)
            onCreated(created)
            dismiss()
        } catch {
            errorText = displayError(error)
        }
    }
}

private func initials(_ name: String, handle: String) -> String {
    let parts = name.split(separator: " ").filter { !$0.isEmpty }
    if parts.count >= 2 {
        return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
    }
    if let first = parts.first, !first.isEmpty {
        return String(first.prefix(2)).uppercased()
    }
    return String(handle.prefix(2)).uppercased()
}

private func relativeTime(from iso: String, now: Date = Date()) -> String {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    guard let date = withFraction.date(from: iso) ?? basic.date(from: iso) else {
        return ""
    }
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
    if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
    if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d ago" }
    return "\(Int(seconds / (86_400 * 7)))w ago"
}

private func displayError(_ error: Error) -> String {
    if let api = error as? FitFightAPIError {
        switch api {
        case .http(_, let body):
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["error"] as? String,
               !message.isEmpty {
                return message
            }
            return body.isEmpty ? "Couldn’t reach FitFight." : body
        case .notConfigured:
            return "FitFight API is not configured."
        case .decoding:
            return "Couldn’t read the server response."
        }
    }
    return (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
}
