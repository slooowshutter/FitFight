import SwiftUI

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            FFScreenTitle(title: "Fights", subtitle: subtitle)
                .padding(.bottom, 6)

            if isEmpty {
                FFEmptyState(
                    systemImage: "trophy",
                    title: "No fights yet",
                    message: "Start one under New. Add people with their username — they must have signed in once.",
                    actionTitle: "Start one",
                    action: { model.tab = .newFight }
                )
            }

            if !model.invitations.isEmpty {
                FFSectionHeader(title: "Invitations")
                ForEach(model.invitations) { fight in
                    InvitationRow(fight: fight)
                }
            }

            // The kit allows one moss hero per screen: the fight you are closest to.
            if let lead = model.live.first {
                Button {
                    model.openFightID = lead.id
                } label: {
                    heroCard(lead)
                }
                .buttonStyle(FFPressStyle(scale: 0.985))
            }

            ForEach(model.live.dropFirst()) { fight in
                FFListRow(
                    monogram: initials(fight),
                    title: fight.name,
                    subtitle: fight.listSubtitle,
                    metric: leadScore(fight),
                    delta: fight.kickerEmphasis,
                    ahead: fight.rank == 1,
                    action: { model.openFightID = fight.id }
                )
            }

            if !model.finished.isEmpty {
                FFSectionHeader(title: "Finished")
                    .padding(.top, theme.space.lg)
                ForEach(model.finished) { fight in
                    FinishedRow(fight: fight)
                }
            }
        }
        .refreshable {
            await model.refreshFights(session: session, steps: steps)
        }
    }

    private var isEmpty: Bool {
        model.live.isEmpty && model.invitations.isEmpty && model.finished.isEmpty
    }

    private var subtitle: String {
        var parts: [String] = ["\(model.live.count) live"]
        if !model.invitations.isEmpty { parts.append("\(model.invitations.count) waiting") }
        return parts.joined(separator: " · ")
    }

    private func heroCard(_ fight: Fight) -> some View {
        FFHeroCard(
            eyebrow: fight.daysLeft.map { "Ends in \($0) days" } ?? fight.metric.eyebrow,
            tag: fight.of == 2 ? "Head to head" : "\(fight.of) in this fight",
            title: fight.name,
            metric: leadScore(fight),
            caption: caption(fight),
            monogram: initials(fight),
            progress: progress(fight)
        )
    }

    private func caption(_ fight: Fight) -> String {
        let unit = fight.metric.eyebrow.lowercased()
        let kicker = [fight.kickerPrefix, fight.kickerEmphasis, fight.kickerRest]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return kicker.isEmpty ? unit : "\(unit) · \(kicker)"
    }

    /// The hero's number is your own score, or the leader's if you are not in it.
    private func leadScore(_ fight: Fight) -> String {
        let standing = model.youStanding(in: fight) ?? fight.standings.first
        guard let standing else { return "—" }
        return model.formatScore(standing.score, metric: fight.metric)
    }

    private func progress(_ fight: Fight) -> Double {
        let scores = fight.standings.filter { !$0.invited }.map(\.score)
        guard let peak = scores.max(), peak > 0 else { return 0 }
        let mine = model.youStanding(in: fight)?.score ?? scores.first ?? 0
        return min(mine / peak, 1)
    }

    /// The other side of a head-to-head, so the hero avatar is who you are up against.
    private func initials(_ fight: Fight) -> String {
        let other = fight.standings.first { !$0.person.isYou && !$0.invited }
        return other?.person.initials ?? fight.standings.first?.person.initials ?? "?"
    }
}

struct InvitationRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 13) {
            FFAvatar(fight.inviter ?? fight.standings.first?.person, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.name)
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                model.openFightID = fight.id
            } label: {
                FFPill(fight.inviteAction ?? "Join", style: .solidMoss)
            }
            .buttonStyle(FFPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.mossWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.mossText.opacity(0.18), radius: theme.radius.card)
        .contentShape(Rectangle())
        .onTapGesture { model.openFightID = fight.id }
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
            HStack(spacing: 13) {
                FFResultGlyph(fight.rank == 1 ? .win : .loss)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fight.name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(fight.endedLabel ?? fight.listSubtitle)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                FFAvatarStack(
                    monograms: fight.standings.map(\.person.initials),
                    visible: 2,
                    size: 26,
                    ring: theme.card
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(FFPressStyle())
    }
}
