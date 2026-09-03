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
    @State private var duration = "1 week"
    @State private var actionText = ""
    @FocusState private var usernameFocused: Bool
    @FocusState private var actionFocused: Bool

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
                    FFScreenTitle(
                        title: "New fight",
                        subtitle: "Set it up one step at a time."
                    )

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
            FFScreenCTA(
                title: model.isCreatingFight ? "Starting…" : "Start fight",
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
            FFScreenCTA(title: "Next", enabled: canContinue) {
                step += 1
            }
        }
    }

    private var flowProgress: some View {
        VStack(spacing: 10) {
            HStack {
                if step > 0 {
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

                Text("Step \(step + 1) of 5")
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
            .accessibilityLabel("Step \(step + 1) of 5")
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
                    title: "Steps",
                    subtitle: "Highest total wins · Apple Health",
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
                        Text(username.isEmpty ? "@username" : username)
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
                                Text("@\(handle)")
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
                            .accessibilityLabel("Remove @\(handle)")
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
                    options: ["3 days", "1 week", "2 weeks", "1 month"],
                    selection: $duration
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
                        Text(actionText.isEmpty ? "Cook dinner" : actionText)
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

                Text("\(actionText.count)/120")
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var reviewStep: some View {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let opponents = inviteHandles.map { "@\($0)" }.joined(separator: ", ")

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
                    title: "Metric",
                    subtitle: "Steps · highest total wins",
                    systemImage: "figure.walk",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 0 }
                )
                FFDivider()
                FFGroupedRow(
                    title: "Duration",
                    subtitle: "\(duration) · ends \(endDate(from: Date()).formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "calendar",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 1 }
                )
                FFDivider()
                FFGroupedRow(
                    title: "Opponents",
                    subtitle: opponents,
                    systemImage: "person.2",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 2 }
                )
                FFDivider()
                FFGroupedRow(
                    title: "Loser action",
                    subtitle: action,
                    systemImage: "flag",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 3 }
                )
                FFDivider()
                FFGroupedRow(
                    title: "Apple Health Steps",
                    subtitle: steps.hasAsked ? "Ready to score this fight" : "Connect to score this fight",
                    systemImage: "heart",
                    subtitleTone: steps.hasAsked ? .moss : .ember,
                    trailing: AnyView(
                        FFPill(
                            steps.hasAsked ? "Connected" : "Connect",
                            style: steps.hasAsked ? .softMoss : .solidMoss
                        )
                    ),
                    action: steps.hasAsked ? nil : connectAppleHealth
                )
            }

            FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("You vs \(opponents)")
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text("Most Steps wins after \(duration.lowercased()).")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    Text("The loser will \(action.prefix(1).lowercased())\(action.dropFirst()).")
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
            usernameError = "Use 2–30 letters, numbers, or underscores."
            return
        }
        if handle == session.profile?.handle {
            usernameError = "Add someone else’s username."
            return
        }
        guard !inviteHandles.contains(handle) else {
            usernameError = "@\(handle) is already in this fight."
            return
        }

        inviteHandles.append(handle)
        username = ""
    }

    private func endDate(from startsAt: Date) -> Date {
        let durationParts: (component: Calendar.Component, value: Int, seconds: TimeInterval) = switch duration {
        case "3 days": (.day, 3, 259_200)
        case "1 week": (.day, 7, 604_800)
        case "2 weeks": (.day, 14, 1_209_600)
        case "1 month": (.day, 30, 2_592_000)
        default: (.day, 7, 604_800)
        }

        return Calendar.current.date(
            byAdding: durationParts.component,
            value: durationParts.value,
            to: startsAt
        ) ?? startsAt.addingTimeInterval(durationParts.seconds)
    }

    private func startFight() {
        guard canStart else { return }
        guard model.beginCreateFight() else { return }

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
    }

    private func connectAppleHealth() {
        Task {
            await steps.refresh(requestAccess: true)
            if session.authSession != nil {
                await steps.syncToBackend(session: session)
            }
        }
    }
}
