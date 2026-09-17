import SwiftUI

struct ProfileStepStatisticsView: View {
    let statistics: ProfileStepStatistics
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFSection(title: String(localized: "Steps and streaks")) {
            FFCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statistics.scopeDays.map { String(format: String(localized: "profile.steps-period"), $0) }
                        ?? String(localized: "Your recorded history"))
                        .ffType(.label)
                    Text(String(localized: "Completed days only, through yesterday. Missing or partial days never count as zero."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                    if let best = statistics.bestDay {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Best recorded day")).ffType(.caption).foregroundStyle(theme.textSecondary)
                            Text(best.steps.formatted(.number.precision(.fractionLength(0))))
                                .ffType(.title).foregroundStyle(theme.gold)
                            Text(verbatim: best.day).ffType(.micro).foregroundStyle(theme.textSecondary)
                        }
                        if let average = statistics.averageSteps {
                            LabeledContent(String(localized: "Average per recorded day"), value: average.formatted(.number.precision(.fractionLength(0))))
                                .ffType(.label)
                        }
                    } else {
                        Text(String(localized: "No completed days recorded yet")).ffType(.body)
                    }
                    if let from = statistics.from {
                        Text(String(format: String(localized: "profile.stats-coverage"), statistics.recordedDays, statistics.unknownDays))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        Text(verbatim: "\(from) - \(statistics.through)")
                            .ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "This week")).ffType(.label)
                        if let average = statistics.week.averageSteps {
                            LabeledContent(String(localized: "Average steps per day"), value: average.formatted(.number.precision(.fractionLength(0))))
                                .ffType(.label)
                            LabeledContent(String(localized: "Recorded steps"), value: statistics.week.totalSteps.formatted(.number.precision(.fractionLength(0))))
                                .ffType(.label)
                        }
                        Text(String(format: String(localized: "profile.stats-week-coverage"), statistics.week.recordedDays, statistics.week.elapsedDays))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        Text(String(localized: "Monday to yesterday. Averages use recorded days only."))
                            .ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "Days by activity level")).ffType(.label)
                        ForEach(statistics.levels) { level in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(levelName(level.level)).ffType(.label)
                                    Spacer(minLength: 8)
                                    Text(String(format: String(localized: "profile.stats-level-days"), level.days))
                                        .ffType(.caption)
                                    if let share = level.share {
                                        Text(share.formatted(.percent.precision(.fractionLength(0)))).ffType(.caption)
                                    }
                                }
                                Text(level.minimumSteps == 8_000
                                    ? String(localized: "8,000+ steps")
                                    : String(format: String(localized: "profile.stats-level-range"), level.minimumSteps, level.minimumSteps + 1_999))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                if let share = level.share {
                                    ProgressView(value: share).tint(theme.gold).accessibilityHidden(true)
                                }
                                Text(String(format: String(localized: "profile.stats-streak-best"), level.longestStreak))
                                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                                if let current = level.currentStreak, current > 0 {
                                    Text(String(format: String(localized: "profile.stats-streak-current"), current))
                                        .ffType(.caption).foregroundStyle(theme.gold)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text(String(localized: "A streak is consecutive recorded days in the same level. Unknown days interrupt the record."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        if statistics.levels.contains(where: { $0.currentStreak == nil }) {
                            Text(String(localized: "Current streak unavailable until yesterday is complete."))
                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func levelName(_ level: String) -> String {
        switch level {
        case "couch": String(localized: "profile.stats-level-couch")
        case "warming_up": String(localized: "profile.stats-level-warming-up")
        case "moving": String(localized: "profile.stats-level-moving")
        case "active": String(localized: "profile.stats-level-active")
        case "ripped": String(localized: "profile.stats-level-ripped")
        default: level
        }
    }
}
