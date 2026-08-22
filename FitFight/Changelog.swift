import Foundation

struct ReleaseNote: Identifiable, Hashable {
    let version: String
    let year: Int
    let month: Int
    let day: Int
    let notes: String

    var id: String { "\(version)-\(year)-\(month)-\(day)" }

    var date: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? .distantPast
    }
}

enum Changelog {
    /// Newest first. Add a row here whenever we ship a user-facing change.
    static let releases: [ReleaseNote] = [
        ReleaseNote(
            version: "0.2.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "Design system. Four switchable themes (Arena, Pulse, Locker, Rogue), a Design catalog, and shared tokens for color, type, and radius."
        ),
        ReleaseNote(
            version: "0.1.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "First TestFlight. App name on screen, version at the top, and a Versions list for every release."
        ),
    ]

    static var newestFirst: [ReleaseNote] {
        releases.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.version > rhs.version
        }
    }
}
