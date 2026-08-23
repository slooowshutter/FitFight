import SwiftUI

/// Zine — printed, not rendered. Ink on bone paper, 2pt rules, index numbers set
/// enormous down the left, and exactly one colour used as a stamp.
struct ZineFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                ForEach(Array(model.live.enumerated()), id: \.element.id) { index, fight in
                    Button { model.openFightID = fight.id } label: {
                        ZineEntry(fight: fight, index: index + 1)
                    }
                    .buttonStyle(.plain)
                }

                if !model.invitations.isEmpty {
                    ZineRule(text: "Unanswered")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            ZineNote(fight: fight, tag: (fight.inviteAction ?? "Join").uppercased())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.finished.isEmpty {
                    ZineRule(text: "In the books")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            ZineNote(fight: fight, tag: "WON")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.text).frame(height: 3)
            HStack(alignment: .top, spacing: 0) {
                Text("FIT / FIGHT")
                    .font(.ff(11, .heavy))
                    .tracking(3)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                Text("ISSUE \(model.live.count + model.finished.count)")
                    .font(.ff(11, .heavy))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
            }
            .padding(.vertical, 9)
            Rectangle().fill(theme.text).frame(height: 1)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(String(format: "%02d", model.live.count))
                    .font(.ff(84, .heavy))
                    .tracking(-4)
                    .foregroundStyle(theme.text)
                VStack(alignment: .leading, spacing: -2) {
                    Text("FIGHTS")
                        .font(.ff(22, .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(theme.text)
                    Text("STILL OPEN")
                        .font(.ff(22, .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(theme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)

            Text(standfirst)
                .font(.ff(13))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 14)

            Rectangle().fill(theme.text).frame(height: 3)
        }
        .padding(.top, 6)
    }

    private var standfirst: String {
        let net = model.projectedNet
        if net < 0 { return "Settle every one of them this second and you hand over $\(abs(net))." }
        if net > 0 { return "Settle every one of them this second and you collect $\(net)." }
        return "Settle every one of them this second and nobody owes anybody."
    }
}

private struct ZineRule: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text.uppercased())
                .font(.ff(11, .heavy))
                .tracking(2.4)
                .foregroundStyle(theme.text)
                .padding(.bottom, 7)
            Rectangle().fill(theme.text).frame(height: 2)
        }
        .padding(.top, 30)
        .padding(.bottom, 4)
    }
}

private struct ZineEntry: View {
    let fight: Fight
    let index: Int

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Text(String(format: "%02d", index))
                    .font(.ff(38, .heavy))
                    .tracking(-2)
                    .foregroundStyle(theme.text.opacity(0.22))
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(fight.name.uppercased())
                        .font(.ff(21, .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(kicker)
                        .font(.ff(13))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    standings
                        .padding(.top, 5)
                }
            }
            .padding(.vertical, 16)

            HStack(spacing: 0) {
                Text("\(fight.daysLeft ?? 0) DAYS")
                Text(" / ")
                Text("$\(fight.pot)")
                Text(" / ")
                Text(fight.settlement.title.uppercased())
                Spacer(minLength: 8)
                Text(pnl)
                    .foregroundStyle(theme.accent)
            }
            .font(.ff(10, .heavy))
            .tracking(1.2)
            .foregroundStyle(theme.muted)
            .padding(.bottom, 14)

            Rectangle().fill(theme.hair).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var kicker: String {
        [fight.kickerPrefix, fight.kickerEmphasis, fight.kickerRest]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(fight.ranked.prefix(3).enumerated()), id: \.element.id) { place, row in
                HStack(spacing: 8) {
                    Text("\(place + 1).")
                        .font(.ff(12, .heavy))
                        .foregroundStyle(theme.text.opacity(0.35))
                        .frame(width: 18, alignment: .leading)
                    Text(row.person.name.uppercased())
                        .font(.ff(12, row.person.isYou ? .heavy : .semibold))
                        .tracking(0.6)
                        .foregroundStyle(row.person.isYou ? theme.text : theme.muted)
                    Rectangle()
                        .fill(theme.hair)
                        .frame(height: 1)
                    Text(model.formatScore(row.score, metric: fight.metric))
                        .font(.ff(12, .heavy))
                        .foregroundStyle(theme.text)
                }
            }
        }
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct ZineNote: View {
    let fight: Fight
    let tag: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.name.uppercased())
                        .font(.ff(14, .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(theme.text)
                    Text(fight.listSubtitle)
                        .font(.ff(12))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(tag)
                    .font(.ff(10, .heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(theme.accent)
                    .rotationEffect(.degrees(-2))
            }
            .padding(.vertical, 13)
            Rectangle().fill(theme.hair).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}
