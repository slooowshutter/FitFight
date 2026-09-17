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

    func load(userID: UUID, session: SessionStore, preview: String? = nil) async {
        clear()
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            let loaded = try await FitFightAPI().sharedProfile(userID: userID, preview: preview, accessToken: token)
            let page: ProfileHistoryPage?
            if preview == nil {
                page = try await FitFightAPI().profileHistory(userID: userID, shared: loaded.record == nil, accessToken: token)
            } else {
                page = nil
            }
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
        guard let cursor = nextCursor, let profile, !loading else { return }
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            let page = try await FitFightAPI().profileHistory(userID: userID, shared: profile.record == nil, cursor: cursor, accessToken: token)
            try Task.checkCancellation()
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            history.append(contentsOf: page.results)
            nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation else { return }
            clear()
            self.error = error.localizedDescription
        }
    }
}
