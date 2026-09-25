import SwiftUI

// Sections 08 and 09 of the kit: progress, comparison and ranking.

// MARK: - Progress

/// One bar, four contexts. Gold on a moss fill, ember or moss on a card.
/// The track is always the same 9% white.
struct FFProgressBar: View {
    let value: Double
    var height: CGFloat = 7
    var fill: Color?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let fraction = min(max(value, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(fill ?? theme.mossFill)
                    .frame(width: geo.size.width * fraction)
                    .id(fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Comparison

/// Leaderboard row — you are always highlighted, rank 1 takes gold ink.
/// The row never names its own metric; the screen header does.
struct FFLeaderboardRow: View {
    let rank: Int
    let monogram: String
    let name: String
    let value: String
    var isYou: Bool = false
    /// Consecutive previous-round wins: one trophy, with ×N when N > 1.
    var trophies: Int = 0
    var avatar: AnyView? = nil
    var captionUrgent: Bool = false
    var captionAt: ((Date) -> String)? = nil
    /// Nested rows subtract their inset from the outer card radius.
    var radius: CGFloat? = nil

    @Environment(\.ffTheme) private var theme

    private var corner: CGFloat { radius ?? theme.radius.card }

    var body: some View {
        HStack(spacing: 13) {
            Text("\(rank)")
                .ffType(.button)
                .foregroundStyle(rank == 1 ? theme.gold : theme.textTertiary)
                .frame(width: 22)
            if let avatar { avatar } else { FFAvatar(monogram: monogram, size: 38) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if trophies > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12, weight: .bold))
                            if trophies > 1 {
                                Text("×\(trophies)")
                                    .ffType(.micro)
                                    .fontWeight(.heavy)
                            }
                        }
                        .foregroundStyle(theme.mossText)
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(
                            appLocalized: "fight.trophies",
                            defaultValue: "Won the last \(trophies) rounds"
                        ))
                    }
                }
                if let captionAt {
                    // NOTE: Only the freshness line belongs in TimelineView. Wrapping
                    // scores in a 30s schedule leaves standings stale after a sync.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        captionText(captionAt(context.date))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("-")
                .ffType(.micro)
                .fontWeight(.heavy)
                .foregroundStyle(theme.textFaint)
            Text(value)
                .font(.ff(17, 800))
                .tracking(17 * -0.02)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            isYou ? theme.mossWash : theme.card,
            in: RoundedRectangle(cornerRadius: corner, style: .continuous)
        )
        .ffBorder(isYou ? theme.mossEdge : theme.hairline, radius: corner)
    }

    @ViewBuilder
    private func captionText(_ caption: String) -> some View {
        if !caption.isEmpty {
            Text(caption)
                .ffType(.micro)
                .foregroundStyle(captionUrgent ? theme.emberText : theme.textSecondary)
                .lineLimit(1)
        }
    }
}
