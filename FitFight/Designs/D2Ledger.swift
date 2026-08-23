import SwiftUI

/// Ledger — the app as a betting statement. Bone paper, hairline rules, no cards
/// at all, and every figure in a monospaced column so the money lines up.
struct LedgerFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                header
                LedgerColumns()
                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        LedgerRow(fight: fight)
                    }
                    .buttonStyle(.plain)
                    theme.hair.frame(height: 1)
                }

                if !model.invitations.isEmpty {
                    LedgerHeading(text: "Open offers")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            LedgerOfferRow(fight: fight)
                        }
                        .buttonStyle(.plain)
                        theme.hair.frame(height: 1)
                    }
                }

                if !model.finished.isEmpty {
                    LedgerHeading(text: "Settled")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            LedgerRow(fight: fight, settled: true)
                        }
                        .buttonStyle(.plain)
                        theme.hair.frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPEN POSITION")
                .font(.ffMono(10, .semibold))
                .tracking(1.6)
                .foregroundStyle(theme.faint)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(net)
                    .font(.ffMono(40, .bold))
                    .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(model.live.count) live")
                        .font(.ffMono(11, .semibold))
                        .foregroundStyle(theme.text)
                    Text("$\(model.live.reduce(0) { $0 + $1.pot }) at stake")
                        .font(.ffMono(11))
                        .foregroundStyle(theme.faint)
                }
            }
            .padding(.top, 2)
            Rectangle()
                .fill(theme.text)
                .frame(height: 2)
                .padding(.top, 14)
        }
        .padding(.top, 10)
    }

    private var net: String {
        let value = model.projectedNet
        let sign = value < 0 ? "−" : "+"
        return "\(sign)$\(abs(value)).00"
    }
}

private struct LedgerColumns: View {
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("FIGHT")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("POS")
                .frame(width: 46, alignment: .trailing)
            Text("P&L")
                .frame(width: 74, alignment: .trailing)
        }
        .font(.ffMono(9, .semibold))
        .tracking(1.2)
        .foregroundStyle(theme.faint)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { theme.hair.frame(height: 1) }
    }
}

private struct LedgerHeading: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.ffMono(10, .semibold))
            .tracking(1.5)
            .foregroundStyle(theme.faint)
            .padding(.top, 26)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { theme.text.frame(height: 1) }
    }
}

private struct LedgerRow: View {
    let fight: Fight
    var settled = false

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(fight.code)
                        .font(.ffMono(9, .semibold))
                        .foregroundStyle(theme.faint)
                    if fight.pending > 0 {
                        Text("\(fight.pending) PENDING")
                            .font(.ffMono(9, .semibold))
                            .foregroundStyle(theme.amber)
                    }
                }
                Text(fight.name)
                    .font(.ff(15, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.ffMono(10))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(fight.yourPlace ?? fight.rank)/\(fight.ranked.count)")
                .font(.ffMono(13, .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 46, alignment: .trailing)
                .padding(.top, 12)

            Text(pnl)
                .font(.ffMono(15, .bold))
                .foregroundStyle(pnlColor)
                .frame(width: 74, alignment: .trailing)
                .padding(.top, 11)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .opacity(settled ? 0.62 : 1)
    }

    private var detail: String {
        let score = fight.yours.map { model.formatScore($0.score, metric: fight.metric) } ?? "—"
        if settled { return "\(fight.endedLabel ?? "Ended") · \(score)" }
        return "\(fight.daysLeft ?? 0)d · \(score) · \(fight.settlement.title.lowercased())"
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        if value == 0 { return "$0.00" }
        return "\(value < 0 ? "−" : "+")$\(abs(value)).00"
    }

    private var pnlColor: Color {
        let value = fight.yours?.projectedNet ?? 0
        if value > 0 { return theme.green }
        if value < 0 { return theme.red }
        return theme.faint
    }
}

private struct LedgerOfferRow: View {
    let fight: Fight
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fight.code)
                    .font(.ffMono(9, .semibold))
                    .foregroundStyle(theme.faint)
                Text(fight.name)
                    .font(.ff(15, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .font(.ffMono(10))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fight.inviteAction?.uppercased() ?? "JOIN")
                .font(.ffMono(11, .bold))
                .tracking(1)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
