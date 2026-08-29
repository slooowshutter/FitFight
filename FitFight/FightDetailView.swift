import SwiftUI

struct FightDetailView: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    private var pendingJoin: Bool {
        fight.status == .invited && !model.joined.contains(fight.id)
    }

    var body: some View {
        FFScreen(top: AnyView(nav)) {
            if pendingJoin {
                invitedHero
            } else if let pair = headToHead {
                FFVSBlock(
                    you: pair.you,
                    them: pair.them,
                    delta: fight.kickerEmphasis,
                    ahead: fight.rank == 1,
                    footnote: "\(fight.metric.eyebrow) · \(fight.lengthDays) day fight",
                    timeLeft: timeLeft
                )
                statTiles
            } else {
                liveHero
                statTiles
            }

            FFSectionHeader(title: "Money right now")
                .padding(.top, theme.space.lg)
            Text(fight.payoutLine)
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            moneyCard

            FFSectionHeader(title: "Standings")
                .padding(.top, theme.space.lg)
            if let meta = fight.standingsMeta {
                Text(meta)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                standingRow(index: index, row: row)
            }

            if !fight.days.isEmpty {
                FFSectionHeader(title: "Every day so far")
                    .padding(.top, theme.space.lg)
                daysCard
            }

            FFScreenCTA(title: "I challenge you") {}
                .padding(.top, theme.space.lg)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var timeLeft: String {
        if let days = fight.daysLeft { return "\(days) days left" }
        return fight.endedLabel ?? "Ended"
    }

    private var nav: some View {
        FFNavDetail(
            title: fight.name,
            subtitle: timeLeft,
            onBack: { model.openFightID = nil },
            onMore: {}
        )
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 12)
        .background(theme.bg)
    }

    /// The kit's VS block only makes sense for two people.
    private var headToHead: (
        you: (monogram: String, name: String, value: String, progress: Double),
        them: (monogram: String, name: String, value: String, progress: Double)
    )? {
        let joined = fight.standings.filter { !$0.invited }
        guard joined.count == 2,
              let mine = joined.first(where: { $0.person.isYou }),
              let theirs = joined.first(where: { !$0.person.isYou })
        else { return nil }
        let peak = max(mine.score, theirs.score, 1)
        return (
            (mine.person.initials, "You", model.formatScore(mine.score, metric: fight.metric), mine.score / peak),
            (theirs.person.initials, theirs.person.name, model.formatScore(theirs.score, metric: fight.metric), theirs.score / peak)
        )
    }

    private var invitedHero: some View {
        FFCard(padding: 24) {
            VStack(spacing: 0) {
                FFTag(fight.metric.eyebrow)
                    .padding(.bottom, 12)
                Text(fight.name)
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                if let pitch = fight.invitePitch {
                    Text(pitch)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                Text("\(fight.lengthDays) days · \(fight.payoutLine)")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)
                FFScreenCTA(title: fight.inviteAction == "Accept" ? "Accept challenge" : "Join fight") {
                    Task {
                        await model.acceptFight(id: fight.id)
                        if (model.createError ?? "").isEmpty {
                            model.joined.insert(fight.id)
                            await model.refreshFromServer()
                        }
                    }
                }
                if let error = model.createError, !error.isEmpty {
                    Text(error)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var liveHero: some View {
        FFRingCard(
            progress: ringProgress,
            title: fight.status == .finished ? "Finished \(fight.rank == 1 ? "first" : "#\(fight.rank)")" : "#\(fight.rank) of \(fight.of)",
            subtitle: "\(fight.metric.eyebrow) · \(timeLeft)",
            metric: model.formatScore(you?.score ?? 0, metric: fight.metric),
            delta: fight.kickerEmphasis,
            ahead: fight.rank == 1
        )
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            FFStatTile(
                tag: "Total", tone: .moss,
                title: fight.metric.title, metric: model.formatScore(you?.score ?? 0, metric: fight.metric),
                caption: "\(fight.lengthDays) day total"
            )
            FFStatTile(
                tag: "Today", tone: (you?.today ?? 0) >= 0 ? .moss : .ember,
                title: fight.metric.title, metric: model.formatDelta(you?.today ?? 0, metric: fight.metric),
                caption: "since midnight"
            )
        }
    }

    private var ringProgress: Double {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        if fight.settlement == .goal, let goal = fight.dailyGoal, goal > 0 {
            let elapsed = max(1, fight.lengthDays - (fight.daysLeft ?? 0))
            return min(1, yours / (goal * Double(elapsed)))
        }
        return leader == 0 ? 0 : min(yours / leader, 1)
    }

    private var joinedStandings: [Standing] {
        fight.standings.filter { !$0.invited }
    }

    private var moneyCard: some View {
        FFGroupedRows {
            ForEach(Array(joinedStandings.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    FFDivider(
                        visible: !joinedStandings[index - 1].person.isYou && !row.person.isYou
                    )
                }
                moneyRow(row)
            }
        }
    }

    private func moneyRow(_ row: Standing) -> some View {
        HStack(spacing: 12) {
            FFAvatar(row.person, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Text(model.paceLine(row, in: fight))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            if let safe = row.safe {
                FFPill(safe ? "Safe" : "At risk", style: safe ? .softMoss : .softEmber)
            } else {
                FFMoney(dollars: row.projectedNet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .ffRowSelection(
            row.person.isYou,
            outerRadius: theme.radius.card,
            fill: theme.mossWash
        )
    }

    private func standingRow(index: Int, row: Standing) -> some View {
        Group {
            if row.invited {
                HStack(spacing: 13) {
                    Text("—")
                        .ffType(.button)
                        .foregroundStyle(theme.textFaint)
                        .frame(width: 22)
                    FFAvatar(row.person, size: 38, pending: true)
                    Text(row.person.name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FFPill("Invited", style: .gold)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(theme.hairline, radius: theme.radius.card)
            } else {
                FFLeaderboardRow(
                    rank: index + 1,
                    monogram: row.person.initials,
                    name: row.person.name,
                    value: model.formatScore(row.score, metric: fight.metric),
                    move: .same,
                    isYou: row.person.isYou
                )
            }
        }
    }

    private var daysCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(fight.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { Color.clear.frame(height: 20) }
                    FFEyebrow(day.label)
                        .padding(.bottom, 12)
                    let peak = day.scores.map(\.value).max() ?? 1
                    let leaderID = fight.standings.first?.person.id
                    VStack(spacing: 10) {
                        ForEach(day.scores) { row in
                            HStack(spacing: 10) {
                                Text(row.person.name)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: 56, alignment: .leading)
                                FFProgressBar(
                                    value: peak == 0 ? 0 : row.value / peak,
                                    fill: row.person.id == leaderID ? theme.mossFill : theme.textFaint
                                )
                                Text(model.formatScore(row.value, metric: fight.metric))
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 56, alignment: .trailing)
                            }
                        }
                    }
                }
                if let note = fight.paceNote {
                    FFDivider(inset: 0)
                        .padding(.vertical, 18)
                    Text(note)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }
}
