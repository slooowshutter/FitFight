import SwiftUI

struct ProfileIdentityLink<Label: View>: View {
    let userID: UUID?
    let source: String
    var onClosed: (() -> Void)? = nil
    @ViewBuilder var label: Label
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var showingProfile = false

    var body: some View {
        if let userID {
            Button {
                // Your own name opens your Profile tab instead of a sheet about yourself.
                if userID == session.authSession?.user.id { model.tab = .you } else { showingProfile = true }
            } label: { label.frame(minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(FFHapticPlainStyle())
            .accessibilityHint(String(appLocalized: "Open profile"))
            .sheet(isPresented: $showingProfile, onDismiss: onClosed) {
                ProfileSheet(userID: userID, source: source)
                    .fitFightTheme(theme)
                    .presentationBackground(theme.bg)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: session.authSession?.user.id) { _, _ in showingProfile = false }
        } else {
            label
        }
    }
}

struct ProfileSheet: View {
    let userID: UUID
    let source: String
    var preview: String? = nil
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ProfileScreenStore()
    @State private var eventID = UUID()
    @State private var busy = false
    @State private var actionError: String?
    @State private var confirmingRemoval = false
    @State private var confirmingCancel = false
    @State private var comparing = false
    @State private var showingAllTogether = false
    @State private var showingTheirStreak = false
    @State private var reporting = false
    @State private var reportReason = ""

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(
                title: preview == nil ? String(appLocalized: "Profile") : String(appLocalized: "Profile preview"),
                role: .heading
            ) { dismiss() }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if store.loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error = store.error ?? actionError {
                        FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                        FFButton(title: String(appLocalized: "Retry"), kind: .secondary) {
                            Task { await store.load(userID: userID, session: session, preview: preview) }
                        }
                    }
                    if let profile = store.profile {
                        profileContent(profile)
                            .task(id: profile.identity.userId) {
                                guard preview == nil, profile.viewMeasurementEnabled,
                                      userID != session.authSession?.user.id else { return }
                                guard let token = try? await session.freshAccessToken() else { return }
                                try? await FitFightAPI().recordProfileView(userID: userID, eventID: eventID, source: source, accessToken: token)
                            }
                    }
                }
                .padding(theme.space.screenPadding)
            }
        }
        .foregroundStyle(theme.text)
        .background(theme.bg.ignoresSafeArea())
        .task(id: userID) {
            await store.load(userID: userID, session: session, preview: preview)
        }
        .onChange(of: scenePhase) { _, phase in
            store.clear()
            if phase == .active { Task { await store.load(userID: userID, session: session, preview: preview) } }
        }
        .onChange(of: session.authSession?.user.id) { _, _ in store.clear(); dismiss() }
        .onDisappear { store.clear() }
        .confirmationDialog(String(appLocalized: "Remove friend?"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button(String(appLocalized: "Remove friend"), role: .destructive) { Task { await act("remove") } }
        } message: {
            Text(String(appLocalized: "You stop seeing each other's steps. Fights together and your record stay."))
        }
        .confirmationDialog(String(appLocalized: "Cancel your friend request?"), isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button(String(appLocalized: "Cancel request"), role: .destructive) { Task { await act("remove") } }
            Button(String(appLocalized: "Keep request"), role: .cancel) {}
        }
        .alert(String(appLocalized: "Report profile"), isPresented: $reporting) {
            TextField(String(appLocalized: "Reason"), text: $reportReason)
            Button(String(appLocalized: "Send report")) { Task { await act("report") } }
                .disabled(reportReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(appLocalized: "Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func profileContent(_ profile: SharedProfile) -> some View {
        if profile.friendship == "self" || preview != nil {
            ownContent(profile)
        } else {
            playerCard(profile)
            if profile.friendship == "incoming" {
                FFCard(fill: theme.mossWash, stroke: theme.mossEdge) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: String(appLocalized: "profile.wants-to-be-friends"), profile.identity.displayName))
                                .ffType(.heading)
                            Text(String(appLocalized: "Friends can see each other's shared steps and stats."))
                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        HStack(spacing: 10) {
                            FFButton(title: String(appLocalized: "Accept"), busy: busy, fullWidth: true) { Task { await act("accept") } }
                            FFButton(title: String(appLocalized: "Decline"), kind: .secondary, busy: busy, fullWidth: true) { Task { await act("decline") } }
                        }
                    }
                }
            }
            if profile.access == "private" {
                FFCard {
                    VStack(spacing: 4) {
                        Image(systemName: "lock").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.textSecondary).padding(.bottom, 4)
                        Text(String(appLocalized: "Private profile")).ffType(.heading)
                        lockedNote(profile, about: String(format: String(appLocalized: "profile.private-note"), profile.identity.displayName))
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if let headToHead = profile.headToHead {
                againstYou(profile, headToHead: headToHead)
            }
            if let statistics = profile.stepStatistics, let activity = profile.activity {
                recentSteps(profile, statistics: statistics, activity: activity)
            }
        }
        if preview == nil {
            let isSelf = profile.friendship == "self"
            FFSection(title: isSelf ? String(appLocalized: "Fight history") : String(appLocalized: "Fights together")) {
                if store.history.isEmpty {
                    Text(isSelf ? String(appLocalized: "No results yet") : String(appLocalized: "No Fights together yet"))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.history) { row in
                            if !showingAllTogether, (store.history.firstIndex(of: row) ?? 0) >= 5 {
                                EmptyView()
                            } else if let fightID = row.fightId, model.fight(id: fightID.uuidString) != nil {
                                Button {
                                    model.openFight(id: fightID.uuidString, preserveRound: true)
                                    dismiss()
                                } label: { historyRow(row, profile: profile) }
                                .buttonStyle(FFHapticPlainStyle())
                            } else {
                                historyRow(row, profile: profile)
                            }
                        }
                        if !showingAllTogether && (store.history.count > 5 || store.nextCursor != nil) {
                            moreRow(store.nextCursor == nil
                                ? String(format: String(appLocalized: "profile.show-all"), store.history.count)
                                : String(appLocalized: "Show all")) { showingAllTogether = true }
                        }
                        if store.nextCursor != nil, showingAllTogether {
                            moreRow(String(appLocalized: "Load more")) {
                                Task { await store.loadMore(userID: userID, session: session) }
                            }
                            .disabled(store.loading)
                        }
                    }
                    .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                    .ffBorder(theme.hairline, radius: theme.radius.card)
                }
            }
            if !isSelf {
                Button(String(appLocalized: "Report profile")) { reporting = true }
                    .ffType(.label).foregroundStyle(theme.textSecondary)
                    .frame(minHeight: 44).disabled(busy)
            }
        }
    }

    /// Your own profile, and the preview of what others see.
    @ViewBuilder
    private func ownContent(_ profile: SharedProfile) -> some View {
        HStack(spacing: 14) {
            CompanionAvatar(
                personID: userID.uuidString, companionID: profile.identity.companionId,
                isYou: userID == session.authSession?.user.id, monogram: profile.identity.initials,
                photoURL: profile.identity.avatarUrl, size: 68
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.identity.displayName).ffType(.title)
                Text(verbatim: "@\(profile.identity.handle)").ffType(.caption).foregroundStyle(theme.textSecondary)
            }
        }
        // A stock or Special companion's words ship in the app; a custom one's come with the profile.
        let animal = companions.animal(for: userID.uuidString, companionID: profile.identity.companionId)
        if let name = animal?.name ?? profile.companionName {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).ffType(.label).foregroundStyle(theme.text)
                if let line = animal?.caption ?? profile.companionLine {
                    Text(verbatim: line).ffType(.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if profile.access == "private" {
            FFNotice(text: String(appLocalized: "Private profile. Friends and current opponents can see what this person shares."), tone: .neutral, systemImage: "lock")
        } else if !profile.competitive && profile.access != "owner" {
            Text(String(appLocalized: "Casual profile. Competitive statistics are hidden."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        }
        if let record = profile.record { ProfileRecordCard(record: record) }
        if let statistics = profile.stepStatistics {
            ProfileStepStatisticsView(statistics: statistics)
        }
        if let activity = profile.activity {
            FFSection(title: String(format: String(appLocalized: "profile.steps-period"), activity.days)) {
                FFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(appLocalized: "Only stored days are shown. Missing days are unknown, not zero."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        ForEach(activity.values) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(verbatim: day.day)
                                    Spacer()
                                    Text(day.steps.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale)))
                                }.ffType(.label)
                                Text(verbatim: day.timeZone ?? String(appLocalized: "Historical time zone unavailable"))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                Text(day.finalized ? String(appLocalized: "Complete day") : String(appLocalized: "Partial day"))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                if let updated = parseServerDate(day.updatedAt) {
                                    HStack(spacing: 4) {
                                        Text(String(appLocalized: "Last updated"))
                                        Text(updated, format: .relative(presentation: .named))
                                    }.ffType(.micro).foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                        if activity.values.isEmpty { Text(String(appLocalized: "No shared days available")).ffType(.body) }
                    }
                }
            }
        }
    }

    /// The Player card: companion, @username, 10K streak, line, member since, friend button, then stats.
    private func playerCard(_ profile: SharedProfile) -> some View {
        let animal = companions.animal(for: userID.uuidString, companionID: profile.identity.companionId)
        let line = animal?.caption ?? profile.companionLine
        let since = profile.memberSince.flatMap(profileDay)
        let cells = playerStats(profile)
        return FFCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    CompanionAvatar(
                        personID: userID.uuidString, companionID: profile.identity.companionId,
                        monogram: profile.identity.initials, photoURL: profile.identity.avatarUrl, size: 124
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            HStack(spacing: 0) {
                                Text(verbatim: "@").foregroundStyle(theme.textSecondary)
                                Text(verbatim: profile.identity.handle).foregroundStyle(theme.text)
                            }
                            .ffType(.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            Spacer(minLength: 0)
                            if let streak = profile.tenKStreak, streak.current > 0 {
                                TenKStreakPill(days: streak.current) { showingTheirStreak = true }
                                    .popover(isPresented: $showingTheirStreak) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label(String(format: String(appLocalized: "profile.their-streak-title"), streakDayCount(streak.current)), systemImage: "flame.fill")
                                                .font(.ff(15, 800)).foregroundStyle(theme.gold)
                                            Text(String(format: String(appLocalized: "profile.their-streak-detail"), profile.identity.displayName, streakDayCount(streak.current)))
                                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(16)
                                        .frame(width: 260, alignment: .leading)
                                        .presentationCompactAdaptation(.popover)
                                        .presentationBackground(theme.overlay)
                                    }
                            }
                        }
                        if let line {
                            Text(verbatim: line).font(.ff(13, 700)).italic().foregroundStyle(theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let since {
                            Text(String(format: String(appLocalized: "profile.member-since"),
                                        since.formatted(Date.FormatStyle(locale: AppLocalization.locale, timeZone: .gmt).month(.abbreviated).year())))
                                .ffType(.micro).foregroundStyle(theme.textSecondary)
                                .padding(.top, 4)
                        }
                        friendButton(profile).padding(.top, 6)
                    }
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(EdgeInsets(top: 18, leading: 10, bottom: 14, trailing: 18))
                ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { index in
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    HStack(spacing: 0) {
                        statCell(cells[index])
                        Rectangle().fill(theme.hairline).frame(width: 1)
                        if index + 1 < cells.count { statCell(cells[index + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The record shows to anyone who can see it; the step pair only when this person shares Steps with you.
    private func playerStats(_ profile: SharedProfile) -> [(value: String, label: String, gold: Bool)] {
        var cells: [(value: String, label: String, gold: Bool)] = []
        if let record = profile.record, let draws = record.draws, let losses = record.losses {
            cells.append((value: "\(record.wins)-\(losses)-\(draws)", label: String(appLocalized: "won · lost · drew"), gold: false))
            cells.append((
                value: record.winRate.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale)) } ?? "-",
                label: String(format: String(appLocalized: "profile.win-rate-fights"), profileFightCount(record.played)),
                gold: false
            ))
        }
        if let statistics = profile.stepStatistics {
            let days = statistics.scopeDays ?? 30
            cells.append((value: statistics.averageSteps.map(formattedSteps) ?? "-",
                          label: String(format: String(appLocalized: "profile.day-average"), days), gold: false))
            cells.append((value: statistics.bestDay.map { formattedSteps($0.steps) } ?? "-",
                          label: String(format: String(appLocalized: "profile.best-day-period"), days), gold: true))
        }
        return cells
    }

    private func statCell(_ cell: (value: String, label: String, gold: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: cell.value).font(.ff(20, 800)).monospacedDigit()
                .foregroundStyle(cell.gold ? theme.gold : theme.text)
            Text(cell.label).ffType(.caption).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func friendButton(_ profile: SharedProfile) -> some View {
        switch profile.friendship {
        case "friends":
            friendPill(String(appLocalized: "Friends"), systemImage: "person.fill.checkmark", fill: theme.control, ink: theme.text, edge: theme.chipEdge) {
                confirmingRemoval = true
            }
        case "outgoing":
            friendPill(String(appLocalized: "Requested"), systemImage: "clock", fill: theme.control, ink: theme.textSecondary, edge: theme.chipEdge) {
                confirmingCancel = true
            }
        case "incoming":
            EmptyView()
        default:
            friendPill(String(appLocalized: "Add friend"), systemImage: "person.badge.plus", fill: theme.mossWash, ink: theme.mossText, edge: theme.mossEdge) {
                Task { await act("request") }
            }
        }
    }

    private func friendPill(_ title: String, systemImage: String, fill: Color, ink: Color, edge: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.ff(12, 800))
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(fill, in: Capsule())
                .overlay { Capsule().strokeBorder(edge, lineWidth: 1) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .disabled(busy)
    }

    /// Why something is hidden, with the friendship step that would show it.
    @ViewBuilder
    private func lockedNote(_ profile: SharedProfile, about: String) -> some View {
        let name = profile.identity.displayName
        let text = profile.friendship == "outgoing" ? String(format: String(appLocalized: "profile.locked-requested"), name)
            : profile.friendship == "incoming" ? String(format: String(appLocalized: "profile.locked-incoming"), name)
            : about
        Text(text).ffType(.caption).foregroundStyle(theme.textSecondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 270)
        if profile.friendship == "none" {
            friendPill(String(appLocalized: "Add friend"), systemImage: "person.badge.plus", fill: theme.mossWash, ink: theme.mossText, edge: theme.mossEdge) {
                Task { await act("request") }
            }
            .padding(.top, 6)
        } else if profile.friendship == "outgoing" {
            Button(String(appLocalized: "Cancel request")) { confirmingCancel = true }
                .font(.ff(13, 800)).foregroundStyle(theme.textSecondary).frame(minHeight: 44)
        }
    }

    /// Every finished Fight you were both in, 1v1 and group, with steps since you became friends below.
    private func againstYou(_ profile: SharedProfile, headToHead: ProfileHeadToHead) -> some View {
        let name = profile.identity.displayName
        let you = session.profile
        return FFCard(padding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(appLocalized: "Against you")).ffType(.heading)
                        Spacer(minLength: 8)
                        Text(profileFightCount(headToHead.wins + headToHead.draws + headToHead.losses))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        CompanionAvatar(personID: you?.userId.uuidString, companionID: you?.companionId, isYou: true,
                                        monogram: you?.initials ?? "?", photoURL: you?.photoURL, size: 56)
                        VStack(spacing: 2) {
                            HStack(spacing: 6) {
                                Text(verbatim: "\(headToHead.wins)").foregroundStyle(theme.mossText)
                                Text(verbatim: "-").foregroundStyle(theme.textFaint)
                                Text(verbatim: "\(headToHead.draws)").foregroundStyle(theme.textSecondary)
                                Text(verbatim: "-").foregroundStyle(theme.textFaint)
                                Text(verbatim: "\(headToHead.losses)").foregroundStyle(theme.emberText)
                            }
                            .font(.ff(30, 800)).monospacedDigit()
                            Text(String(format: String(appLocalized: "profile.against-legend"), name))
                                .ffType(.micro).foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(format: String(appLocalized: "profile.against-accessibility"), headToHead.wins, headToHead.draws, headToHead.losses))
                        CompanionAvatar(personID: userID.uuidString, companionID: profile.identity.companionId,
                                        monogram: profile.identity.initials, photoURL: profile.identity.avatarUrl, size: 56)
                    }
                    if headToHead.form.isEmpty {
                        Text(String(appLocalized: "No finished Fights together yet."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: String(appLocalized: "profile.last-results"), headToHead.form.count))
                                .ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                            HStack(spacing: 5) {
                                ForEach(Array(headToHead.form.prefix(10).enumerated()), id: \.offset) { _, result in
                                    Text(result == "win" ? String(appLocalized: "profile.form-win")
                                         : result == "loss" ? String(appLocalized: "profile.form-loss") : String(appLocalized: "profile.form-draw"))
                                        .font(.ff(11, 800))
                                        .foregroundStyle(result == "win" ? theme.mossText : result == "loss" ? theme.emberText : theme.textSecondary)
                                        .frame(maxWidth: .infinity, minHeight: 26)
                                        .background(result == "win" ? theme.mossWash : result == "loss" ? theme.emberWash : theme.chip,
                                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                // Ten even slots, so a short run keeps the same chip width.
                                ForEach(min(headToHead.form.count, 10)..<10, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 26)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                if comparing {
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    compareSteps(profile).padding(.horizontal, 18)
                }
                Rectangle().fill(theme.hairline).frame(height: 1)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { comparing.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(comparing ? String(appLocalized: "Hide steps") : String(appLocalized: "Compare steps"))
                        Image(systemName: "chevron.down").rotationEffect(.degrees(comparing ? 180 : 0))
                    }
                    .font(.ff(13, 800))
                    .foregroundStyle(theme.mossText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }

    @ViewBuilder
    private func compareSteps(_ profile: SharedProfile) -> some View {
        if let comparison = profile.friendComparison {
            VStack(spacing: 0) {
                Text(comparison.days == 0
                     ? String(appLocalized: "Since you became friends today")
                     : String(format: String(appLocalized: "profile.friends-since"),
                              profileDay(comparison.since)?.formatted(Date.FormatStyle(locale: AppLocalization.locale, timeZone: .gmt).day().month(.abbreviated)) ?? comparison.since))
                    .font(.ff(12, 800)).foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12).padding(.bottom, 4)
                if comparison.days == 0 {
                    Text(String(appLocalized: "Your comparison starts tomorrow."))
                        .ffType(.label).foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)
                } else {
                    compareRow(String(appLocalized: "Total steps"), you: comparison.you.totalSteps, them: comparison.them.totalSteps)
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    compareRow(String(appLocalized: "Daily average"), you: comparison.you.averageSteps, them: comparison.them.averageSteps)
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    compareRow(String(appLocalized: "Best day"), you: comparison.you.bestDaySteps, them: comparison.them.bestDaySteps)
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    compareRow(String(appLocalized: "10K+ days"), you: Double(comparison.you.tenKDays), them: Double(comparison.them.tenKDays))
                }
            }
        } else {
            VStack(spacing: 4) {
                lockedNote(profile, about: profile.friendship == "friends"
                           ? String(format: String(appLocalized: "profile.locked-not-shared"), profile.identity.displayName)
                           : String(appLocalized: "Become friends to compare steps."))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    /// Your number left, theirs right; the leader's side of the bar takes moss or ember. The mark is even.
    private func compareRow(_ label: String, you: Double?, them: Double?) -> some View {
        let mine = you ?? 0
        let theirs = them ?? 0
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: you.map(formattedSteps) ?? "-")
                    .foregroundStyle(mine > theirs ? theme.mossText : theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(label)
                    .font(.ff(11, 800)).tracking(0.9).textCase(.uppercase)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1).fixedSize()
                Text(verbatim: them.map(formattedSteps) ?? "-")
                    .foregroundStyle(theirs > mine ? theme.emberText : theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.ff(15, 800)).monospacedDigit()
            GeometryReader { proxy in
                HStack(spacing: 4) {
                    Capsule().fill(mine > theirs ? theme.mossFill : theme.textFaint)
                        .frame(width: max(0, (proxy.size.width - 4) * (mine + theirs > 0 ? mine / (mine + theirs) : 0.5)))
                    Capsule().fill(theirs > mine ? theme.emberFill : theme.textFaint)
                }
                .overlay { Capsule().fill(theme.text.opacity(0.55)).frame(width: 2, height: 14) }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Their shared days as bars, the best in full gold, then the days spent at each activity level.
    private func recentSteps(_ profile: SharedProfile, statistics: ProfileStepStatistics, activity: ProfileActivity) -> some View {
        let days = activity.values.filter { $0.day <= statistics.through }
        let best = days.map(\.steps).max() ?? 0
        let counted = statistics.levels.reduce(0) { $0 + $1.days }
        return FFCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: String(appLocalized: "profile.their-last-days"), profile.identity.displayName, activity.days))
                        .ffType(.heading)
                    Spacer(minLength: 8)
                    Text(String(appLocalized: "profile.ten-k-day-count", defaultValue: "\(days.filter { $0.steps >= 10_000 }.count) days at 10K+"))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days) { day in
                        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
                            .fill(day.steps == best ? theme.gold : theme.gold.opacity(day.steps >= 10_000 ? 0.82 : 0.64))
                            .frame(maxWidth: .infinity)
                            .frame(height: best > 0 ? max(6, 64 * day.steps / best) : 6)
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .accessibilityHidden(true)
                if counted > 0 {
                    GeometryReader { proxy in
                        let levels = statistics.levels.filter { $0.days > 0 }
                        HStack(spacing: 2) {
                            ForEach(levels) { level in
                                Rectangle().fill(levelColor(level.level))
                                    .frame(width: max(0, (proxy.size.width - CGFloat(levels.count - 1) * 2) * CGFloat(level.days) / CGFloat(counted)))
                            }
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(statistics.levels) { level in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(levelColor(level.level)).frame(width: 9, height: 9)
                            Text(verbatim: "\(ProfileStepStatisticsView.levelName(level.level)) \(level.days)")
                                .ffType(.micro).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "couch": theme.gold.opacity(0.28)
        case "warming_up": theme.gold.opacity(0.46)
        case "moving": theme.gold.opacity(0.64)
        case "active": theme.gold.opacity(0.82)
        default: theme.gold
        }
    }

    private func historyRow(_ row: ProfileHistoryRow, profile: SharedProfile) -> some View {
        Group {
            if profile.friendship == "self" {
                ProfileHistoryContent(row: row)
            } else {
                ProfileTogetherRow(row: row, name: profile.identity.displayName, liveGap: liveGap(row))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if row != store.history.first { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }

    private func moreRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ff(13, 800)).foregroundStyle(theme.mossText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
    }

    /// Your lead over this person in a live Fight, from its standings on this phone.
    private func liveGap(_ row: ProfileHistoryRow) -> Double? {
        guard row.result == "ongoing", let fightID = row.fightId, let fight = model.fight(id: fightID.uuidString),
              let mine = fight.standings.first(where: { $0.person.isYou })?.score,
              let theirs = fight.standings.first(where: { $0.person.id.caseInsensitiveCompare(userID.uuidString) == .orderedSame })?.score
        else { return nil }
        return mine - theirs
    }

    private func act(_ action: String) async {
        guard !busy else { return }
        let accountID = session.authSession?.user.id
        busy = true
        actionError = nil
        store.clear()
        defer { busy = false }
        do {
            let token = try await session.freshAccessToken()
            if action == "report" {
                try await FitFightAPI().reportProfile(userID: userID, reason: reportReason, accessToken: token)
                await store.load(userID: userID, session: session)
            } else {
                _ = try await FitFightAPI().changeFriendship(userID: userID, action: action, accessToken: token)
                await store.load(userID: userID, session: session)
            }
        } catch is CancellationError {
        } catch {
            guard accountID == session.authSession?.user.id else { return }
            actionError = error.localizedDescription
        }
    }
}

struct ProfileRecordCard: View {
    let record: ProfileRecord
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 16) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
                layout {
                    metric(String(appLocalized: "Fights played"), value: record.played.formatted(.number.locale(AppLocalization.locale)))
                    metric(String(appLocalized: "Wins"), value: record.wins.formatted(.number.locale(AppLocalization.locale)))
                    metric(String(appLocalized: "Win rate"), value: record.winRate.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale)) } ?? String(appLocalized: "No results yet"))
                }
                ForEach(["public", "private", "unknown"], id: \.self) { category in
                    if let counts = record.categories[category], counts.played > 0 {
                        HStack {
                            Text(category == "public" ? String(appLocalized: "Public Fights") : category == "private" ? String(appLocalized: "Private Fights") : String(appLocalized: "Category unknown"))
                            Spacer()
                            Text(String(format: String(appLocalized: "profile.category-record"), counts.wins, counts.played))
                        }.ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
                if record.excluded > 0 {
                    Text(String(appLocalized: "Ongoing, cancelled, solo and unverifiable historical results are excluded from win rate."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).ffType(.heading).foregroundStyle(theme.text)
            Text(title).ffType(.caption).foregroundStyle(theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct ProfileHistoryContent: View {
    let row: ProfileHistoryRow
    @Environment(\.ffTheme) private var theme
    static func label(for result: String) -> String {
        switch result {
        case "win": return String(appLocalized: "Won")
        case "loss": return String(appLocalized: "Lost")
        case "draw": return String(appLocalized: "Draw")
        case "withdrawn": return String(appLocalized: "Withdrew")
        case "removed": return String(appLocalized: "Removed")
        case "incomplete": return String(appLocalized: "Incomplete final sync")
        case "cancelled": return String(appLocalized: "Cancelled")
        case "ongoing": return String(appLocalized: "Ongoing")
        case "solo": return String(appLocalized: "Solo Fight")
        case "not_entered": return String(appLocalized: "Did not enter")
        default: return String(appLocalized: "Historical result unavailable")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: row.name ?? String(appLocalized: "Fight result")).ffType(.heading)
            HStack {
                Text(Self.label(for: row.result))
                Spacer()
                if let placement = row.placement {
                    Text(String(format: String(appLocalized: "profile.placement"), placement, row.fieldSize))
                }
            }.ffType(.label)
            Text(verbatim: String(row.endsAt.prefix(10))).ffType(.caption).foregroundStyle(theme.textSecondary)
            if row.complete == false && row.result != "incomplete" {
                Text(String(appLocalized: "Incomplete final sync")).ffType(.caption).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

/// One Fight you were both in: your result against this person, both places in a group, or your live lead.
struct ProfileTogetherRow: View {
    let row: ProfileHistoryRow
    let name: String
    let liveGap: Double?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.name ?? String(appLocalized: "Fight result"))
                    .font(.ff(15, 800)).foregroundStyle(theme.text).lineLimit(1)
                Text(verbatim: detail).ffType(.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            outcome
                .font(.ff(13, 800))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let size = row.fieldSize == 2 ? String(appLocalized: "1v1") : String(format: String(appLocalized: "profile.group-of"), row.fieldSize)
        let date = parseServerDate(row.endsAt)?.formatted(Date.FormatStyle(locale: AppLocalization.locale).day().month(.abbreviated)) ?? ""
        return row.result == "ongoing"
            ? "\(size) · " + String(format: String(appLocalized: "profile.ends-on"), date)
            : "\(size) · \(date)"
    }

    @ViewBuilder
    private var outcome: some View {
        if row.result == "ongoing" {
            if let liveGap {
                HStack(spacing: 5) {
                    Circle().frame(width: 7, height: 7)
                    if liveGap >= 0 {
                        Text(String(format: String(appLocalized: "profile.live-ahead"), formattedSteps(liveGap)))
                    } else {
                        Text(String(format: String(appLocalized: "profile.live-behind"), formattedSteps(-liveGap)))
                    }
                }
                .foregroundStyle(liveGap >= 0 ? theme.mossText : theme.emberText)
            } else {
                Text(String(appLocalized: "Ongoing")).foregroundStyle(theme.textSecondary)
            }
        } else if let result = row.headToHead {
            let color = result == "win" ? theme.mossText : result == "loss" ? theme.emberText : theme.textSecondary
            if row.fieldSize > 2, let mine = row.viewerPlacement, let theirs = row.placement {
                Text(String(format: String(appLocalized: "profile.both-places"), AppModel.ordinal(mine), name, AppModel.ordinal(theirs)))
                    .foregroundStyle(color)
            } else if result == "win" {
                Text(String(appLocalized: "You won")).foregroundStyle(color)
            } else if result == "loss" {
                Text(String(format: String(appLocalized: "profile.they-won"), name)).foregroundStyle(color)
            } else {
                Text(String(appLocalized: "Draw")).foregroundStyle(color)
            }
        } else {
            Text(ProfileHistoryContent.label(for: row.result)).foregroundStyle(theme.textSecondary)
        }
    }
}
