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
            version: "0.1.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "English and French. The app follows your iPhone language, and you can change it in Settings."
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

    /// Newest changelog row whose version matches the installed marketing version.
    static var currentRelease: ReleaseNote? {
        newestFirst.first { $0.version == AppVersion.marketing }
    }
}
