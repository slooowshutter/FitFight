import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    @State private var metric: MetricKind = .steps
    @State private var selected: Set<String> = ["leo", "sam"]
    @State private var lengthDays = 7
    @State private var pickingDate = false
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var stake: StakeKind = .ten
    @State private var customKind: CustomStakeKind = .money
    @State private var customMoney = 15
    @State private var forfeit = ""
    @State private var settlement: SettlementKind = .winner
    @State private var dailyGoal = 10000.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                VStack(alignment: .leading, spacing: 6) {
                    FFLabel(text: "New fight", role: .display)
                    FFLabel(text: "Scores sync automatically. You settle up at the end.", role: .body, color: theme.muted)
                }
                metricSection
                peopleSection
                lengthSection
                stakeSection
                if stake != .bragging {
                    settlementSection
                }
                if settlement == .goal && stake != .bragging {
                    goalSection
                }
                summary
                FFButton(title: "Start fight", icon: "arrow.right") {
                    model.tab = .fights
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, theme.space.xl)
        }
        .background(theme.bg)
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Metric")
            FFGroup {
                ForEach(Array(MetricKind.allCases.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { FFHairline() }
                    radio(title: item.eyebrow, subtitle: item.blurb, on: metric == item) {
                        metric = item
                        dailyGoal = item == .steps ? 10000 : (item == .activeMinutes ? 45 : 1)
                    }
                }
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Who's in", action: "\(selected.count + 1) players")
            FFGroup {
                ForEach(Array(model.people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { FFHairline() }
                    let on = selected.contains(person.id)
                    Button {
                        if on { selected.remove(person.id) } else { selected.insert(person.id) }
                    } label: {
                        HStack(spacing: 12) {
                            FFAvatar(initials: person.initials, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                FFLabel(text: person.name, role: .bodyStrong)
                                FFLabel(text: person.handle, role: .caption, color: theme.muted)
                            }
                            Spacer()
                            checkbox(on)
                        }
                        .padding(.horizontal, theme.space.rowPaddingX)
                        .padding(.vertical, theme.space.rowPaddingY)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Ends", action: "\(lengthDays) days")
            HStack(spacing: 8) {
                ForEach([3, 7, 14], id: \.self) { days in
                    lengthChip("\(days)d", on: !pickingDate && lengthDays == days) {
                        pickingDate = false
                        lengthDays = days
                        endDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                    }
                }
                lengthChip("Pick a date", on: pickingDate) {
                    pickingDate = true
                }
            }
            if pickingDate {
                DatePicker("End date", selection: $endDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(theme.accent)
                    .onChange(of: endDate) { _, new in
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: new).day ?? 1
                        lengthDays = max(1, days)
                    }
            }
            FFLabel(text: "Runs from tomorrow to \(endDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).", role: .caption, color: theme.muted)
        }
    }

    private var stakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "What’s on the line")
            HStack(spacing: 8) {
                lengthChip("Bragging rights", on: stake == .bragging) { stake = .bragging }
                lengthChip("$10", on: stake == .ten) { stake = .ten }
                lengthChip("Custom", on: stake == .custom) { stake = .custom }
            }
            if stake == .custom {
                HStack(spacing: 8) {
                    lengthChip("Money", on: customKind == .money) {
                        customKind = .money
                    }
                    lengthChip("Action", on: customKind == .action) {
                        customKind = .action
                        if settlement == .proportional { settlement = .winner }
                    }
                }
                if customKind == .money {
                    stepper("$\(customMoney)", minus: { customMoney = max(5, customMoney - 5) }, plus: { customMoney += 5 })
                } else {
                    TextField("what does the loser owe?", text: $forfeit)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.text)
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        }
                    HStack(spacing: 8) {
                        ForEach(["Loser buys dinner", "Loser posts the recap", "Loser runs extra 5K"], id: \.self) { chip in
                            FFChip(text: chip, suggestion: true) { forfeit = chip }
                        }
                    }
                }
            }
        }
    }

    private var settlementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "How the pot settles")
            FFGroup {
                let options: [SettlementKind] = {
                    if stake == .custom && customKind == .action {
                        return [.winner, .goal]
                    }
                    return SettlementKind.allCases
                }()
                ForEach(Array(options.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { FFHairline() }
                    radio(title: item.title, subtitle: item.blurb, on: settlement == item) {
                        settlement = item
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFSectionHeader(title: "Daily goal")
            stepper(goalLabel, minus: { dailyGoal = max(step, dailyGoal - step) }, plus: { dailyGoal += step })
        }
    }

    private var step: Double {
        switch metric {
        case .steps: return 500
        case .activeMinutes: return 5
        case .workouts: return 1
        }
    }

    private var goalLabel: String {
        switch metric {
        case .steps: return "\(Int(dailyGoal)) steps"
        case .activeMinutes: return "\(Int(dailyGoal)) min"
        case .workouts: return "\(Int(dailyGoal)) workouts"
        }
    }

    private var summary: some View {
        FFLabel(text: summaryText, role: .caption, color: theme.muted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
    }

    private var summaryText: String {
        let players = selected.count + 1
        let end = endDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let stakeText: String = {
            switch stake {
            case .bragging: return "bragging rights only"
            case .ten: return "$10 each — the winner takes all $\(10 * players)"
            case .custom:
                if customKind == .money {
                    return "$\(customMoney) each"
                }
                return forfeit.isEmpty ? "a custom forfeit" : forfeit
            }
        }()
        return "\(lengthDays)-day \(metric.eyebrow.lowercased()) fight with \(players) players, ending \(end). \(stakeText)."
    }

    private func lengthChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(.bodyStrong))
                .foregroundStyle(on ? theme.ink : theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    on ? theme.accent : theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                )
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
    }

    private func radio(title: String, subtitle: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    FFLabel(text: title, role: .bodyStrong)
                    FFLabel(text: subtitle, role: .caption, color: theme.muted)
                }
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(on ? theme.accent : theme.line, lineWidth: on ? 0 : 1)
                        .background(Circle().fill(on ? theme.accent : Color.clear))
                        .frame(width: 22, height: 22)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.ink)
                    }
                }
            }
            .padding(.horizontal, theme.space.rowPaddingX)
            .padding(.vertical, theme.space.rowPaddingY)
            .background(on ? theme.selectedOption() : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(on ? theme.accent : theme.line, lineWidth: on ? 0 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? theme.accent : Color.clear)
                )
                .frame(width: 22, height: 22)
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.ink)
            }
        }
    }

    private func stepper(_ label: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Button(action: minus) {
                Image(systemName: "minus")
                    .frame(width: 40, height: 40)
                    .background(theme.chip, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            FFLabel(text: label, role: .headline)
            Spacer()
            Button(action: plus) {
                Image(systemName: "plus")
                    .frame(width: 40, height: 40)
                    .background(theme.chip, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.text)
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }
}
