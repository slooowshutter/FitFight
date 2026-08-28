import SwiftUI

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 19)

                if model.live.isEmpty && model.invitations.isEmpty && model.finished.isEmpty {
                    Text("No fights yet. Start one under New. Add people with their username — they must have signed in once.")
                        .font(.ff(13))
                        .foregroundStyle(theme.faint)
                        .padding(.bottom, 16)
                }

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
                    FFSectionHeader(title: "Invitations", inset: 0)
                        .padding(.top, theme.space.sectionGap)
                        .padding(.bottom, 12)
                    VStack(spacing: 10) {
                        ForEach(model.invitations) { fight in
                            InvitationRow(fight: fight)
                        }
                    }
                }

                if !model.finished.isEmpty {
                    FFSectionHeader(title: "Finished", inset: 0)
                        .padding(.top, theme.space.sectionGap)
                        .padding(.bottom, 12)
                    VStack(spacing: 10) {
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
        .refreshable {
            await steps.refresh(requestAccess: false)
            if let userId = session.authSession?.user.id {
                await steps.syncToSupabase(client: session.client, userId: userId)
            }
            await model.refreshFromServer(session: session)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                FFLabel(text: "\(model.live.count) live fights", role: .display)
                HStack(spacing: 5) {
                    Text("If it ends like this you're")
                        .font(.ff(13))
                        .foregroundStyle(theme.faint)
                    FFMoney(dollars: model.projectedNet, size: 13)
                }
            }
            Spacer(minLength: 0)
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
                        FFLabel(text: fight.metric.eyebrow, role: .eyebrow)
                            .padding(.top, 2)
                            .padding(.bottom, 6.5)
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
                            .font(.ff(10, .semibold))
                            .foregroundStyle(theme.amber)
                            .padding(.horizontal, 5)
                            .frame(height: 19)
                            .background(theme.amber.opacity(0.12), in: Capsule())
                    }
                }
                // Fixed so the pending pill does not make this card taller than
                // the ones without it, the way it does in the mock.
                .frame(height: 19)
                .padding(.top, 10.5)

                VStack(spacing: FFMetric.miniRowGap) {
                    ForEach(Array(visibleStandings.enumerated()), id: \.element.id) { index, row in
                        miniRow(index: index, row: row)
                    }
                }
                .padding(.top, 20.5)

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more")
                        .font(.ff(11))
                        .foregroundStyle(theme.faint)
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
                                .font(.ff(12))
                                .foregroundStyle(theme.faint)
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
        max(0, fight.standings.count - 3)
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
            FFAvatar(row.person, size: FFMetric.miniAvatar)
            Text(row.person.name)
                .font(.ff(12, .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.leading, FFMetric.miniNameGap)
                .frame(width: FFMetric.miniNameWidth + FFMetric.miniNameGap, alignment: .leading)
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
        FFCard(padding: 13.5, horizontal: 16) {
            HStack(spacing: 12) {
                FFAvatar(fight.standings.first?.person, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.name)
                        .font(.ff(14, .bold))
                        .foregroundStyle(theme.text)
                    Text(fight.listSubtitle)
                        .font(.ff(11))
                        .foregroundStyle(theme.muted)
                }
                Spacer(minLength: 8)
                FFButton(title: fight.inviteAction ?? "Join", kind: .small) {
                    Task { await model.acceptFight(id: fight.id) }
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
            FFCard(padding: 13.5, horizontal: 16) {
                HStack(spacing: 12) {
                    let won = fight.youWon
                    Text(won ? "W" : "L")
                        .font(.ff(13, .bold))
                        .foregroundStyle(won ? theme.green : theme.red)
                        .frame(width: 36, height: 36)
                        .background(
                            (won ? theme.green : theme.red).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fight.name)
                            .font(.ff(14, .bold))
                            .foregroundStyle(theme.text)
                        Text(fight.listSubtitle)
                            .font(.ff(11))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: -8) {
                        ForEach(fight.standings.prefix(2)) { row in
                            FFAvatar(row.person, size: 26)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
