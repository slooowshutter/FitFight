import Foundation

struct PreferencesTestUser { let id: UUID }
struct PreferencesTestSession { let user: PreferencesTestUser }
enum AppVersion { static let backend = "test" }

@MainActor
final class SessionStore {
    var authSession: PreferencesTestSession?
    func freshAccessToken() async throws -> String {
        guard let authSession else { throw CancellationError() }
        return authSession.user.id.uuidString
    }
}

@MainActor
final class PreferencesAPI {
    struct Request {
        let token: String
        let update: AccountPreferencesUpdate?
        let continuation: CheckedContinuation<AccountPreferences, Error>
    }
    static let shared = PreferencesAPI()
    var requests: [Request] = []

    func request(token: String, update: AccountPreferencesUpdate? = nil) async throws -> AccountPreferences {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(token: token, update: update, continuation: continuation))
        }
    }

    func next() async -> Request {
        while requests.isEmpty { await Task.yield() }
        return requests.removeFirst()
    }
}

struct FitFightAPI {
    func accountPreferences(accessToken: String) async throws -> AccountPreferences {
        try await PreferencesAPI.shared.request(token: accessToken)
    }
    func updateAccountPreferences(_ update: AccountPreferencesUpdate, accessToken: String) async throws -> AccountPreferences {
        try await PreferencesAPI.shared.request(token: accessToken, update: update)
    }
}

@main
struct AccountPreferencesTests {
    @MainActor
    static func main() async throws {
        let deviceLocale = Locale.current
        AppLocalization.apply(.system)
        precondition(AppLocalization.locale.identifier == deviceLocale.identifier,
                     "Follow iPhone must preserve the full device locale")
        for language in [AppLanguage.system, .en, .fr] {
            AppLocalization.apply(language)
            let locale = AppLocalization.locale
            precondition(locale.region == deviceLocale.region, "Language changes must preserve the region")
            precondition(locale.hourCycle == deviceLocale.hourCycle, "Language changes must preserve clock preferences")
            precondition(locale.firstDayOfWeek == deviceLocale.firstDayOfWeek, "Language changes must preserve the first weekday")
            precondition(locale.calendar.identifier == deviceLocale.calendar.identifier, "Language changes must preserve the calendar")
            if language != .system {
                precondition(locale.language.languageCode?.identifier == language.rawValue)
            }
        }
        AppLocalization.apply(.system)

        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let frenchDark = try JSONDecoder().decode(AccountPreferences.self, from: Data(contentsOf: fixture))
        precondition(frenchDark == AccountPreferences(language: .fr, appearance: .dark))
        let patch = try JSONEncoder().encode(AccountPreferencesUpdate(language: .en))
        let json = try JSONSerialization.jsonObject(with: patch) as! [String: String]
        precondition(json == ["language": "en"], "Omitted settings must not overwrite another device's choice")

        let suite = "fitfight-preferences-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let userA = UUID()
        let userB = UUID()
        let session = SessionStore()
        session.authSession = .init(user: .init(id: userA))
        let store = AccountPreferencesStore(defaults: defaults)
        store.activate(userID: userA)
        precondition(store.value == AccountPreferences() && !store.isAvailable)

        let load = Task { await store.refresh(session: session) }
        let read = await PreferencesAPI.shared.next()
        precondition(read.token == userA.uuidString && store.isLoading)
        read.continuation.resume(returning: frenchDark)
        await load.value
        precondition(store.value == frenchDark && store.isAvailable && !store.isLoading)
        precondition(AppLocalization.languageCode == "fr")
        precondition(String(appLocalized: "Preferences") == "Préférences")
        let count = 2
        precondition(String(appLocalized: "test.count", defaultValue: "\(count) choices") == "2 choix")

        let restored = AccountPreferencesStore(defaults: defaults)
        restored.activate(userID: userA)
        precondition(restored.value == frenchDark, "A relaunch restores only this account's cache")

        let failure = Task { await store.save(.init(language: .en), session: session) }
        let failedWrite = await PreferencesAPI.shared.next()
        precondition(store.isSaving && store.value == frenchDark)
        failedWrite.continuation.resume(throwing: URLError(.notConnectedToInternet))
        await failure.value
        precondition(store.value == frenchDark && store.error != nil && !store.isSaving)

        let staleLoad = Task { await store.refresh(session: session) }
        let staleRead = await PreferencesAPI.shared.next()
        let save = Task { await store.save(.init(appearance: .light), session: session) }
        let write = await PreferencesAPI.shared.next()
        precondition(write.update?.appearance == .light && write.update?.language == nil)
        write.continuation.resume(returning: AccountPreferences(language: .fr, appearance: .light))
        await save.value
        staleRead.continuation.resume(returning: frenchDark)
        await staleLoad.value
        precondition(store.value.appearance == .light, "A read started before a save cannot revert it")

        let oldAccountLoad = Task { await store.refresh(session: session) }
        let oldRead = await PreferencesAPI.shared.next()
        session.authSession = .init(user: .init(id: userB))
        store.activate(userID: userB)
        precondition(store.value == AccountPreferences() && !store.isAvailable && store.error == nil)
        oldRead.continuation.resume(returning: frenchDark)
        await oldAccountLoad.value
        precondition(store.value == AccountPreferences(), "A previous account's response must not leak settings")

        let loadB = Task { await store.refresh(session: session) }
        let readB = await PreferencesAPI.shared.next()
        readB.continuation.resume(returning: AccountPreferences(language: .en, appearance: .system))
        await loadB.value
        precondition(String(appLocalized: "Preferences") == "Preferences")
        let saveB = Task { await store.save(.init(language: .fr), session: session) }
        let writeB = await PreferencesAPI.shared.next()
        session.authSession = nil
        store.activate(userID: nil)
        writeB.continuation.resume(returning: frenchDark)
        await saveB.value
        precondition(store.value == AccountPreferences() && !store.isSaving && !store.isAvailable)

        store.removeCache(for: userA)
        store.activate(userID: userA)
        precondition(store.value == AccountPreferences(), "Deleting the account removes its preference cache")
        print("Account preferences: API fixture, patches, localization, cache, failures, stale reads, account changes, and deletion passed")
    }
}
