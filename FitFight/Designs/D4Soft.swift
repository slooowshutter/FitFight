import SwiftUI

/// Soft — the calm read. Warm paper, 28pt corners, one plain-English sentence per
/// fight and a lot of air. The opposite of a trading screen.
struct SoftFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 18) {
                header

                ForEach(model.live) { fight in
                    Button { model.openFightID = fight.id } label: {
                        SoftFightCard(fight: fight)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.985))
                }

                if !model.invitations.isEmpty {
                    SoftHeading(text: "Someone asked you")
                    VStack(spacing: 10) {
                        ForEach(model.invitations) { fight in
                            Button { model.openFightID = fight.id } label: {
                                SoftInvite(fight: fight)
                            }
                            .buttonStyle(FFPressStyle(scale: 0.985))
                        }
                    }
                }

                if !model.finished.isEmpty {
                    SoftHeading(text: "Done")
                    VStack(spacing: 10) {
                        ForEach(model.finished) { fight in
                            Button { model.openFightID = fight.id } label: {
                                SoftInvite(fight: fight, done: true)
                            }
                            .buttonStyle(FFPressStyle(scale: 0.985))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You have \(model.live.count) fights running")
                .font(.ff(26, .bold))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Circle()
                    .fill(model.projectedNet < 0 ? theme.red : theme.green)
                    .frame(width: 8, height: 8)
                Text(sentence)
                    .font(.ff(13))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.chip, in: Capsule())
        }
        .padding(.top, 12)
    }

    private var sentence: String {
        let net = model.projectedNet
        if net > 0 { return "Finishing now would put you $\(net) up" }
        if net < 0 { return "Finishing now would cost you $\(abs(net))" }
        return "Finishing now would leave you even"
    }
}

private struct SoftHeading: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text)
            .font(.ff(15, .bold))
            .foregroundStyle(theme.text)
            .padding(.top, 8)
    }
}

private struct SoftFightCard: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fight.name)
                        .font(.ff(20, .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(fight.daysLeft ?? 0) days left · $\(fight.pot) pot")
                        .font(.ff(12))
                        .foregroundStyle(theme.faint)
                }
                Spacer(minLength: 0)
                Text("\(fight.yourPlace ?? fight.rank)\(suffix)")
                    .font(.ff(15, .bold))
                    .foregroundStyle(fight.yourPlace == 1 ? theme.ink : theme.text)
                    .frame(width: 44, height: 44)
                    .background(
                        fight.yourPlace == 1 ? theme.accent : theme.chip,
                        in: Circle()
                    )
            }

            bar
                .padding(.top, 20)

            HStack(spacing: -7) {
                ForEach(fight.ranked.prefix(4)) { row in
                    FFAvatar(row.person, size: 26)
                        .overlay { Circle().strokeBorder(theme.surface, lineWidth: 2) }
                }
                if fight.notJoined > 0 {
                    Text("+\(fight.notJoined)")
                        .font(.ff(10, .semibold))
                        .foregroundStyle(theme.faint)
                        .padding(.leading, 13)
                }
                Spacer(minLength: 8)
                Text(kicker)
                    .font(.ff(12))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: shape)
        .shadow(color: Color(hex: "#2a2724").opacity(0.06), radius: 18, y: 8)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    private var suffix: String {
        switch fight.yourPlace ?? fight.rank {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// One bar, you against the leader — the only number that decides the money.
    private var bar: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                Capsule()
                    .fill(theme.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: max(10, geo.size.width * progress))
                    }
            }
            .frame(height: 10)
            HStack {
                Text(mine)
                    .font(.ff(12, .semibold))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                Text(top)
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
            }
        }
    }

    private var progress: CGFloat {
        guard let lead = fight.leader?.score, lead > 0, let you = fight.yours?.score else { return 0.04 }
        return CGFloat(min(1, you / lead))
    }

    private var mine: String {
        guard let you = fight.yours else { return "Not started" }
        return "You · \(model.formatScore(you.score, metric: fight.metric))"
    }

    private var top: String {
        guard let lead = fight.leader else { return "" }
        if lead.person.isYou { return "You're leading" }
        return "\(lead.person.name) · \(model.formatScore(lead.score, metric: fight.metric))"
    }

    private var kicker: String {
        [fight.kickerPrefix, fight.kickerEmphasis, fight.kickerRest]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct SoftInvite: View {
    let fight: Fight
    var done = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.green)
                    .frame(width: 40, height: 40)
                    .background(theme.green.opacity(0.12), in: Circle())
            } else {
                FFAvatar(fight.standings.first?.person, size: 40)
            }
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
            if !done {
                Text(fight.inviteAction ?? "Join")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
    }
}
