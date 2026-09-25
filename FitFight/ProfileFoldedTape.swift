import SwiftUI

/// Friend drawer header: both companions with their one-on-one wins above their heads,
/// then a tale-of-the-tape table. Draws only appear once there is one.
struct ProfileFoldedTape: View {
    let theirName: String
    let theirAnimal: StockCompanion?
    let yourAnimal: StockCompanion?
    /// Nil when the score is private or there is no one-on-one yet; `note` explains which.
    let rivalry: ProfileRivalry?
    let note: String?
    let yours: ProfileStepStatistics?
    let theirs: ProfileStepStatistics?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard {
            VStack(spacing: 14) {
                // Scores sit above each companion; the draw count only appears once there is one.
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    score(rivalry?.wins, name: String(appLocalized: "You"), color: theme.mossText)
                    score(rivalry?.losses, name: theirName, color: theme.emberText)
                }
                .overlay {
                    if let draws = rivalry?.draws, draws > 0 {
                        VStack(spacing: 2) {
                            Text("\(draws)").font(.ff(28, 800)).monospacedDigit().foregroundStyle(theme.textSecondary)
                            Text(draws == 1 ? String(appLocalized: "Draw") : String(appLocalized: "Draws")).ffType(.micro).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    art(yourAnimal)
                    art(theirAnimal)
                }
                if let note {
                    Text(note).ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                VStack(spacing: 0) {
                    HStack {
                        Text(String(appLocalized: "You"))
                        Spacer()
                        Text(verbatim: theirName)
                    }
                    .ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                    .padding(.bottom, 6)
                    row(String(appLocalized: "This week"), yours?.week.totalSteps, theirs?.week.totalSteps)
                    row(String(appLocalized: "Daily average"), yours?.averageSteps, theirs?.averageSteps)
                    row(String(appLocalized: "Best day"), yours?.bestDay?.steps, theirs?.bestDay?.steps)
                }
            }
        }
    }

    private func score(_ wins: Int?, name: String, color: Color) -> some View {
        VStack(spacing: 2) {
            if let wins {
                Text("\(wins)").font(.ff(44, 800)).monospacedDigit().foregroundStyle(color)
            }
            Text(verbatim: name).ffType(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func art(_ animal: StockCompanion?) -> some View {
        Group {
            if let animal {
                Image(animal.image).resizable().scaledToFit()
            } else {
                Image(systemName: "figure.walk").font(.system(size: 64)).foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    private func row(_ label: String, _ you: Double?, _ them: Double?) -> some View {
        let format = { (value: Double?) in
            value.map { $0.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)) } ?? String(appLocalized: "Private")
        }
        return VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack {
                Text(format(you)).font(.ff(17, 800)).monospacedDigit().foregroundStyle(you == nil ? theme.textSecondary : theme.text)
                Spacer()
                Text(label).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                Spacer()
                Text(format(them)).font(.ff(17, 800)).monospacedDigit().foregroundStyle(them == nil ? theme.textSecondary : theme.text)
            }
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
    }
}
