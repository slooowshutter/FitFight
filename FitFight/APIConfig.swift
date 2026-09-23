import Foundation

/// Authenticated backend for private uploads and domain commands.
/// Empty `FFAPIBaseURL` / `BuildEnv.apiBaseURL` means backend features are disabled.
enum APIConfig {
    static let baseURL = configuredValue(BuildEnv.apiBaseURL, infoKey: "FFAPIBaseURL").flatMap(URL.init(string:))

    static var publicOrigin: URL {
        guard let baseURL else { return URL(string: "https://fitfight.app")! }
        var root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let range = root.range(of: "/api/v1", options: .caseInsensitive) {
            root = String(root[..<range.lowerBound])
        }
        return URL(string: root) ?? URL(string: "https://fitfight.app")!
    }

    static func joinShareURL(code: String, referralCode: UUID?) -> URL {
        let url = publicOrigin.appendingPathComponent("j").appendingPathComponent(code)
        guard let referralCode else { return url }
        return url.appending(queryItems: [URLQueryItem(name: "ref", value: referralCode.uuidString.lowercased())])
    }
}
