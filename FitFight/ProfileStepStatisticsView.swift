import SwiftUI

struct ProfileStepStatisticsView: View {
    let statistics: ProfileStepStatistics
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFSection(title: String(appLocalized: "Steps and streaks")) {
            FFCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statistics.scopeDays.map { String(format: String(appLocalized: "profile.steps-period"), $0) }
                        ?? String(appLocalized: "Your recorded history"))
                        .ffType(.label)
                    Text(String(appLocalized: "Completed days only, through yesterday. Missing or partial days never count as zero."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                    if let best = statistics.bestDay {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(appLocalized: "Best recorded day")).ffType(.caption).foregroundStyle(theme.textSecondary)
                            Text(best.steps.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)))
                                .ffType(.title).foregroundStyle(theme.gold)
                            Text(verbatim: best.day).ffType(.micro).foregroundStyle(theme.textSecondary)
                        }
                        if let average = statistics.averageSteps {
                            LabeledContent(String(appLocalized: "Average per recorded day"), value: average.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)))
                                .ffType(.label)
                        }
                    } else {
                        Text(String(appLocalized: "No completed days recorded yet")).ffType(.body)
                    }
                    if let from = statistics.from {
                        Text(String(format: String(appLocalized: "profile.stats-coverage"), statistics.recordedDays, statistics.unknownDays))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        Text(verbatim: "\(from) - \(statistics.through)")
                            .ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(appLocalized: "This week")).ffType(.label)
                        if let average = statistics.week.averageSteps {
                            LabeledContent(String(appLocalized: "Average steps per day"), value: average.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)))
                                .ffType(.label)
                            LabeledContent(String(appLocalized: "Recorded steps"), value: statistics.week.totalSteps.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)))
                                .ffType(.label)
                        }
                        Text(String(format: String(appLocalized: "profile.stats-week-coverage"), statistics.week.recordedDays, statistics.week.elapsedDays))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        Text(String(appLocalized: "Monday to yesterday. Averages use recorded days only."))
                            .ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(appLocalized: "Days by activity level")).ffType(.label)
                        ForEach(statistics.levels) { level in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(levelName(level.level)).ffType(.label)
                                    Spacer(minLength: 8)
                                    Text(String(format: String(appLocalized: "profile.stats-level-days"), level.days))
                                        .ffType(.caption)
                                    if let share = level.share {
                                        Text(share.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale))).ffType(.caption)
                                    }
                                }
                                Text(level.minimumSteps == 8_000
                                    ? String(appLocalized: "8,000+ steps")
                                    : String(format: String(appLocalized: "profile.stats-level-range"), level.minimumSteps, level.minimumSteps + 1_999))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                if let share = level.share {
                                    ProgressView(value: share).tint(theme.gold).accessibilityHidden(true)
                                }
                                Text(String(format: String(appLocalized: "profile.stats-streak-best"), level.longestStreak))
                                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                                if let current = level.currentStreak, current > 0 {
                                    Text(String(format: String(appLocalized: "profile.stats-streak-current"), current))
                                        .ffType(.caption).foregroundStyle(theme.gold)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text(String(appLocalized: "A streak is consecutive recorded days in the same level. Unknown days interrupt the record."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        if statistics.levels.contains(where: { $0.currentStreak == nil }) {
                            Text(String(appLocalized: "Current streak unavailable until yesterday is complete."))
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
        case "couch": String(appLocalized: "profile.stats-level-couch")
        case "warming_up": String(appLocalized: "profile.stats-level-warming-up")
        case "moving": String(appLocalized: "profile.stats-level-moving")
        case "active": String(appLocalized: "profile.stats-level-active")
        case "ripped": String(appLocalized: "profile.stats-level-ripped")
        default: level
        }
    }
}
