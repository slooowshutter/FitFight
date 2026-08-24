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
            version: "0.7.1",
            year: 2026,
            month: 8,
            day: 24,
            notes: "Tapping a look on the Design tab actually switches it. The little live previews were eating the tap, so it felt like the tab was stuck."
        ),
        ReleaseNote(
            version: "0.7.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Requests has a Talk to the boss button. It opens a private chat with Marc — not the public vote board. What you send is emailed to him; he writes back from his inbox until the app has a server."
        ),
        ReleaseNote(
            version: "0.6.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Ten new looks for the app, plus a Design tab to flip between them. Each one is a real redesign of the fights screen with its own colours and its own idea of what matters: Ring closes an activity ring for every fight, Ledger reads like a betting statement, Arena puts you face to face with whoever is beating you, Soft says it in a sentence, Terminal prints it as monospace, Stack floats it on frosted glass, Podium builds a gold podium, Pulse turns the pot into one stacked bar, Bento lays it out as uneven tiles and Zine sets it like a printed page. Every design shows the same fights and the same money — only the look changes. The tab shows all eleven side by side, live, and one tap swaps the app over."
        ),
        ReleaseNote(
            version: "0.5.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Everything was too round. Measuring the corners against the mockups showed the request cards curving over 12 points where the design curves over 6, and the Top/Features/Bugs switcher, the vote pill, the Feature/Bug tags and the day and stake chips were all close to twice as round as they should be. Section titles also sit slightly inside the card below them, the way the design draws them."
        ),
        ReleaseNote(
            version: "0.5.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "The app was shouting. Measuring the brightness of every line against the mockups showed that most quiet text — the eyebrows over card titles, the line under each screen title, stat labels, handles, timestamps, +2 more — was rendering at 62% white where the design uses 40%. The bell, the Edit pill and the fight nav buttons also had a grey fill the design does not have, and the bell itself was three points too big. Buttons are the mockups' size now, and a part-filled progress bar is no longer two translucent whites stacked up."
        ),
        ReleaseNote(
            version: "0.4.2",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Another measuring pass over the mockups. The Top/Features/Bugs switcher was seven points too tall, a fight card with people still to accept grew taller than one without, and the kickers above every card title sat two points high. All fixed."
        ),
        ReleaseNote(
            version: "0.4.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Everyone has their face back: Leo, Sam, Nina, Theo, Ivy and you now use the photographs from the design instead of coloured initials. Settings rows, the pending pill and the option rows on New fight are the sizes the mockups use."
        ),
        ReleaseNote(
            version: "0.4.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "The app now uses Manrope, the typeface the design was drawn in, instead of the system font. Every title, name and number is the shape it is in the mockups."
        ),
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
