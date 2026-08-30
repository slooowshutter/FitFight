import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    @State private var metric: MetricKind = .steps
    @State private var selected: Set<String> = []
    @State private var friendHandle = ""
    @State private var lengthDays = 7
    @State private var pickingDate = false
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var stake: StakeKind = .ten
    @State private var customKind: CustomStakeKind = .money
    @State private var customMoney = 15
    @State private var forfeit = ""
    @State private var settlement: SettlementKind = .winner
    @State private var dailyGoal = 10000.0

    private var selectedPeople: [Person] {
        model.people.filter { selected.contains($0.id) }
    }

    private var playerCount: Int { selectedPeople.count + 1 }

    private var canStartSteps: Bool { metric == .steps }

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "New fight",
                subtitle: "Scores sync automatically. You settle up at the end."
            )
            .padding(.bottom, 6)

            metricSection
            peopleSection.padding(.top, theme.space.lg)
            lengthSection.padding(.top, theme.space.lg)
            stakeSection.padding(.top, theme.space.lg)
            if stake != .bragging {
                settlementSection.padding(.top, theme.space.lg)
            }
            if settlement == .goal && stake != .bragging {
                goalSection.padding(.top, theme.space.lg)
            }
            summary.padding(.top, theme.space.lg)

            FFScreenCTA(
                title: model.isCreatingFight ? "Starting…" : "Start fight",
                enabled: canStartSteps,
                busy: model.isCreatingFight
            ) {
                startFight()
            }
            .padding(.top, 6)

            if !canStartSteps {
                Text("Steps only for now")
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity)
            }
            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var metricSection: some View {
        let options = MetricKind.allCases
        return VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Metric")
            FFGroupedRows {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        FFDivider(visible: options[index - 1] != metric && item != metric)
                    }
                    optionRow(title: item.title, subtitle: item.blurb, on: metric == item) {
                        metric = item
                        dailyGoal = item == .steps ? 10000 : (item == .activeMinutes ? 45 : 1)
                    }
                }
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Who's in")
                FFPill("\(playerCount) player\(playerCount == 1 ? "" : "s")", style: .softMoss)
            }
            Text("Type their username. They must have opened the app and picked one. You can start alone.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
            TextField("@username", text: $friendHandle)
                .font(.ff(15, 700))
                .foregroundStyle(theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.join)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(theme.line, radius: theme.radius.field)
                .onSubmit { addFriendFromField() }
            if model.people.isEmpty {
                FFAddRow(title: "No friends yet", subtitle: "Add one above, or start alone") {}
            } else {
                FFGroupedRows {
                    ForEach(Array(model.people.enumerated()), id: \.element.id) { index, person in
                        let on = selected.contains(person.id)
                        if index > 0 {
                            let previousOn = selected.contains(model.people[index - 1].id)
                            FFDivider(visible: !previousOn && !on)
                        }
                        Button {
                            if on { selected.remove(person.id) } else { selected.insert(person.id) }
                        } label: {
                            HStack(spacing: 13) {
                                FFAvatar(person, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .ffType(.rowTitle)
                                        .foregroundStyle(theme.text)
                                    Text(person.handle)
                                        .ffType(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                tick(on, square: true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .ffRowSelection(on, outerRadius: theme.radius.card, fill: theme.mossWash)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FFSectionHeader(title: "Ends")
                FFPill("\(lengthDays) days", style: .softMoss)
            }
            FFDurationPicker(options: ["3 days", "1 week", "2 weeks", "Pick a date"], selection: durationBinding)
            if pickingDate {
                DatePicker("End date", selection: $endDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(theme.mossFill)
                    .onChange(of: endDate) { _, new in
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: new).day ?? 1
                        lengthDays = max(1, days)
                    }
            }
            Text("Runs from tomorrow to \(endLabel).")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
    }

    /// FFDurationPicker speaks strings; the fight speaks days.
    private var durationBinding: Binding<String> {
        Binding(
            get: {
                if pickingDate { return "Pick a date" }
                switch lengthDays {
                case 3: return "3 days"
                case 7: return "1 week"
                case 14: return "2 weeks"
                default: return "Pick a date"
                }
            },
            set: { choice in
                let days = ["3 days": 3, "1 week": 7, "2 weeks": 14][choice]
                if let days {
                    pickingDate = false
                    lengthDays = days
                    endDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                } else {
                    pickingDate = true
                }
            }
        )
    }

    private var stakeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "What’s on the line")
            HStack(spacing: 8) {
                FFChip(title: "Bragging rights", selected: stake == .bragging) { stake = .bragging }
                FFChip(title: "$10", selected: stake == .ten) { stake = .ten }
                FFChip(title: "Custom", selected: stake == .custom) { stake = .custom }
                Spacer(minLength: 0)
            }
            if stake == .custom {
                HStack(spacing: 8) {
                    FFChip(title: "Money", selected: customKind == .money) { customKind = .money }
                    FFChip(title: "Action", selected: customKind == .action) {
                        customKind = .action
                        if settlement == .proportional { settlement = .winner }
                    }
                    Spacer(minLength: 0)
                }
                if customKind == .money {
                    FFCard {
                        FFStepper(value: $customMoney, step: 5, minimum: 5, unit: "each")
                    }
                } else {
                    TextField("what does the loser owe?", text: $forfeit)
                        .font(.ff(15, 700))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                        .ffBorder(theme.line, radius: theme.radius.field)
                    HStack(spacing: 8) {
                        ForEach(["Loser buys dinner", "Loser posts the recap"], id: \.self) { suggestion in
                            FFChip(title: suggestion, selected: forfeit == suggestion) { forfeit = suggestion }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var settlementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "How the pot settles")
            FFGroupedRows {
                let options: [SettlementKind] = {
                    if stake == .custom && customKind == .action {
                        return [.winner, .goal]
                    }
                    return SettlementKind.allCases
                }()
                ForEach(Array(options.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        FFDivider(visible: options[index - 1] != settlement && item != settlement)
                    }
                    optionRow(title: item.title, subtitle: item.blurb, on: settlement == item, leadingTick: true) {
                        settlement = item
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Daily goal")
            FFCard {
                FFStepper(value: goalBinding, step: Int(step), minimum: Int(step), unit: goalUnit)
            }
        }
    }

    private var goalBinding: Binding<Int> {
        Binding(get: { Int(dailyGoal) }, set: { dailyGoal = Double($0) })
    }

    private var step: Double {
        switch metric {
        case .steps: return 500
        case .activeMinutes: return 5
        case .workouts: return 1
        }
    }

    private var goalUnit: String {
        switch metric {
        case .steps: return "steps a day"
        case .activeMinutes: return "minutes a day"
        case .workouts: return "workouts a day"
        }
    }

    /// The mocks write dates as "Mon 27 Jul", which no locale-driven style gives us.
    private static let endFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E d MMM"
        return formatter
    }()

    private var endLabel: String {
        Self.endFormatter.string(from: endDate)
    }

    private var summary: some View {
        FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(lengthDays)-day \(metric.eyebrow.lowercased())")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Text("Fight with \(playerCount) players, ending \(endLabel). \(stakeSummary).")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stakeSummary: String {
        let players = playerCount
        switch stake {
        case .bragging: return "Bragging rights only"
        case .ten: return "$10 each — the winner takes all $\(10 * players)"
        case .custom:
            if customKind == .money {
                return "$\(customMoney) each"
            }
            return forfeit.isEmpty ? "a custom forfeit" : forfeit
        }
    }

    private func optionRow(
        title: String,
        subtitle: String,
        on: Bool,
        leadingTick: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if leadingTick { tick(on) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The text takes the whole remaining width; a Spacer here would
                // compete with it and wrap the sentence a word early.
                .frame(maxWidth: .infinity, alignment: .leading)
                if !leadingTick { tick(on) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ffRowSelection(on, outerRadius: theme.radius.card, fill: theme.mossWash)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let tickSize: CGFloat = 22

    @ViewBuilder
    private func tick(_ on: Bool, square: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: square ? 7 : Self.tickSize / 2, style: .continuous)
        ZStack {
            shape
                .fill(on ? theme.mossFill : Color.clear)
                .overlay {
                    if !on { shape.strokeBorder(theme.textTertiary, lineWidth: 2) }
                }
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(theme.mossOn)
            }
        }
        .frame(width: Self.tickSize, height: Self.tickSize)
    }

    private func bareHandle(_ handle: String) -> String {
        handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
    }

    private func addFriendFromField() {
        let raw = friendHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let handle = bareHandle(raw)
        friendHandle = ""
        Task {
            await model.addFriend(handle: handle)
            await model.refreshFromServer()
        }
    }

    private func startFight() {
        guard canStartSteps else { return }
        guard session.isSignedIn else {
            model.tab = .you
            return
        }
        guard model.beginCreateFight() else { return }
        var inviteHandles = selectedPeople.map { bareHandle($0.handle) }
        let typed = bareHandle(friendHandle.trimmingCharacters(in: .whitespacesAndNewlines))
        if !typed.isEmpty, !inviteHandles.contains(typed) {
            inviteHandles.append(typed)
        }
        Task {
            await model.createAndStartFight(
                startsAt: Date(),
                endsAt: endDate,
                outcomeRule: settlement,
                stake: stake,
                customKind: customKind,
                customMoney: customMoney,
                actionText: forfeit,
                dailyGoal: dailyGoal,
                inviteHandles: inviteHandles
            )
            if (model.createError ?? "").isEmpty {
                model.tab = .fights
            }
        }
    }
}
