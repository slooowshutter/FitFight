import SwiftUI

struct EditFightView: View {
    private let fight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var step = FightComposerStep.review
    @State private var fightTitle: String
    @State private var actionText: String
    @State private var visibilityJoinable: Bool
    @State private var recurring: Bool
    @State private var durationDays: Int
    @State private var customSchedule: Bool
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var timeZone: TimeZone
    @State private var people: [FightComposerPerson]
    @State private var username = ""
    @State private var usernameError: String?
    @State private var confirmDelete = false
    @FocusState private var usernameFocused: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var actionFocused: Bool

    init(fight: Fight) {
        self.fight = fight
        _timeZone = State(initialValue: fight.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current)
        let stored = fight.name.trimmingCharacters(in: .whitespacesAndNewlines)
        _fightTitle = State(initialValue: stored == "Steps Fight" || stored == "Défi de pas" ? "" : stored)
        _actionText = State(initialValue: fight.actionText)
        _visibilityJoinable = State(initialValue: fight.visibility == "joinable")
        _recurring = State(initialValue: fight.recurring)
        let days = max(1, Int((fight.windowEnd.timeIntervalSince(fight.windowStart) / 86_400).rounded()))
        let preset = [3, 7, 14, 30].contains(days)
        _durationDays = State(initialValue: preset ? days : 7)
        _customSchedule = State(initialValue: !preset)
        _customStart = State(initialValue: fight.windowStart)
        _customEnd = State(initialValue: fight.windowEnd)
        let ownerID = fight.inviter?.id
        _people = State(initialValue: fight.standings.map { row in
            FightComposerPerson(
                id: row.person.id,
                handle: SessionStore.strippedHandle(row.person.handle),
                name: row.person.name,
                photoURL: row.person.photoURL,
                isOwner: row.person.id == ownerID || (row.person.isYou && fight.inviter?.isYou == true),
                invited: row.invited,
                deferred: row.deferred,
                pendingAdd: false
            )
        })
    }

    private var duration: String {
        FightComposer.durationLabel(days: durationDays, customSchedule: customSchedule)
    }

    private var canEditStart: Bool { fight.isUpcoming }

    private var durationStart: Date {
        canEditStart && customSchedule ? customStart : fight.windowStart
    }

    private var scheduleError: String? {
        let startsAt = durationStart
        let endsAt = customSchedule ? customEnd : FightComposer.endDate(from: startsAt, days: durationDays, timeZone: timeZone)
        if canEditStart, customSchedule, customStart <= Date() {
            return String(localized: "Choose a start time in the future.")
        }
        if endsAt <= startsAt { return String(localized: "The end must be after the start.") }
        if endsAt <= Date() { return String(localized: "The end must be in the future.") }
        return nil
    }

    private var canSave: Bool {
        fightTitle.trimmingCharacters(in: .whitespacesAndNewlines).count <= 120
            && actionText.trimmingCharacters(in: .whitespacesAndNewlines).count <= 120
            && scheduleError == nil
            && !model.isUpdatingFight
            && !model.isDeletingFight
    }

    private var isOwner: Bool { fight.inviter?.isYou == true }

    var body: some View {
        FFScreen(top: AnyView(header), clearance: false) {
            currentStep
            Spacer(minLength: theme.space.lg)
            flowAction
        }
        .confirmationDialog(
            String(localized: "Delete fight?"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await deleteFight() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This ends the fight for everyone in it. If it repeats, the next windows stop too. This can’t be undone."))
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(String(localized: "Edit fight"))
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                HStack {
                    FFNavGlyph(systemName: "xmark") { dismiss() }
                    Spacer()
                    if step != .review {
                        Button(String(localized: "Done")) { returnToSummary() }
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                            .buttonStyle(FFHapticPlainStyle())
                    }
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
        }
        .background(theme.bg)
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .metric:
            FightComposerMetricPage()
        case .duration:
            FightComposerDurationPage(
                durationDays: $durationDays,
                customSchedule: $customSchedule,
                customStart: $customStart,
                customEnd: $customEnd,
                recurring: $recurring,
                timeZone: $timeZone,
                canEditStart: canEditStart,
                startsImmediately: false,
                constrainEnd: true,
                scheduleError: scheduleError
            )
        case .people:
            FightComposerPeoplePage(
                visibilityJoinable: $visibilityJoinable,
                username: $username,
                usernameError: $usernameError,
                people: $people,
                usernameFocused: $usernameFocused,
                createMode: false,
                onAdd: addUsername
            )
        case .details:
            FightComposerDetailsPage(
                fightTitle: $fightTitle,
                actionText: $actionText,
                titleFocused: $titleFocused,
                actionFocused: $actionFocused
            )
        case .review:
            FightComposerReviewPage(
                isEditing: true,
                fightTitle: fightTitle,
                actionText: actionText,
                duration: duration,
                customSchedule: customSchedule,
                customStart: customStart,
                customEnd: customEnd,
                durationStart: durationStart,
                durationDays: durationDays,
                timeZone: timeZone,
                visibilityJoinable: visibilityJoinable,
                opponentHandles: people.filter { !$0.isOwner }.map(\.handle),
                recurring: recurring,
                healthConnected: steps.hasAsked,
                healthBusy: model.isRefreshingFights,
                onChange: { step = $0 },
                onConnectHealth: connectAppleHealth
            )
        }
    }

    @ViewBuilder
    private var flowAction: some View {
        if step == .review {
            FFButton(
                title: model.isUpdatingFight ? String(localized: "Saving…") : String(localized: "Save changes"),
                size: .large,
                enabled: canSave,
                busy: model.isUpdatingFight,
                fullWidth: true
            ) {
                save()
            }

            if isOwner {
                FFButton(
                    title: model.isDeletingFight ? String(localized: "Deleting…") : String(localized: "Delete"),
                    kind: .ember,
                    size: .large,
                    enabled: !model.isUpdatingFight && !model.isDeletingFight,
                    busy: model.isDeletingFight,
                    fullWidth: true
                ) {
                    confirmDelete = true
                }
                .padding(.top, theme.space.sm)
            }

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if let scheduleError {
                FFNotice(text: scheduleError, tone: .ember, systemImage: "calendar")
            }
        } else {
            FFButton(title: String(localized: "Done"), size: .large, enabled: step != .duration || scheduleError == nil, fullWidth: true) {
                returnToSummary()
            }
        }
    }

    private func returnToSummary() {
        if step == .people, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addUsername()
            if usernameError != nil { return }
        }
        step = .review
    }

    private func addUsername() {
        let handle = SessionStore.strippedHandle(username)
        usernameError = nil
        guard SessionStore.isValidHandle(handle) else {
            usernameError = String(localized: "Use 2–30 letters, numbers, or underscores.")
            return
        }
        if handle == session.profile?.handle {
            usernameError = String(localized: "Add someone else’s username.")
            return
        }
        guard !people.contains(where: { $0.handle == handle }) else {
            usernameError = String(
                localized: "fight.handle-already-added",
                defaultValue: "@\(handle) is already in this fight."
            )
            return
        }
        people.append(
            FightComposerPerson(
                id: "handle:\(handle)",
                handle: handle,
                name: "@\(handle)",
                photoURL: nil,
                isOwner: false,
                invited: true,
                deferred: false,
                pendingAdd: true
            )
        )
        username = ""
    }

    private func connectAppleHealth() {
        Task {
            await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
        }
    }

    private func save() {
        guard canSave else { return }
        let startsAt = durationStart
        let endsAt = customSchedule ? customEnd : FightComposer.endDate(from: startsAt, days: durationDays, timeZone: timeZone)
        let originalIDs = Set(fight.standings.map(\.person.id))
        let remainingIDs = Set(people.filter { !$0.pendingAdd }.map(\.id))
        let removeUserIds = originalIDs.subtracting(remainingIDs).filter { id in
            people.first(where: { $0.id == id })?.isOwner != true
                && fight.standings.first(where: { $0.person.id == id })?.person.isYou != true
        }
        let inviteHandles = people.filter(\.pendingAdd).map(\.handle)
        Task {
            let saved = await model.updateFight(
                id: fight.id,
                name: fightTitle,
                actionText: actionText,
                visibility: visibilityJoinable ? "joinable" : "invite_only",
                recurring: recurring,
                startsAt: canEditStart ? startsAt : nil,
                endsAt: endsAt,
                timeZone: canEditStart && timeZone.identifier != fight.timeZone ? timeZone.identifier : nil,
                inviteHandles: inviteHandles,
                removeUserIds: Array(removeUserIds)
            )
            if saved {
                dismiss()
            }
        }
    }

    private func deleteFight() async {
        let deleted = await model.deleteFight(id: fight.id)
        if deleted {
            dismiss()
        }
    }
}
