import SwiftUI

struct FightDetailView: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    private var pendingJoin: Bool {
        fight.status == .invited && !model.joined.contains(fight.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                if pendingJoin {
                    invitedHero
                } else {
                    liveHero
                }
                moneyNow
                standings
                if !fight.days.isEmpty {
                    days
                }
                FFButton(title: "i challenge you", icon: "square.and.arrow.up") {}
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.xl)
        }
        .background(theme.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            nav
        }
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var nav: some View {
        HStack {
            Button {
                model.openFightID = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Fights")
                }
                .font(theme.font(.bodyStrong))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay {
                    Capsule().strokeBorder(theme.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            FFLabel(text: fight.code, role: .eyebrow, color: theme.muted)
            Spacer()
            FFIconButton(systemName: "square.and.arrow.up") {}
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.vertical, 8)
        .background(theme.bg)
    }

    private var invitedHero: some View {
        FFCard {
            VStack(spacing: 10) {
                FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                FFLabel(text: fight.name, role: .title)
                if let pitch = fight.invitePitch {
                    FFLabel(text: pitch, role: .body, color: theme.muted)
                }
                FFLabel(
                    text: "\(fight.lengthDays) days · \(fight.payoutLine)",
                    role: .caption,
                    color: theme.muted
                )
                FFButton(title: fight.inviteAction == "Accept" ? "Accept challenge" : "Join fight") {
                    model.joined.insert(fight.id)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var liveHero: some View {
        FFCard {
            VStack(spacing: 16) {
                FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                FFLabel(text: fight.name, role: .title)
                ring
                FFKicker(
                    prefix: fight.kickerPrefix,
                    emphasis: fight.kickerEmphasis,
                    rest: fight.kickerRest
                )
                HStack(spacing: 8) {
                    stat(model.formatScore(you?.score ?? 0, metric: fight.metric), "Your total", theme.text)
                    stat(model.formatDelta(you?.today ?? 0, metric: fight.metric), "Today", theme.text)
                    stat(moneyTitle, "Standing to", moneyColor)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var ring: some View {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        let progress: CGFloat = {
            if fight.settlement == .goal, let goal = fight.dailyGoal, goal > 0 {
                return min(1, CGFloat(yours / (goal * Double(fight.lengthDays))))
            }
            return leader == 0 ? 0 : CGFloat(yours / leader)
        }()
        return ZStack {
            Circle()
                .stroke(theme.track, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                FFLabel(text: fight.status == .finished ? "1st" : "#\(fight.rank)", role: .heroNumber)
                FFLabel(text: "of \(fight.of)", role: .tiny, color: theme.muted)
            }
        }
        .frame(width: 140, height: 140)
        .padding(.vertical, 8)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(theme.font(.rank))
                .foregroundStyle(color)
                .monospacedDigit()
            FFLabel(text: label, role: .tiny, color: theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
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

    private var moneyNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Money right now", action: "if nothing changes", actionMuted: true)
            FFGroup {
                FFLabel(text: fight.payoutLine, role: .caption, color: theme.muted)
                    .padding(.horizontal, theme.space.rowPaddingX)
                    .padding(.vertical, 12)
                ForEach(fight.standings.filter { !$0.invited }) { row in
                    FFHairline()
                    moneyRow(row)
                        .padding(.horizontal, theme.space.rowPaddingX)
                        .padding(.vertical, theme.space.rowPaddingY)
                        .background(row.person.isYou ? theme.selectedRow() : Color.clear)
                }
            }
        }
    }

    private func moneyRow(_ row: Standing) -> some View {
        HStack(spacing: 12) {
            FFAvatar(initials: row.person.initials, size: 36, ring: row.person.isYou, pending: row.invited)
            VStack(alignment: .leading, spacing: 2) {
                FFLabel(text: row.person.name, role: .bodyStrong, color: row.invited ? theme.muted : theme.text)
                FFLabel(text: model.paceLine(row, in: fight), role: .caption, color: theme.muted)
            }
            Spacer()
            if let safe = row.safe {
                FFBadge(text: safe ? "Safe" : "At risk", tone: safe ? .green : .red)
            } else {
                FFMoney(dollars: row.projectedNet)
            }
        }
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(
                title: "Standings",
                action: fight.standingsMeta,
                actionMuted: true
            )
            FFGroup {
                ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { FFHairline() }
                    standingRow(index: index, row: row)
                }
            }
        }
    }

    private func standingRow(index: Int, row: Standing) -> some View {
        let isLead = index == 0 && !row.invited
        let maxScore = fight.standings.map(\.score).max() ?? 1
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                FFLabel(
                    text: "\(index + 1)",
                    role: .headline,
                    color: isLead ? theme.accent : theme.muted
                )
                .frame(width: 20, alignment: .leading)
                FFAvatar(initials: row.person.initials, size: 32, ring: row.person.isYou, pending: row.invited)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        FFLabel(text: row.person.name, role: .bodyStrong, color: row.invited ? theme.muted : theme.text)
                        if !row.invited && row.today != 0 {
                            Text(model.formatDelta(row.today, metric: fight.metric))
                                .font(theme.font(.micro))
                                .foregroundStyle(row.today > 0 ? theme.green : theme.red)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                if row.invited {
                    FFBadge(text: "Invited", tone: .amber, style: .solid)
                } else {
                    FFLabel(text: model.formatScore(row.score, metric: fight.metric), role: .rank)
                }
            }
            if !row.invited {
                FFProgressBar(
                    progress: maxScore == 0 ? 0 : CGFloat(row.score / maxScore),
                    fill: isLead ? theme.accent : (row.person.isYou ? theme.text : theme.muted.opacity(0.55))
                )
            }
        }
        .padding(.horizontal, theme.space.rowPaddingX)
        .padding(.vertical, theme.space.rowPaddingY)
        .background(row.person.isYou ? theme.selectedRow() : Color.clear)
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Every day so far")
            FFCard {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(fight.days) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            FFLabel(text: day.label, role: .caption, color: theme.muted)
                            let maxVal = day.scores.map(\.value).max() ?? 1
                            let leaderID = fight.standings.first?.person.id
                            ForEach(day.scores) { row in
                                let isLead = row.person.id == leaderID
                                HStack(spacing: 8) {
                                    FFLabel(text: row.person.name, role: .caption, color: theme.muted)
                                        .frame(width: 44, alignment: .leading)
                                    FFProgressBar(
                                        progress: maxVal == 0 ? 0 : CGFloat(row.value / maxVal),
                                        fill: isLead ? theme.accent : theme.muted.opacity(0.55),
                                        height: 6
                                    )
                                    FFLabel(
                                        text: model.formatScore(row.value, metric: fight.metric),
                                        role: .caption,
                                        color: theme.muted
                                    )
                                    .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }
                    }
                    if let note = fight.paceNote {
                        FFHairline(inset: 0)
                        FFLabel(text: note, role: .caption, color: theme.muted)
                    }
                }
            }
        }
    }
}
