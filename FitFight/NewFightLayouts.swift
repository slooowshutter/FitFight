import SwiftUI

struct NewFightLayoutBody: View {
    let layout: NewFightLayout

    var body: some View {
        switch layout {
        case .current: NewFightCurrentLayout()
        case .checklist: NewFightChecklistLayout()
        case .wizard: NewFightWizardLayout()
        case .peopleFirst: NewFightPeopleFirstLayout()
        case .stakeFirst: NewFightStakeFirstLayout()
        case .liveCard: NewFightLiveCardLayout()
        case .plain: NewFightPlainLayout()
        case .compact: NewFightCompactLayout()
        case .sentence: NewFightSentenceLayout()
        case .ticket: NewFightTicketLayout()
        }
    }
}

struct NewFightCurrentLayout: View {
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "New fight",
                subtitle: "Challenge friends. Most steps wins."
            )
            .padding(.bottom, 6)

            NewFightHealthSection()
            NewFightPeopleSection().padding(.top, 8)
            NewFightDurationChips().padding(.top, 8)
            NewFightActionSection().padding(.top, 8)
            if !staticRender {
                NewFightSummaryCard().padding(.top, 8)
            }
            NewFightStartBlock(title: "Start fight").padding(.top, 6)
        }
    }
}

struct NewFightChecklistLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @State private var open: NewFightEditField = .people

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "Start a fight",
                subtitle: remaining.isEmpty
                    ? "Ready. Start when you are."
                    : "\(remaining.count) left before this can start."
            )
            .padding(.bottom, 6)

            job(
                field: .people,
                number: "1",
                title: "Invite someone",
                done: !draft.inviteHandles.isEmpty,
                detail: draft.inviteHandles.isEmpty
                    ? "Exact username. They must have opened FitFight once."
                    : draft.versusLine
            ) {
                NewFightPeopleSection(header: "Who")
            }

            job(
                field: .duration,
                number: "2",
                title: "How long",
                done: true,
                detail: "\(draft.duration) · \(draft.endsCaption)"
            ) {
                NewFightDurationChips()
            }

            job(
                field: .action,
                number: "3",
                title: "Name the stake",
                done: !draft.trimmedAction.isEmpty,
                detail: draft.trimmedAction.isEmpty
                    ? "What the loser has to do."
                    : draft.trimmedAction
            ) {
                NewFightActionSection(starters: true)
            }

            if !steps.hasAsked {
                FFNotice(
                    text: "Connect Apple Health so the fight can be scored.",
                    tone: .ember,
                    systemImage: "heart",
                    actionTitle: "Connect",
                    action: { draft.connectAppleHealth(session: session, steps: steps) }
                )
                .padding(.top, 8)
            }

            NewFightStartBlock().padding(.top, 8)
        }
    }

    private var remaining: [String] {
        draft.missing(session: session, steps: steps)
    }

    @ViewBuilder
    private func job(
        field: NewFightEditField,
        number: String,
        title: String,
        done: Bool,
        detail: String,
        @ViewBuilder editor: () -> some View
    ) -> some View {
        let expanded = open == field
        VStack(alignment: .leading, spacing: 10) {
            Button {
                open = field
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                        } else {
                            Text(number)
                                .font(.ff(13, 800))
                        }
                    }
                    .foregroundStyle(done ? theme.mossOn : theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        done ? theme.mossFill : theme.control,
                        in: Circle()
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                        Text(detail)
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                }
                .padding(16)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(expanded ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
            }
            .buttonStyle(.plain)

            if expanded {
                editor()
            }
        }
    }
}

struct NewFightWizardLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    private let lastStep = 3

    var body: some View {
        FFScreen {
            FFNavDetail(
                title: stepTitle,
                subtitle: "Step \(draft.wizardStep + 1) of 4",
                onBack: draft.wizardStep == 0 ? nil : { draft.wizardStep -= 1 }
            )

            Group {
                switch draft.wizardStep {
                case 0:
                    NewFightPeopleSection(showAddButton: false, header: "Who")
                case 1:
                    VStack(alignment: .leading, spacing: 8) {
                        NewFightDurationList()
                        Text("The fight starts the moment you confirm.")
                            .ffType(.caption)
                            .foregroundStyle(theme.textFaint)
                    }
                case 2:
                    NewFightActionSection(starters: true, prompt: "Make it specific. Everyone in the fight will see this.")
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        NewFightHealthSection()
                        NewFightSummaryCard()
                        if !draft.missing(session: session, steps: steps).isEmpty {
                            FFNotice(
                                text: draft.missing(session: session, steps: steps).joined(separator: " · "),
                                tone: .ember,
                                systemImage: "exclamationmark.triangle"
                            )
                        }
                    }
                }
            }
            .padding(.top, 8)

            if draft.wizardStep < lastStep {
                FFScreenCTA(title: "Next", enabled: canAdvance) {
                    advance()
                }
                .padding(.top, 12)
            } else {
                NewFightStartBlock().padding(.top, 12)
            }
        }
        .onAppear {
            if draft.wizardStep < 0 || draft.wizardStep > lastStep {
                draft.wizardStep = 0
            }
        }
    }

    private var stepTitle: String {
        switch draft.wizardStep {
        case 0: return "Who’s in?"
        case 1: return "How long?"
        case 2: return "What’s at stake?"
        default: return "Start this fight?"
        }
    }

    private var canAdvance: Bool {
        switch draft.wizardStep {
        case 0:
            return draft.hasInvitees
        case 2:
            return !draft.trimmedAction.isEmpty
        default:
            return true
        }
    }

    private func advance() {
        if draft.wizardStep == 0 {
            guard draft.commitPendingUsername(session: session) else { return }
            guard !draft.inviteHandles.isEmpty else { return }
        }
        guard canAdvance else { return }
        draft.wizardStep = min(draft.wizardStep + 1, lastStep)
    }
}

struct NewFightPeopleFirstLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "Who are you fighting?",
                subtitle: "Add people first. Length and the stake come after."
            )
            .padding(.bottom, 6)

            NewFightPeopleSection(showAddButton: false, header: "Players")

            if draft.inviteHandles.isEmpty {
                Text("Duration and the loser action show up once someone is in.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .padding(.top, 8)
            } else {
                NewFightDurationChips().padding(.top, 8)
                NewFightActionSection().padding(.top, 8)
                NewFightHealthSection(compact: true).padding(.top, 8)
                NewFightStartBlock().padding(.top, 8)
            }
        }
    }
}

struct NewFightStakeFirstLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            Text("The loser has to")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("Write the thing. Then pick who and how long.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .padding(.bottom, 6)

            NewFightActionSection(starters: true, prompt: "Keep it short. 120 characters max.")

            if !draft.trimmedAction.isEmpty {
                NewFightPeopleSection(showAddButton: false, header: "Against").padding(.top, 8)
                NewFightDurationChips().padding(.top, 8)
                NewFightHealthSection(compact: true).padding(.top, 8)
                NewFightStartBlock().padding(.top, 8)
            }
        }
    }
}

struct NewFightLiveCardLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "New fight",
                subtitle: "Tap a line on the card to edit it."
            )
            .padding(.bottom, 6)

            FFCard(fill: theme.mossFill, stroke: theme.mossEdge) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Steps fight")
                            .font(.ff(12, 800))
                            .tracking(12 * 0.1)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.mossSoft)
                        Spacer()
                        FFPill(draft.duration, style: .solidMoss)
                    }
                    Text(draft.inviteHandles.isEmpty ? "Add people below" : draft.versusLine)
                        .font(.ff(21, 800))
                        .foregroundStyle(theme.mossOn)
                    Text(draft.trimmedAction.isEmpty ? "Name the loser action" : draft.trimmedAction)
                        .ffType(.body)
                        .foregroundStyle(theme.mossOn.opacity(0.86))
                    Text("Most steps wins · \(draft.endsCaption)")
                        .ffType(.caption)
                        .foregroundStyle(theme.mossSoft)
                }
            }

            VStack(spacing: 8) {
                cardLine(
                    field: .people,
                    label: "Players",
                    value: draft.inviteHandles.isEmpty ? "Add a username" : draft.versusLine
                )
                cardLine(
                    field: .duration,
                    label: "Length",
                    value: "\(draft.duration) · \(draft.endsCaption)"
                )
                cardLine(
                    field: .action,
                    label: "Loser does",
                    value: draft.trimmedAction.isEmpty ? "Name the action" : draft.trimmedAction
                )
            }

            if let field = draft.editingField {
                Group {
                    switch field {
                    case .people:
                        NewFightPeopleSection(showAddButton: false, header: "Players")
                    case .duration:
                        NewFightDurationChips()
                    case .action:
                        NewFightActionSection(starters: true)
                    }
                }
                .padding(.top, 4)
            }

            NewFightHealthSection(compact: true).padding(.top, 8)
            NewFightStartBlock().padding(.top, 8)
        }
    }

    private func cardLine(field: NewFightEditField, label: String, value: String) -> some View {
        let on = draft.editingField == field
        return Button {
            draft.editingField = on ? nil : field
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .frame(width: 78, alignment: .leading)
                Text(value)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: on ? "pencil.circle.fill" : "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(on ? theme.mossText : theme.textFaint)
            }
            .padding(16)
            .background(on ? theme.mossWash : theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(.plain)
    }
}

struct NewFightPlainLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @FocusState private var usernameFocused: Bool

    var body: some View {
        FFScreen {
            FFScreenTitle(title: "New fight", subtitle: "Most steps wins.")
                .padding(.bottom, 6)

            FFSectionHeader(title: "Who")
            FFGroupedRows {
                HStack(spacing: 8) {
                    if staticRender {
                        Text(draft.username.isEmpty ? "@username" : draft.username)
                            .foregroundStyle(draft.username.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("@username", text: $draft.username)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($usernameFocused)
                            .onSubmit {
                                draft.addUsername(session: session)
                                if draft.usernameError == nil { usernameFocused = false }
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                ForEach(draft.inviteHandles, id: \.self) { handle in
                    FFDivider()
                    HStack {
                        Text("@\(handle)")
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                        Spacer()
                        Button("Remove") { draft.removeHandle(handle) }
                            .ffType(.caption)
                            .foregroundStyle(theme.emberText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            if let usernameError = draft.usernameError {
                Text(usernameError)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }

            NewFightDurationList().padding(.top, 8)

            FFSectionHeader(title: "Loser does").padding(.top, 8)
            FFGroupedRows {
                Group {
                    if staticRender {
                        Text(draft.actionText.isEmpty ? "Type the action" : draft.actionText)
                            .foregroundStyle(draft.actionText.isEmpty ? theme.textFaint : theme.text)
                    } else {
                        TextField("Type the action", text: $draft.actionText)
                            .foregroundStyle(theme.text)
                            .onChange(of: draft.actionText) { _, _ in draft.clampAction() }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            FFSectionHeader(title: "Scoring").padding(.top, 8)
            FFGroupedRows {
                FFGroupedRow(
                    title: "Apple Health",
                    subtitle: steps.hasAsked ? "Steps on" : "Required to start",
                    systemImage: "heart",
                    subtitleTone: steps.hasAsked ? .moss : .ember,
                    trailing: AnyView(
                        FFPill(
                            steps.hasAsked ? "On" : "Connect",
                            style: steps.hasAsked ? .softMoss : .solidMoss
                        )
                    ),
                    action: { draft.connectAppleHealth(session: session, steps: steps) }
                )
            }

            NewFightStartBlock(title: "Start fight").padding(.top, 12)
        }
    }
}

struct NewFightCompactLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        Group {
            if staticRender {
                FFScreen(clearance: false) {
                    compactBody
                    NewFightStartBlock()
                }
            } else {
                ScrollView(.vertical) {
                    compactBody
                        .containerRelativeFrame(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.bg)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NewFightStickyBar {
                        NewFightStartBlock()
                    }
                }
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            FFScreenTitle(
                title: "New fight",
                subtitle: "Short form. Start stays on screen."
            )
            NewFightHealthSection(compact: true)
            NewFightPeopleSection(showAddButton: false, header: "Vs")
            NewFightDurationSlider()
            NewFightActionSection()
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, theme.space.base)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NewFightSentenceLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @FocusState private var usernameFocused: Bool
    @FocusState private var actionFocused: Bool

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "Say the fight",
                subtitle: "Fill in the blanks. Same rules as always."
            )
            .padding(.bottom, 6)

            FFCard(fill: theme.card) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Challenge")
                        .ffType(.caption)
                        .foregroundStyle(theme.textFaint)

                    if draft.inviteHandles.isEmpty {
                        sentenceField(
                            placeholder: "@username",
                            text: $draft.username,
                            focused: $usernameFocused
                        ) {
                            draft.addUsername(session: session)
                            if draft.usernameError == nil { usernameFocused = false }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(draft.inviteHandles, id: \.self) { handle in
                                HStack {
                                    Text("@\(handle)")
                                        .font(.ff(22, 800))
                                        .foregroundStyle(theme.text)
                                    Spacer()
                                    Button {
                                        draft.removeHandle(handle)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove @\(handle)")
                                }
                            }
                            sentenceField(
                                placeholder: "Add another",
                                text: $draft.username,
                                focused: $usernameFocused
                            ) {
                                draft.addUsername(session: session)
                                if draft.usernameError == nil { usernameFocused = false }
                            }
                        }
                    }

                    if let usernameError = draft.usernameError {
                        Text(usernameError)
                            .ffType(.caption)
                            .foregroundStyle(theme.emberText)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("for")
                            .font(.ff(22, 800))
                            .foregroundStyle(theme.textSecondary)
                        Text(draft.duration)
                            .font(.ff(22, 800))
                            .foregroundStyle(theme.mossText)
                    }

                    FFDurationPicker(options: NewFightDraft.testDurations, selection: $draft.duration)
                    FFDurationPicker(options: NewFightDraft.realDurations, selection: $draft.duration)

                    Text("Loser")
                        .font(.ff(22, 800))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 4)

                    sentenceField(
                        placeholder: "cooks dinner",
                        text: $draft.actionText,
                        focused: $actionFocused,
                        submit: false
                    )
                    .onChange(of: draft.actionText) { _, _ in draft.clampAction() }
                }
            }

            NewFightHealthSection(compact: true).padding(.top, 8)
            NewFightStartBlock().padding(.top, 8)
        }
    }

    private func sentenceField(
        placeholder: String,
        text: Binding<String>,
        focused: FocusState<Bool>.Binding,
        submit: Bool = true,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        Group {
            if staticRender {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .font(.ff(22, 800))
                    .foregroundStyle(text.wrappedValue.isEmpty ? theme.textFaint : theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: text)
                    .font(.ff(22, 800))
                    .foregroundStyle(theme.text)
                    .textInputAutocapitalization(submit ? .never : .sentences)
                    .autocorrectionDisabled(submit)
                    .submitLabel(submit ? .join : .done)
                    .focused(focused)
                    .onSubmit { onSubmit?() }
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.mossText.opacity(0.45)).frame(height: 2)
        }
    }
}

struct NewFightTicketLayout: View {
    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        if draft.showingTicket {
            ticket
        } else {
            form
        }
    }

    private var form: some View {
        FFScreen {
            FFScreenTitle(
                title: "Set the terms",
                subtitle: "You’ll get a ticket to confirm before it starts."
            )
            .padding(.bottom, 6)

            NewFightPeopleSection(showAddButton: false, header: "Players")
            NewFightDurationChips().padding(.top, 8)
            NewFightActionSection(starters: true).padding(.top, 8)
            NewFightHealthSection(compact: true).padding(.top, 8)

            FFScreenCTA(
                title: draft.canStart(session: session, steps: steps, model: model)
                    ? "Review ticket"
                    : draft.startTitle(session: session, steps: steps, model: model),
                enabled: draft.canStart(session: session, steps: steps, model: model)
            ) {
                guard draft.commitPendingUsername(session: session) else { return }
                guard draft.canStart(session: session, steps: steps, model: model) else { return }
                draft.showingTicket = true
            }
            .padding(.top, 8)
        }
    }

    private var ticket: some View {
        FFScreen {
            FFNavFlow(
                title: "Confirm fight",
                step: "Read it once, then start.",
                onClose: { draft.showingTicket = false }
            )

            FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.22)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        FFEyebrow("Steps · highest total")
                        Spacer()
                        FFPill(draft.duration, style: .solidMoss)
                    }
                    Text(draft.versusLine)
                        .font(.ff(22, 800))
                        .foregroundStyle(theme.text)
                    Text(draft.endsCaption)
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    Rectangle().fill(theme.mossText.opacity(0.18)).frame(height: 1)
                    Text("Loser")
                        .ffType(.caption)
                        .foregroundStyle(theme.mossText)
                    Text(draft.trimmedAction)
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                }
            }

            Text("Starts the moment you tap Start fight. Later steps do not count.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)

            NewFightStartBlock(title: "Start fight").padding(.top, 8)
            Button("Edit terms") { draft.showingTicket = false }
                .ffType(.label)
                .foregroundStyle(theme.mossText)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}
