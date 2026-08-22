import SwiftUI

struct FightDetailView: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                hero
                if fight.status == .invited && !model.joined.contains(fight.id) {
                    FFButton(title: fight.inviteAction == "Accept" ? "Accept challenge" : "Join fight") {
                        model.joined.insert(fight.id)
                    }
                }
                moneyNow
                standings
                days
                FFButton(title: "i challenge you", icon: "square.and.arrow.up") {}
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.tabBarClearance)
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
                .background(theme.chip, in: Capsule())
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

    private var hero: some View {
        FFCard {
            VStack(spacing: 16) {
                FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                FFLabel(text: fight.name, role: .title)
                ring
                HStack(spacing: 8) {
                    stat(model.formatScore(you?.score ?? 0, metric: fight.metric), "Your total")
                    stat(model.formatScore(you?.today ?? 0, metric: fight.metric), "Today")
                    stat(moneyTitle, moneyLabel)
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
                return min(1, CGFloat(yours / (goal * 7)))
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            FFLabel(text: value, role: .rank)
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

    private var moneyLabel: String { "Standing to" }

    private var payoutLine: String {
        switch fight.settlement {
        case .winner:
            return "Winner takes the whole $\(fight.pot)"
        case .proportional:
            return "Your share of the min is your share of the pot"
        case .goal:
            let goal = fight.dailyGoal.map { String(format: "%.1fk", $0 / 1000) } ?? "goal"
            return "Hit \(goal) steps/day and your $\(fight.buyIn) comes back"
        }
    }

    private var moneyNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Money right now")
            FFLabel(text: payoutLine, role: .caption, color: theme.muted)
            FFGroup {
                ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { FFHairline() }
                    HStack(spacing: 12) {
                        FFAvatar(initials: row.person.initials, size: 36, ring: row.person.isYou, pending: row.invited)
                        VStack(alignment: .leading, spacing: 2) {
                            FFLabel(text: row.person.name, role: .bodyStrong, color: row.invited ? theme.muted : theme.text)
                            FFLabel(
                                text: paceLine(row),
                                role: .caption,
                                color: theme.muted
                            )
                        }
                        Spacer()
                        if row.invited {
                            FFBadge(text: "Invited", tone: .amber)
                        } else if let safe = row.safe {
                            FFBadge(text: safe ? "Safe" : "At risk", tone: safe ? .green : .red)
                        } else {
                            FFMoney(dollars: row.projectedNet)
                        }
                    }
                    .padding(.horizontal, theme.space.rowPaddingX)
                    .padding(.vertical, theme.space.rowPaddingY)
                    .background(row.person.isYou ? theme.selectedRow() : Color.clear)
                }
            }
        }
    }

    private func paceLine(_ row: Standing) -> String {
        if row.invited { return "Hasn’t joined yet" }
        switch fight.metric {
        case .activeMinutes:
            return "on pace for \(Int(row.score * 3)) min"
        case .steps:
            return "on pace for \(model.formatScore(row.score * 1.4, metric: .steps))"
        case .workouts:
            return "\(Int(row.score)) so far"
        }
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Standings")
            FFGroup {
                ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { FFHairline() }
                    let isLead = index == 0
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            FFLabel(
                                text: "\(index + 1)",
                                role: .headline,
                                color: isLead ? theme.accent : theme.muted
                            )
                            .frame(width: 20, alignment: .leading)
                            FFAvatar(initials: row.person.initials, size: 32, ring: row.person.isYou, pending: row.invited)
                            VStack(alignment: .leading, spacing: 2) {
                                FFLabel(text: row.person.name, role: .bodyStrong, color: row.invited ? theme.muted : theme.text)
                                FFLabel(text: "today \(model.formatScore(row.today, metric: fight.metric))", role: .micro, color: theme.muted)
                            }
                            Spacer()
                            FFLabel(text: model.formatScore(row.score, metric: fight.metric), role: .rank)
                        }
                        if !row.invited {
                            let maxScore = fight.standings.map(\.score).max() ?? 1
                            FFProgressBar(
                                progress: maxScore == 0 ? 0 : row.score / maxScore,
                                fill: isLead ? theme.accent : (row.person.isYou ? theme.text : theme.track)
                            )
                        }
                    }
                    .padding(.horizontal, theme.space.rowPaddingX)
                    .padding(.vertical, theme.space.rowPaddingY)
                    .background(row.person.isYou ? theme.selectedRow() : Color.clear)
                }
            }
        }
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Every day so far")
            FFCard {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<7, id: \.self) { day in
                        let height: CGFloat = [0.4, 0.7, 0.55, 0.9, 0.35, 0.8, 0.6][day]
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(day == 3 ? theme.accent : theme.track)
                                .frame(width: 18, height: 64 * height)
                            FFLabel(text: ["M", "T", "W", "T", "F", "S", "S"][day], role: .tiny, color: theme.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
            }
        }
    }
}
