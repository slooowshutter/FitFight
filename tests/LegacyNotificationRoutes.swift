import Foundation

// Released parsers, unchanged from builds 201 (d97145a) and 202 (e2783be).
@MainActor final class LegacyNotificationRoutes {
    static let pendingFightRouteKey = "fitfight.tests.legacy.route"
    static let pendingDailyStatusKey = "fitfight.tests.legacy.daily"
    var openFightID: String?
    func openFightFromFeed(id: String) { openFightID = id }
    func presentDailyStatusRecap(for id: String) async {}
    func consumeForTest() { consumePendingFightRoute(showDailyStatusRecap: false) }
    static func storePendingFightRoute(_ route: String, dailyStatus: Bool = false) {
        let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
        let withSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        let components = URLComponents(string: "https://fitfight.app\(withSlash)")
        let path = (components?.path.isEmpty == false) ? components!.path : withSlash
        let queryDailyStatus = components?.queryItems?.contains { item in
            item.name == "daily_status" && (item.value == "1" || item.value?.lowercased() == "true")
        } ?? false
        UserDefaults.standard.set(path, forKey: pendingFightRouteKey)
        UserDefaults.standard.set(dailyStatus || queryDailyStatus, forKey: pendingDailyStatusKey)
    }

    private func consumePendingFightRoute(showDailyStatusRecap: Bool) {
        guard let route = UserDefaults.standard.string(forKey: Self.pendingFightRouteKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingFightRouteKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingDailyStatusKey)
        let parts = route.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "fights", UUID(uuidString: parts[1]) != nil else { return }
        openFightFromFeed(id: parts[1])
        if showDailyStatusRecap {
            Task { await presentDailyStatusRecap(for: parts[1]) }
        }
    }

}
