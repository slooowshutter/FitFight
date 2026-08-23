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
            version: "0.3.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Rebuilt every screen against pixel measurements of the design screenshots: inline standings bars, tinted card footers, the rank ring on a fight, and the real spacing everywhere."
        ),
        ReleaseNote(
            version: "0.3.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "The approved look, as a real iOS app. Four tabs matching the screenshots: Fights, New, Requests, You. Dark/light plus ten accents."
        ),
        ReleaseNote(
            version: "0.2.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "Placeholder themes (Arena, Pulse, Locker, Rogue). Superseded."
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
