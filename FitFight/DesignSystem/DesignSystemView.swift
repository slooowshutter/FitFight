import SwiftUI

/// Every token and component the app is built from, in the kit's own order.
/// Internal reference: Debug menu and the screenshot workflow.
struct DesignSystemView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    // Live state for the interactive pieces, seeded with the kit's values.
    @State private var notifications = true
    @State private var units = "km"
    @State private var duration = "1 week"

    var body: some View {
        Group {
            if staticRender {
                // A scroll view only lays out its viewport off-screen, so the export
                // renders the sections directly onto the tall canvas instead.
                sections.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { sections }
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: theme.space.sectionGap) {
            header
            colour
            typeAndShape
            buttons
            badgesAndAvatars
            cards
            controls
            emptyState
            progress
            comparison
            navigation
            motion
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 60)
    }

    // MARK: 00 — header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Design system")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                FFSegmented(items: Mode.allCases, selection: $themeStore.mode) { $0.label }
            }
            Text("Every token and component the app is built from. Night is the primary theme; each colour carries its day-mode counterpart so a screen can be built either way from the same names.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: 01 — colour

    private var colour: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "01 · Colour")
            Text("Four families. Ink is every surface, Moss is you and winning, Ember is urgency and losing, Gold is progress only. Nothing else gets to be a colour.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ThemeCatalog.swatches, id: \.title) { group in
                swatchGroup(group)
            }
        }
    }

    private func swatchGroup(_ group: SwatchGroup) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: 14) {
                FFEyebrow(group.title)
                ForEach(group.items, id: \.name) { item in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                            .fill(Color(token: item.value))
                            .frame(width: 52, height: 38)
                            .ffBorder(theme.line, radius: theme.radius.glyph)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .ffType(.label)
                                    .foregroundStyle(theme.text)
                                Text(item.value)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textFaint)
                            }
                            Text(item.use)
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: 02 — type & shape

    private var typeAndShape: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "02 · Type & shape")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Nunito · 600 / 700 / 800")
                    specimen("26,410", .metric, "Metric hero — 34/800/−0.03em · tabular")
                    specimen("Screen title", .title, "Title — 26/800/−0.025em")
                    specimen("Card heading", .heading, "Heading — 16/800/−0.01em")
                    specimen("Supporting line under a heading", .body, "Body — 13/700 · ash")
                    specimen("Section eyebrow", .eyebrow, "Eyebrow — 12/800/0.06em/uppercase")
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    FFEyebrow("Radius")
                    radiusRow("pill · 999", theme.radius.pill, "Buttons, chips, badges, avatars, switches")
                    radiusRow("card · 22", theme.radius.card, "Every card, row, panel, notice and tile")
                    radiusRow("field · 14", theme.radius.field, "Form fields, tab bodies, drawer rows")
                    radiusRow("glyph · 9", theme.radius.glyph, "Result glyphs, icon tiles, menu items")
                    radiusRow("shell · 28", theme.radius.shell, "Drawer lip and device frame only")
                }
            }
        }
    }

    private func specimen(_ text: String, _ role: TypeRole, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .ffType(role)
                .foregroundStyle(role == .body || role == .eyebrow ? theme.textSecondary : theme.text)
            Text(note)
                .ffType(.micro)
                .foregroundStyle(theme.textFaint)
        }
    }

    private func radiusRow(_ name: String, _ radius: CGFloat, _ use: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: min(radius, 19), style: .continuous)
                .fill(theme.control)
                .frame(width: 52, height: 38)
                .ffBorder(theme.track, radius: min(radius, 19))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).ffType(.label).foregroundStyle(theme.text)
                Text(use).ffType(.micro).foregroundStyle(theme.textFaint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 03 — buttons

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "03 · Buttons")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Variants")
                    FFFlow(spacing: 10) {
                        FFButton(title: "Primary") {}
                        FFButton(title: "Ember", kind: .ember) {}
                        FFButton(title: "Secondary", kind: .secondary) {}
                        FFButton(title: "Ghost", kind: .ghost) {}
                        FFButton(title: "Disabled", enabled: false) {}
                    }
                    FFEyebrow("Sizes")
                    FFFlow(spacing: 10) {
                        FFButton(title: "Small", size: .small) {}
                        FFButton(title: "Medium", size: .medium) {}
                        FFButton(title: "Large", size: .large) {}
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    FFEyebrow("Screen CTA: tap to continue")
                    Text("A full-width button with a centered label. Sliding confirmation is reserved for creating a fight.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    FFScreenCTA(title: "Challenge Marc") {}
                }
            }
        }
    }

    // MARK: 04 — badges & avatars

    private var badgesAndAvatars: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "04 · Badges & avatars")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Mode tags — caps, 10pt, on cards")
                    FFFlow(spacing: 8) {
                        FFTag("1v1")
                        FFTag("Group")
                        FFTag("Goal", tone: .ember)
                        FFTag("Streak", tone: .gold)
                    }
                    FFEyebrow("Status pills — sentence case, 11–13pt")
                    FFFlow(spacing: 8) {
                        FFPill("On")
                        FFPill("Connect", style: .solidMoss)
                        FFPill("2 days left", style: .softEmber)
                        FFPill("75% win rate", style: .gold)
                        FFPill("Ended", style: .neutral)
                    }
                    FFEyebrow("Result glyphs — 24pt square, in dense rows")
                    HStack(spacing: 8) {
                        FFResultGlyph(.win)
                        FFResultGlyph(.loss)
                        FFResultGlyph(.draw)
                        FFResultGlyph(.pending)
                        Spacer(minLength: 0)
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Avatar — monogram until a photo exists")
                    Text("Always a circle, always the control fill with a hairline. Sizes are fixed so photos drop in with no layout change.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .bottom, spacing: 16) {
                        avatarSample("MB", 32, "32")
                        avatarSample("NK", 38, "38")
                        avatarSample("MR", 44, "44")
                        avatarSample("TD", 54, "selected", selected: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func avatarSample(_ monogram: String, _ size: CGFloat, _ label: String, selected: Bool = false) -> some View {
        VStack(spacing: 8) {
            FFAvatar(monogram: monogram, size: size, selected: selected)
            Text(label)
                .font(.ff(10, 700))
                .foregroundStyle(selected ? theme.mossText : theme.textFaint)
        }
    }

    // MARK: 05 — cards

    private var cards: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "05 · Cards")
            FFEyebrow("List row")
            FFListRow(
                monogram: "MB", title: "Step Derby", subtitle: "Head to head · steps",
                metric: "4,310", ahead: true, metricIsGap: true
            )
            FFListRow(
                monogram: "NK", title: "Sunday Climb", subtitle: "Head to head · steps",
                metric: "280", ahead: false, metricIsGap: true
            )
            FFEyebrow("Notice — ember wash")
            FFNotice(text: "2 invites expire in 2 days", tone: .ember, systemImage: "clock")
            FFNotice(text: "You won Sleep Streak", tone: .moss, actionTitle: "See", action: {})
            FFEyebrow("Grouped rows — settings pattern")
            FFGroupedRows {
                FFGroupedRow(
                    title: "Apple Watch", subtitle: "Steps · active minutes",
                    systemImage: "applewatch",
                    trailing: AnyView(FFPill("On"))
                )
                FFDivider()
                FFGroupedRow(
                    title: "Whoop", subtitle: "Sleep · recovery",
                    systemImage: "waveform.path.ecg", enabled: false,
                    trailing: AnyView(FFPill("Connect", style: .solidMoss))
                )
            }
        }
    }

    // MARK: 06 — controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "06 · Controls")
            FFCard {
                VStack(alignment: .leading, spacing: 16) {
                    FFEyebrow("Switch & segmented")
                    HStack(spacing: 12) {
                        Text("Notifications").ffType(.rowTitle).foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                        FFSwitch(isOn: $notifications)
                    }
                    HStack(spacing: 12) {
                        Text("Units").ffType(.rowTitle).foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                        FFSegmented(items: ["km", "mi"], selection: $units) { $0 }
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Form field — every state")
                    FFField(label: "Challenge name", help: "Everyone invited sees this name.") {
                        Text("Step Derby")
                    }
                    FFField(label: "Empty & focused", state: .focused) {
                        Text("Name your fight").foregroundStyle(theme.textFaint)
                    }
                    FFField(label: "Daily target", state: .error, help: "Pick a number above zero.") {
                        Text("0")
                    }
                    FFField(label: "Metric source", state: .disabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock").font(.system(size: 12, weight: .semibold))
                            Text("Apple Watch — locked to steps")
                        }
                    }
                    FFField(label: "Trash talk", counter: "17 / 140", minHeight: 88) {
                        Text("Easy week for me.")
                    }
                }
            }
        }
    }

    // MARK: 07 - empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "07 · Empty state")
            FFCard {
                FFEmptyState(
                    systemImage: "trophy",
                    title: "No fights yet",
                    message: "Pick a friend and a metric. Steps is the easy first one.",
                    actionTitle: "Start one",
                    action: {}
                )
            }
        }
    }

    // MARK: 08 — progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "08 · Progress")
            Text("One component: ember or moss on a card. Track is always the same 9% white.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            FFCard {
                VStack(alignment: .leading, spacing: 20) {
                    FFEyebrow("Bars")
                    bar("On a card, ahead · 7pt", "72%", theme.mossText, 0.72, theme.mossFill)
                    bar("On a card, behind · 7pt", "38%", theme.emberText, 0.38, theme.emberFill)
                    bar("Complete", "Done", theme.mossText, 1, theme.mossFill)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Two-up · you vs them").ffType(.caption).fontWeight(.heavy).foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                            Text("26,410 / 22,100").ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        FFProgressBar(value: 1, fill: theme.mossFill)
                        FFProgressBar(value: 0.84, fill: theme.textFaint)
                    }
                }
            }
        }
    }

    private func bar(_ label: String, _ value: String, _ ink: Color, _ progress: Double, _ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(label).ffType(.caption).fontWeight(.heavy).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Text(value).ffType(.caption).fontWeight(.heavy).foregroundStyle(ink)
            }
            FFProgressBar(value: progress, fill: fill)
        }
    }

    // MARK: 09 — comparison

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "09 · Comparison & ranking")
            FFEyebrow("Leaderboard row — you always highlighted")
            VStack(spacing: 8) {
                FFLeaderboardRow(rank: 1, monogram: "NK", name: "Nina", value: "412")
                FFLeaderboardRow(rank: 2, monogram: "MB", name: "Marc", value: "388")
                FFLeaderboardRow(rank: 3, monogram: "MR", name: "Maya", value: "341")
                FFLeaderboardRow(rank: 4, monogram: "AM", name: "You", value: "312", isYou: true, captionAt: { _ in "Synced 3 Sep, 12:41" })
                FFLeaderboardRow(rank: 5, monogram: "TD", name: "Theo", value: "204")
            }
            Text("Rank 1 takes gold ink. The row never names its own metric; the screen header does.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 10 - navigation & pickers

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "10 · Navigation & pickers")
            FFEyebrow("Nav header")
            FFNavDetail(title: "Step Derby", onBack: {})
            FFEyebrow("Duration picker")
            FFDurationPicker(options: ["3 days", "1 week", "1 month", "Custom"], selection: $duration)
        }
    }

    // MARK: 11 - motion

    private var motion: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "11 · Motion")
            FFGroupedRows {
                ForEach(Array(Self.motionTokens.enumerated()), id: \.offset) { index, token in
                    if index > 0 { FFDivider() }
                    HStack(alignment: .top, spacing: 16) {
                        Text(token.0)
                            .ffType(.button)
                            .foregroundStyle(theme.mossText)
                            .frame(width: 78, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(token.1).ffType(.caption).foregroundStyle(theme.textDim)
                            Text(token.2).ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            Text("Reduced motion is a global kill switch — every duration collapses to near-zero, nothing loops. Wins may celebrate; losses never animate.")
                .ffType(.body)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Kit sample data

    private static let motionTokens: [(String, String, String)] = [
        ("instant", "0ms", "Selection, chip and tab state — never animate a filter"),
        ("quick", "150ms expo-out", "Popovers, dropdowns, toggles"),
        ("sheet", "320ms expo-out", "Drawers, dialogs, carousel travel"),
        ("count", "600ms ease-out", "A metric number ticking up after a sync"),
        ("celebrate", "900ms ease-out, once", "Win state only. Never on a loss."),
        ("shimmer", "1400ms linear, infinite", "Skeletons while a connector is fetching")
    ]
}

/// Wrapping horizontal stack — the kit lays button and badge rows out with flex-wrap.
struct FFFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
                x = 0
            }
            row.indices.append(index)
            row.height = max(row.height, size.height)
            x += size.width + spacing
            row.width = x - spacing
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#Preview {
    let store = ThemeStore()
    return DesignSystemView()
        .environmentObject(store)
        .fitFightTheme(store.theme)
}
