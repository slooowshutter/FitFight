import SwiftUI

struct EditFightView: View {
    private let fight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss

    @State private var fightTitle: String
    @State private var actionText: String
    @State private var visibilityJoinable: Bool
    @State private var recurring: Bool
    @State private var durationDays: Int
    @State private var customSchedule: Bool
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var roster: [RosterEntry]
    @State private var username = ""
    @State private var usernameError: String?
    @FocusState private var usernameFocused: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var actionFocused: Bool

    init(fight: Fight) {
        self.fight = fight
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
        _roster = State(initialValue: fight.standings.map { row in
            RosterEntry(
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
        if customSchedule { return String(localized: "Custom") }
        switch durationDays {
        case 3: return String(localized: "3 days")
        case 14: return String(localized: "2 weeks")
        case 30: return String(localized: "1 month")
        default: return String(localized: "1 week")
        }
    }

    private var scheduleError: String? {
        let startsAt = canEditStart ? (customSchedule ? customStart : fight.windowStart) : fight.windowStart
        let endsAt = customSchedule ? customEnd : endDate(from: startsAt)
        if canEditStart, customSchedule, customStart <= Date() {
            return String(localized: "Choose a start time in the future.")
        }
        if endsAt <= startsAt { return String(localized: "The end must be after the start.") }
        if endsAt <= Date() { return String(localized: "The end must be in the future.") }
        return nil
    }

    private var canEditStart: Bool { fight.isUpcoming }

    private var canSave: Bool {
        fightTitle.trimmingCharacters(in: .whitespacesAndNewlines).count <= 120
            && actionText.trimmingCharacters(in: .whitespacesAndNewlines).count <= 120
            && scheduleError == nil
            && !model.isUpdatingFight
    }

    var body: some View {
        FFScreen(top: AnyView(nav), clearance: false) {
            visibilitySection
            titleSection.padding(.top, theme.space.lg)
            durationSection.padding(.top, theme.space.lg)
            peopleSection.padding(.top, theme.space.lg)

            FFButton(
                title: model.isUpdatingFight ? String(localized: "Saving…") : String(localized: "Save changes"),
                size: .large,
                enabled: canSave,
                busy: model.isUpdatingFight,
                fullWidth: true
            ) {
                save()
            }
            .padding(.top, theme.space.lg)

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if let scheduleError {
                FFNotice(text: scheduleError, tone: .ember, systemImage: "calendar")
            }
        }
    }

    private var nav: some View {
        FFNavFlow(
            title: String(localized: "Edit fight"),
            onClose: { dismiss() }
        )
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 12)
        .background(theme.bg)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: String(localized: "Who can join?"))
            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Private"),
                    subtitle: String(localized: "Default · code or invite link"),
                    systemImage: "lock",
                    subtitleTone: visibilityJoinable ? .neutral : .moss,
                    trailing: visibilityJoinable
                        ? nil
                        : AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText)),
                    action: { visibilityJoinable = false }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Public"),
                    subtitle: String(localized: "Listed on Join"),
                    systemImage: "link",
                    subtitleTone: visibilityJoinable ? .moss : .neutral,
                    trailing: visibilityJoinable
                        ? AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText))
                        : nil,
                    action: { visibilityJoinable = true }
                )
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: String(localized: "Title and action"))
            limitedField(
                label: String(localized: "Title"),
                placeholder: String(localized: "Weekend walk-off"),
                text: $fightTitle,
                focus: $titleFocused,
                submitLabel: .next,
                onSubmit: { actionFocused = true }
            )
            limitedField(
                label: String(localized: "Loser action"),
                placeholder: String(localized: "Cook dinner"),
                text: $actionText,
                focus: $actionFocused,
                submitLabel: .done,
                onSubmit: { actionFocused = false }
            )
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: String(localized: "Duration"))
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
                        customSchedule = false
                        if selection == String(localized: "3 days") { durationDays = 3 }
                        else if selection == String(localized: "2 weeks") { durationDays = 14 }
                        else if selection == String(localized: "1 month") { durationDays = 30 }
                        else { durationDays = 7 }
                    }
                )
            )
            FFButton(title: String(localized: "Custom"), kind: customSchedule ? .primary : .secondary, fullWidth: true) {
                customSchedule = true
            }
            if customSchedule {
                FFCard {
                    VStack(alignment: .leading, spacing: 16) {
                        if canEditStart {
                            DatePicker(
                                "Start",
                                selection: $customStart,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            FFDivider()
                        }
                        DatePicker(
                            "End",
                            selection: $customEnd,
                            in: (canEditStart ? customStart : Date())...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .tint(theme.mossText)
                }
            }
            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Repeat when it ends"),
                    subtitle: String(localized: "The next window starts when this one ends"),
                    systemImage: "arrow.clockwise",
                    subtitleTone: recurring ? .moss : .neutral,
                    trailing: AnyView(
                        Toggle("", isOn: $recurring)
                            .labelsHidden()
                            .tint(theme.mossFill)
                    )
                )
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: String(localized: "People"))
            Text("Add a username or remove someone. Only you can kick people out.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)

            HStack(spacing: 8) {
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
                FFButton(
                    title: String(localized: "Add"),
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

            if !roster.isEmpty {
                FFGroupedRows {
                    ForEach(Array(roster.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(monogram: String(person.handle.prefix(2)).uppercased(), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: person.name)
                                    .ffType(.rowTitle)
                                    .foregroundStyle(theme.text)
                                Text(person.subtitle)
                                    .ffType(.caption)
                                    .foregroundStyle(person.isOwner ? theme.mossText : theme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            if person.isOwner {
                                FFPill(String(localized: "Owner"), style: .softMoss)
                            } else {
                                Button {
                                    roster.removeAll { $0.id == person.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(theme.textSecondary)
                                        .frame(width: 44, height: 44)
                                        .background(theme.control, in: Circle())
                                }
                                .buttonStyle(FFHapticPlainStyle())
                                .accessibilityLabel(
                                    String(
                                        localized: "fight.remove-handle",
                                        defaultValue: "Remove @\(person.handle)"
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private func limitedField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
            Group {
                if staticRender {
                    Text(verbatim: text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                        .foregroundStyle(text.wrappedValue.isEmpty ? theme.textFaint : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: text)
                        .focused(focus)
                        .foregroundStyle(theme.text)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                        .onChange(of: text.wrappedValue) { _, value in
                            if value.count > 120 {
                                text.wrappedValue = String(value.prefix(120))
                            }
                        }
                }
            }
            .font(.ff(15, 700))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(theme.line, radius: theme.radius.field)

            Text(verbatim: "\(text.wrappedValue.count)/120")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
        guard !roster.contains(where: { $0.handle == handle }) else {
            usernameError = String(
                localized: "fight.handle-already-added",
                defaultValue: "@\(handle) is already in this fight."
            )
            return
        }
        roster.append(
            RosterEntry(
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

    private func endDate(from startsAt: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: durationDays, to: startsAt)
            ?? startsAt.addingTimeInterval(TimeInterval(durationDays * 86_400))
    }

    private func save() {
        guard canSave else { return }
        let startsAt = canEditStart && customSchedule ? customStart : fight.windowStart
        let endsAt = customSchedule ? customEnd : endDate(from: startsAt)
        let originalIDs = Set(fight.standings.map(\.person.id))
        let remainingIDs = Set(roster.filter { !$0.pendingAdd }.map(\.id))
        let removeUserIds = originalIDs.subtracting(remainingIDs).filter { id in
            roster.first(where: { $0.id == id })?.isOwner != true
                && fight.standings.first(where: { $0.person.id == id })?.person.isYou != true
        }
        let inviteHandles = roster.filter(\.pendingAdd).map(\.handle)
        Task {
            let saved = await model.updateFight(
                id: fight.id,
                name: fightTitle,
                actionText: actionText,
                visibility: visibilityJoinable ? "joinable" : "invite_only",
                recurring: recurring,
                startsAt: canEditStart ? startsAt : nil,
                endsAt: endsAt,
                inviteHandles: inviteHandles,
                removeUserIds: Array(removeUserIds)
            )
            if saved {
                dismiss()
            }
        }
    }
}

private struct RosterEntry: Identifiable, Equatable {
    let id: String
    let handle: String
    let name: String
    let photoURL: URL?
    let isOwner: Bool
    let invited: Bool
    let deferred: Bool
    let pendingAdd: Bool

    var subtitle: String {
        if isOwner { return String(localized: "Created this fight") }
        if pendingAdd { return String(localized: "Will be invited") }
        if deferred { return String(localized: "Next round") }
        if invited { return String(localized: "Invited") }
        return String(localized: "In this fight")
    }
}
