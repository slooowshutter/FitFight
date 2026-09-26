import Foundation

enum RemainingTime {
    struct Breakdown: Equatable {
        var months: Int = 0
        var weeks: Int = 0
        var days: Int = 0
        var hours: Int = 0
        var minutes: Int = 0
    }

    /// Use one coarse unit, adding hours only below two days and minutes only below two hours.
    static func breakdown(
        from now: Date = Date(),
        until end: Date,
        calendar: Calendar = .current
    ) -> Breakdown {
        guard end > now else { return Breakdown() }

        let remaining = calendar.dateComponents(
            [.month, .day, .hour, .minute],
            from: now,
            to: end
        )
        let months = max(0, remaining.month ?? 0)
        let totalDays = max(0, remaining.day ?? 0)
        let weeks = totalDays / 7
        let hours = max(0, remaining.hour ?? 0)
        let minutes = max(0, remaining.minute ?? 0)

        if months > 0 { return Breakdown(months: months) }
        if weeks > 0 { return Breakdown(weeks: weeks) }
        if totalDays >= 2 { return Breakdown(days: totalDays) }
        if totalDays >= 1 {
            return Breakdown(days: totalDays, hours: hours)
        }
        if hours >= 2 { return Breakdown(hours: hours) }
        if hours == 1 {
            return Breakdown(hours: hours, minutes: minutes)
        }
        return Breakdown(minutes: max(1, minutes))
    }

    static func phrase(
        from now: Date = Date(),
        until end: Date,
        calendar: Calendar = .current
    ) -> String {
        let parts = breakdown(from: now, until: end, calendar: calendar)
        var labels: [String] = []
        if parts.months > 0 {
            labels.append(
                String(appLocalized: "duration.months", defaultValue: "\(parts.months) months")
            )
        }
        if parts.weeks > 0 {
            labels.append(
                String(appLocalized: "duration.weeks", defaultValue: "\(parts.weeks) weeks")
            )
        }
        if parts.days > 0 {
            labels.append(
                String(appLocalized: "duration.days", defaultValue: "\(parts.days) days")
            )
        }
        if parts.hours > 0 {
            labels.append(
                String(appLocalized: "duration.hours", defaultValue: "\(parts.hours) hours")
            )
        }
        if parts.minutes > 0 {
            labels.append(
                String(appLocalized: "duration.minutes", defaultValue: "\(parts.minutes) minutes")
            )
        }
        let list = ListFormatter()
        list.locale = AppLocalization.locale
        return list.string(from: labels) ?? labels.joined(separator: ", ")
    }
}
