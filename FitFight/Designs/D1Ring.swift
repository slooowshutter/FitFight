import SwiftUI

/// Ring — closed-ring fitness. Your standing in a fight is an arc, not a bar:
/// how much of the leader's score you have closed. Acid lime on near-black.
struct RingFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.bottom, 6)

                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        RingFightCard(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.985))
                }

                if !model.invitations.isEmpty {
                    RingSectionRule(title: "Waiting on you")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            RingInviteRow(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.985))
                    }
                }

                if !model.finished.isEmpty {
                    RingSectionRule(title: "Closed")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            RingInviteRow(fight: fight, done: true)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.985))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.live.count) OPEN")
                    .font(.ff(11, .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)
                Text(netLabel)
                    .font(.ff(44, .heavy))
                    .foregroundStyle(theme.text)
                Text("on the table right now")
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
            }
            Spacer(minLength: 0)
            RingArc(progress: inProfit, size: 60, stroke: 8)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
        }
        .padding(.top, 6)
    }

    /// The header ring closes as more of your live fights are in the black.
    private var inProfit: CGFloat {
        let live = model.live
        guard !live.isEmpty else { return 0 }
        let up = live.filter { ($0.yours?.projectedNet ?? 0) >= 0 }.count
        return CGFloat(up) / CGFloat(live.count)
    }

    private var netLabel: String {
        let net = model.projectedNet
        if net > 0 { return "+$\(net)" }
        if net < 0 { return "−$\(abs(net))" }
        return "$0"
    }
}

private struct RingSectionRule: View {
    let title: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.ff(10, .bold))
                .tracking(1.4)
                .foregroundStyle(theme.faint)
            theme.hair.frame(height: 1)
        }
        .padding(.top, 14)
    }
}

/// The arc itself. Lime for a lead, white for everyone else, drawn from the top.
struct RingArc: View {
    var progress: CGFloat
    var size: CGFloat
    var stroke: CGFloat
    var color: Color? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(color ?? theme.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct RingFightCard: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(fight.metric.eyebrow.uppercased())
                    .font(.ff(9, .bold))
                    .tracking(1.3)
                    .foregroundStyle(theme.faint)
                Text(fight.name)
                    .font(.ff(19, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .padding(.top, 3)
                Text("\(fight.daysLeft ?? 0)d left · $\(fight.pot) · \(fight.settlement.title)")
                    .font(.ff(11))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .padding(.top, 5)

                VStack(spacing: 7) {
                    ForEach(Array(fight.ranked.prefix(3).enumerated()), id: \.element.id) { index, row in
                        lane(index: index, row: row)
                    }
                }
                .padding(.top, 13)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: shape)
        .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    private var ring: some View {
        RingArc(progress: closed, size: 76, stroke: 9)
            .overlay {
                VStack(spacing: -1) {
                    Text("\(fight.yourPlace ?? fight.rank)")
                        .font(.ff(24, .heavy))
                        .foregroundStyle(theme.text)
                    Text("of \(fight.ranked.count)")
                        .font(.ff(9, .semibold))
                        .foregroundStyle(theme.faint)
                }
            }
    }

    /// How much of the leader's score you have closed. First place is a full ring.
    private var closed: CGFloat {
        guard let lead = fight.leader?.score, lead > 0, let mine = fight.yours?.score else { return 0.06 }
        return CGFloat(min(1, mine / lead))
    }

    private func lane(index: Int, row: Standing) -> some View {
        let top = fight.leader?.score ?? 1
        let share = top == 0 ? 0 : CGFloat(row.score / top)
        let color: Color = row.person.isYou ? theme.accent : theme.text.opacity(index == 0 ? 0.85 : 0.34)
        return HStack(spacing: 8) {
            Text(row.person.name)
                .font(.ff(11, .semibold))
                .foregroundStyle(row.person.isYou ? theme.text : theme.muted)
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                Capsule()
                    .fill(theme.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * share))
                    }
            }
            .frame(height: 4)
            Text(model.formatScore(row.score, metric: fight.metric))
                .font(.ff(11, .bold))
                .foregroundStyle(theme.text)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private struct RingInviteRow: View {
    let fight: Fight
    var done = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            RingArc(
                progress: done ? 1 : 0.25,
                size: 34,
                stroke: 5,
                color: done ? theme.green : theme.muted
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name)
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
            }
            Spacer(minLength: 8)
            if done {
                Text("WON")
                    .font(.ff(10, .bold))
                    .tracking(1)
                    .foregroundStyle(theme.green)
            } else {
                Text(fight.inviteAction ?? "Join")
                    .font(.ff(12, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        .opacity(done ? 0.7 : 1)
    }
}
