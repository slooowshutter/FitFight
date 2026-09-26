import SwiftUI

enum FightDayChartKind: String, CaseIterable, Identifiable {
    case oval
    case bars
    case line
    case histogram
    case pace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oval: return String(appLocalized: "Oval")
        case .bars: return String(appLocalized: "Bars")
        case .line: return String(appLocalized: "Line")
        case .histogram: return String(appLocalized: "Histogram")
        case .pace: return String(appLocalized: "Pace")
        }
    }
}

struct FightDayChartsView: View {
    let days: [FightDay]
    let standings: [Standing]
    var initialKind: FightDayChartKind? = nil
    let formatScore: (Double) -> String

    @AppStorage("fight.dayChart.kind.v2") private var kindRaw = FightDayChartKind.oval.rawValue
    @State private var pickedKind: FightDayChartKind?
    @State private var selectedDay: Int?
    /// People flipped away from the default (top four plus you) by tapping the legend.
    @State private var toggledPeople: Set<String> = []
    @Environment(\.ffTheme) private var theme

    private var kind: FightDayChartKind {
        pickedKind ?? initialKind ?? FightDayChartKind(rawValue: kindRaw) ?? .oval
    }

    var body: some View {
        let full = FightDayChartModel(days: days, standings: standings, theme: theme)
        let shown = Set(full.series.prefix(4).map(\.id) + full.series.filter(\.person.isYou).map(\.id))
            .symmetricDifference(toggledPeople)
        var model = full
        if kind != .oval {
            model.series = full.series.filter { shown.contains($0.id) }
        }
        return VStack(alignment: .leading, spacing: 16) {
            FFFlow(spacing: 8) {
                ForEach(FightDayChartKind.allCases) { item in
                    badge(item)
                }
            }
            if !full.series.isEmpty {
                if kind == .oval {
                    Text("Confirmed Fight totals")
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                }
                if kind == .oval || full.dayCount > 0 {
                    chart(model)
                } else {
                    Text("Daily history isn't available yet. Confirmed totals are shown in Oval and standings.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                if [.line, .histogram, .pace].contains(kind), full.dayCount > 0 {
                    let day = min(selectedDay ?? full.dayCount - 1, full.dayCount - 1)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(full.labels[day])
                                .ffType(.label)
                                .foregroundStyle(theme.text)
                            Spacer()
                            Text(kind == .pace ? String(appLocalized: "Cumulative steps") : String(appLocalized: "Daily steps"))
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: selectedDay = min(day + 1, full.dayCount - 1)
                            case .decrement: selectedDay = max(day - 1, 0)
                            @unknown default: break
                            }
                        }
                        legend(full, shown: shown, day: day)
                    }
                    Text(kind == .line || kind == .pace
                         ? String(appLocalized: "Touch or slide to inspect a day. Tap a name to show or hide it.")
                         : String(appLocalized: "Tap a day to see its steps. Tap a name to show or hide it."))
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                    Text("Only synced steps are shown. Missing daily data is marked with a dash.")
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                } else if kind == .bars {
                    legend(full, shown: shown, day: nil)
                    Text(String(appLocalized: "Tap a name to show or hide it."))
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                } else {
                    legend(full, shown: nil, day: nil)
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
        case .oval:
            FightDayOvalChart(model: model, formatScore: formatScore)
        }
    }

    /// Oval passes `shown: nil` and lists everyone. The other charts make each name a toggle.
    private func legend(_ model: FightDayChartModel, shown: Set<String>?, day: Int?) -> some View {
        FFFlow(spacing: day == nil ? 10 : 12) {
            ForEach(model.series) { series in
                let on = shown?.contains(series.id) ?? true
                let name = series.person.isYou ? String(appLocalized: "You") : series.person.name
                let chip = HStack(spacing: 6) {
                    Circle()
                        .fill(on ? series.color : .clear)
                        .overlay { Circle().strokeBorder(series.color, lineWidth: 1.5) }
                        .frame(width: 8, height: 8)
                    Text(name)
                        .lineLimit(1)
                    if let day {
                        Text((kind == .pace ? series.cumulative[day] : series.daily[day])?
                            .formatted(.number.precision(.fractionLength(0))) ?? "-")
                            .fontWeight(.heavy)
                            .monospacedDigit()
                    }
                }
                .ffType(day == nil ? .micro : .caption)
                .foregroundStyle(day == nil ? theme.textSecondary : theme.text)
                .opacity(on ? 1 : 0.45)
                if shown == nil {
                    chip
                } else {
                    Button {
                        toggledPeople.formSymmetricDifference([series.id])
                    } label: {
                        chip.contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

private struct FightDayChartSeries: Identifiable {
    var person: Person
    var color: Color
    var daily: [Double?]
    var cumulative: [Double?]
    var total: Double

    var id: String { person.id }
}

private struct FightDayChartModel {
    var labels: [String]
    var series: [FightDayChartSeries]

    var dayCount: Int { labels.count }
    // Computed so the scale follows whoever is shown after legend toggles.
    var peakDaily: Double { max(series.flatMap(\.daily).compactMap { $0 }.max() ?? 0, 0) }
    var peakTotal: Double { max(series.map(\.total).max() ?? 0, 0) }

    init(days: [FightDay], standings: [Standing], theme: Theme) {
        labels = days.map(\.label)
        let ordered = standings.filter { !$0.invited && !$0.deferred }
        var otherIndex = 0
        series = ordered.map { standing in
            let person = standing.person
            let daily: [Double?] = days.map { day in
                guard let score = day.scores.first(where: { $0.person.id == person.id }), score.hasData else {
                    return nil
                }
                return score.value
            }
            var running: Double?
            let cumulative = daily.map { value -> Double? in
                if let value { running = (running ?? 0) + value }
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
                total: standing.score
            )
        }
        // A curve must belong to the same score revision. Missing history is a gap, not a wipe.
        for index in series.indices {
            let hasPoints = series[index].daily.contains { $0 != nil }
            if hasPoints && (series[index].cumulative.last ?? nil) != series[index].total {
                series[index].daily = Array(repeating: nil, count: series[index].daily.count)
                series[index].cumulative = Array(repeating: nil, count: series[index].cumulative.count)
            }
        }
        if !labels.isEmpty, series.allSatisfy({ $0.daily.allSatisfy { $0 == nil } }) {
            labels = []
            for index in series.indices {
                series[index].daily = []
                series[index].cumulative = []
            }
        }
        // Oval already plots these totals. Bars, line, histogram, and pace use the same scores
        // when no matching daily history is attached yet.
        if labels.isEmpty, !series.isEmpty {
            labels = [String(appLocalized: "So far")]
            for index in series.indices {
                series[index].daily = [series[index].total]
                series[index].cumulative = [series[index].total]
            }
        }
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

    func values(_ series: FightDayChartSeries, cumulative: Bool) -> [Double?] {
        cumulative ? series.cumulative : series.daily
    }

    func peak(cumulative: Bool) -> Double {
        cumulative ? peakTotal : peakDaily
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

private func fightDayPolyline(values: [Double?], peak: Double, in size: CGSize) -> [CGPoint?] {
    guard !values.isEmpty else { return [] }
    if values.count == 1 {
        guard let value = values[0] else { return [nil, nil] }
        let y = fightDayPlotY(value: value, peak: peak, height: size.height)
        return [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]
    }
    return values.enumerated().map { index, value in
        guard let value else { return nil }
        return CGPoint(
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
                            if series.person.isYou, points.allSatisfy({ $0 != nil }),
                               let first = points.first ?? nil, let last = points.last ?? nil {
                                Path { path in
                                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                                    for point in points.compactMap({ $0 }) { path.addLine(to: point) }
                                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                                    path.closeSubpath()
                                }
                                .fill(series.color.opacity(0.12))
                            }
                            Path { path in
                                var started = false
                                for point in points {
                                    guard let point else { started = false; continue }
                                    if started { path.addLine(to: point) } else { path.move(to: point) }
                                    started = true
                                }
                            }
                            .stroke(series.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            let day = min(selectedDay ?? model.dayCount - 1, model.dayCount - 1)
                            let x = model.dayCount == 1 ? geo.size.width / 2
                                : CGFloat(day) / CGFloat(model.dayCount - 1) * geo.size.width
                            if let value = values[day] {
                                Circle()
                                    .fill(series.color)
                                    .frame(width: 7, height: 7)
                                    .position(x: x, y: fightDayPlotY(value: value, peak: peak, height: geo.size.height))
                            }
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
                    .accessibilityLabel(String(appLocalized: "Steps chart"))
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
            Text(String(appLocalized: "chart.scale", defaultValue: "0-\(model.peakDaily.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))) steps"))
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
                                            : CGFloat((value ?? 0) / model.peakDaily) * 140
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
                        HStack(spacing: 8) {
                            CompanionAvatar(series.person, size: 16)
                            Text(series.person.isYou ? String(appLocalized: "You") : series.person.name)
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 52, alignment: .leading)
                            FFProgressBar(
                                value: model.peakDaily == 0 ? 0 : (value ?? 0) / model.peakDaily,
                                fill: series.color
                            )
                            Text(value.map(formatScore) ?? "-")
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 52, alignment: .trailing)
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
                        Text(leader.person.isYou ? String(appLocalized: "You") : leader.person.name)
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
