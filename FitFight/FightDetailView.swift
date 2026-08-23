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
            VStack(alignment: .leading, spacing: 0) {
                if pendingJoin {
                    invitedHero
                } else {
                    liveHero
                }

                sectionGap
                FFSectionHeader(title: "Money right now", action: "if nothing changes", actionMuted: true)
                    .padding(.bottom, 10)
                moneyCard

                sectionGap
                FFSectionHeader(title: "Standings", action: fight.standingsMeta, actionMuted: true)
                    .padding(.bottom, 10)
                standingsCard

                if !fight.days.isEmpty {
                    sectionGap
                    FFSectionHeader(title: "Every day so far")
                        .padding(.bottom, 10)
                    daysCard
                }

                FFButton(title: "i challenge you", icon: "square.and.arrow.up") {}
                    .padding(.top, theme.space.sectionGap)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.xl)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sectionGap: some View {
        Color.clear.frame(height: 30)
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var nav: some View {
        HStack(spacing: 12) {
            Button {
                model.openFightID = nil
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Fights")
                        .font(.ff(13, .semibold))
                }
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(theme.chip, in: Capsule())
                .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }
            .buttonStyle(FFPressStyle(scale: 0.97))
            Spacer(minLength: 0)
            Text(fight.code)
                .font(.ff(11, .semibold))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
            Spacer(minLength: 0)
            FFIconButton(systemName: "square.and.arrow.up", size: 36) {}
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 16)
        .background(theme.bg)
    }

    private var invitedHero: some View {
        FFCard(padding: 24) {
            VStack(spacing: 0) {
                FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                    .padding(.top, 2)
                    .padding(.bottom, 6.5)
                heroTitle
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)
                if let pitch = fight.invitePitch {
                    Text(pitch)
                        .font(.ff(14))
                        .foregroundStyle(theme.text)
                        .padding(.bottom, 8)
                }
                Text("\(fight.lengthDays) days · \(fight.payoutLine)")
                    .font(.ff(13))
                    .foregroundStyle(theme.muted)
                    .padding(.bottom, 22)
                FFButton(title: fight.inviteAction == "Accept" ? "Accept challenge" : "Join fight") {
                    model.joined.insert(fight.id)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var liveHero: some View {
        FFCard(padding: 24) {
            VStack(spacing: 0) {
                FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                    .padding(.top, 2)
                    .padding(.bottom, 6.5)
                heroTitle
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, 27)
                FFRing(progress: ringProgress) {
                    VStack(spacing: 1) {
                        Text(fight.status == .finished ? "1st" : "#\(fight.rank)")
                            .font(.ff(34, .bold))
                            .foregroundStyle(theme.text)
                        Text("OF \(fight.of)")
                            .font(.ff(10, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(theme.muted)
                    }
                }
                .padding(.bottom, 24)
                FFKicker(
                    prefix: fight.kickerPrefix,
                    emphasis: fight.kickerEmphasis,
                    rest: fight.kickerRest,
                    size: 14
                )
                .padding(.bottom, 16)
                HStack(spacing: 8) {
                    FFStatTile(
                        value: model.formatScore(you?.score ?? 0, metric: fight.metric),
                        label: "Your total"
                    )
                    FFStatTile(
                        value: model.formatDelta(you?.today ?? 0, metric: fight.metric),
                        label: "Today"
                    )
                    FFStatTile(value: moneyTitle, label: "Standing to")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A shade larger than a screen title: the fight name is the hero of this screen.
    private var heroTitle: some View {
        Text(fight.name)
            .font(.ff(27, .bold))
            .tracking(-0.54)
            .foregroundStyle(theme.text)
    }

    private var ringProgress: CGFloat {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        if fight.settlement == .goal, let goal = fight.dailyGoal, goal > 0 {
            let elapsed = max(1, fight.lengthDays - (fight.daysLeft ?? 0))
            return min(1, CGFloat(yours / (goal * Double(elapsed))))
        }
        return leader == 0 ? 0 : CGFloat(yours / leader)
    }

    private var moneyTitle: String {
        if let you {
            if you.projectedNet > 0 { return "+$\(you.projectedNet)" }
            if you.projectedNet < 0 { return "−$\(abs(you.projectedNet))" }
        }
        return "even"
    }

    private var moneyColor: Color {
        guard let you else { return theme.faint }
        if you.projectedNet > 0 { return theme.green }
        if you.projectedNet < 0 { return theme.red }
        return theme.faint
    }

    private var moneyCard: some View {
        FFPanel {
            FFBand(vertical: 15) {
                Text(fight.payoutLine)
                    .font(.ff(12))
                    .foregroundStyle(theme.muted)
            }
            ForEach(Array(joinedStandings.enumerated()), id: \.element.id) { index, row in
                if index > 0 { FFHairline() }
                moneyRow(row)
            }
        }
    }

    private var joinedStandings: [Standing] {
        fight.standings.filter { !$0.invited }
    }

    private func moneyRow(_ row: Standing) -> some View {
        HStack(spacing: 10) {
            FFAvatar(row.person, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Text(model.paceLine(row, in: fight))
                    .font(.ff(11))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 8)
            if let safe = row.safe {
                FFBadge(text: safe ? "Safe" : "At risk", tone: safe ? .green : .red)
            } else {
                FFMoney(dollars: row.projectedNet, size: 13)
            }
        }
        .padding(.horizontal, FFMetric.rowPaddingX)
        .frame(height: 60)
        .background(row.person.isYou ? theme.selectedRow() : Color.clear)
    }

    private var standingsCard: some View {
        FFPanel {
            ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                if index > 0 { FFHairline() }
                standingRow(index: index, row: row)
            }
        }
    }

    private func standingRow(index: Int, row: Standing) -> some View {
        let isLead = index == 0 && !row.invited
        let maxScore = fight.standings.map(\.score).max() ?? 1
        let fill: Color = isLead ? theme.accent : (row.person.isYou ? theme.text : Color.white.opacity(0.45))
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(isLead ? theme.accent : theme.muted)
                    .frame(width: 22, alignment: .leading)
                FFAvatar(row.person, size: 26, pending: row.invited)
                Text(row.person.name)
                    .font(.ff(15, .semibold))
                    .foregroundStyle(row.invited ? theme.muted : theme.text)
                    .lineLimit(1)
                    .padding(.leading, 10)
                Spacer(minLength: 8)
                if row.invited {
                    FFBadge(text: "Invited", tone: .amber, style: .solid)
                } else {
                    if row.today != 0 {
                        Text(model.formatDelta(row.today, metric: fight.metric))
                            .font(.ff(12, .semibold))
                            .foregroundStyle(row.today > 0 ? theme.green : theme.red)
                            .padding(.trailing, 14)
                    }
                    Text(model.formatScore(row.score, metric: fight.metric))
                        .font(.ff(15, .bold))
                        .foregroundStyle(theme.text)
                }
            }
            .frame(height: 26)
            if !row.invited {
                FFProgressBar(
                    progress: maxScore == 0 ? 0 : CGFloat(row.score / maxScore),
                    fill: fill
                )
            }
        }
        .padding(.horizontal, FFMetric.rowPaddingX)
        .padding(.vertical, FFMetric.rowPaddingY)
        .background(row.person.isYou ? theme.selectedRow() : Color.clear)
    }

    private var daysCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(fight.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        Color.clear.frame(height: 22)
                    }
                    Text(day.label)
                        .font(.ff(11))
                        .foregroundStyle(theme.muted)
                        .padding(.bottom, 11)
                    let maxVal = day.scores.map(\.value).max() ?? 1
                    let leaderID = fight.standings.first?.person.id
                    VStack(spacing: 11.5) {
                        ForEach(day.scores) { row in
                            HStack(spacing: 0) {
                                Text(row.person.name)
                                    .font(.ff(11))
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(1)
                                    .frame(width: 56, alignment: .leading)
                                FFProgressBar(
                                    progress: maxVal == 0 ? 0 : CGFloat(row.value / maxVal),
                                    fill: row.person.id == leaderID ? theme.accent : Color.white.opacity(0.45)
                                )
                                Text(model.formatScore(row.value, metric: fight.metric))
                                    .font(.ff(11))
                                    .foregroundStyle(theme.muted)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .frame(height: 9)
                        }
                    }
                }
                if let note = fight.paceNote {
                    FFHairline()
                        .padding(.top, 24)
                        .padding(.bottom, 16)
                    Text(note)
                        .font(.ff(11))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }
}
