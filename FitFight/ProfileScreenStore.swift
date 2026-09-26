import Combine
import Foundation

@MainActor
final class ProfileScreenStore: ObservableObject {
    @Published private(set) var profile: SharedProfile?
    @Published private(set) var history: [ProfileHistoryRow] = []
    @Published private(set) var nextCursor: UUID?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = 0

    func clear() {
        generation += 1
        profile = nil
        history = []
        nextCursor = nil
        loading = false
        error = nil
    }

    /// You shows only the record and statistics, so it skips the history request.
    func load(userID: UUID, session: SessionStore, preview: String? = nil, includeHistory: Bool = true) async {
        clear()
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            profile = CompanionPreview.profile(userID: userID)
            history = includeHistory && userID == CompanionPreview.youID ? CompanionPreview.sampleHistory : []
            return
        }
        #endif
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            async let profileRequest = FitFightAPI().sharedProfile(userID: userID, preview: preview, accessToken: token)
            let page: ProfileHistoryPage? = preview == nil && includeHistory
                ? try await FitFightAPI().profileHistory(userID: userID, shared: userID != accountID, accessToken: token)
                : nil
            let loaded = try await profileRequest
            try Task.checkCancellation()
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            profile = loaded
            history = page?.results ?? []
            nextCursor = page?.nextCursor
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore(userID: UUID, session: SessionStore) async {
        guard let cursor = nextCursor, !loading else { return }
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            let page = try await FitFightAPI().profileHistory(userID: userID, shared: userID != accountID, cursor: cursor, accessToken: token)
            try Task.checkCancellation()
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            history.append(contentsOf: page.results)
            nextCursor = page.nextCursor
            error = nil
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            // A network failure keeps the rows and cursor for Load more; a server refusal
            // (blocked, deleted, invalid cursor) hides the Profile as before.
            if !(error is URLError) { clear() }
            self.error = error.localizedDescription
        }
    }
}
