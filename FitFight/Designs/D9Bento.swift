import SwiftUI

/// Bento — asymmetric tiles instead of a uniform stack. The summary is one wide
/// tile, the first fight gets a big one, the rest pair up two to a row.
struct BentoFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(spacing: 10) {
                summaryRow

                if let first = model.live.first {
                    Button { model.openFightID = first.id } label: {
                        BentoWideTile(fight: first)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.98))
                }

                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 10) {
                        ForEach(pair) { fight in
                            Button { model.openFightID = fight.id } label: {
                                BentoSmallTile(fight: fight)
                            }
                            .buttonStyle(FFPressStyle(scale: 0.98))
                        }
                        if pair.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }

                ForEach(model.invitations) { fight in
                    Button { model.openFightID = fight.id } label: {
                        BentoInviteTile(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.98))
                }

                ForEach(model.finished) { fight in
                    Button { model.openFightID = fight.id } label: {
                        BentoDoneTile(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
    }

    private var pairs: [[Fight]] {
        let rest = Array(model.live.dropFirst())
        return stride(from: 0, to: rest.count, by: 2).map {
            Array(rest[$0..<Swift.min($0 + 2, rest.count)])
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("If it ended now")
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                Text(net)
                    .font(.ff(30, .heavy))
                    .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.surface, in: BentoShape())
            .overlay { BentoShape().strokeBorder(theme.line, lineWidth: 1) }

            VStack(spacing: 1) {
                Text("\(model.live.count)")
                    .font(.ff(26, .heavy))
                    .foregroundStyle(theme.ink)
                Text("LIVE")
                    .font(.ff(9, .bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.ink.opacity(0.8))
            }
            .frame(width: 92)
            .frame(maxHeight: .infinity)
            .background(theme.accent, in: BentoShape())
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

/// Shared tile shape so every corner in the grid matches.
private struct BentoShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> BentoShape {
        BentoShape(inset: inset + amount)
    }
}

private struct BentoWideTile: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.metric.eyebrow.uppercased())
                        .font(.ff(9, .bold))
                        .tracking(1.3)
                        .foregroundStyle(theme.accent)
                    Text(fight.name)
                        .font(.ff(22, .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("#\(fight.yourPlace ?? fight.rank)")
                    .font(.ff(16, .heavy))
                    .foregroundStyle(theme.ink)
                    .frame(width: 40, height: 40)
                    .background(theme.accent, in: Circle())
            }

            VStack(spacing: 9) {
                ForEach(Array(fight.ranked.prefix(3).enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) {
                        FFAvatar(row.person, size: 24)
                        Text(row.person.name)
                            .font(.ff(12, .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 54, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(theme.track)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(index == 0 ? theme.accent : theme.text.opacity(0.28))
                                        .frame(width: max(6, geo.size.width * width(row)))
                                }
                        }
                        .frame(height: 6)
                        Text(model.formatScore(row.score, metric: fight.metric))
                            .font(.ff(12, .bold))
                            .foregroundStyle(theme.text)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 18)

            HStack(spacing: 6) {
                BentoPill(text: "\(fight.daysLeft ?? 0)d left")
                BentoPill(text: "$\(fight.pot)")
                BentoPill(text: fight.settlement.title)
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: BentoShape())
        .overlay { BentoShape().strokeBorder(theme.line, lineWidth: 1) }
    }

    private func width(_ row: Standing) -> CGFloat {
        let top = fight.leader?.score ?? 1
        return top == 0 ? 0 : CGFloat(row.score / top)
    }
}

private struct BentoPill: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text)
            .font(.ff(10, .semibold))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(theme.chip, in: Capsule())
            .lineLimit(1)
    }
}

private struct BentoSmallTile: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("#\(fight.yourPlace ?? fight.rank) of \(fight.ranked.count)")
                .font(.ff(10, .bold))
                .tracking(0.8)
                .foregroundStyle(theme.accent)
            Text(fight.name)
                .font(.ff(15, .bold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Spacer(minLength: 12)
            HStack(spacing: -6) {
                ForEach(fight.ranked.prefix(3)) { row in
                    FFAvatar(row.person, size: 22)
                        .overlay { Circle().strokeBorder(theme.surface, lineWidth: 1.5) }
                }
                Spacer(minLength: 4)
                Text(pnl)
                    .font(.ff(12, .bold))
                    .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
            }
            .padding(.top, 14)
            Text("\(fight.daysLeft ?? 0)d left · $\(fight.pot)")
                .font(.ff(10))
                .foregroundStyle(theme.faint)
                .padding(.top, 7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(theme.surface, in: BentoShape())
        .overlay { BentoShape().strokeBorder(theme.line, lineWidth: 1) }
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct BentoInviteTile: View {
    let fight: Fight
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            FFAvatar(fight.standings.first?.person, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.invitePitch ?? fight.name)
                    .font(.ff(14, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fight.inviteAction ?? "Join")
                .font(.ff(12, .bold))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(theme.accent, in: Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent.opacity(0.07), in: BentoShape())
        .overlay { BentoShape().strokeBorder(theme.accent.opacity(0.25), lineWidth: 1) }
    }
}

private struct BentoDoneTile: View {
    let fight: Fight
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.green)
                .frame(width: 38, height: 38)
                .background(theme.green.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name)
                    .font(.ff(14, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("+$\(fight.yours?.projectedNet ?? 0)")
                .font(.ff(14, .bold))
                .foregroundStyle(theme.green)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: BentoShape())
        .overlay { BentoShape().strokeBorder(theme.line, lineWidth: 1) }
    }
}
