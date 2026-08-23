import SwiftUI

/// Arena — a fight-night card. Every live fight is a bout: you on the left, the
/// person you have to beat on the right, and the pot printed like a purse.
struct ArenaFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 12) {
                header

                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        ArenaBout(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.99))
                }

                if !model.invitations.isEmpty {
                    ArenaRule(text: "Challenges")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            ArenaChallenge(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.99))
                    }
                }

                if !model.finished.isEmpty {
                    ArenaRule(text: "Results")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            ArenaResult(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.99))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(theme.accent).frame(width: 7, height: 7)
                Text("LIVE CARD")
                    .font(.ff(10, .bold))
                    .tracking(2.4)
                    .foregroundStyle(theme.accent)
            }
            Text("\(model.live.count) BOUTS")
                .font(.ff(38, .heavy))
                .tracking(-1)
                .foregroundStyle(theme.text)
                .padding(.top, 2)
            HStack(spacing: 6) {
                Text("PURSE")
                    .font(.ff(10, .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.faint)
                Text(net)
                    .font(.ff(13, .bold))
                    .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
            }
            .padding(.top, 3)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct ArenaRule: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.ff(10, .bold))
                .tracking(2.2)
                .foregroundStyle(theme.faint)
            theme.line.frame(height: 1)
        }
        .padding(.top, 16)
    }
}

private struct ArenaBout: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            title
            corners
            footer
        }
        .background(theme.surface)
        .overlay(alignment: .top) { theme.accent.frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fight.metric.eyebrow.uppercased())
                .font(.ff(9, .bold))
                .tracking(2)
                .foregroundStyle(theme.accent)
            Text(fight.name.uppercased())
                .font(.ff(24, .heavy))
                .tracking(-0.6)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 14)
    }

    /// You in the near corner, whoever is beating you in the far one.
    private var corners: some View {
        HStack(alignment: .center, spacing: 0) {
            corner(fight.yours, align: .leading)
            VStack(spacing: 2) {
                Text("VS")
                    .font(.ff(15, .heavy))
                    .foregroundStyle(theme.accent)
                Text("\(fight.daysLeft ?? 0)D LEFT")
                    .font(.ff(8, .bold))
                    .tracking(1)
                    .foregroundStyle(theme.faint)
            }
            .frame(width: 62)
            corner(rival, align: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    /// The person directly above you, or the runner-up when you are already first.
    private var rival: Standing? {
        let ranked = fight.ranked
        guard let mine = ranked.firstIndex(where: { $0.person.isYou }) else { return ranked.first }
        return mine == 0 ? (ranked.count > 1 ? ranked[1] : nil) : ranked[mine - 1]
    }

    private func corner(_ row: Standing?, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 6) {
            FFAvatar(row?.person, size: 44)
            Text((row?.person.name ?? "—").uppercased())
                .font(.ff(11, .bold))
                .tracking(0.8)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            Text(row.map { model.formatScore($0.score, metric: fight.metric) } ?? "0")
                .font(.ff(27, .heavy))
                .foregroundStyle(row?.person.isYou == true ? theme.text : theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text("$\(fight.pot)")
                .font(.ff(13, .heavy))
                .foregroundStyle(theme.text)
            Text(" · \(fight.settlement.title.uppercased())")
                .font(.ff(10, .bold))
                .tracking(1)
                .foregroundStyle(theme.faint)
            Spacer(minLength: 8)
            Text(pnl)
                .font(.ff(13, .heavy))
                .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(theme.chip)
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct ArenaChallenge: View {
    let fight: Fight
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            FFAvatar(fight.standings.first?.person, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name.uppercased())
                    .font(.ff(14, .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(fight.invitePitch ?? fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fight.inviteAction?.uppercased() ?? "JOIN")
                .font(.ff(11, .heavy))
                .tracking(1.2)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .overlay { Rectangle().strokeBorder(theme.line, lineWidth: 1) }
    }
}

private struct ArenaResult: View {
    let fight: Fight
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text("W")
                .font(.ff(15, .heavy))
                .foregroundStyle(theme.ink)
                .frame(width: 40, height: 40)
                .background(theme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name.uppercased())
                    .font(.ff(14, .heavy))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
            }
            Spacer(minLength: 8)
            Text("+$\(fight.yours?.projectedNet ?? 0)")
                .font(.ff(14, .heavy))
                .foregroundStyle(theme.green)
        }
        .padding(14)
        .background(theme.surface)
        .overlay { Rectangle().strokeBorder(theme.line, lineWidth: 1) }
    }
}
