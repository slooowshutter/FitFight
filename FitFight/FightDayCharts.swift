import SwiftUI

enum FightDayChartKind: String, CaseIterable, Identifiable {
    case line
    case histogram
    case bars
    case pace
    case heat
    case oval
    case rings
    case stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return String(localized: "Line")
        case .histogram: return String(localized: "Histogram")
        case .bars: return String(localized: "Bars")
        case .pace: return String(localized: "Pace")
        case .heat: return String(localized: "Heat")
        case .oval: return String(localized: "Oval")
        case .rings: return String(localized: "Rings")
        case .stack: return String(localized: "Stack")
        }
    }
}

struct FightDayChartsView: View {
    let days: [FightDay]
    var initialKind: FightDayChartKind? = nil
    let formatScore: (Double) -> String

    @AppStorage("fight.dayChart.kind") private var kindRaw = FightDayChartKind.line.rawValue
    @State private var pickedKind: FightDayChartKind?
    @State private var selectedDay: Int?
    @Environment(\.ffTheme) private var theme

    private var kind: FightDayChartKind {
        pickedKind ?? initialKind ?? FightDayChartKind(rawValue: kindRaw) ?? .line
    }

    var body: some View {
        let model = FightDayChartModel(days: days, theme: theme)
        VStack(alignment: .leading, spacing: 16) {
            FFFlow(spacing: 8) {
                ForEach(FightDayChartKind.allCases) { item in
                    badge(item)
                }
            }
            if !model.series.isEmpty {
                if kind == .rings || kind == .oval {
                    Text("Totals across the days shown")
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                }
                chart(model)
                if [.line, .histogram, .pace, .heat, .stack].contains(kind), model.dayCount > 0 {
                    let day = min(selectedDay ?? model.dayCount - 1, model.dayCount - 1)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(model.labels[day])
                                .ffType(.label)
                                .foregroundStyle(theme.text)
                            Spacer()
                            Text(kind == .pace ? String(localized: "Cumulative steps") : String(localized: "Daily steps"))
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                        }
                        FFFlow(spacing: 12) {
                            ForEach(model.series) { series in
                                HStack(spacing: 6) {
                                    Circle().fill(series.color).frame(width: 7, height: 7)
                                    Text(series.person.isYou ? String(localized: "You") : series.person.name)
                                    Text((kind == .pace ? series.cumulative[day] : series.daily[day]).formatted(.number.precision(.fractionLength(0))))
                                        .fontWeight(.heavy)
                                        .monospacedDigit()
                                }
                                .ffType(.caption)
                                .foregroundStyle(theme.text)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: selectedDay = min(day + 1, model.dayCount - 1)
                        case .decrement: selectedDay = max(day - 1, 0)
                        @unknown default: break
                        }
                    }
                    Text(kind == .line || kind == .pace
                         ? String(localized: "Touch or slide to inspect a day.")
                         : String(localized: "Tap a day to see its steps."))
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                } else if showsLegend {
                    legend(model)
                }
            }
        }
    }

    private func badge(_ item: FightDayChartKind) -> some View {
        let selected = item == kind
        let shape = RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
        return Button {
            pickedKind = item
            kindRaw = item.rawValue
        } label: {
            Text(item.title)
                .ffType(.micro)
                .fontWeight(.heavy)
                .foregroundStyle(selected ? theme.mossOn : theme.chipInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(selected ? theme.mossFill : theme.chip, in: shape)
                .overlay {
                    shape.strokeBorder(
                        selected ? theme.chipEdgeOn : theme.chipEdge,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func chart(_ model: FightDayChartModel) -> some View {
        switch kind {
        case .line:
            FightDayLineChart(model: model, cumulative: false, selectedDay: $selectedDay)
        case .histogram:
            FightDayHistogramChart(model: model, selectedDay: $selectedDay)
        case .bars:
            FightDayBarsChart(model: model, formatScore: formatScore)
        case .pace:
            FightDayLineChart(model: model, cumulative: true, selectedDay: $selectedDay)
        case .heat:
            FightDayHeatChart(model: model, selectedDay: $selectedDay)
        case .oval:
            FightDayOvalChart(model: model, formatScore: formatScore)
        case .rings:
            FightDayRingsChart(model: model)
        case .stack:
            FightDayStackChart(model: model, selectedDay: $selectedDay)
        }
    }

    private var showsLegend: Bool {
        switch kind {
        case .bars, .heat, .rings:
            return false
        case .line, .histogram, .pace, .oval, .stack:
            return true
        }
    }

    private func legend(_ model: FightDayChartModel) -> some View {
        FFFlow(spacing: 10) {
            ForEach(model.series) { series in
                HStack(spacing: 6) {
                    Circle()
                        .fill(series.color)
                        .frame(width: 8, height: 8)
                    Text(series.person.isYou ? String(localized: "You") : series.person.name)
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct FightDayChartSeries: Identifiable {
    var person: Person
    var color: Color
    var daily: [Double]
    var cumulative: [Double]
    var total: Double

    var id: String { person.id }
}

private struct FightDayChartModel {
    var labels: [String]
    var series: [FightDayChartSeries]
    var peakDaily: Double
    var peakTotal: Double

    var peakCumulative: Double { peakTotal }
    var dayCount: Int { labels.count }

    init(days: [FightDay], theme: Theme) {
        labels = days.map(\.label)
        var totals: [String: Double] = [:]
        var people: [String: Person] = [:]
        for day in days {
            for score in day.scores {
                people[score.person.id] = score.person
                totals[score.person.id, default: 0] += score.value
            }
        }
        let ordered = people.values.sorted { lhs, rhs in
            let left = totals[lhs.id] ?? 0
            let right = totals[rhs.id] ?? 0
            if left != right { return left > right }
            return lhs.name < rhs.name
        }
        var otherIndex = 0
        series = ordered.map { person in
            let daily = days.map { day in
                day.scores.first { $0.person.id == person.id }?.value ?? 0
            }
            var running = 0.0
            let cumulative = daily.map { value -> Double in
                running += value
                return running
            }
            let color: Color
            if person.isYou {
                color = theme.mossFill
            } else {
                color = FightDayChartModel.otherColor(otherIndex, theme: theme)
                otherIndex += 1
            }
            return FightDayChartSeries(
                person: person,
                color: color,
                daily: daily,
                cumulative: cumulative,
                total: totals[person.id] ?? 0
            )
        }
        peakDaily = max(series.flatMap(\.daily).max() ?? 0, 0)
        peakTotal = max(series.map(\.total).max() ?? 0, 0)
    }

    private static func otherColor(_ index: Int, theme: Theme) -> Color {
        switch index {
        case 0: return theme.gold
        case 1: return theme.emberFill
        case 2: return theme.mossEdge
        case 3: return theme.emberText
        default: return theme.textSecondary
        }
    }

    func values(_ series: FightDayChartSeries, cumulative: Bool) -> [Double] {
        cumulative ? series.cumulative : series.daily
    }

    func peak(cumulative: Bool) -> Double {
        cumulative ? peakCumulative : peakDaily
    }
}

private func fightDayTickIndices(count: Int) -> [Int] {
    guard count > 0 else { return [] }
    if count <= 7 { return Array(0..<count) }
    var ticks = Set([0, count / 2, count - 1])
    if count >= 14 {
        ticks.insert(count / 4)
        ticks.insert((count * 3) / 4)
    }
    return ticks.sorted()
}

private func fightDayPlotY(value: Double, peak: Double, height: CGFloat) -> CGFloat {
    guard peak > 0 else { return height }
    return height - CGFloat(min(max(value / peak, 0), 1)) * height
}

private func fightDayPolyline(values: [Double], peak: Double, in size: CGSize) -> [CGPoint] {
    guard !values.isEmpty else { return [] }
    if values.count == 1 {
        let y = fightDayPlotY(value: values[0], peak: peak, height: size.height)
        return [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]
    }
    return values.enumerated().map { index, value in
        CGPoint(
            x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
            y: fightDayPlotY(value: value, peak: peak, height: size.height)
        )
    }
}

private struct FightDayLineChart: View {
    let model: FightDayChartModel
    var cumulative: Bool
    @Binding var selectedDay: Int?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let peak = model.peak(cumulative: cumulative)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .trailing) {
                    Text(peak.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                    Spacer()
                    Text((peak / 2).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                    Spacer()
                    Text("0")
                }
                .ffType(.micro)
                .foregroundStyle(theme.textFaint)
                .frame(width: 34, height: 156)
                GeometryReader { geo in
                    ZStack {
                        ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                            Path { path in
                                let y = geo.size.height * fraction
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                        if let selectedDay, selectedDay < model.dayCount {
                            let x = model.dayCount == 1 ? geo.size.width / 2
                                : CGFloat(selectedDay) / CGFloat(model.dayCount - 1) * geo.size.width
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geo.size.height))
                            }
                            .stroke(theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        ForEach(model.series) { series in
                            let values = model.values(series, cumulative: cumulative)
                            let points = fightDayPolyline(values: values, peak: peak, in: geo.size)
                            if series.person.isYou, let first = points.first, let last = points.last {
                                Path { path in
                                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                                    for point in points { path.addLine(to: point) }
                                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                                    path.closeSubpath()
                                }
                                .fill(series.color.opacity(0.12))
                            }
                            Path { path in
                                guard let first = points.first else { return }
                                path.move(to: first)
                                for point in points.dropFirst() { path.addLine(to: point) }
                            }
                            .stroke(series.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            let day = min(selectedDay ?? model.dayCount - 1, model.dayCount - 1)
                            let x = model.dayCount == 1 ? geo.size.width / 2
                                : CGFloat(day) / CGFloat(model.dayCount - 1) * geo.size.width
                            Circle()
                                .fill(series.color)
                                .frame(width: 7, height: 7)
                                .position(x: x, y: fightDayPlotY(value: values[day], peak: peak, height: geo.size.height))
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                            let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                            selectedDay = Int((fraction * CGFloat(model.dayCount - 1)).rounded())
                        }
                    )
                    .accessibilityLabel(String(localized: "Steps chart"))
                }
                .frame(height: 156)
            }
            FightDayAxisLabels(labels: model.labels)
                .padding(.leading, 42)
        }
    }
}

private struct FightDayHistogramChart: View {
    let model: FightDayChartModel
    @Binding var selectedDay: Int?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "chart.scale", defaultValue: "0–\(model.peakDaily.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))) steps"))
                .ffType(.micro)
                .foregroundStyle(theme.textSecondary)
            GeometryReader { geo in
                let people = max(model.series.count, 1)
                let minGroup = CGFloat(people) * 9 + 10
                let gap: CGFloat = 8
                let natural = CGFloat(model.dayCount) * minGroup + CGFloat(max(model.dayCount - 1, 0)) * gap
                let contentWidth = max(geo.size.width, natural)
                let groupWidth = (contentWidth - CGFloat(max(model.dayCount - 1, 0)) * gap) / CGFloat(max(model.dayCount, 1))
                let barWidth = max((groupWidth - CGFloat(people - 1) * 2) / CGFloat(people), 3)
                FightDayHorizontalScroll(showsIndicators: contentWidth > geo.size.width + 1) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            VStack(spacing: 8) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    ForEach(model.series) { series in
                                        let value = series.daily[day]
                                        let height = model.peakDaily == 0
                                            ? 0
                                            : CGFloat(value / model.peakDaily) * 140
                                        RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                                            .fill(series.color)
                                            .frame(width: barWidth, height: height)
                                    }
                                }
                                .frame(height: 140, alignment: .bottom)
                                Text(model.labels[day])
                                    .ffType(.micro)
                                    .foregroundStyle(selectedDay == day ? theme.mossText : theme.textFaint)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(width: groupWidth)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedDay = day }
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
            }
            .frame(height: 168)
        }
    }
}

private struct FightDayBarsChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.labels.enumerated()), id: \.offset) { day, label in
                if day > 0 { Color.clear.frame(height: 20) }
                FFEyebrow(label)
                    .padding(.bottom, 12)
                VStack(spacing: 10) {
                    ForEach(model.series) { series in
                        let value = series.daily[day]
                        HStack(spacing: 10) {
                            Text(series.person.isYou ? String(localized: "You") : series.person.name)
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 56, alignment: .leading)
                            FFProgressBar(
                                value: model.peakDaily == 0 ? 0 : value / model.peakDaily,
                                fill: series.color
                            )
                            Text(formatScore(value))
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct FightDayHeatChart: View {
    let model: FightDayChartModel
    @Binding var selectedDay: Int?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let cell: CGFloat = 22
        FightDayHorizontalScroll(showsIndicators: model.dayCount > 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.series) { series in
                    HStack(spacing: 4) {
                        CompanionAvatar(series.person, size: 22)
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            let value = series.daily[day]
                            let tone = model.peakDaily == 0 ? 0 : value / model.peakDaily
                            RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                                .fill(value == 0 ? theme.track : series.color.opacity(0.18 + 0.82 * tone))
                                .frame(width: cell, height: cell)
                                .overlay {
                                    RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                                        .strokeBorder(selectedDay == day ? theme.text : .clear, lineWidth: 1.5)
                                }
                                .onTapGesture { selectedDay = day }
                                .accessibilityLabel(Text(verbatim: "\(series.person.name), \(model.labels[day]), \(value.formatted(.number.precision(.fractionLength(0))))"))
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
        }
    }
}

private struct FightDayOvalChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let rect = geo.frame(in: .local).insetBy(dx: 22, dy: 22)
            let corner = theme.radius.shell
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(theme.track, lineWidth: 14)
                    .padding(22)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
                    .padding(22)
                Path { path in
                    let start = pointOnCircuit(progress: 0, in: rect, corner: corner)
                    path.move(to: CGPoint(x: start.x, y: start.y - 12))
                    path.addLine(to: CGPoint(x: start.x, y: start.y + 12))
                }
                .stroke(theme.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                VStack(spacing: 4) {
                    if let leader = model.series.first {
                        Text(leader.person.isYou ? String(localized: "You") : leader.person.name)
                            .ffType(.label)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Text(formatScore(leader.total))
                            .font(.ff(22, 800))
                            .foregroundStyle(leader.color)
                    }
                }
                ForEach(model.series) { series in
                    let progress = model.peakTotal == 0
                        ? 0.02
                        : 0.04 + 0.90 * (series.total / model.peakTotal)
                    let point = pointOnCircuit(progress: progress, in: rect, corner: corner)
                    CompanionAvatar(series.person, size: 30)
                        .overlay { Circle().strokeBorder(series.color, lineWidth: 2) }
                        .position(point)
                        .zIndex(series.total)
                }
            }
        }
        .frame(height: 220)
    }
}

private struct FightDayRingsChart: View {
    let model: FightDayChartModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFFlow(spacing: 16) {
            ForEach(model.series) { series in
                VStack(spacing: 8) {
                    FFRing(
                        value: model.peakTotal == 0 ? 0 : series.total / model.peakTotal,
                        size: 76,
                        lineWidth: 8,
                        fill: series.color
                    ) {
                        CompanionAvatar(series.person, size: 32)
                    }
                    Text(series.person.isYou ? String(localized: "You") : series.person.name)
                        .ffType(.micro)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(series.total.formatted(.number.precision(.fractionLength(0))))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(minWidth: 88)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct FightDayStackChart: View {
    let model: FightDayChartModel
    @Binding var selectedDay: Int?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let peaks = (0..<model.dayCount).map { day in
            model.series.reduce(0) { $0 + $1.daily[day] }
        }
        let peak = max(peaks.max() ?? 0, 0.0001)
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "chart.group-scale", defaultValue: "0–\((peaks.max() ?? 0).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))) combined steps"))
                .ffType(.micro)
                .foregroundStyle(theme.textSecondary)
            GeometryReader { geo in
                let minGroup: CGFloat = 18
                let gap: CGFloat = 6
                let natural = CGFloat(model.dayCount) * minGroup + CGFloat(max(model.dayCount - 1, 0)) * gap
                let contentWidth = max(geo.size.width, natural)
                let groupWidth = (contentWidth - CGFloat(max(model.dayCount - 1, 0)) * gap) / CGFloat(max(model.dayCount, 1))
                FightDayHorizontalScroll(showsIndicators: contentWidth > geo.size.width + 1) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            VStack(spacing: 8) {
                                VStack(spacing: 0) {
                                    ForEach(Array(model.series.reversed())) { series in
                                        let value = series.daily[day]
                                        if value > 0 {
                                            Rectangle()
                                                .fill(series.color)
                                                .frame(height: CGFloat(value / peak) * 140)
                                        }
                                    }
                                }
                                .frame(width: groupWidth)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous))
                                .frame(height: 140, alignment: .bottom)
                                Text(model.labels[day])
                                    .ffType(.micro)
                                    .foregroundStyle(selectedDay == day ? theme.mossText : theme.textFaint)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(width: groupWidth)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedDay = day }
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
            }
            .frame(height: 168)
        }
    }
}

private struct FightDayHorizontalScroll<Content: View>: View {
    var showsIndicators: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        if staticRender {
            content()
        } else {
            ScrollView(.horizontal, showsIndicators: showsIndicators) { content() }
        }
    }
}

private struct FightDayAxisLabels: View {
    let labels: [String]
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let ticks = fightDayTickIndices(count: labels.count)
        GeometryReader { geo in
            let width = geo.size.width / CGFloat(max(ticks.count, 1))
            ForEach(ticks, id: \.self) { index in
                let first = index == 0
                let last = index == labels.count - 1
                Text(labels[index])
                    .ffType(.micro)
                    .foregroundStyle(theme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: width, alignment: first ? .leading : last ? .trailing : .center)
                    .position(
                        x: labels.count == 1 ? geo.size.width / 2
                            : first ? width / 2
                            : last ? geo.size.width - width / 2
                            : geo.size.width * CGFloat(index) / CGFloat(labels.count - 1),
                        y: 8
                    )
            }
        }
        .frame(height: 16)
    }
}

private func pointOnCircuit(progress: CGFloat, in rect: CGRect, corner: CGFloat) -> CGPoint {
    let radius = min(corner, rect.width / 2, rect.height / 2)
    let left = rect.minX + radius
    let right = rect.maxX - radius
    let top = rect.minY + radius
    let bottom = rect.maxY - radius
    let horiz = max(right - left, 0)
    let vert = max(bottom - top, 0)
    let arc = .pi / 2 * radius
    let half = horiz / 2
    let lengths = [half, arc, vert, arc, horiz, arc, vert, arc, half]
    let total = max(lengths.reduce(0, +), 0.0001)
    var distance = min(max(progress, 0), 0.999) * total

    func take(_ length: CGFloat, _ point: (CGFloat) -> CGPoint) -> CGPoint? {
        if distance <= length {
            return point(length == 0 ? 0 : distance / length)
        }
        distance -= length
        return nil
    }

    if let point = take(half, { t in CGPoint(x: rect.midX + half * t, y: rect.maxY) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = .pi / 2 * (1 - t)
        return CGPoint(x: right + cos(angle) * radius, y: bottom + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(vert, { t in CGPoint(x: rect.maxX, y: bottom - vert * t) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi / 2 * t
        return CGPoint(x: right + cos(angle) * radius, y: top + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(horiz, { t in CGPoint(x: right - horiz * t, y: rect.minY) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi / 2 - .pi / 2 * t
        return CGPoint(x: left + cos(angle) * radius, y: top + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(vert, { t in CGPoint(x: rect.minX, y: top + vert * t) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi - .pi / 2 * t
        return CGPoint(x: left + cos(angle) * radius, y: bottom + sin(angle) * radius)
    }) {
        return point
    }
    return CGPoint(x: left + half * min(max(distance / max(half, 0.0001), 0), 1), y: rect.maxY)
}
