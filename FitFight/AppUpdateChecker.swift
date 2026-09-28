import Combine
import Foundation

struct AppRelease: Codable, Equatable {
    let version: String
    let build: Int
    let updateURL: URL

    enum CodingKeys: String, CodingKey {
        case version, build
        case updateURL = "update_url"
    }

    func matches(version: String, build: String) -> Bool {
        self.version == version && String(self.build) == build
    }

    func isNewer(thanVersion version: String, build: String) -> Bool {
        guard let installedBuild = Int(build) else { return false }
        let versionOrder = self.version.compare(version, options: .numeric)
        return versionOrder == .orderedDescending
            || (versionOrder == .orderedSame && self.build > installedBuild)
    }
}

struct AppReleasePolicy: Codable, Equatable {
    let latest: AppRelease?
    let review: AppRelease?
    let internalLatest: AppRelease?
    let enforced: Bool

    enum CodingKeys: String, CodingKey {
        case latest, review, enforced
        case internalLatest = "internal"
    }

    init(latest: AppRelease?, review: AppRelease?, enforced: Bool, internalLatest: AppRelease? = nil) {
        self.latest = latest
        self.review = review
        self.internalLatest = internalLatest
        self.enforced = enforced
    }

    func allows(version: String, build: String) -> Bool {
        [latest, review, internalLatest].compactMap { $0 }.contains { $0.matches(version: version, build: build) }
    }
}

extension AppRelease {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(String.self, forKey: .version)
        let build = try values.decode(Int.self, forKey: .build)
        let updateURL = try values.decode(URL.self, forKey: .updateURL)
        guard build > 0,
              version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              updateURL.absoluteString == "itms-beta://"
                || updateURL.absoluteString.range(
                    of: #"^https://apps\.apple\.com/app/id\d+$"#, options: .regularExpression
                ) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid app release"))
        }
        self.init(version: version, build: build, updateURL: updateURL)
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    enum Status: Equatable { case checking, current, updateAvailable, unavailable }

    @Published private(set) var status: Status = .checking
    @Published private(set) var policy: AppReleasePolicy?
    @Published private(set) var pendingToastRelease: AppRelease?

    let isTestFlight: Bool

    private let version: String
    private let build: String
    private let releaseURL: URL
    private let defaults: UserDefaults
    private let session: URLSession
    private let now: () -> Date
    private let cacheKey: String
    private let reminderDateKey: String
    private var lastNotifiedAt: Date?
    private var inFlight: Task<Void, Never>?

    init(version: String, build: String, releaseURL: URL, isTestFlight: Bool = false,
         defaults: UserDefaults = .standard,
         session: URLSession = .shared,
         now: @escaping () -> Date = Date.init) {
        self.version = version
        self.build = build
        self.releaseURL = releaseURL
        self.isTestFlight = isTestFlight
        self.defaults = defaults
        self.session = session
        self.now = now
        cacheKey = "fitfight.release-policy.\(releaseURL.absoluteString)"
        reminderDateKey = "fitfight.release-reminded.\(releaseURL.absoluteString).\(version).\(build).date"
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(AppReleasePolicy.self, from: data) {
            policy = cached
        }
        lastNotifiedAt = defaults.object(forKey: reminderDateKey) as? Date
        if let policy, policy.allows(version: version, build: build) {
            status = .current
        }
    }

    func check() async {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor in
            defer { self.inFlight = nil }
            do {
                var request = URLRequest(url: self.releaseURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await self.session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let policy = try JSONDecoder().decode(AppReleasePolicy.self, from: data)
                self.policy = policy
                self.defaults.set(data, forKey: self.cacheKey)
                if policy.allows(version: self.version, build: self.build) {
                    self.status = .current
                    self.pendingToastRelease = nil
                } else if let latest = policy.latest {
                    // Internal/review membership does not prove what this user can install.
                    let isNewer = latest.isNewer(thanVersion: self.version, build: self.build)
                    self.status = isNewer ? .updateAvailable : .current
                    if isNewer {
                        let notifiedAt = self.now()
                        let remindedRecently = self.lastNotifiedAt.map {
                            notifiedAt.timeIntervalSince($0) < 3 * 24 * 60 * 60
                        } ?? false
                        if !remindedRecently {
                            self.lastNotifiedAt = notifiedAt
                            self.defaults.set(notifiedAt, forKey: self.reminderDateKey)
                            self.pendingToastRelease = latest
                        }
                    } else {
                        self.pendingToastRelease = nil
                    }
                } else {
                    self.status = .unavailable
                    self.pendingToastRelease = nil
                }
            } catch {
                self.status = .unavailable
                self.pendingToastRelease = nil
            }
        }
        inFlight = task
        await task.value
    }

    func dismissToast() {
        pendingToastRelease = nil
    }
}
