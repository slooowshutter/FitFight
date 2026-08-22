import SwiftUI

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                header
                ForEach(model.live) { fight in
                    Button {
                        model.openFightID = fight.id
                    } label: {
                        LiveFightCard(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.985))
                }

                if !model.invitations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        FFSectionHeader(title: "Invitations")
                        FFGroup {
                            ForEach(Array(model.invitations.enumerated()), id: \.element.id) { index, fight in
                                if index > 0 { FFHairline() }
                                InvitationRow(fight: fight)
                            }
                        }
                    }
                }

                if !model.finished.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        FFSectionHeader(title: "Finished")
                        FFGroup {
                            ForEach(model.finished) { fight in
                                FinishedRow(fight: fight)
                            }
                        }
                        .opacity(0.85)
                    }
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.tabBarClearance)
        }
        .background(theme.bg)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                FFLabel(text: "\(model.live.count) live fights", role: .display)
                HStack(spacing: 4) {
                    FFLabel(text: "If it ends like this you're", role: .body, color: theme.muted)
                    FFMoney(dollars: model.projectedNet)
                }
            }
            Spacer()
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.text)
                    .frame(width: 40, height: 40)
                    .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
                Circle()
                    .fill(theme.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -4, y: 4)
            }
        }
        .padding(.top, 8)
    }
}

struct LiveFightCard: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        FFLabel(text: fight.metric.eyebrow, role: .eyebrow, color: theme.muted)
                        FFLabel(text: fight.name, role: .title)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        rankBadge
                        if fight.pending > 0 {
                            FFBadge(text: "\(fight.pending) pending", tone: .amber)
                        }
                    }
                }

                HStack(spacing: 12) {
                    meta(icon: "clock", text: "\(fight.daysLeft ?? 0)d left")
                    meta(icon: "dollarsign.circle", text: "$\(fight.pot)")
                    FFLabel(text: fight.settlement.title, role: .caption, color: theme.muted)
                }

                VStack(spacing: 10) {
                    ForEach(visibleStandings) { row in
                        miniRow(row)
                    }
                    if fight.standings.filter({ !$0.invited }).count > 3 {
                        FFLabel(text: "+\(fight.standings.count - 3) more", role: .micro, color: theme.muted)
                    }
                }

                HStack {
                    FFLabel(text: fight.headline, role: .caption, color: theme.muted)
                    Spacer()
                    if let you = model.youStanding(in: fight) {
                        FFMoney(dollars: you.projectedNet)
                        FFLabel(text: "right now", role: .caption, color: theme.muted)
                    }
                }
            }
        }
    }

    private var visibleStandings: [Standing] {
        Array(fight.standings.filter { !$0.invited }.prefix(3))
    }

    private var rankBadge: some View {
        let first = fight.rank == 1
        return Text("#\(fight.rank) OF \(fight.of)")
            .font(theme.font(.tiny))
            .tracking(theme.tracking(.tiny))
            .foregroundStyle(first ? theme.ink : theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                first ? theme.accent : theme.chip,
                in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
            )
            .monospacedDigit()
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            FFLabel(text: text, role: .caption, color: theme.muted)
        }
        .foregroundStyle(theme.muted)
    }

    private func miniRow(_ row: Standing) -> some View {
        let maxScore = fight.standings.map(\.score).max() ?? 1
        let isLead = fight.standings.first?.person.id == row.person.id
        let fill: Color = isLead ? theme.accent : (row.person.isYou ? theme.text : theme.track)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                FFLabel(
                    text: "\(fight.standings.firstIndex(where: { $0.id == row.id }).map { $0 + 1 } ?? 0)",
                    role: .headline,
                    color: isLead ? theme.accent : theme.muted
                )
                .frame(width: 18, alignment: .leading)
                FFAvatar(initials: row.person.initials, size: 24, ring: row.person.isYou)
                FFLabel(text: row.person.name, role: .bodyStrong)
                Spacer()
                FFLabel(text: model.formatScore(row.score, metric: fight.metric), role: .bodyStrong, color: theme.muted)
            }
            FFProgressBar(progress: maxScore == 0 ? 0 : row.score / maxScore, fill: fill)
        }
    }
}

struct InvitationRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            FFAvatar(initials: fight.standings.first?.person.initials ?? "?", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                FFLabel(text: fight.name, role: .bodyStrong)
                FFLabel(text: fight.headline, role: .caption, color: theme.muted)
            }
            Spacer()
            FFButton(title: fight.inviteAction ?? "Join", kind: .small) {
                model.openFightID = fight.id
            }
        }
        .padding(.horizontal, theme.space.rowPaddingX)
        .padding(.vertical, theme.space.rowPaddingY)
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
            HStack(spacing: 12) {
                Text("W")
                    .font(theme.font(.bodyStrong))
                    .foregroundStyle(theme.onPhoto)
                    .frame(width: 32, height: 32)
                    .background(theme.green, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    FFLabel(text: fight.name, role: .bodyStrong)
                    FFLabel(
                        text: [fight.endedLabel, fight.headline].compactMap { $0 }.joined(separator: " · "),
                        role: .caption,
                        color: theme.muted
                    )
                }
                Spacer()
                HStack(spacing: -8) {
                    ForEach(fight.standings.prefix(2)) { row in
                        FFAvatar(initials: row.person.initials, size: 24)
                    }
                }
            }
            .padding(.horizontal, theme.space.rowPaddingX)
            .padding(.vertical, theme.space.rowPaddingY)
        }
        .buttonStyle(.plain)
    }
}
