import SwiftUI

struct ProfileIdentityLink<Label: View>: View {
    let userID: UUID?
    let source: String
    var onClosed: (() -> Void)? = nil
    @ViewBuilder var label: Label
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @State private var showingProfile = false

    var body: some View {
        if let userID {
            Button { showingProfile = true } label: { label.frame(minHeight: 44).contentShape(Rectangle()) }
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
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ProfileScreenStore()
    /// Your own statistics fill the You column of a friend's tale of the tape.
    @StateObject private var ownStore = ProfileScreenStore()
    @State private var eventID = UUID()
    @State private var busy = false
    @State private var actionError: String?
    @State private var confirmingBlock = false
    @State private var confirmingRemoval = false
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
            if let ownID = session.authSession?.user.id, ownID != userID, preview == nil {
                await ownStore.load(userID: ownID, session: session, includeHistory: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            store.clear()
            if phase == .active { Task { await store.load(userID: userID, session: session, preview: preview) } }
        }
        .onChange(of: session.authSession?.user.id) { _, _ in store.clear(); dismiss() }
        .onDisappear { store.clear() }
        .confirmationDialog(String(appLocalized: "Block this person?"), isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button(String(appLocalized: "Block"), role: .destructive) { Task { await act("block") } }
        } message: {
            Text(String(appLocalized: "This removes the friendship and hides profiles and shared artwork. Existing Fight results stay."))
        }
        .confirmationDialog(String(appLocalized: "Remove friend?"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button(String(appLocalized: "Remove friend"), role: .destructive) { Task { await act("remove") } }
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
        HStack(spacing: 14) {
            CompanionAvatar(
                personID: userID.uuidString, companionID: profile.identity.companionId,
                isYou: userID == session.authSession?.user.id, monogram: profile.identity.initials,
                photoURL: profile.identity.avatarUrl, size: 68
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.identity.displayName).ffType(.title)
                Text(verbatim: "@\(profile.identity.handle)").ffType(.caption).foregroundStyle(theme.textSecondary)
                if let id = profile.identity.companionId, let animal = StockCompanion(rawValue: id), animal.isLimited {
                    Text(animal.caption).ffType(.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if preview == nil && profile.friendship != "self" {
            friendshipActions(profile)
            FFButton(title: String(appLocalized: "Challenge"), fullWidth: true) { challenge(profile) }
        }
        if profile.access == "private" {
            FFNotice(text: String(appLocalized: "Private profile. Friends and current opponents can see what this person shares."), tone: .neutral, systemImage: "lock")
        } else if !profile.competitive && profile.access != "owner" {
            Text(String(appLocalized: "Casual profile. Competitive statistics are hidden."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        }
        if profile.friendship != "self" && preview == nil {
            let duels = profile.rivalry.map { $0.wins + $0.losses + $0.draws } ?? 0
            ProfileFoldedTape(
                theirName: profile.identity.displayName,
                theirCompanion: profile.identity.companionId,
                yourCompanion: session.profile?.companionId,
                rivalry: duels > 0 ? profile.rivalry : nil,
                note: duels > 0 ? nil : profile.competitive ? String(appLocalized: "No one-on-one yet") : String(appLocalized: "Keeps the score private"),
                yours: ownStore.profile?.stepStatistics,
                theirs: profile.stepStatistics
            )
        } else {
            if let record = profile.record { ProfileRecordCard(record: record) }
            if let rivalry = profile.rivalry {
                FFSection(title: String(appLocalized: "Your rivalry")) {
                    FFCard {
                        VStack(alignment: .leading, spacing: 12) {
                            if rivalry.wins + rivalry.losses + rivalry.draws == 0 {
                                Text(String(appLocalized: "No head-to-head results yet")).ffType(.body)
                            } else {
                                Text(String(format: String(appLocalized: "profile.rivalry-score"), rivalry.wins, rivalry.losses, rivalry.draws))
                                    .ffType(.heading)
                                Text(String(appLocalized: "Decided 1v1 Fights only. Group results appear in history."))
                                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }
            if let statistics = profile.stepStatistics {
                ProfileStepStatisticsView(statistics: statistics)
            }
        }
        if profile.friendship == "self" || preview != nil, let activity = profile.activity {
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
        if preview == nil {
            FFSection(title: profile.friendship == "self" ? String(appLocalized: "Fight history") : String(appLocalized: "Fights together")) {
                if store.history.isEmpty {
                    Text(profile.friendship == "self" ? String(appLocalized: "No results yet") : String(appLocalized: "No Fights together yet"))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                }
                ForEach(store.history) { row in
                    if let fightID = row.fightId, model.fight(id: fightID.uuidString) != nil {
                        Button {
                            model.openFight(id: fightID.uuidString, preserveRound: true)
                            dismiss()
                        } label: { FFCard { ProfileHistoryContent(row: row) } }
                        .buttonStyle(FFHapticPlainStyle())
                    } else {
                        FFCard { ProfileHistoryContent(row: row) }
                    }
                }
                if store.nextCursor != nil {
                    FFButton(title: String(appLocalized: "Load more"), kind: .ghost, busy: store.loading) {
                        Task { await store.loadMore(userID: userID, session: session) }
                    }
                }
            }
            if profile.friendship != "self" {
                HStack {
                    Button(String(appLocalized: "Report profile")) { reporting = true }
                    Spacer()
                    Button(String(appLocalized: "Block"), role: .destructive) { confirmingBlock = true }
                }.ffType(.label).frame(minHeight: 44).disabled(busy)
            }
        }
    }

    @ViewBuilder
    private func friendshipActions(_ profile: SharedProfile) -> some View {
        HStack {
            switch profile.friendship {
            case "outgoing":
                FFButton(title: String(appLocalized: "Requested, cancel"), kind: .secondary, busy: busy, fullWidth: true) { Task { await act("remove") } }
            case "incoming":
                FFButton(title: String(appLocalized: "Accept"), busy: busy) { Task { await act("accept") } }
                FFButton(title: String(appLocalized: "Decline"), kind: .secondary, busy: busy) { Task { await act("decline") } }
            case "friends":
                FFButton(title: String(appLocalized: "Friends"), kind: .secondary, busy: busy, fullWidth: true) { confirmingRemoval = true }
            default:
                FFButton(title: String(appLocalized: "Add friend"), busy: busy, fullWidth: true) { Task { await act("request") } }
            }
        }
    }

    private func challenge(_ profile: SharedProfile) {
        model.profileChallenge = ProfileChallengeDraft(handle: profile.identity.handle, durationSeconds: nil, actionText: nil)
        model.pendingJoinable = nil
        model.tab = .newFight
        dismiss()
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
            if action == "block" {
                try await FitFightAPI().blockProfile(userID: userID, accessToken: token)
                dismiss()
            } else if action == "report" {
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

private struct ProfileHistoryContent: View {
    let row: ProfileHistoryRow
    @Environment(\.ffTheme) private var theme
    private var result: String {
        switch row.result {
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
                Text(result)
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
