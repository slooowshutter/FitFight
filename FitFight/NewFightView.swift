import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var username = ""
    @State private var inviteHandles: [String] = []
    @State private var usernameError: String?
    @State private var lengthDays = 7
    @State private var actionText = ""

    private var canStart: Bool {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.isSignedIn
            && steps.hasAsked
            && !inviteHandles.isEmpty
            && !action.isEmpty
            && action.count <= 120
            && !model.isCreatingFight
    }

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "New fight",
                subtitle: "Challenge friends. Most steps wins."
            )
            .padding(.bottom, 6)

            stepsSection
            peopleSection.padding(.top, theme.space.lg)
            lengthSection.padding(.top, theme.space.lg)
            actionSection.padding(.top, theme.space.lg)
            summary.padding(.top, theme.space.lg)

            FFScreenCTA(
                title: model.isCreatingFight ? "Starting…" : "Start fight",
                enabled: canStart,
                busy: model.isCreatingFight
            ) {
                startFight()
            }
            .padding(.top, 6)

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Challenge")
            FFGroupedRows {
                FFGroupedRow(
                    title: "Most steps wins",
                    subtitle: "FitFight uploads your Fight total and relevant daily totals. Accepted players see both and your rank.",
                    systemImage: "figure.walk",
                    subtitleTone: .moss,
                    trailing: AnyView(
                        FFPill(
                            steps.hasAsked ? "Steps on" : "Connect",
                            style: steps.hasAsked ? .softMoss : .solidMoss
                        )
                    ),
                    action: connectAppleHealth
                )
            }
            if !steps.hasAsked {
                Text("Connect Apple Health to score and start a fight.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Friends")
                FFPill("\(inviteHandles.count + 1) players", style: .softMoss)
            }
            Text("Add at least one exact username. They must have opened FitFight and chosen one.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
            HStack(spacing: 8) {
                TextField("@username", text: $username)
                    .font(.ff(15, 700))
                    .foregroundStyle(theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                    .ffBorder(usernameError == nil ? theme.line : theme.emberText, radius: theme.radius.field)
                    .onSubmit { addUsername() }
                FFButton(
                    title: "Add",
                    size: .small,
                    enabled: !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    addUsername()
                }
            }
            if let usernameError {
                Text(usernameError)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            if !inviteHandles.isEmpty {
                FFGroupedRows {
                    ForEach(Array(inviteHandles.enumerated()), id: \.element) { index, handle in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(monogram: String(handle.prefix(2)).uppercased(), size: 36)
                            Text("@\(handle)")
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 8)
                            Button {
                                inviteHandles.removeAll { $0 == handle }
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

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Duration")
                FFPill(durationLabel, style: .softMoss)
            }
            FFDurationPicker(
                options: ["3 days", "1 week", "2 weeks", "1 month"],
                selection: durationBinding
            )
            Text("The fight starts now. Steps after the end time do not count.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
    }

    private var durationBinding: Binding<String> {
        Binding(
            get: { durationLabel },
            set: { choice in
                lengthDays = ["3 days": 3, "1 week": 7, "2 weeks": 14, "1 month": 30][choice] ?? 7
            }
        )
    }

    private var durationLabel: String {
        switch lengthDays {
        case 3: return "3 days"
        case 14: return "2 weeks"
        case 30: return "1 month"
        default: return "1 week"
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Action")
            Text("What does the loser have to do?")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            TextField("Loser cooks dinner", text: $actionText)
                .font(.ff(15, 700))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(theme.line, radius: theme.radius.field)
                .onChange(of: actionText) { _, value in
                    if value.count > 120 {
                        actionText = String(value.prefix(120))
                    }
                }
        }
    }

    private var summary: some View {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps · \(durationLabel)")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Text(inviteHandles.isEmpty ? "Add a username to start." : "You vs \(inviteHandles.map { "@\($0)" }.joined(separator: ", ")).")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                Text(action.isEmpty ? "Add the action the loser will do." : action)
                    .ffType(.body)
                    .foregroundStyle(action.isEmpty ? theme.textFaint : theme.text)
                    .lineLimit(3)
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

    private func startFight() {
        guard canStart else { return }
        guard model.beginCreateFight() else { return }

        let startsAt = Date()
        let endsAt = Calendar.current.date(byAdding: .day, value: lengthDays, to: startsAt)
            ?? startsAt.addingTimeInterval(TimeInterval(lengthDays * 86_400))
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await model.createAndStartFight(
                startsAt: startsAt,
                endsAt: endsAt,
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
