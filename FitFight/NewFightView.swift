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
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    FFLabel(text: "New fight", role: .display)
                    Text("Scores sync automatically. You settle up at the end.")
                        .font(.ff(13))
                        .foregroundStyle(theme.muted)
                }
                .padding(.bottom, theme.space.sectionGap)

                metricSection
                peopleSection.padding(.top, theme.space.sectionGap)
                lengthSection.padding(.top, theme.space.sectionGap)
                stakeSection.padding(.top, theme.space.sectionGap)
                if stake != .bragging {
                    settlementSection.padding(.top, theme.space.sectionGap)
                }
                if settlement == .goal && stake != .bragging {
                    goalSection.padding(.top, theme.space.sectionGap)
                }
                summary.padding(.top, theme.space.sectionGap)
                FFButton(title: "Start fight", icon: "arrow.right", iconTrailing: true) {
                    model.tab = .fights
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 2)
            .padding(.bottom, theme.space.xl)
        }
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Metric")
            FFPanel {
                ForEach(Array(MetricKind.allCases.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { FFHairline() }
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
            FFSectionHeader(title: "Who's in", action: "\(selected.count + 1) players")
            FFPanel {
                ForEach(Array(model.people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { FFHairline() }
                    let on = selected.contains(person.id)
                    Button {
                        if on { selected.remove(person.id) } else { selected.insert(person.id) }
                    } label: {
                        HStack(spacing: 12) {
                            FFAvatar(person, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name)
                                    .font(.ff(13, .semibold))
                                    .foregroundStyle(theme.text)
                                Text(person.handle)
                                    .font(.ff(11))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer(minLength: 8)
                            checkbox(on)
                        }
                        .padding(.horizontal, FFMetric.rowPaddingX)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "Ends", action: "\(lengthDays) days")
            HStack(spacing: 8) {
                ForEach([3, 7, 14], id: \.self) { days in
                    chip("\(days)d", on: !pickingDate && lengthDays == days) {
                        pickingDate = false
                        lengthDays = days
                        endDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                    }
                }
                chip("Pick a date", on: pickingDate) {
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
            Text("Runs from tomorrow to \(endLabel).")
                .font(.ff(13))
                .foregroundStyle(theme.muted)
        }
    }

    private var stakeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "What’s on the line")
            HStack(spacing: 8) {
                chip("Bragging rights", on: stake == .bragging) { stake = .bragging }
                chip("$10", on: stake == .ten) { stake = .ten }
                chip("Custom", on: stake == .custom) { stake = .custom }
            }
            if stake == .custom {
                HStack(spacing: 10) {
                    chip("Money", on: customKind == .money) {
                        customKind = .money
                    }
                    chip("Action", on: customKind == .action) {
                        customKind = .action
                        if settlement == .proportional { settlement = .winner }
                    }
                }
                if customKind == .money {
                    stepper("$\(customMoney)", minus: { customMoney = max(5, customMoney - 5) }, plus: { customMoney += 5 })
                } else {
                    TextField("what does the loser owe?", text: $forfeit)
                        .font(.ff(15))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        }
                    HStack(spacing: 10) {
                        ForEach(["Loser buys dinner", "Loser posts the recap"], id: \.self) { suggestion in
                            FFChip(text: suggestion, suggestion: true) { forfeit = suggestion }
                        }
                    }
                }
            }
        }
    }

    private var settlementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFSectionHeader(title: "How the pot settles")
            FFPanel {
                let options: [SettlementKind] = {
                    if stake == .custom && customKind == .action {
                        return [.winner, .goal]
                    }
                    return SettlementKind.allCases
                }()
                ForEach(Array(options.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { FFHairline() }
                    optionRow(title: item.title, subtitle: item.blurb, on: settlement == item, leadingRadio: true) {
                        settlement = item
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private var endLabel: String {
        endDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var summary: some View {
        (Text("\(lengthDays)-day \(metric.eyebrow.lowercased())")
            .font(.ff(14, .bold))
            .foregroundStyle(theme.text)
        + Text(" fight with \(selected.count + 1) players, ending \(endLabel). \(stakeSummary).")
            .font(.ff(14))
            .foregroundStyle(theme.muted))
            .lineSpacing(3)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
    }

    private var stakeSummary: String {
        let players = selected.count + 1
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

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ff(15, .semibold))
                .foregroundStyle(on ? theme.ink : theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    on ? theme.accent : theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                )
                .overlay {
                    if !on {
                        RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
    }

    private func optionRow(
        title: String,
        subtitle: String,
        on: Bool,
        leadingRadio: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                if leadingRadio { radio(on) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.ff(13, .semibold))
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .font(.ff(11))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !leadingRadio { radio(on) }
            }
            .padding(.horizontal, FFMetric.rowPaddingX)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? theme.selectedOption() : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func radio(_ on: Bool) -> some View {
        ZStack {
            Circle()
                .fill(on ? theme.accent : Color.clear)
                .frame(width: 26, height: 26)
                .overlay {
                    if !on {
                        Circle().strokeBorder(theme.line, lineWidth: 1.5)
                    }
                }
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func checkbox(_ on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? theme.accent : Color.clear)
                .frame(width: 26, height: 26)
                .overlay {
                    if !on {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1.5)
                    }
                }
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
            }
        }
        .frame(width: 26, height: 26)
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
            Text(label)
                .font(.ff(19, .bold))
                .foregroundStyle(theme.text)
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
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        }
    }
}
