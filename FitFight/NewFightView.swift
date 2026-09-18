import SwiftUI

enum NewFightOpening {
    case choose
    case create
    case join
}

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var opening: NewFightOpening
    @State private var step = 0
    @State private var username = ""
    @State private var inviteHandles: [String] = []
    @State private var usernameError: String?
    @State private var durationDays = 7
    @State private var customSchedule = false
    @State private var selectedTimeZone: TimeZone?
    @State private var customStart = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 60) * 60 + 3_600)
    @State private var customEnd = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 60) * 60 + 7 * 86_400 + 3_600)
    @State private var fightTitle = ""
    @State private var actionText = ""
    @State private var visibilityJoinable = false
    @State private var recurring = true
    @State private var joinCode = ""
    @State private var lookingUp = false
    @State private var composing = false
    @FocusState private var usernameFocused: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var actionFocused: Bool
    @FocusState private var joinCodeFocused: Bool

    init(opening: NewFightOpening = .choose, initialStep: Int = 0) {
        let capturing = CompanionPreview.isEnabled && ScreenshotExport.isEnabled
        _opening = State(initialValue: capturing ? .create : opening)
        _step = State(initialValue: initialStep)
    }

    private var fightTimeZone: TimeZone { selectedTimeZone ?? session.profile?.calendarTimeZone ?? .current }

    private func applyProfileChallenge(now: Date = Date()) {
        guard let draft = model.profileChallenge else { return }
        opening = .create
        step = 0
        durationDays = 7
        selectedTimeZone = nil
        customSchedule = false
        recurring = true
        fightTitle = ""
        visibilityJoinable = false
        inviteHandles = [draft.handle]
        actionText = draft.actionText ?? ""
        if let seconds = draft.durationSeconds {
            if let days = [3, 7, 14, 30].first(where: {
                FightComposer.endDate(from: now, days: $0, timeZone: fightTimeZone).timeIntervalSince(now) == TimeInterval(seconds)
            }) {
                durationDays = days
            } else {
                customSchedule = true
                customStart = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 60) * 60 + 3_600)
                customEnd = customStart.addingTimeInterval(TimeInterval(seconds))
            }
        }
        model.profileChallenge = nil
    }

    private var duration: String {
        FightComposer.durationLabel(days: durationDays, customSchedule: customSchedule)
    }

    private var scheduleError: String? {
        guard customSchedule else { return nil }
        if customStart <= Date() { return String(appLocalized: "Choose a start time in the future.") }
        if customEnd <= customStart { return String(appLocalized: "The end must be after the start.") }
        return nil
    }

    private var canStart: Bool {
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.isSignedIn
            && (steps.hasAsked || CompanionPreview.isEnabled)
            && title.count <= 120
            && action.count <= 120
            && scheduleError == nil
            && !model.isCreatingFight
    }

    var body: some View {
        GeometryReader { proxy in
            FFScreen(clearance: false) {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    flowProgress
                    currentScreen
                    Spacer(minLength: theme.space.lg)
                    flowAction
                }
                .frame(
                    minHeight: max(0, proxy.size.height - theme.space.base - theme.space.lg),
                    alignment: .top
                )
            }
        }
        .onAppear { applyProfileChallenge() }
        .onChange(of: model.profileChallenge) { _, _ in applyProfileChallenge() }
        .task(id: opening) {
            guard opening != .create, !staticRender else { return }
            await model.loadFightDiscovery(session: session)
        }
        .sheet(isPresented: $composing) {
            FeedComposeSheet()
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(feed)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .task {
            if model.pendingJoinable != nil, opening != .create {
                opening = .join
            }
        }
        .onChange(of: model.pendingJoinable?.id) { _, id in
            if id != nil, opening != .create {
                opening = .join
            }
        }
    }

    private var showingJoinPreview: Bool {
        model.pendingJoinable != nil && opening != .create
    }

    private var effectiveOpening: NewFightOpening {
        showingJoinPreview ? .join : opening
    }

    @ViewBuilder
    private var flowAction: some View {
        if effectiveOpening == .choose || showingJoinPreview {
            EmptyView()
        } else if effectiveOpening == .join {
            FFButton(
                title: lookingUp ? String(appLocalized: "Looking up…") : String(appLocalized: "Open fight"),
                size: .large,
                enabled: joinCode.count == 4,
                busy: lookingUp,
                fullWidth: true
            ) {
                lookupCode()
            }
            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        } else if step == 4 {
            FFSlideToConfirm(
                title: model.isCreatingFight
                    ? String(appLocalized: "Starting…")
                    : customSchedule ? String(appLocalized: "Slide to schedule") : String(appLocalized: "Slide to start"),
                enabled: canStart,
                busy: model.isCreatingFight
            ) {
                startFight()
            }

            if CompanionPreview.isEnabled {
                Text(CompanionPreview.writeUnavailable)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !steps.hasAsked {
                Text("Connect Apple Health above to start this fight.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if let scheduleError {
                FFNotice(text: scheduleError, tone: .ember, systemImage: "calendar")
            }
        } else {
            FFButton(title: String(appLocalized: "Next"), size: .large, enabled: step != 1 || scheduleError == nil, fullWidth: true) {
                step += 1
            }
        }
    }

    private var flowProgress: some View {
        VStack(spacing: 10) {
            HStack {
                if effectiveOpening == .choose {
                    Text("New")
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                        .frame(minHeight: 44)
                } else {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .ffType(.buttonSmall)
                            .foregroundStyle(theme.text)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }

                Spacer()

                if opening == .create {
                    Text(
                        String(
                            appLocalized: "fight.step-progress",
                            defaultValue: "Step \(step + 1) of 5"
                        )
                    )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(minHeight: 44)
                }
            }

            if opening == .create {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? theme.mossFill : theme.disabledBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(
                        appLocalized: "fight.step-progress",
                        defaultValue: "Step \(step + 1) of 5"
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        if let fight = model.pendingJoinable, opening != .create {
            JoinFightPreview(
                fight: fight,
                joining: model.isJoiningFight,
                onJoinNow: { Task { await model.acceptFight(id: fight.id, start: "now") } },
                onJoinNext: { Task { await model.acceptFight(id: fight.id, start: "next") } },
                onDismiss: {
                    Task { await model.declineFight(id: fight.id) }
                }
            )
        } else {
            switch opening {
            case .choose:
                chooseStep
            case .join:
                joinStep
            case .create:
                currentStep
            }
        }
    }

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CompanionIntroduction(surface: .newFight)
            VStack(alignment: .leading, spacing: 6) {
                Text("Create, join, or post?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Start a new fight, join one that's already going, or post to the Feed.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(appLocalized: "Create"),
                    subtitle: String(appLocalized: "Start a new fight"),
                    systemImage: "plus",
                    subtitleTone: .neutral,
                    action: { opening = .create }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Join"),
                    subtitle: String(appLocalized: "Code, invite link, or a public fight"),
                    systemImage: "person.badge.plus",
                    subtitleTone: .neutral,
                    action: { opening = .join }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Post"),
                    subtitle: String(appLocalized: "Share a note, photo, or video on the Feed"),
                    systemImage: "square.and.pencil",
                    subtitleTone: .neutral,
                    action: { composing = true }
                )
            }

            suggestedSection
        }
    }

    private var suggestedSection: some View {
        let rows = staticRender ? Array(Self.screenshotJoinable.prefix(2)) : model.suggestedFights
        return VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: String(appLocalized: "Suggested"))
            if let error = model.discoveryError {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if model.isLoadingDiscovery && rows.isEmpty && !staticRender {
                FFLoadingBlock()
            } else if rows.isEmpty && model.discoveryError == nil {
                Text(String(appLocalized: "No suggested fights right now."))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            } else if !rows.isEmpty {
                ForEach(rows) { item in
                    SuggestedFightOffer(fight: item) { Task { await model.openJoinable(item, session: session) } }
                }
            }
        }
    }

    private var joinStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Join a fight")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Private fights join with a code or invite link. Public fights also show below.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Code")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Group {
                    if staticRender {
                        Text(verbatim: joinCode.isEmpty ? "K7M2" : joinCode)
                            .foregroundStyle(joinCode.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("K7M2", text: $joinCode)
                            .focused($joinCodeFocused)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { lookupCode() }
                            .onChange(of: joinCode) { _, value in
                                let allowed = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTVWXYZ")
                                let cleaned = value.uppercased().unicodeScalars
                                    .filter { allowed.contains($0) }
                                joinCode = String(String.UnicodeScalarView(cleaned).prefix(4))
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(theme.line, radius: theme.radius.field)
            }

            FFSectionHeader(title: String(appLocalized: "Live public fights"))
            let rows = staticRender ? Self.screenshotJoinable : model.joinableFights
            if let error = model.discoveryError {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if model.isLoadingDiscovery && rows.isEmpty && !staticRender {
                FFLoadingBlock()
            } else if rows.isEmpty && model.discoveryError == nil {
                Text("No live public fights right now. Use a code or invite link.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            } else if !rows.isEmpty {
                FFGroupedRows {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { FFDivider() }
                        FFGroupedRow(
                            title: Fight.displayTitle(name: item.name, actionText: item.actionText),
                            subtitle: item.recurring
                                ? String(
                                    appLocalized: "fight.joinable-row-repeats",
                                    defaultValue: "@\(item.ownerHandle) · \(item.memberCount) in · repeats"
                                )
                                : String(
                                    appLocalized: "fight.joinable-row",
                                    defaultValue: "@\(item.ownerHandle) · \(item.memberCount) in"
                                ),
                            systemImage: "figure.walk",
                            subtitleTone: .neutral,
                            trailing: AnyView(Text(item.joinCode).ffType(.caption).foregroundStyle(theme.textSecondary)),
                            action: {
                                Task { await model.openJoinable(item, session: session) }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch FightComposerStep(rawValue: step) ?? .review {
        case .metric:
            FightComposerMetricPage()
        case .duration:
            FightComposerDurationPage(
                durationDays: $durationDays,
                customSchedule: $customSchedule,
                customStart: $customStart,
                customEnd: $customEnd,
                recurring: $recurring,
                timeZone: Binding(get: { fightTimeZone }, set: { selectedTimeZone = $0 }),
                canEditStart: true,
                startsImmediately: true,
                constrainEnd: false,
                scheduleError: scheduleError
            )
        case .people:
            FightComposerPeoplePage(
                visibilityJoinable: $visibilityJoinable,
                username: $username,
                usernameError: $usernameError,
                people: peopleBinding,
                usernameFocused: $usernameFocused,
                createMode: true,
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
                isEditing: false,
                fightTitle: fightTitle,
                actionText: actionText,
                duration: duration,
                customSchedule: customSchedule,
                customStart: customStart,
                customEnd: customEnd,
                durationStart: Date(),
                durationDays: durationDays,
                timeZone: fightTimeZone,
                visibilityJoinable: visibilityJoinable,
                opponentHandles: inviteHandles,
                recurring: recurring,
                healthConnected: steps.hasAsked,
                healthBusy: model.isRefreshingFights,
                onChange: { step = $0.rawValue },
                onConnectHealth: connectAppleHealth
            )
        }
    }

    private var peopleBinding: Binding<[FightComposerPerson]> {
        Binding(
            get: {
                inviteHandles.map { handle in
                    FightComposerPerson(
                        id: handle,
                        handle: handle,
                        name: "@\(handle)",
                        photoURL: nil,
                        isOwner: false,
                        invited: true,
                        deferred: false,
                        pendingAdd: true
                    )
                }
            },
            set: { inviteHandles = $0.map(\.handle) }
        )
    }

    private func goBack() {
        if let pending = model.pendingJoinable, opening != .create {
            Task { await model.declineFight(id: pending.id) }
            return
        }
        if opening == .join || (opening == .create && step == 0) {
            opening = .choose
            model.createError = nil
            return
        }
        if opening == .create {
            step -= 1
        }
    }

    private func lookupCode() {
        guard joinCode.count == 4, !lookingUp else { return }
        lookingUp = true
        Task {
            await model.openJoinCode(joinCode, session: session)
            lookingUp = false
        }
    }

    private func addUsername() {
        let handle = SessionStore.strippedHandle(username)
        usernameError = nil

        guard SessionStore.isValidHandle(handle) else {
            usernameError = String(appLocalized: "Use 2–30 letters, numbers, or underscores.")
            return
        }
        if handle == session.profile?.handle {
            usernameError = String(appLocalized: "Add someone else’s username.")
            return
        }
        guard !inviteHandles.contains(handle) else {
            usernameError = String(
                appLocalized: "fight.handle-already-added",
                defaultValue: "@\(handle) is already in this fight."
            )
            return
        }

        inviteHandles.append(handle)
        username = ""
    }

    private func endDate(from startsAt: Date) -> Date {
        FightComposer.endDate(from: startsAt, days: durationDays, timeZone: fightTimeZone)
    }

    private func startFight() -> Bool {
        guard canStart else { return false }
        guard model.beginCreateFight() else { return false }

        let startsAt = customSchedule ? customStart : Date()
        let endsAt = customSchedule ? customEnd : endDate(from: startsAt)
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await model.createAndStartFight(
                name: title,
                startsAt: startsAt,
                endsAt: endsAt,
                timeZone: fightTimeZone,
                actionText: action,
                inviteHandles: inviteHandles,
                visibility: visibilityJoinable ? "joinable" : "invite_only",
                recurring: recurring,
                scheduled: customSchedule
            )
            if (model.createError ?? "").isEmpty {
                opening = .choose
                step = 0
                visibilityJoinable = false
                model.tab = .fights
            }
        }
        return true
    }

    private func connectAppleHealth() {
        Task {
            await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
        }
    }

    private static var screenshotJoinable: [FitFightJoinableFight] {
        [
            FitFightJoinableFight(
                fightId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                seriesId: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
                name: "Office steps",
                joinCode: "K7M2",
                ownerHandle: "maya",
                actionText: "Cook dinner",
                startsAt: "2026-09-04T12:00:00Z",
                endsAt: "2026-09-11T12:00:00Z",
                memberCount: 8,
                recurring: true,
                alreadyMember: false,
                canJoinNext: true
            ),
        ]
    }
}
