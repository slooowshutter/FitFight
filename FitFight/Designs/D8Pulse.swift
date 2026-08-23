import SwiftUI

/// Pulse — the pot as one stacked bar. Each person's slice is literally their share
/// of the effort, which is also their share of the money on a proportional fight.
struct PulseFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 12) {
                header

                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        PulseCard(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.985))
                }

                if !model.invitations.isEmpty {
                    PulseHeading(text: "Pending")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            PulseThinRow(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.985))
                    }
                }

                if !model.finished.isEmpty {
                    PulseHeading(text: "Settled")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            PulseThinRow(fight: fight, done: true)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.live.count)")
                    .font(.ff(34, .heavy))
                    .foregroundStyle(theme.accent)
                Text("fights in play")
                    .font(.ff(15, .semibold))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                stat("Exposure", "$\(model.live.reduce(0) { $0 + $1.buyIn })")
                stat("Pot", "$\(model.live.reduce(0) { $0 + $1.pot })")
                stat("Net", net, tint: model.projectedNet < 0 ? theme.red : theme.green)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func stat(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.ff(9, .semibold))
                .tracking(1.1)
                .foregroundStyle(theme.faint)
            Text(value)
                .font(.ff(15, .bold))
                .foregroundStyle(tint ?? theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct PulseHeading: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.ff(9, .bold))
            .tracking(1.6)
            .foregroundStyle(theme.faint)
            .padding(.top, 14)
    }
}

private struct PulseCard: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fight.name)
                        .font(.ff(17, .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(fight.metric.eyebrow) · \(fight.settlement.title) · \(fight.daysLeft ?? 0)d")
                        .font(.ff(10.5))
                        .foregroundStyle(theme.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(yourShare)%")
                    .font(.ff(19, .heavy))
                    .foregroundStyle(theme.accent)
            }

            shareBar
                .padding(.top, 16)

            legend
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: shape)
        .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    private var total: Double {
        max(1, fight.ranked.reduce(0) { $0 + $1.score })
    }

    private var yourShare: Int {
        Int(((fight.yours?.score ?? 0) / total * 100).rounded())
    }

    /// One bar, segment per person, widths in proportion to the real scores.
    private var shareBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(fight.ranked.enumerated()), id: \.element.id) { index, row in
                    Rectangle()
                        .fill(color(index: index, row: row))
                        .frame(width: max(3, (geo.size.width - CGFloat(fight.ranked.count - 1) * 2) * CGFloat(row.score / total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 26)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
    }

    private func color(index: Int, row: Standing) -> Color {
        if row.person.isYou { return theme.accent }
        return theme.text.opacity(0.30 - Double(index) * 0.045)
    }

    private var legend: some View {
        VStack(spacing: 6) {
            ForEach(Array(fight.ranked.prefix(3).enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(index: index, row: row))
                        .frame(width: 8, height: 8)
                    Text(row.person.name)
                        .font(.ff(11, row.person.isYou ? .bold : .regular))
                        .foregroundStyle(row.person.isYou ? theme.text : theme.muted)
                    Spacer(minLength: 6)
                    Text(model.formatScore(row.score, metric: fight.metric))
                        .font(.ff(11, .semibold))
                        .foregroundStyle(theme.muted)
                    Text("\(Int((row.score / total * 100).rounded()))%")
                        .font(.ff(11, .bold))
                        .foregroundStyle(theme.text)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            if fight.ranked.count > 3 {
                Text("+\(fight.ranked.count - 3) more")
                    .font(.ff(10))
                    .foregroundStyle(theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) { theme.hair.frame(height: 1).offset(y: -8) }
    }
}

private struct PulseThinRow: View {
    let fight: Fight
    var done = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(done ? theme.green : theme.accent)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(fight.name)
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .font(.ff(10))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(done ? "Won" : (fight.inviteAction ?? "Join").uppercased())
                .font(.ff(10, .bold))
                .tracking(0.8)
                .foregroundStyle(done ? theme.green : theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }
}
