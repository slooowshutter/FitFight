import SwiftUI

/// Stack — frosted panels floating over colour. A blurred accent orb sits behind
/// each card, and the running total lives in a pill at the top of the screen.
struct StackFightsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 16) {
                header

                ForEach(Array(model.live.enumerated()), id: \.element.id) { index, fight in
                    Button { model.openFightID = fight.id } label: {
                        StackCard(fight: fight, index: index)
                    }
                    .buttonStyle(FFPressStyle(scale: 0.98))
                }

                if !model.invitations.isEmpty {
                    StackHeading(text: "Invites")
                    ForEach(model.invitations) { fight in
                        Button { model.openFightID = fight.id } label: {
                            StackSmallRow(fight: fight)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.98))
                    }
                }

                if !model.finished.isEmpty {
                    StackHeading(text: "Archive")
                    ForEach(model.finished) { fight in
                        Button { model.openFightID = fight.id } label: {
                            StackSmallRow(fight: fight, done: true)
                        }
                        .buttonStyle(FFPressStyle(scale: 0.98))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    /// The pill: one line of status, the shape of a Dynamic Island.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                Text("\(model.live.count) live")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Rectangle()
                    .fill(theme.text.opacity(0.15))
                    .frame(width: 1, height: 12)
                Text(net)
                    .font(.ff(13, .bold))
                    .foregroundStyle(model.projectedNet < 0 ? theme.red : theme.green)
                Spacer(minLength: 0)
                Image(systemName: "bell.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background {
                Capsule()
                    .fill(theme.surface.opacity(0.7))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }

            Text("Your fights")
                .font(.ff(28, .bold))
                .foregroundStyle(theme.text)
        }
        .padding(.top, 8)
    }

    private var net: String {
        let value = model.projectedNet
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct StackHeading: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text)
            .font(.ff(13, .bold))
            .foregroundStyle(theme.faint)
            .padding(.top, 10)
    }
}

private struct StackCard: View {
    let fight: Fight
    let index: Int

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.name)
                        .font(.ff(20, .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(fight.metric.eyebrow) · \(fight.daysLeft ?? 0)d left")
                        .font(.ff(11))
                        .foregroundStyle(theme.faint)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("#\(fight.yourPlace ?? fight.rank)")
                        .font(.ff(17, .bold))
                        .foregroundStyle(theme.text)
                    Text("of \(fight.ranked.count)")
                        .font(.ff(9, .semibold))
                        .foregroundStyle(theme.faint)
                }
                .frame(width: 46, height: 46)
                .background(theme.text.opacity(0.07), in: Circle())
                .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
            }

            HStack(spacing: 8) {
                ForEach(fight.ranked.prefix(3)) { row in
                    chip(row)
                }
            }
            .padding(.top, 18)

            HStack(spacing: 6) {
                Text("$\(fight.pot)")
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.settlement.title)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                Spacer(minLength: 8)
                Text(pnl)
                    .font(.ff(13, .bold))
                    .foregroundStyle((fight.yours?.projectedNet ?? 0) < 0 ? theme.red : theme.green)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // The orb is what the glass has something to refract.
                Circle()
                    .fill(orbColor)
                    .frame(width: 210, height: 210)
                    .blur(radius: 60)
                    .offset(x: index % 2 == 0 ? 90 : -90, y: -50)
                shape.fill(theme.surface.opacity(0.55))
                shape.fill(.ultraThinMaterial)
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.text.opacity(0.10), lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    private var orbColor: Color {
        switch index % 3 {
        case 0: return theme.accent.opacity(0.55)
        case 1: return theme.green.opacity(0.45)
        default: return theme.amber.opacity(0.40)
        }
    }

    private func chip(_ row: Standing) -> some View {
        VStack(spacing: 5) {
            FFAvatar(row.person, size: 28)
            Text(model.formatScore(row.score, metric: fight.metric))
                .font(.ff(12, .bold))
                .foregroundStyle(theme.text)
            Text(row.person.name)
                .font(.ff(9))
                .foregroundStyle(theme.faint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            row.person.isYou ? theme.accent.opacity(0.18) : theme.text.opacity(0.05),
            in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
        )
    }

    private var pnl: String {
        let value = fight.yours?.projectedNet ?? 0
        return "\(value < 0 ? "−" : "+")$\(abs(value))"
    }
}

private struct StackSmallRow: View {
    let fight: Fight
    var done = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            FFAvatar(fight.standings.first?.person, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name)
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(done ? "Won" : (fight.inviteAction ?? "Join"))
                .font(.ff(12, .semibold))
                .foregroundStyle(done ? theme.green : theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        }
        .opacity(done ? 0.72 : 1)
    }
}
