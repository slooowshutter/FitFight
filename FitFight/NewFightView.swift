import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var username = ""
    @State private var inviteHandles: [String] = []
    @State private var usernameError: String?
    @State private var duration = "1 week"
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
            if !staticRender {
                summary.padding(.top, theme.space.lg)
            }

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
                FFPill(
                    "\(inviteHandles.count + 1) \(inviteHandles.isEmpty ? "player" : "players")",
                    style: .softMoss
                )
            }
            Text("Add at least one exact username. They must have opened FitFight and chosen one.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
            HStack(spacing: 8) {
                Group {
                    if staticRender {
                        Text(username.isEmpty ? "@username" : username)
                            .foregroundStyle(username.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("@username", text: $username)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.join)
                            .onSubmit { addUsername() }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(usernameError == nil ? theme.line : theme.emberText, radius: theme.radius.field)
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
                FFPill(duration, style: .softMoss)
            }
            FFDurationPicker(
                options: ["1 hour", "6 hours", "1 day"],
                selection: $duration
            )
            FFDurationPicker(
                options: ["3 days", "1 week", "2 weeks", "1 month"],
                selection: $duration
            )
            Text("The fight starts now. Steps after the end time do not count.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Action")
            Text("What does the loser have to do?")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            Group {
                if staticRender {
                    Text(actionText.isEmpty ? "Loser cooks dinner" : actionText)
                        .foregroundStyle(actionText.isEmpty ? theme.textFaint : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Loser cooks dinner", text: $actionText)
                        .foregroundStyle(theme.text)
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
        }
    }

    private var summary: some View {
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps · \(duration)")
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
        let durationParts: (component: Calendar.Component, value: Int, seconds: TimeInterval) = switch duration {
        case "1 hour": (.hour, 1, 3_600)
        case "6 hours": (.hour, 6, 21_600)
        case "1 day": (.day, 1, 86_400)
        case "3 days": (.day, 3, 259_200)
        case "1 week": (.day, 7, 604_800)
        case "2 weeks": (.day, 14, 1_209_600)
        case "1 month": (.day, 30, 2_592_000)
        default: (.day, 7, 604_800)
        }
        let endsAt = Calendar.current.date(
            byAdding: durationParts.component,
            value: durationParts.value,
            to: startsAt
        ) ?? startsAt.addingTimeInterval(durationParts.seconds)
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
