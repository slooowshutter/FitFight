import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var step = 0
    @State private var username = ""
    @State private var inviteHandles: [String] = []
    @State private var usernameError: String?
    @State private var durationDays = 7
    @State private var actionText = ""
    @FocusState private var usernameFocused: Bool
    @FocusState private var actionFocused: Bool

    private var duration: String {
        switch durationDays {
        case 3: return String(localized: "3 days")
        case 14: return String(localized: "2 weeks")
        case 30: return String(localized: "1 month")
        default: return String(localized: "1 week")
        }
    }

    private var canStart: Bool {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.isSignedIn
            && steps.hasAsked
            && !inviteHandles.isEmpty
            && !action.isEmpty
            && action.count <= 120
            && !model.isCreatingFight
    }

    private var canContinue: Bool {
        switch step {
        case 2: return !inviteHandles.isEmpty
        case 3: return !actionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            FFScreen(clearance: false) {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    flowProgress
                    currentStep
                    Spacer(minLength: theme.space.lg)
                    flowAction
                }
                .frame(
                    minHeight: max(0, proxy.size.height - theme.space.base - theme.space.lg),
                    alignment: .top
                )
            }
        }
    }

    @ViewBuilder
    private var flowAction: some View {
        if step == 4 {
            FFSlideToConfirm(
                title: model.isCreatingFight
                    ? String(localized: "Starting…")
                    : String(localized: "Slide to start"),
                enabled: canStart,
                busy: model.isCreatingFight
            ) {
                startFight()
            }

            if !steps.hasAsked {
                Text("Connect Apple Health above to start this fight.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        } else {
            FFButton(title: String(localized: "Next"), size: .large, enabled: canContinue, fullWidth: true) {
                step += 1
            }
        }
    }

    private var flowProgress: some View {
        VStack(spacing: 10) {
            HStack {
                if step == 0 {
                    Text("New fight")
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                        .frame(minHeight: 44)
                } else {
                    Button {
                        step -= 1
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .ffType(.buttonSmall)
                            .foregroundStyle(theme.text)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(
                    String(
                        localized: "fight.step-progress",
                        defaultValue: "Step \(step + 1) of 5"
                    )
                )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(minHeight: 44)
            }

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
                    localized: "fight.step-progress",
                    defaultValue: "Step \(step + 1) of 5"
                )
            )
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0: metricStep
        case 1: durationStep
        case 2: peopleStep
        case 3: actionStep
        default: reviewStep
        }
    }

    private var metricStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you competing on?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Every fight tracks one metric. Steps is the only metric available right now.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Steps"),
                    subtitle: String(localized: "Highest total wins · Apple Health"),
                    systemImage: "figure.walk",
                    subtitleTone: .moss,
                    trailing: AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText))
                )
            }
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who are you fighting?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Add at least one exact username and press Return. They must already have a FitFight account.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)

                Group {
                    if staticRender {
                        Text(verbatim: username.isEmpty ? String(localized: "@username") : username)
                            .foregroundStyle(username.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("@username", text: $username)
                            .focused($usernameFocused)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                addUsername()
                                usernameFocused = false
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(usernameError == nil ? theme.line : theme.emberText, radius: theme.radius.field)

                if let usernameError {
                    Text(usernameError)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                }
            }

            if !inviteHandles.isEmpty {
                FFGroupedRows {
                    ForEach(Array(inviteHandles.enumerated()), id: \.element) { index, handle in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(monogram: String(handle.prefix(2)).uppercased(), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: "@\(handle)")
                                    .ffType(.rowTitle)
                                    .foregroundStyle(theme.text)
                                Text("Added to this fight")
                                    .ffType(.caption)
                                    .foregroundStyle(theme.mossText)
                            }
                            Spacer(minLength: 8)
                            Button {
                                inviteHandles.removeAll { $0 == handle }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(theme.control, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                String(
                                    localized: "fight.remove-handle",
                                    defaultValue: "Remove @\(handle)"
                                )
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How long will the fight last?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("It starts immediately. Steps after the exact end time do not count.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Duration")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                FFDurationPicker(
                    options: [
                        String(localized: "3 days"),
                        String(localized: "1 week"),
                        String(localized: "2 weeks"),
                        String(localized: "1 month"),
                    ],
                    selection: Binding(
                        get: { duration },
                        set: { selection in
                            if selection == String(localized: "3 days") { durationDays = 3 }
                            else if selection == String(localized: "2 weeks") { durationDays = 14 }
                            else if selection == String(localized: "1 month") { durationDays = 30 }
                            else { durationDays = 7 }
                        }
                    )
                )
            }

        }
    }

    private var actionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What will the loser do?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Enter the action to continue—for example, cook dinner.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Loser action")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Group {
                    if staticRender {
                        Text(verbatim: actionText.isEmpty ? String(localized: "Cook dinner") : actionText)
                            .foregroundStyle(actionText.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("Cook dinner", text: $actionText)
                            .focused($actionFocused)
                            .foregroundStyle(theme.text)
                            .submitLabel(.done)
                            .onSubmit { actionFocused = false }
                            .onChange(of: actionText) { _, value in
                                if value.count > 120 {
                                    actionText = String(value.prefix(120))
                                }
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(theme.line, radius: theme.radius.field)

                Text(verbatim: "\(actionText.count)/120")
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var reviewStep: some View {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let opponents = inviteHandles.map { "@\($0)" }.formatted(.list(type: .and))

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to fight?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Check the agreement before you invite everyone.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Metric"),
                    subtitle: String(localized: "Steps · highest total wins"),
                    systemImage: "figure.walk",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 0 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Duration"),
                    subtitle: String(
                        localized: "fight.duration-end",
                        defaultValue: "\(duration) · ends \(endDate(from: Date()).formatted(date: .abbreviated, time: .shortened))"
                    ),
                    systemImage: "calendar",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 1 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Opponents"),
                    subtitle: opponents,
                    systemImage: "person.2",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 2 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Loser action"),
                    subtitle: action,
                    systemImage: "flag",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 3 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Apple Health Steps"),
                    subtitle: steps.hasAsked
                        ? String(localized: "Ready to score this fight")
                        : String(localized: "Connect to score this fight"),
                    systemImage: "heart",
                    subtitleTone: steps.hasAsked ? .moss : .ember,
                    trailing: AnyView(
                        FFPill(
                            steps.hasAsked ? String(localized: "Connected") : String(localized: "Connect"),
                            style: steps.hasAsked ? .softMoss : .solidMoss
                        )
                    ),
                    action: steps.hasAsked ? nil : connectAppleHealth
                )
            }

            FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        String(
                            localized: "fight.you-versus",
                            defaultValue: "You vs \(opponents)"
                        )
                    )
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(
                        String(
                            localized: "fight.winner-after-duration",
                            defaultValue: "Most Steps wins after \(duration.lowercased())."
                        )
                    )
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    Text(
                        String(
                            localized: "fight.loser-will",
                            defaultValue: "The loser will \(action)."
                        )
                    )
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                }
            }
        }
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
        guard !inviteHandles.contains(handle) else {
            usernameError = String(
                localized: "fight.handle-already-added",
                defaultValue: "@\(handle) is already in this fight."
            )
            return
        }

        inviteHandles.append(handle)
        username = ""
    }

    private func endDate(from startsAt: Date) -> Date {
        return Calendar.current.date(
            byAdding: .day,
            value: durationDays,
            to: startsAt
        ) ?? startsAt.addingTimeInterval(TimeInterval(durationDays * 86_400))
    }

    private func startFight() -> Bool {
        guard canStart else { return false }
        guard model.beginCreateFight() else { return false }

        let startsAt = Date()
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await model.createAndStartFight(
                startsAt: startsAt,
                endsAt: endDate(from: startsAt),
                actionText: action,
                inviteHandles: inviteHandles
            )
            if (model.createError ?? "").isEmpty {
                model.tab = .fights
            }
        }
        return true
    }

    private func connectAppleHealth() {
        Task {
            await steps.refresh(requestAccess: true)
            if session.authSession != nil {
                await steps.syncToBackend(session: session, trigger: .manual)
            }
        }
    }
}
