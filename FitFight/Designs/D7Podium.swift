import SwiftUI

/// Podium — the leaderboard is the hero. The fight where the money is biggest gets
/// a gold-silver-bronze podium at the top; everything else collapses to a row.
struct PodiumFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let feature {
                    Button { model.openFightID = feature.id } label: {
                        PodiumHero(fight: feature)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.99))
                }

                PodiumHeading(text: "Other fights")
                VStack(spacing: 8) {
                    ForEach(model.live.filter { $0.id != feature?.id }) { fight in
                        Button { model.openFightID = fight.id } label: {
                            PodiumRow(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.99))
                    }
                }

                if !model.invitations.isEmpty {
                    PodiumHeading(text: "Invitations")
                    VStack(spacing: 8) {
                        ForEach(model.invitations) { fight in
                            Button { model.openFightID = fight.id } label: {
                                PodiumRow(fight: fight, invite: true)
                            }
                            .buttonStyle(FFPressStyle(scale: 0.99))
                        }
                    }
                }

                if !model.finished.isEmpty {
                    PodiumHeading(text: "Hall of fame")
                    VStack(spacing: 8) {
                        ForEach(model.finished) { fight in
                            Button { model.openFightID = fight.id } label: {
                                PodiumRow(fight: fight)
                            }
                            .buttonStyle(FFPressStyle(scale: 0.99))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    /// Biggest pot wins the hero slot — that is the one worth looking at.
    private var feature: Fight? {
        model.live.max { $0.pot < $1.pot }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Standings")
                .font(.ff(28, .bold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 8)
            Text(net)
                .font(.ff(14, .bold))
                .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(theme.chip, in: Capsule())
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct PodiumHeading: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.ff(10, .bold))
            .tracking(1.6)
            .foregroundStyle(theme.faint)
            .padding(.top, 26)
            .padding(.bottom, 10)
    }
}

private struct PodiumHero: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    private let heights: [CGFloat] = [96, 128, 72]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fight.metric.eyebrow.uppercased())
                    .font(.ff(9, .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)
                Text(fight.name)
                    .font(.ff(22, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            podium
                .padding(.top, 22)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                Text("$\(fight.pot) pot")
                    .font(.ff(12, .semibold))
                    .foregroundStyle(theme.text)
                Text(" · \(fight.daysLeft ?? 0)d left")
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
                Spacer(minLength: 8)
                Text(pnl)
                    .font(.ff(13, .bold))
                    .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(theme.chip)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        }
    }

    /// Second, first, third — the way a real podium is arranged.
    private var order: [Standing?] {
        let ranked = fight.ranked
        return [ranked[safe: 1], ranked[safe: 0], ranked[safe: 2]]
    }

    private var podium: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(order.enumerated()), id: \.offset) { index, row in
                step(index: index, row: row)
            }
        }
    }

    private func step(index: Int, row: Standing?) -> some View {
        let place = [2, 1, 3][index]
        let medal = [theme.muted, theme.accent, Color(hex: "#b4732f")][index]
        return VStack(spacing: 7) {
            if let row {
                FFAvatar(row.person, size: index == 1 ? 44 : 36, ring: index == 1)
                Text(row.person.name)
                    .font(.ff(11, .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(model.formatScore(row.score, metric: fight.metric))
                    .font(.ff(12, .bold))
                    .foregroundStyle(medal)
            } else {
                Circle().fill(theme.chip).frame(width: 36, height: 36)
                Text("Open")
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
            }
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.surface2)
                    .frame(height: heights[index])
                // Your step gets a lit edge rather than a tinted block, which went
                // muddy where a gold wash met the navy surface.
                if row?.person.isYou == true {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.accent)
                        .frame(height: 3)
                }
                Text("\(place)")
                    .font(.ff(20, .heavy))
                    .foregroundStyle(medal)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct PodiumRow: View {
    let fight: Fight
    var invite = false

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(invite ? "—" : "\(fight.yourPlace ?? fight.rank)")
                .font(.ff(15, .bold))
                .foregroundStyle(fight.yourPlace == 1 ? theme.ink : theme.text)
                .frame(width: 34, height: 34)
                .background(
                    fight.yourPlace == 1 && !invite ? theme.accent : theme.chip,
                    in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name)
                    .font(.ff(14, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if invite {
                Text(fight.inviteAction ?? "Join")
                    .font(.ff(12, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(theme.accent, in: Capsule())
            } else {
                Text(pnl)
                    .font(.ff(13, .bold))
                    .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        }
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
