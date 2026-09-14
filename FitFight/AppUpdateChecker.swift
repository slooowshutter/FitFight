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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        latest = try values.decodeIfPresent(AppRelease.self, forKey: .latest)
        review = try values.decodeIfPresent(AppRelease.self, forKey: .review)
        internalLatest = try values.decodeIfPresent(AppRelease.self, forKey: .internalLatest)
        enforced = try values.decode(Bool.self, forKey: .enforced)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(latest, forKey: .latest)
        try values.encode(review, forKey: .review)
        try values.encodeIfPresent(internalLatest, forKey: .internalLatest)
        try values.encode(enforced, forKey: .enforced)
    }

    func allows(version: String, build: String) -> Bool {
        [latest, review, internalLatest].compactMap { $0 }.contains { $0.matches(version: version, build: build) }
    }

    var offeredRelease: AppRelease? { internalLatest ?? latest ?? review }
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
    enum Status: Equatable { case checking, current, updateRequired, unavailable }

    @Published private(set) var status: Status = .checking
    @Published private(set) var policy: AppReleasePolicy?
    @Published private(set) var isChecking = false

    var allowsUse: Bool { status != .updateRequired }

    private let version: String
    private let build: String
    private let releaseURL: URL
    private let defaults: UserDefaults
    private let session: URLSession
    private let cacheKey: String
    private var inFlight: Task<Bool, Never>?

    init(version: String, build: String, releaseURL: URL, defaults: UserDefaults = .standard,
         session: URLSession = .shared) {
        self.version = version
        self.build = build
        self.releaseURL = releaseURL
        self.defaults = defaults
        self.session = session
        cacheKey = "fitfight.release-policy.\(releaseURL.absoluteString)"
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(AppReleasePolicy.self, from: data) {
            policy = cached
            if cached.allows(version: version, build: build) {
                status = .current
            } else if cached.latest != nil {
                status = .updateRequired
            }
        }
    }

    @discardableResult
    func check() async -> Bool {
        if let inFlight { return await inFlight.value }
        isChecking = true
        let task = Task { @MainActor in
            defer {
                self.inFlight = nil
                self.isChecking = false
            }
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
                } else if self.status == .updateRequired || policy.latest != nil {
                    self.status = .updateRequired
                } else {
                    self.status = .unavailable
                }
            } catch {
                if self.status != .updateRequired { self.status = .unavailable }
            }
            return self.status != .updateRequired
        }
        inFlight = task
        return await task.value
    }

    func permitsRequests() async -> Bool {
        allowsUse
    }

    func rejectRequest(updateRequired: Bool) {
        if updateRequired {
            status = .updateRequired
        } else if status != .updateRequired {
            status = .unavailable
        }
    }
}
