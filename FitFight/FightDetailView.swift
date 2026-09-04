import SwiftUI

struct FightDetailView: View {
    private let initialFight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    init(fight: Fight) {
        initialFight = fight
    }

    private var fight: Fight {
        model.fight(id: initialFight.id) ?? initialFight
    }

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
                    footnote: "\(fight.metric.eyebrow) · \(fight.durationLabel) fight",
                    timeLeft: fight.timeLeftLabel
                )
            } else {
                liveHero
            }

            if !pendingJoin {
                FFSectionHeader(title: String(localized: "Action"))
                    .padding(.top, theme.space.lg)
                FFCard {
                    Text(fight.actionText)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FFSectionHeader(title: String(localized: "Standings"))
                    .padding(.top, theme.space.lg)
                if let meta = fight.standingsMeta {
                    Text(meta)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                        standingRow(index: index, row: row, now: context.date)
                    }
                }

                if !fight.days.isEmpty {
                    FFSectionHeader(title: String(localized: "Every day so far"))
                        .padding(.top, theme.space.lg)
                    daysCard
                }
            }
        }
        .refreshable {
            await model.refreshFights(session: session, steps: steps)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var nav: some View {
        FFNavDetail(
            title: fight.name,
            subtitle: fight.timeLeftLabel,
            onBack: { model.openFightID = nil }
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
            (mine.person.initials, String(localized: "You"), model.formatScore(mine.score, metric: fight.metric), mine.score / peak),
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
                Text(
                    String(
                        localized: "fight.duration-rule",
                        defaultValue: "\(fight.durationLabel) · Most steps wins"
                    )
                )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text(fight.actionText)
                    .ffType(.body)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)
                FFScreenCTA(title: String(localized: "Accept challenge")) {
                    Task {
                        await model.acceptFight(id: fight.id)
                        if (model.createError ?? "").isEmpty {
                            model.joined.insert(fight.id)
                        }
                    }
                }
                FFButton(title: String(localized: "Decline"), kind: .ghost, fullWidth: true) {
                    Task {
                        await model.declineFight(id: fight.id)
                        if (model.createError ?? "").isEmpty {
                            model.openFightID = nil
                        }
                    }
                }
                .padding(.top, 8)
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
            title: fight.status == .finished
                ? String(
                    localized: "fight.finished-rank",
                    defaultValue: "Finished #\(fight.rank)"
                )
                : String(
                    localized: "fight.rank-of-count",
                    defaultValue: "#\(fight.rank) of \(fight.of)"
                ),
            subtitle: String(
                localized: "fight.metric-time-left",
                defaultValue: "\(fight.metric.eyebrow) · \(fight.timeLeftLabel)"
            ),
            metric: model.formatScore(you?.score ?? 0, metric: fight.metric),
            delta: fight.kickerEmphasis,
            ahead: fight.rank == 1
        )
    }

    private var ringProgress: Double {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        return leader == 0 ? 0 : min(yours / leader, 1)
    }

    private func standingRow(index: Int, row: Standing, now: Date) -> some View {
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
                    FFPill(String(localized: "Invited"), style: .gold)
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
                    isYou: row.person.isYou,
                    caption: model.formatStandingFreshness(row, fight: fight, now: now),
                    captionUrgent: false
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
