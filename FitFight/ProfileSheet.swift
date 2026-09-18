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
            .accessibilityHint(String(localized: "Open profile"))
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
    @State private var eventID = UUID()
    @State private var busy = false
    @State private var actionError: String?
    @State private var confirmingBlock = false
    @State private var confirmingRemoval = false
    @State private var reporting = false
    @State private var reportReason = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preview == nil ? String(localized: "Profile") : String(localized: "Profile preview"))
                    .ffType(.heading)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if store.loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error = store.error ?? actionError {
                        FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                        FFButton(title: String(localized: "Retry"), kind: .secondary) {
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
        .task(id: userID) { await store.load(userID: userID, session: session, preview: preview) }
        .onChange(of: scenePhase) { _, phase in
            store.clear()
            if phase == .active { Task { await store.load(userID: userID, session: session, preview: preview) } }
        }
        .onChange(of: session.authSession?.user.id) { _, _ in store.clear(); dismiss() }
        .onDisappear { store.clear() }
        .confirmationDialog(String(localized: "Block this person?"), isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button(String(localized: "Block"), role: .destructive) { Task { await act("block") } }
        } message: {
            Text(String(localized: "This removes the friendship and hides profiles and shared artwork. Existing Fight results stay."))
        }
        .confirmationDialog(String(localized: "Remove friend?"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button(String(localized: "Remove friend"), role: .destructive) { Task { await act("remove") } }
        }
        .alert(String(localized: "Report profile"), isPresented: $reporting) {
            TextField(String(localized: "Reason"), text: $reportReason)
            Button(String(localized: "Send report")) { Task { await act("report") } }
                .disabled(reportReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "Cancel"), role: .cancel) {}
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
            }
        }
        if preview == nil && profile.friendship != "self" {
            friendshipActions(profile)
            FFButton(title: String(localized: "Challenge"), fullWidth: true) { challenge(profile) }
        }
        if profile.access == "private" {
            FFNotice(text: String(localized: "Private profile. Friends and current opponents can see what this person shares."), tone: .neutral, systemImage: "lock")
        } else if !profile.competitive && profile.access != "owner" {
            Text(String(localized: "Casual profile. Competitive statistics are hidden."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        }
        if let record = profile.record { ProfileRecordCard(record: record) }
        if let rivalry = profile.rivalry {
            FFSection(title: String(localized: "Your rivalry")) {
                FFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if rivalry.wins + rivalry.losses + rivalry.draws == 0 {
                            Text(String(localized: "No head-to-head results yet")).ffType(.body)
                        } else {
                            Text(String(format: String(localized: "profile.rivalry-score"), rivalry.wins, rivalry.losses, rivalry.draws))
                                .ffType(.heading)
                            Text(String(localized: "Decided 1v1 Fights only. Group results appear in history."))
                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
        if let activity = profile.activity {
            FFSection(title: String(format: String(localized: "profile.steps-period"), activity.days)) {
                FFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Only stored days are shown. Missing days are unknown, not zero."))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                        ForEach(activity.values) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(verbatim: day.day)
                                    Spacer()
                                    Text(day.steps.formatted(.number.precision(.fractionLength(0))))
                                }.ffType(.label)
                                Text(verbatim: day.timeZone ?? String(localized: "Historical time zone unavailable"))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                Text(day.finalized ? String(localized: "Complete day") : String(localized: "Partial day"))
                                    .ffType(.micro).foregroundStyle(theme.textSecondary)
                                if let updated = FightRow.parse(day.updatedAt) {
                                    HStack(spacing: 4) {
                                        Text(String(localized: "Last updated"))
                                        Text(updated, format: .relative(presentation: .named))
                                    }.ffType(.micro).foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                        if activity.values.isEmpty { Text(String(localized: "No shared days available")).ffType(.body) }
                    }
                }
            }
        }
        if preview == nil {
            FFSection(title: profile.friendship == "self" ? String(localized: "Fight history") : String(localized: "Fights together")) {
                if store.history.isEmpty {
                    Text(profile.friendship == "self" ? String(localized: "No results yet") : String(localized: "No Fights together yet"))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                }
                ForEach(store.history) { row in
                    if let fightID = row.fightId, model.canonicalFight(for: fightID.uuidString) != nil {
                        Button {
                            model.openFightFromFeed(id: fightID.uuidString)
                            dismiss()
                        } label: { FFCard { ProfileHistoryContent(row: row) } }
                        .buttonStyle(FFHapticPlainStyle())
                    } else {
                        FFCard { ProfileHistoryContent(row: row) }
                    }
                }
                if store.nextCursor != nil {
                    FFButton(title: String(localized: "Load more"), kind: .ghost, busy: store.loading) {
                        Task { await store.loadMore(userID: userID, session: session) }
                    }
                }
            }
            if profile.friendship != "self" {
                HStack {
                    Button(String(localized: "Report profile")) { reporting = true }
                    Spacer()
                    Button(String(localized: "Block"), role: .destructive) { confirmingBlock = true }
                }.ffType(.label).frame(minHeight: 44).disabled(busy)
            }
        }
    }

    @ViewBuilder
    private func friendshipActions(_ profile: SharedProfile) -> some View {
        HStack {
            switch profile.friendship {
            case "outgoing":
                FFButton(title: String(localized: "Requested, cancel"), kind: .secondary, busy: busy, fullWidth: true) { Task { await act("remove") } }
            case "incoming":
                FFButton(title: String(localized: "Accept"), busy: busy) { Task { await act("accept") } }
                FFButton(title: String(localized: "Decline"), kind: .secondary, busy: busy) { Task { await act("decline") } }
            case "friends":
                FFButton(title: String(localized: "Friends"), kind: .secondary, busy: busy, fullWidth: true) { confirmingRemoval = true }
            default:
                FFButton(title: String(localized: "Add friend"), busy: busy, fullWidth: true) { Task { await act("request") } }
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
                    metric(String(localized: "Fights played"), value: record.played.formatted())
                    metric(String(localized: "Wins"), value: record.wins.formatted())
                    metric(String(localized: "Win rate"), value: record.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? String(localized: "No results yet"))
                }
                ForEach(["public", "private", "unknown"], id: \.self) { category in
                    if let counts = record.categories[category], counts.played > 0 {
                        HStack {
                            Text(category == "public" ? String(localized: "Public Fights") : category == "private" ? String(localized: "Private Fights") : String(localized: "Category unknown"))
                            Spacer()
                            Text(String(format: String(localized: "profile.category-record"), counts.wins, counts.played))
                        }.ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
                if record.excluded > 0 {
                    Text(String(localized: "Ongoing, cancelled, solo and unverifiable historical results are excluded from win rate."))
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
        case "win": return String(localized: "Won")
        case "loss": return String(localized: "Lost")
        case "draw": return String(localized: "Draw")
        case "withdrawn": return String(localized: "Withdrew")
        case "removed": return String(localized: "Removed")
        case "incomplete": return String(localized: "Incomplete final sync")
        case "cancelled": return String(localized: "Cancelled")
        case "ongoing": return String(localized: "Ongoing")
        case "solo": return String(localized: "Solo Fight")
        case "not_entered": return String(localized: "Did not enter")
        default: return String(localized: "Historical result unavailable")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: row.name ?? String(localized: "Fight result")).ffType(.heading)
            HStack {
                Text(result)
                Spacer()
                if let placement = row.placement {
                    Text(String(format: String(localized: "profile.placement"), placement, row.fieldSize))
                }
            }.ffType(.label)
            Text(verbatim: String(row.endsAt.prefix(10))).ffType(.caption).foregroundStyle(theme.textSecondary)
            if row.complete == false && row.result != "incomplete" {
                Text(String(localized: "Incomplete final sync")).ffType(.caption).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
