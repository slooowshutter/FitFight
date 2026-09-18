import SwiftUI

enum FightComposerStep: Int, Hashable {
    case metric = 0
    case duration = 1
    case people = 2
    case details = 3
    case review = 4
}

struct FightComposerPerson: Identifiable, Equatable {
    let id: String
    let handle: String
    let name: String
    let photoURL: URL?
    let isOwner: Bool
    let invited: Bool
    let deferred: Bool
    let pendingAdd: Bool

    func subtitle(createMode: Bool) -> String {
        if isOwner { return String(localized: "Created this fight") }
        if pendingAdd {
            return createMode
                ? String(localized: "Added to this fight")
                : String(localized: "Will be invited")
        }
        if deferred { return String(localized: "Next round") }
        if invited { return String(localized: "Invited") }
        return String(localized: "In this fight")
    }
}

enum FightComposer {
    static func durationLabel(days: Int, customSchedule: Bool) -> String {
        if customSchedule { return String(localized: "Custom") }
        switch days {
        case 3: return String(localized: "3 days")
        case 14: return String(localized: "2 weeks")
        case 30: return String(localized: "1 month")
        default: return String(localized: "1 week")
        }
    }

    static func endDate(from startsAt: Date, days: Int, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: days, to: startsAt)
            ?? startsAt.addingTimeInterval(TimeInterval(days * 86_400))
    }

    static func moveWallTime(_ date: Date, from oldZone: TimeZone, to newZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oldZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        calendar.timeZone = newZone
        return calendar.date(from: components) ?? date
    }
}

struct FightComposerMetricPage: View {
    @Environment(\.ffTheme) private var theme

    var body: some View {
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
}

struct FightComposerDurationPage: View {
    @Binding var durationDays: Int
    @Binding var customSchedule: Bool
    @Binding var customStart: Date
    @Binding var customEnd: Date
    @Binding var recurring: Bool
    @Binding var timeZone: TimeZone
    var canEditStart: Bool
    var startsImmediately: Bool
    var constrainEnd: Bool
    var scheduleError: String?

    @Environment(\.ffTheme) private var theme

    private var duration: String {
        FightComposer.durationLabel(days: durationDays, customSchedule: customSchedule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How long will the fight last?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(customSchedule
                     ? String(localized: "Choose the exact start and end. Only steps inside this window count.")
                     : startsImmediately
                        ? String(localized: "It starts immediately. Steps after the exact end time do not count.")
                        : String(localized: "Steps after the exact end time do not count."))
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
            }

            if customSchedule {
                FFCard {
                    VStack(alignment: .leading, spacing: 16) {
                        if canEditStart {
                            DatePicker("Start", selection: $customStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            FFDivider()
                        }
                        if constrainEnd {
                            DatePicker(
                                "End",
                                selection: $customEnd,
                                in: (canEditStart ? customStart : Date())...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        } else {
                            DatePicker("End", selection: $customEnd, displayedComponents: [.date, .hourAndMinute])
                        }
                        if canEditStart {
                            FitFightTimeZonePicker(selection: $timeZone)
                        } else {
                            Text(verbatim: timeZone.identifier)
                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .tint(theme.mossText)
                    .environment(\.timeZone, timeZone)
                    .onChange(of: timeZone) { oldZone, newZone in
                        if canEditStart {
                            customStart = FightComposer.moveWallTime(customStart, from: oldZone, to: newZone)
                        }
                        customEnd = FightComposer.moveWallTime(customEnd, from: oldZone, to: newZone)
                    }
                }
                if let scheduleError {
                    FFNotice(text: scheduleError, tone: .ember, systemImage: "calendar")
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
}

struct FightComposerPeoplePage: View {
    @Binding var visibilityJoinable: Bool
    @Binding var username: String
    @Binding var usernameError: String?
    @Binding var people: [FightComposerPerson]
    var usernameFocused: FocusState<Bool>.Binding
    var createMode: Bool
    var onAdd: () -> Void

    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who can join?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(
                    visibilityJoinable
                        ? String(localized: "Listed on Join. Anyone with the code or invite link can join. Usernames are optional.")
                        : String(localized: "New fights start private. People still join with the code or invite link. Usernames are optional.")
                )
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)

                HStack(spacing: 8) {
                    Group {
                        if staticRender {
                            Text(verbatim: username.isEmpty ? String(localized: "@username") : username)
                                .foregroundStyle(username.isEmpty ? theme.textFaint : theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField("@username", text: $username)
                                .focused(usernameFocused)
                                .foregroundStyle(theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit {
                                    onAdd()
                                    usernameFocused.wrappedValue = false
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
                        onAdd()
                    }
                }

                if let usernameError {
                    Text(usernameError)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                }
            }

            if !people.isEmpty {
                FFGroupedRows {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            ProfileIdentityLink(userID: UUID(uuidString: person.id), source: "participants") {
                                HStack(spacing: 12) {
                                    FFAvatar(monogram: String(person.handle.prefix(2)).uppercased(), size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: person.name)
                                            .ffType(.rowTitle)
                                            .foregroundStyle(theme.text)
                                        Text(person.subtitle(createMode: createMode))
                                            .ffType(.caption)
                                            .foregroundStyle(person.isOwner ? theme.mossText : (createMode || person.pendingAdd ? theme.mossText : theme.textSecondary))
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            if person.isOwner {
                                FFPill(String(localized: "Owner"), style: .softMoss)
                            } else {
                                Button {
                                    people.removeAll { $0.id == person.id }
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
}

struct FightComposerDetailsPage: View {
    @Binding var fightTitle: String
    @Binding var actionText: String
    var titleFocused: FocusState<Bool>.Binding
    var actionFocused: FocusState<Bool>.Binding

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title and action")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Both are optional. If you skip a title, the action is the name of the fight.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FightComposerLimitedField(
                label: String(localized: "Title"),
                placeholder: String(localized: "Weekend walk-off"),
                text: $fightTitle,
                focus: titleFocused,
                submitLabel: .next,
                onSubmit: { actionFocused.wrappedValue = true }
            )
            FightComposerLimitedField(
                label: String(localized: "Loser action"),
                placeholder: String(localized: "Cook dinner"),
                text: $actionText,
                focus: actionFocused,
                submitLabel: .done,
                onSubmit: { actionFocused.wrappedValue = false }
            )
        }
    }
}

struct FightComposerLimitedField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var submitLabel: SubmitLabel
    var onSubmit: () -> Void

    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
            Group {
                if staticRender {
                    Text(verbatim: text.isEmpty ? placeholder : text)
                        .foregroundStyle(text.isEmpty ? theme.textFaint : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $text)
                        .focused(focus)
                        .foregroundStyle(theme.text)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                        .onChange(of: text) { _, value in
                            if value.count > 120 {
                                text = String(value.prefix(120))
                            }
                        }
                }
            }
            .font(.ff(15, 700))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(theme.line, radius: theme.radius.field)

            Text(verbatim: "\(text.count)/120")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct FightComposerReviewPage: View {
    var isEditing: Bool
    var fightTitle: String
    var actionText: String
    var duration: String
    var customSchedule: Bool
    var customStart: Date
    var customEnd: Date
    var durationStart: Date
    var durationDays: Int
    var timeZone: TimeZone
    var visibilityJoinable: Bool
    var opponentHandles: [String]
    var recurring: Bool
    var healthConnected: Bool
    var healthBusy: Bool
    var onChange: (FightComposerStep) -> Void
    var onConnectHealth: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let listing = visibilityJoinable
            ? String(localized: "Listed on Join")
            : String(localized: "Join with code or invite link")
        let opponents = opponentHandles.map { "@\($0)" }.formatted(.list(type: .and))
        let matchup = opponents.isEmpty ? String(localized: "people who join") : opponents
        let privacy = opponents.isEmpty
            ? listing
            : "\(listing) · \(opponents)"
        let windowEnd = customSchedule
            ? customEnd
            : FightComposer.endDate(from: durationStart, days: durationDays, timeZone: timeZone)
        let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: timeZone)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isEditing ? String(localized: "This fight") : String(localized: "Ready to fight?"))
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(isEditing
                     ? String(localized: "Change a row, then save.")
                     : String(localized: "Check the agreement before you start."))
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
                    action: { onChange(.metric) }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Duration"),
                    subtitle: (customSchedule ? String(
                        localized: "fight.custom-window",
                        defaultValue: "\(customStart.formatted(dateFormat)) → \(customEnd.formatted(dateFormat))"
                    ) : String(
                        localized: "fight.duration-end",
                        defaultValue: "\(duration) · ends \(windowEnd.formatted(dateFormat))"
                    )) + " · \(timeZone.identifier)",
                    systemImage: "calendar",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { onChange(.duration) }
                )
                FFDivider()
                FFGroupedRow(
                    title: visibilityJoinable ? String(localized: "Public") : String(localized: "Private"),
                    subtitle: privacy,
                    systemImage: visibilityJoinable ? "link" : "lock",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { onChange(.people) }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Title"),
                    subtitle: title.isEmpty
                        ? (action.isEmpty ? String(localized: "None") : String(localized: "Uses the action"))
                        : title,
                    systemImage: "textformat",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { onChange(.details) }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Loser action"),
                    subtitle: action.isEmpty ? String(localized: "None") : action,
                    systemImage: "flag",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { onChange(.details) }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Apple Health Steps"),
                    subtitle: CompanionPreview.isEnabled ? String(localized: "Sample steps · preview") : healthConnected
                        ? String(localized: "Ready to score this fight")
                        : String(localized: "Connect to score this fight"),
                    systemImage: "heart",
                    enabled: !healthBusy,
                    subtitleTone: healthConnected ? .moss : .ember,
                    trailing: AnyView(
                        FFPill(
                            healthConnected ? String(localized: "Connected") : String(localized: "Connect"),
                            style: healthConnected ? .softMoss : .solidMoss
                        )
                    ),
                    action: healthConnected ? nil : onConnectHealth
                )
                .disabled(healthBusy)
            }

            FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        String(
                            localized: "fight.you-versus",
                            defaultValue: "You vs \(matchup)"
                        )
                    )
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(
                        customSchedule ? String(localized: "Most Steps inside the selected window wins.") : String(
                            localized: "fight.winner-after-duration",
                            defaultValue: "Most Steps wins after \(duration.lowercased())."
                        )
                    )
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    if recurring {
                        Text("When it ends, the next window starts automatically.")
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if !action.isEmpty {
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
    }
}

struct FitFightTimeZonePicker: View {
    @Binding var selection: TimeZone
    @Environment(\.ffTheme) private var theme
    @State private var showingPicker = false
    @State private var search = ""

    var body: some View {
        Button {
            search = ""
            showingPicker = true
        } label: {
            HStack {
                Text(String(localized: "Time zone"))
                Spacer(minLength: 8)
                Text(verbatim: selection.identifier.replacingOccurrences(of: "_", with: " "))
                    .foregroundStyle(theme.textSecondary).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").foregroundStyle(theme.textFaint)
            }.ffType(.body).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                List {
                    ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", selection.identifier])).sorted().filter {
                        search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search)
                    }, id: \.self) { identifier in
                        if let zone = TimeZone(identifier: identifier) {
                            Button {
                                selection = zone
                                showingPicker = false
                            } label: {
                                HStack {
                                    Text(verbatim: identifier.replacingOccurrences(of: "_", with: " "))
                                    Spacer()
                                    if zone == selection { Image(systemName: "checkmark").foregroundStyle(theme.mossText) }
                                }.ffType(.body).frame(minHeight: 44).foregroundStyle(theme.text)
                            }.listRowBackground(theme.card)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.bg)
                .searchable(text: $search, prompt: String(localized: "Search time zones"))
                .navigationTitle(String(localized: "Time zone"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { showingPicker = false }
                    }
                }
            }.tint(theme.mossText).fitFightTheme(theme).presentationBackground(theme.bg)
        }
    }
}
