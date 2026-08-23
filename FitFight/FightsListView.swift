import SwiftUI

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 19)

                VStack(spacing: theme.space.cardGap) {
                    ForEach(model.live) { fight in
                        Button {
                            model.openFightID = fight.id
                        } label: {
                            LiveFightCard(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.985))
                    }
                }

                if !model.invitations.isEmpty {
                    FFSectionHeader(title: "Invitations")
                        .padding(.top, theme.space.sectionGap)
                        .padding(.bottom, 12)
                    VStack(spacing: theme.space.cardGap) {
                        ForEach(model.invitations) { fight in
                            InvitationRow(fight: fight)
                        }
                    }
                }

                if !model.finished.isEmpty {
                    FFSectionHeader(title: "Finished")
                        .padding(.top, theme.space.sectionGap)
                        .padding(.bottom, 12)
                    VStack(spacing: theme.space.cardGap) {
                        ForEach(model.finished) { fight in
                            FinishedRow(fight: fight)
                        }
                    }
                    .opacity(0.85)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.xl)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                FFLabel(text: "\(model.live.count) live fights", role: .display)
                HStack(spacing: 5) {
                    Text("If it ends like this you're")
                        .font(.ff(14))
                        .foregroundStyle(theme.muted)
                    FFMoney(dollars: model.projectedNet, size: 14)
                }
            }
            Spacer(minLength: 0)
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.text)
                    .frame(width: 40, height: 40)
                    .background(theme.chip, in: Circle())
                    .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
                Circle()
                    .fill(theme.red)
                    .frame(width: 7, height: 7)
                    .offset(x: -6, y: 6)
            }
        }
        .padding(.top, 2)
    }
}

/// A live fight: kicker, name, meta line, three standings rows, tinted footer band.
struct LiveFightCard: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                            .padding(.bottom, 9)
                        FFLabel(text: fight.name, role: .title)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 0)
                    FFRankBadge(rank: fight.rank, of: fight.of)
                }

                HStack(spacing: 0) {
                    meta(icon: "clock", text: "\(fight.daysLeft ?? 0)d left")
                    dot
                    meta(icon: "dollarsign.circle", text: "$\(fight.pot)")
                    dot
                    Text(fight.settlement.title)
                        .font(.ff(12))
                        .foregroundStyle(theme.muted)
                    Spacer(minLength: 8)
                    if fight.pending > 0 {
                        Text("\(fight.pending) pending")
                            .font(.ff(12, .semibold))
                            .foregroundStyle(theme.amber)
                            .padding(.horizontal, 8)
                            .frame(height: 19)
                            .background(theme.amber.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.top, 17)

                VStack(spacing: FFMetric.miniRowGap) {
                    ForEach(Array(visibleStandings.enumerated()), id: \.element.id) { index, row in
                        miniRow(index: index, row: row)
                    }
                }
                .padding(.top, 26)

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more")
                        .font(.ff(12))
                        .foregroundStyle(theme.muted)
                        .padding(.top, 11)
                }
            }
            .padding(FFMetric.cardPadding)

            FFBand {
                HStack(spacing: 0) {
                    FFKicker(
                        prefix: fight.kickerPrefix,
                        emphasis: fight.kickerEmphasis,
                        rest: fight.kickerRest
                    )
                    Spacer(minLength: 8)
                    if let you = model.youStanding(in: fight) {
                        HStack(spacing: 6) {
                            FFMoney(dollars: you.projectedNet)
                            Text("right now")
                                .font(.ff(13))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
            }
        }
    }

    private var joined: [Standing] {
        fight.standings.filter { !$0.invited }
    }

    private var visibleStandings: [Standing] {
        Array(joined.prefix(3))
    }

    private var hiddenCount: Int {
        max(0, joined.count - 3)
    }

    private var dot: some View {
        Text("·")
            .font(.ff(12))
            .foregroundStyle(theme.faint)
            .padding(.horizontal, 7)
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .regular))
            Text(text)
                .font(.ff(12))
        }
        .foregroundStyle(theme.muted)
    }

    private func miniRow(index: Int, row: Standing) -> some View {
        let maxScore = joined.map(\.score).max() ?? 1
        let isLead = index == 0
        let fill: Color = isLead ? theme.accent : (row.person.isYou ? theme.text : Color.white.opacity(0.45))
        return HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.ff(12, .semibold))
                .foregroundStyle(isLead ? theme.accent : theme.muted)
                .frame(width: FFMetric.miniRankWidth, alignment: .leading)
            FFAvatar(initials: row.person.initials, size: FFMetric.miniAvatar)
            Text(row.person.name)
                .font(.ff(12, .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.leading, 8)
                .frame(width: FFMetric.miniNameWidth + 8, alignment: .leading)
            FFProgressBar(
                progress: maxScore == 0 ? 0 : CGFloat(row.score / maxScore),
                fill: fill
            )
            Text(model.formatScore(row.score, metric: fight.metric))
                .font(.ff(12, .bold))
                .foregroundStyle(theme.text)
                .frame(width: FFMetric.miniValueWidth, alignment: .trailing)
        }
        .frame(height: FFMetric.miniRowHeight)
    }
}

struct InvitationRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard(padding: 16) {
            HStack(spacing: 12) {
                FFAvatar(initials: fight.standings.first?.person.initials ?? "?", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.name)
                        .font(.ff(17, .bold))
                        .foregroundStyle(theme.text)
                    Text(fight.listSubtitle)
                        .font(.ff(13))
                        .foregroundStyle(theme.muted)
                }
                Spacer(minLength: 8)
                FFButton(title: fight.inviteAction ?? "Join", kind: .small) {
                    model.openFightID = fight.id
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.openFightID = fight.id
        }
    }
}

struct FinishedRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            model.openFightID = fight.id
        } label: {
            FFCard(padding: 16) {
                HStack(spacing: 12) {
                    Text("W")
                        .font(.ff(15, .bold))
                        .foregroundStyle(theme.green)
                        .frame(width: 40, height: 40)
                        .background(theme.green.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fight.name)
                            .font(.ff(17, .bold))
                            .foregroundStyle(theme.text)
                        Text(fight.listSubtitle)
                            .font(.ff(13))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: -8) {
                        ForEach(fight.standings.prefix(2)) { row in
                            FFAvatar(initials: row.person.initials, size: 26)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
