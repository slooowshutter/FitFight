import Charts
import SwiftUI

/// Marc's analytics inside Profile > Dashboard. The server defines every section, card and
/// chart, so new ones need no app update. The copy is English only, so it uses verbatim text.
struct AdminDashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    /// Starts on Production and remembers the switch. A new key, so a Staging choice saved by
    /// an earlier build doesn't stick.
    @AppStorage("fitfight.admin-dashboard.environment") private var server = Server.production
    @State private var sectionID = "overview"
    /// The sections listed by the last payload. Empty until the first one loads.
    @State private var sections: [FitFightAdminDashboard.Section] = []
    @State private var timeframe = Timeframe.week
    @State private var customDays = 14
    @State private var dashboard: FitFightAdminDashboard?
    @State private var loading = false
    @State private var failure: String?
    /// Cards tapped to show the exact value instead of the rounded-down one.
    @State private var exactCards: Set<String> = []
    /// Refresh and Retry bump this to rerun the load task.
    @State private var reloads = 0

    enum Server: String, CaseIterable {
        case production, staging

        var title: String { self == .production ? "Production" : "Staging" }
        /// Both read through Vercel's preview branch address, which always serves the newest
        /// `preview` backend: staging from its own database, production through its read-only
        /// connection, so new charts reach production data without `main`. staging.fitfight.app
        /// is pinned to a hand-picked deployment in Vercel.
        var baseURL: URL? {
            URL(string: "https://fit-fight-git-preview-blendai.vercel.app")
        }
    }

    enum Timeframe: CaseIterable {
        case day, week, month, quarter, year, custom
    }

    private var days: Int {
        switch timeframe {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .custom: return customDays
        }
    }

    /// Only the payload for the selected environment, section and period, so an earlier
    /// section's cards never sit under a newly selected chip while its data loads.
    private var shown: FitFightAdminDashboard? {
        guard let dashboard, dashboard.section == sectionID, dashboard.days == days,
              dashboard.environment == server.rawValue else { return nil }
        return dashboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            controls
            statusLine
            if let failure {
                FFNotice(text: failure, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: "Retry", kind: .secondary) { reloads += 1 }
            }
            if let dashboard = shown {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                    ],
                    spacing: 12
                ) {
                    ForEach(dashboard.cards) { card in
                        cardTile(card)
                    }
                }
                ForEach(dashboard.charts) { chart in
                    FFCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(verbatim: chart.title)
                                .ffType(.heading)
                                .foregroundStyle(theme.text)
                            AdminChart(chart: chart)
                            if let note = chart.note {
                                Text(verbatim: note)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            } else if loading && failure == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .task(id: "\(server)-\(sectionID)-\(days)-\(reloads)") {
            await load()
        }
    }

    @ViewBuilder
    private var controls: some View {
        FFSegmented(items: Server.allCases, selection: $server) { $0.title }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections, id: \.id) { item in
                    let on = item.id == sectionID
                    Button {
                        sectionID = item.id
                    } label: {
                        Text(verbatim: item.title)
                            .ffType(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(on ? theme.mossOn : theme.chipInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(on ? theme.mossFill : theme.chip, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(on ? theme.chipEdgeOn : theme.chipEdge, lineWidth: 1)
                            }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        FFSegmented(items: Timeframe.allCases, selection: $timeframe) { item in
            switch item {
            case .day: "1D"
            case .week: "7D"
            case .month: "30D"
            case .quarter: "90D"
            case .year: "1Y"
            case .custom: "Custom"
            }
        }
        if timeframe == .custom {
            Stepper(value: $customDays, in: 1...3650) {
                Text(verbatim: customDays == 1 ? "Last 1 day" : "Last \(customDays) days")
                    .ffType(.label)
                    .foregroundStyle(theme.text)
            }
        }
    }

    private var statusLine: some View {
        let range = days == 1 ? "last day vs the day before" : "last \(days) days vs the \(days) before"
        let time = shown.map { " · " + $0.generatedAt.formatted(date: .omitted, time: .shortened) } ?? ""
        return HStack(spacing: 8) {
            Text(verbatim: "\(server.title) · \(range)\(time)")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if loading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                reloads += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(theme.control, in: Circle())
            }
            .buttonStyle(FFHapticPlainStyle())
            .accessibilityLabel(Text(verbatim: "Refresh"))
        }
    }

    private func cardTile(_ card: FitFightAdminDashboard.Card) -> some View {
        let exact = exactCards.contains(card.id)
        let change = changeLine(card)
        return Button {
            exactCards.formSymmetricDifference([card.id])
        } label: {
            FFCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: card.title)
                        .ffType(.eyebrow)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                    Text(verbatim: card.value.map { adminValue($0, unit: card.unit, exact: exact) } ?? "-")
                        .font(.ff(28, 800))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let change {
                        Text(verbatim: change.text)
                            .ffType(.caption)
                            .foregroundStyle(change.color)
                    }
                    if let note = card.note {
                        Text(verbatim: note)
                            .ffType(.micro)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(FFHapticPlainStyle())
    }

    /// "+12% (+3)", or "+2.5 pts" on a percent card. Moss is good news and ember bad, by the
    /// card's direction; a neutral card or no change stays secondary.
    private func changeLine(_ card: FitFightAdminDashboard.Card) -> (text: String, color: Color)? {
        guard let value = card.value, let previous = card.previous else { return nil }
        let delta = value - previous
        let deltaSign = delta > 0 ? "+" : ""
        let text: String
        if card.unit == "percent" {
            text = "\(deltaSign)\(adminTenths(delta)) pts"
        } else if previous == 0 {
            guard value > 0 else { return (text: "No change", color: theme.textSecondary) }
            text = "New"
        } else {
            let percent = delta / abs(previous) * 100
            let percentSign = percent > 0 ? "+" : ""
            text = "\(percentSign)\(adminTenths(percent))% (\(deltaSign)\(adminValue(delta, unit: card.unit)))"
        }
        guard let better = card.higherIsBetter, delta != 0 else {
            return (text: text, color: theme.textSecondary)
        }
        return (text: text, color: (delta > 0) == better ? theme.mossText : theme.emberText)
    }

    private func load() async {
        let target = server
        let section = sectionID
        let window = days
        loading = true
        do {
            let token = try await session.freshAccessToken()
            let project = SupabaseConfig.projectURL.host?.components(separatedBy: ".").first ?? ""
            let result = try await FitFightAPI(baseURL: target.baseURL).adminDashboard(
                section: section,
                days: window,
                environment: target.rawValue,
                authProject: project,
                accessToken: token
            )
            try Task.checkCancellation()
            dashboard = result
            if let listed = result.sections {
                sections = listed
            }
            failure = nil
        } catch {
            // A newer selection cancelled this load. Its own run owns the spinner and the result.
            guard !Task.isCancelled else { return }
            dashboard = nil
            if case FitFightAPIError.http(let status, _, _) = error, status == 403 {
                failure = "This account isn't the FitFight admin on \(target.title)."
            } else {
                failure = error.localizedDescription
            }
        }
        loading = false
    }
}

/// One server chart. Unknown kinds draw as bars, unknown units read as counts.
private struct AdminChart: View {
    let chart: FitFightAdminDashboard.Chart
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let colors = seriesColors
        let marks = plottedMarks(colors: colors)
        let hasData = chart.kind == "heatmap" ? !chart.cells.isEmpty : !marks.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            if !hasData {
                Text(verbatim: "No data yet")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            } else if chart.kind == "heatmap" {
                heatmap
            } else if chart.kind == "line" {
                if chart.xKind == "date" {
                    dateLine(marks, unit: dateUnit)
                } else {
                    labelLine(marks)
                }
            } else if chart.xKind == "date" {
                columns(marks, unit: dateUnit)
            } else {
                rows(marks)
            }
            if hasData, chart.kind != "heatmap", chart.series.count > 1 {
                FFFlow(spacing: 12) {
                    ForEach(chart.series.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colors[index])
                                .frame(width: 8, height: 8)
                            Text(verbatim: chart.series[index].name)
                        }
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    /// Current periods take gold, then moss, then ember. Previous periods and any further
    /// series use the secondary text color.
    private var seriesColors: [Color] {
        let palette = [theme.gold, theme.mossFill, theme.emberFill]
        var colors: [Color] = []
        var current = 0
        for series in chart.series {
            if series.previous {
                colors.append(theme.textSecondary)
            } else {
                colors.append(current < palette.count ? palette[current] : theme.textSecondary)
                current += 1
            }
        }
        return colors
    }

    /// Every point flattened with its series style, so each chart builder holds one mark.
    /// A date chart skips a point whose day doesn't parse.
    private func plottedMarks(colors: [Color]) -> [AdminMark] {
        var marks: [AdminMark] = []
        for (index, series) in chart.series.enumerated() {
            for point in series.points {
                let day = chart.xKind == "date" ? adminDay(point.x) : nil
                if chart.xKind == "date" && day == nil { continue }
                marks.append(AdminMark(
                    id: marks.count,
                    series: series.name,
                    color: colors[index],
                    dashed: series.previous,
                    label: point.x,
                    day: day,
                    value: point.y
                ))
            }
        }
        return marks
    }

    /// Long periods arrive as weekly or monthly points; each bar then spans its whole bucket.
    private var dateUnit: Calendar.Component {
        let days = Set(chart.series.filter { !$0.previous }.flatMap { $0.points.compactMap { adminDay($0.x) } }).sorted()
        let gap = zip(days, days.dropFirst()).map { $1.timeIntervalSince($0) }.min() ?? 86_400
        return gap >= 27 * 86_400 ? .month : gap >= 6 * 86_400 ? .weekOfYear : .day
    }

    private func dateLine(_ marks: [AdminMark], unit: Calendar.Component) -> some View {
        Chart {
            ForEach(marks) { mark in
                LineMark(
                    x: .value("Day", mark.day ?? Date.distantPast, unit: unit),
                    y: .value("Value", mark.value),
                    series: .value("Series", mark.series)
                )
                .foregroundStyle(mark.color)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: mark.dashed ? [4, 3] : []))
            }
        }
        .chartXAxis { dayAxis }
        .chartYAxis { valueAxis }
        .frame(height: 160)
    }

    private func labelLine(_ marks: [AdminMark]) -> some View {
        Chart {
            ForEach(marks) { mark in
                LineMark(
                    x: .value("Label", mark.label),
                    y: .value("Value", mark.value),
                    series: .value("Series", mark.series)
                )
                .foregroundStyle(mark.color)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: mark.dashed ? [4, 3] : []))
            }
        }
        .chartXAxis { labelAxis(leading: false) }
        .chartYAxis { valueAxis }
        .frame(height: 160)
    }

    /// Vertical bars per day, several series side by side.
    private func columns(_ marks: [AdminMark], unit: Calendar.Component) -> some View {
        Chart {
            ForEach(marks) { mark in
                BarMark(
                    x: .value("Day", mark.day ?? Date.distantPast, unit: unit),
                    y: .value("Value", mark.value)
                )
                .foregroundStyle(mark.color)
                .position(by: .value("Series", mark.series))
            }
        }
        .chartXAxis { dayAxis }
        .chartYAxis { valueAxis }
        .frame(height: 160)
    }

    /// Horizontal bars so long labels read in full, with each value at the bar's end.
    private func rows(_ marks: [AdminMark]) -> some View {
        let low = min(marks.map(\.value).min() ?? 0, 0)
        // Headroom past the longest bar for its value text.
        let high = max((marks.map(\.value).max() ?? 0) * 1.25, 1)
        let labels = Set(marks.map(\.label)).count
        return Chart {
            ForEach(marks) { mark in
                BarMark(
                    x: .value("Value", mark.value),
                    y: .value("Label", mark.label)
                )
                .foregroundStyle(mark.color)
                .position(by: .value("Series", mark.series))
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(verbatim: adminValue(mark.value, unit: chart.unit))
                        .font(.ff(10, 700))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .chartXScale(domain: low...high)
        .chartXAxis(.hidden)
        .chartYAxis { labelAxis(leading: true) }
        .frame(height: CGFloat(labels) * 26)
    }

    private var heatmap: some View {
        let peak = chart.cells.map(\.value).max() ?? 0
        let shades = chart.cells.map { peak > 0 ? 0.08 + 0.92 * max($0.value / peak, 0) : 0.08 }
        let rowCount = Set(chart.cells.map(\.y)).count
        return Chart {
            ForEach(chart.cells.indices, id: \.self) { index in
                RectangleMark(
                    x: .value("Column", chart.cells[index].x),
                    y: .value("Row", chart.cells[index].y)
                )
                .foregroundStyle(theme.gold.opacity(shades[index]))
            }
        }
        .chartXAxis { labelAxis(leading: false) }
        .chartYAxis { labelAxis(leading: true) }
        .frame(height: CGFloat(rowCount) * 24 + 24)
    }

    private var valueAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                Text(verbatim: adminValue(value.as(Double.self) ?? 0, unit: chart.unit))
                    .font(.ff(10, 700))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
                Text(verbatim: value.as(Date.self).map { adminDayLabel.string(from: $0) } ?? "")
                    .font(.ff(10, 700))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func labelAxis(leading: Bool) -> some AxisContent {
        AxisMarks(position: leading ? .leading : .automatic) { value in
            AxisValueLabel {
                Text(verbatim: value.as(String.self) ?? "")
                    .font(.ff(10, 700))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

/// One plotted value with its series style.
private struct AdminMark: Identifiable {
    let id: Int
    let series: String
    let color: Color
    let dashed: Bool
    let label: String
    /// Set only on date charts.
    let day: Date?
    let value: Double
}

/// "2026-09-22" as the start of that day in the phone's calendar. Swift Charts bins
/// `unit: .day` with that same calendar; UTC midnight would slide every bar onto the
/// previous day west of Greenwich.
private func adminDay(_ raw: String) -> Date? {
    let parts = raw.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

/// "22 Sep" whatever the phone's language.
private let adminDayLabel: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM"
    return formatter
}()

/// Marc's rule: round down, never up. 999,999 is "999K" and 1,099,999 is "1M".
private func adminNumber(_ value: Double) -> String {
    let magnitude = abs(value)
    let tier = [(1e15, "Q"), (1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")].first { magnitude >= $0.0 }
    let scaled = magnitude / (tier?.0 ?? 1)
    let digits: String
    if tier != nil, scaled < 100 {
        // The epsilon stops floating error from truncating 1.1M to 1M.
        let tenths = Int((scaled * 10 + 1e-9).rounded(.down))
        digits = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    } else {
        digits = String(format: "%.0f", (scaled + 1e-9).rounded(.down))
    }
    let sign = value < 0 && digits != "0" ? "-" : ""
    return sign + digits + (tier?.1 ?? "")
}

/// Truncated toward zero with one decimal under 10 ("4.5", "4"), a smart number from 10 up.
private func adminTenths(_ value: Double) -> String {
    guard abs(value) < 10 else { return adminNumber(value) }
    let tenths = Int((abs(value) * 10 + 1e-9).rounded(.down))
    let digits = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    return value < 0 && tenths != 0 ? "-" + digits : digits
}

/// A value in its unit: "42%", "4.2%", "3 h", "1.5K". `exact` shows grouped digits instead.
private func adminValue(_ value: Double, unit: String, exact: Bool = false) -> String {
    let suffix: String
    switch unit {
    case "percent": suffix = "%"
    case "days": suffix = " d"
    case "hours": suffix = " h"
    case "minutes": suffix = " min"
    case "seconds": suffix = " s"
    default: suffix = ""
    }
    if exact {
        return value.formatted(.number.precision(.fractionLength(0...1))) + suffix
    }
    return (unit == "percent" ? adminTenths(value) : adminNumber(value)) + suffix
}
