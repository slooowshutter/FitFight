import SwiftUI

/// Terminal — everything as a fixed-width readout. Zero corner radius, one column
/// of monospace, bars drawn out of block characters instead of shapes.
struct TerminalFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                header

                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        TerminalBlock(fight: fight)
                    }
                    .buttonStyle(.plain)
                }

                if !model.invitations.isEmpty {
                    TerminalDivider(label: "INBOUND")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            TerminalStub(fight: fight, action: fight.inviteAction?.uppercased() ?? "JOIN")
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.finished.isEmpty {
                    TerminalDivider(label: "ARCHIVE")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            TerminalStub(fight: fight, action: "CLOSED")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("─ END OF FEED ─")
                    .font(.ffMono(10))
                    .foregroundStyle(theme.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 26)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FITFIGHT // FEED")
                .font(.ffMono(11, .bold))
                .foregroundStyle(theme.accent)
            HStack(spacing: 0) {
                Text("ACTIVE ")
                    .foregroundStyle(theme.faint)
                Text("\(model.live.count)")
                    .foregroundStyle(theme.text)
                Text("   NET ")
                    .foregroundStyle(theme.faint)
                Text(net)
                    .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
                Text("   POT ")
                    .foregroundStyle(theme.faint)
                Text("$\(model.live.reduce(0) { $0 + $1.pot })")
                    .foregroundStyle(theme.text)
            }
            .font(.ffMono(12, .semibold))
            Rectangle()
                .fill(theme.accent.opacity(0.35))
                .frame(height: 1)
                .padding(.top, 8)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "-" : "+")\(abs(value)).00"
    }
}

private struct TerminalDivider: View {
    let label: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Text("[\(label)]")
                .font(.ffMono(10, .bold))
                .foregroundStyle(theme.accent)
            Rectangle().fill(theme.line).frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

private struct TerminalBlock: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    /// 12 cells of block characters. Monospace means they line up down the column.
    private static let cells = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fight.code)
                    .font(.ffMono(10, .bold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(theme.accent)
                Text(fight.name.uppercased())
                    .font(.ffMono(13, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("D-\(fight.daysLeft ?? 0)")
                    .font(.ffMono(11, .semibold))
                    .foregroundStyle(theme.amber)
            }

            Text(metaLine)
                .font(.ffMono(10))
                .foregroundStyle(theme.faint)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(fight.ranked.prefix(4).enumerated()), id: \.element.id) { index, row in
                    line(index: index, row: row)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 0) {
                Text("PNL  ")
                    .foregroundStyle(theme.faint)
                Text(pnl)
                    .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
                Spacer(minLength: 8)
                Text("OPEN >")
                    .foregroundStyle(theme.accent)
            }
            .font(.ffMono(11, .semibold))
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(alignment: .leading) { theme.accent.frame(width: 2) }
        .overlay { Rectangle().strokeBorder(theme.line, lineWidth: 1) }
        .padding(.top, 10)
        .contentShape(Rectangle())
    }

    private var metaLine: String {
        "\(fight.metric.eyebrow.uppercased()) | $\(fight.pot) | \(fight.settlement.title.uppercased())"
            + (fight.pending > 0 ? " | \(fight.pending) PENDING" : "")
    }

    private func line(index: Int, row: Standing) -> some View {
        let top = fight.leader?.score ?? 1
        let filled = top == 0 ? 0 : Int((Double(Self.cells) * row.score / top).rounded())
        let bar = String(repeating: "█", count: max(0, min(Self.cells, filled)))
            + String(repeating: "░", count: max(0, Self.cells - max(0, min(Self.cells, filled))))
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .foregroundStyle(theme.faint)
            Text(row.person.name.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0))
                .foregroundStyle(row.person.isYou ? theme.accent : theme.muted)
            Text(bar)
                .foregroundStyle(row.person.isYou ? theme.accent : theme.text.opacity(0.55))
            Spacer(minLength: 4)
            Text(model.formatScore(row.score, metric: fight.metric))
                .foregroundStyle(theme.text)
        }
        .font(.ffMono(11, row.person.isYou ? .bold : .regular))
        .lineLimit(1)
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "-" : "+")\(abs(value)).00"
    }
}

private struct TerminalStub: View {
    let fight: Fight
    let action: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(fight.name.uppercased())
                    .font(.ffMono(12, .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(fight.listSubtitle.uppercased())
                    .font(.ffMono(9))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("[\(action)]")
                .font(.ffMono(10, .bold))
                .foregroundStyle(theme.accent)
        }
        .font(.ffMono(12))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { Rectangle().strokeBorder(theme.hair, lineWidth: 1) }
        .padding(.top, 6)
        .contentShape(Rectangle())
    }
}
