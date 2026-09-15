import Foundation

@main
struct RemainingTimeTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let now = date(2026, 9, 10, 12, 0, calendar: calendar)

        let oneDayFiveHours = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 11, 17, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            oneDayFiveHours == RemainingTime.Breakdown(days: 1, hours: 5),
            "Under two days must keep the day and show hours, not round up to 2 days"
        )

        let justUnderTwoDays = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 12, 11, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            justUnderTwoDays == RemainingTime.Breakdown(days: 1, hours: 23),
            "1 day 23 hours must stay 1 day plus hours"
        )

        let twoDaysPlus = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 12, 13, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            twoDaysPlus == RemainingTime.Breakdown(days: 2),
            "Two days and an hour must not show hours"
        )

        let tenDays = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 20, 12, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            tenDays == RemainingTime.Breakdown(weeks: 1),
            "10 days should show only whole weeks"
        )

        let fiveHours = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 10, 17, 20, calendar: calendar),
            calendar: calendar
        )
        precondition(
            fiveHours == RemainingTime.Breakdown(hours: 5),
            "Two hours or more should show only hours"
        )

        let fortyFiveMinutes = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 10, 12, 45, calendar: calendar),
            calendar: calendar
        )
        precondition(
            fortyFiveMinutes == RemainingTime.Breakdown(minutes: 45),
            "Under an hour should show minutes"
        )

        let thirtySeconds = RemainingTime.breakdown(
            from: now,
            until: now.addingTimeInterval(30),
            calendar: calendar
        )
        precondition(
            thirtySeconds == RemainingTime.Breakdown(minutes: 1),
            "A few seconds left should still show 1 minute"
        )

        let oneMonth = RemainingTime.breakdown(
            from: now,
            until: calendar.date(byAdding: .month, value: 1, to: now)!,
            calendar: calendar
        )
        precondition(
            oneMonth == RemainingTime.Breakdown(months: 1),
            "A calendar month later should show 1 month"
        )

        let boundaries: [(TimeInterval, RemainingTime.Breakdown)] = [
            (0, .init()),
            (-60, .init()),
            (60, .init(minutes: 1)),
            (3_599, .init(minutes: 59)),
            (3_600, .init(hours: 1)),
            (7_140, .init(hours: 1, minutes: 59)),
            (7_200, .init(hours: 2)),
            (86_340, .init(hours: 23)),
            (86_400, .init(days: 1)),
            (172_740, .init(days: 1, hours: 23)),
            (172_800, .init(days: 2)),
            (604_740, .init(days: 6)),
            (604_800, .init(weeks: 1)),
            (29 * 86_400, .init(weeks: 4)),
            (40 * 86_400, .init(months: 1)),
            (65 * 86_400, .init(months: 2)),
        ]
        for (seconds, expected) in boundaries {
            precondition(
                RemainingTime.breakdown(from: now, until: now.addingTimeInterval(seconds), calendar: calendar) == expected,
                "Incorrect countdown at \(seconds) seconds remaining"
            )
        }

        let phrase = RemainingTime.phrase(
            from: now,
            until: date(2026, 9, 11, 17, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(!phrase.isEmpty, "Remaining phrase must not be empty")
        precondition(
            !phrase.contains("2026") && !phrase.contains("Sep"),
            "Remaining phrase must not include a calendar date"
        )
        print("Remaining-time thresholds passed")
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}
