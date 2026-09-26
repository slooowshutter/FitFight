import Combine
import Foundation

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return String(appLocalized: "Follow iPhone")
        case .light: return String(appLocalized: "Light")
        case .dark: return String(appLocalized: "Dark")
        }
    }
}

struct AccountPreferences: Codable, Equatable {
    var language: AppLanguage = .system
    var appearance: AppAppearance = .system
}

struct AccountPreferencesUpdate: Encodable {
    var language: AppLanguage?
    var appearance: AppAppearance?
}

@MainActor
final class AccountPreferencesStore: ObservableObject {
    @Published private(set) var value = AccountPreferences()
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isAvailable = false
    @Published private(set) var error: String?

    private var userID: UUID?
    private var revision = 0
    private let defaults: UserDefaults
    private let api = FitFightAPI()
    private let cachePrefix = "fitfight.preferences.\(AppVersion.backend)."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(userID: UUID?) {
        guard self.userID != userID else { return }
        self.userID = userID
        revision += 1
        isLoading = false
        isSaving = false
        isAvailable = false
        error = nil
        var restored = AccountPreferences()
        if let userID, let data = defaults.data(forKey: cachePrefix + userID.uuidString),
           let cached = try? JSONDecoder().decode(AccountPreferences.self, from: data) {
            restored = cached
        }
        AppLocalization.apply(restored.language)
        value = restored
    }

    func refresh(session: SessionStore) async {
        activate(userID: session.authSession?.user.id)
        guard let userID, !isSaving else { return }
        revision += 1
        let requestRevision = revision
        isLoading = true
        defer { if requestRevision == revision { isLoading = false } }
        do {
            let token = try await session.freshAccessToken()
            let loaded = try await api.accountPreferences(accessToken: token)
            try Task.checkCancellation()
            guard requestRevision == revision, session.authSession?.user.id == userID else { return }
            apply(loaded, userID: userID)
        } catch {
            guard requestRevision == revision, session.authSession?.user.id == userID,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = String(appLocalized: "Couldn’t load your preferences. Try again.")
        }
    }

    func save(_ update: AccountPreferencesUpdate, session: SessionStore) async {
        guard let userID, session.authSession?.user.id == userID,
              isAvailable, !isSaving else { return }
        revision += 1
        let requestRevision = revision
        isLoading = false
        isSaving = true
        error = nil
        defer { if requestRevision == revision { isSaving = false } }
        do {
            let token = try await session.freshAccessToken()
            let saved = try await api.updateAccountPreferences(update, accessToken: token)
            try Task.checkCancellation()
            guard requestRevision == revision, session.authSession?.user.id == userID else { return }
            apply(saved, userID: userID)
        } catch {
            guard requestRevision == revision, session.authSession?.user.id == userID,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = String(appLocalized: "Couldn’t save your preferences. Your previous settings are unchanged.")
        }
    }

    func removeCache(for userID: UUID) {
        defaults.removeObject(forKey: cachePrefix + userID.uuidString)
    }

    private func apply(_ preferences: AccountPreferences, userID: UUID) {
        AppLocalization.apply(preferences.language)
        value = preferences
        isAvailable = true
        error = nil
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: cachePrefix + userID.uuidString)
        }
    }
}
