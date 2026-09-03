import SwiftUI

struct NewFightLayoutSwitcher: View {
    @EnvironmentObject private var layouts: NewFightLayoutStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Layout \(layouts.layout.number)")
                    .ffType(.micro)
                    .foregroundStyle(theme.mossText)
                Text(layouts.layout.title)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(NewFightLayout.allCases) { layout in
                        let on = layouts.layout == layout
                        Button {
                            layouts.layout = layout
                        } label: {
                            Text("\(layout.number)")
                                .font(.ff(12, 800))
                                .foregroundStyle(on ? theme.mossOn : theme.textDim)
                                .frame(width: 32, height: 32)
                                .background(
                                    on ? theme.mossFill : theme.card,
                                    in: Circle()
                                )
                                .overlay {
                                    Circle().strokeBorder(
                                        on ? theme.mossEdge : theme.hairline,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Layout \(layout.number), \(layout.title)")
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

struct NewFightHealthSection: View {
    var compact: Bool = false

    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        if compact, steps.hasAsked {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !compact { FFSectionHeader(title: "Challenge") }
                FFGroupedRows {
                    FFGroupedRow(
                        title: "Most steps wins",
                        subtitle: compact
                            ? "Needed to score the fight."
                            : "FitFight uploads your Fight total and relevant daily totals. Accepted players see both and your rank.",
                        systemImage: "figure.walk",
                        subtitleTone: .moss,
                        trailing: AnyView(
                            FFPill(
                                steps.hasAsked ? "Steps on" : "Connect",
                                style: steps.hasAsked ? .softMoss : .solidMoss
                            )
                        ),
                        action: { draft.connectAppleHealth(session: session, steps: steps) }
                    )
                }
                if !steps.hasAsked {
                    Text("Connect Apple Health to score and start a fight.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

struct NewFightPeopleSection: View {
    var showAddButton: Bool = true
    var header: String = "Friends"
    var caption: String = "Add at least one exact username. They must have opened FitFight and chosen one."

    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @FocusState private var usernameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: header)
                FFPill(draft.playerLabel, style: .softMoss)
            }
            Text(showAddButton ? caption : "Type an exact username and tap Return. They must have opened FitFight once.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
            HStack(spacing: 8) {
                Group {
                    if staticRender {
                        Text(draft.username.isEmpty ? "@username" : draft.username)
                            .foregroundStyle(draft.username.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("@username", text: $draft.username)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(showAddButton ? .join : .done)
                            .focused($usernameFocused)
                            .onSubmit { add() }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(draft.usernameError == nil ? theme.line : theme.emberText, radius: theme.radius.field)
                if showAddButton {
                    FFButton(
                        title: "Add",
                        size: .small,
                        enabled: !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        add()
                    }
                }
            }
            if let usernameError = draft.usernameError {
                Text(usernameError)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            if !draft.inviteHandles.isEmpty {
                FFGroupedRows {
                    ForEach(Array(draft.inviteHandles.enumerated()), id: \.element) { index, handle in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(monogram: String(handle.prefix(2)).uppercased(), size: 36)
                            Text("@\(handle)")
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 8)
                            Button {
                                draft.removeHandle(handle)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(theme.control, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove @\(handle)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private func add() {
        draft.addUsername(session: session)
        if draft.usernameError == nil {
            usernameFocused = false
        }
    }
}

struct NewFightDurationChips: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Duration")
                FFPill(draft.duration, style: .softMoss)
            }
            FFDurationPicker(options: NewFightDraft.testDurations, selection: $draft.duration)
            FFDurationPicker(options: NewFightDraft.realDurations, selection: $draft.duration)
            Text("The fight starts now. Steps after the end time do not count.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
    }
}

struct NewFightDurationSlider: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Duration")
                FFPill(draft.duration, style: .softMoss)
            }
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(draft.duration)
                            .font(.ff(22, 800))
                            .foregroundStyle(theme.text)
                        Spacer(minLength: 8)
                        Text(draft.endsCaption)
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    FFSlider(value: indexBinding, range: 0...Double(NewFightDraft.durations.count - 1), step: 1)
                }
            }
            Text("The fight starts now. Steps after the end time do not count.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
    }

    private var indexBinding: Binding<Double> {
        Binding(
            get: {
                Double(NewFightDraft.durations.firstIndex(of: draft.duration) ?? 3)
            },
            set: { value in
                let index = min(max(Int(value.rounded()), 0), NewFightDraft.durations.count - 1)
                draft.duration = NewFightDraft.durations[index]
            }
        )
    }
}

struct NewFightDurationList: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Duration")
            FFGroupedRows {
                ForEach(Array(NewFightDraft.durations.enumerated()), id: \.element) { index, option in
                    if index > 0 { FFDivider() }
                    Button {
                        draft.duration = option
                    } label: {
                        HStack {
                            Text(option)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Spacer()
                            if option == draft.duration {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(theme.mossText)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ffRowSelection(
                        option == draft.duration,
                        outerRadius: theme.radius.card,
                        fill: theme.mossWash
                    )
                }
            }
        }
    }
}

struct NewFightActionSection: View {
    var starters: Bool = false
    var prompt: String = "What does the loser have to do?"

    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Action")
            Text(prompt)
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            if starters {
                HStack(spacing: 8) {
                    ForEach(NewFightDraft.actionStarters, id: \.self) { starter in
                        Button {
                            draft.actionText = starter
                        } label: {
                            Text(starter)
                                .ffType(.micro)
                                .fontWeight(.heavy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(draft.actionText == starter ? theme.mossOn : theme.textSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    draft.actionText == starter ? theme.mossFill : theme.card,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().strokeBorder(
                                        draft.actionText == starter ? theme.mossEdge : theme.hairline,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Group {
                if staticRender {
                    Text(draft.actionText.isEmpty ? "Loser cooks dinner" : draft.actionText)
                        .foregroundStyle(draft.actionText.isEmpty ? theme.textFaint : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Loser cooks dinner", text: $draft.actionText)
                        .foregroundStyle(theme.text)
                        .onChange(of: draft.actionText) { _, _ in
                            draft.clampAction()
                        }
                }
            }
            .font(.ff(15, 700))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(theme.line, radius: theme.radius.field)
        }
    }
}

struct NewFightSummaryCard: View {
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps · \(draft.duration)")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Text(draft.versusLine)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                Text(draft.trimmedAction.isEmpty ? "Add the action the loser will do." : draft.trimmedAction)
                    .ffType(.body)
                    .foregroundStyle(draft.trimmedAction.isEmpty ? theme.textFaint : theme.text)
                    .lineLimit(3)
            }
        }
    }
}

struct NewFightStartBlock: View {
    var title: String?

    @EnvironmentObject private var draft: NewFightDraft
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFScreenCTA(
                title: {
                    if model.isCreatingFight { return "Starting…" }
                    return title ?? draft.startTitle(session: session, steps: steps, model: model)
                }(),
                enabled: draft.canStart(session: session, steps: steps, model: model),
                busy: model.isCreatingFight
            ) {
                draft.startFight(model: model, session: session, steps: steps)
            }
            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
    }
}

struct NewFightStickyBar<Content: View>: View {
    @Environment(\.ffTheme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(theme.bg)
            .overlay(alignment: .top) {
                theme.hairline.frame(height: 1)
            }
    }
}
