import SwiftUI
import UIKit

// Geometry measured from docs/design/source/screenshots (393pt canvas, 2x captures).
enum FFMetric {
    static let cardRadius: CGFloat = 22
    /// Request cards are drawn with a tighter corner than fight cards.
    static let tightCardRadius: CGFloat = 15
    static let chipRadius: CGFloat = 10
    static let cardPadding: CGFloat = 20
    /// Section titles sit 4pt inside the card edge below them, except on the
    /// fights list and the standings, where the mock lines them up flush.
    static let sectionTitleInset: CGFloat = 4
    /// List rows (settings, sources, options) inset 16; rows that sit inside a
    /// fight card, and the tinted bands, inset by the card padding instead.
    static let rowPaddingX: CGFloat = 16
    static let rowPaddingY: CGFloat = 14
    static let barHeight: CGFloat = 6
    static let miniRowHeight: CGFloat = 24
    static let miniRowGap: CGFloat = 10
    static let miniRankWidth: CGFloat = 22
    static let miniAvatar: CGFloat = 22
    static let miniNameWidth: CGFloat = 75
    static let miniNameGap: CGFloat = 10
    static let miniValueWidth: CGFloat = 58
    static let rankBadgeWidth: CGFloat = 54
    static let rankBadgeHeight: CGFloat = 50
    static let statTileHeight: CGFloat = 58
    static let ringSize: CGFloat = 121
    static let ringStroke: CGFloat = 11
}

private struct FFStaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while ScreenshotExport renders screens off-screen, where scroll views stay blank.
    var ffStaticRender: Bool {
        get { self[FFStaticRenderKey.self] }
        set { self[FFStaticRenderKey.self] = newValue }
    }
}

struct FFScreen<Content: View>: View {
    var top: AnyView? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.ffTheme) private var theme

    var body: some View {
        if staticRender {
            // Color.clear takes exactly the offered size, so an overlay on top of it
            // pins the screen to the top and lets anything taller run off the bottom
            // instead of being centred.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        if let top { top }
                        // Without this the greedy children a scroll view would leave
                        // alone (vote pills, filled rows) split the leftover height.
                        content()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .background(theme.bg)
        } else {
            ScrollView {
                content()
            }
            .background(theme.bg)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let top { top }
            }
        }
    }
}

struct FFLabel: View {
    let text: String
    var role: TypeRole
    var color: Color? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let spec = theme.type.spec(role)
        Text(spec.uppercase ? text.uppercased() : text)
            .font(theme.font(role))
            .tracking(theme.tracking(role))
            .foregroundStyle(color ?? defaultColor)
    }

    /// Kickers and eyebrows are labels, and labels are faint everywhere in the mock.
    private var defaultColor: Color {
        switch role {
        case .eyebrow, .tiny: return theme.faint
        default: return theme.text
        }
    }
}

enum FFButtonKind {
    case primary
    case secondary
    case quiet
    case destructive
    case small
}

struct FFButton: View {
    let title: String
    var kind: FFButtonKind = .primary
    var icon: String? = nil
    var iconTrailing = false
    var enabled = true
    var action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: kind == .small ? 7 : 12) {
                if let icon, !iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: kind == .small ? 11 : 13, weight: .semibold))
                }
                Text(title)
                    .font(.ff(kind == .small ? 13 : 15, kind == .small ? .semibold : .bold))
                if let icon, iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: kind == .small ? 11 : 13, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: kind == .small ? nil : .infinity)
            .padding(.horizontal, kind == .small ? 12 : 16)
            .frame(height: kind == .small ? 34 : 54)
            .background(background, in: theme.rounded(theme.buttonRadius))
            .overlay {
                if kind == .quiet {
                    theme.rounded(theme.buttonRadius).strokeBorder(theme.line, lineWidth: theme.strokeWidth)
                }
            }
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
        .disabled(!enabled)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .small: return theme.ink
        case .secondary: return theme.accent
        case .quiet: return theme.text
        case .destructive: return theme.red
        }
    }

    private var background: Color {
        switch kind {
        case .primary, .small: return theme.accent
        case .secondary: return theme.chip
        case .quiet: return Color.clear
        case .destructive: return theme.red.opacity(0.12)
        }
    }
}

struct FFIconButton: View {
    let systemName: String
    var size: CGFloat = 40
    var destructive = false
    var action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(destructive ? theme.red : theme.text)
                .frame(width: size, height: size)
                .overlay {
                    theme.blob(size, radius: theme.iconButtonRadius)
                        .strokeBorder(theme.line, lineWidth: theme.strokeWidth)
                }
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
    }
}

/// Card chrome that follows the active look: fill, stroke, rail, or outline.
struct FFChrome<Content: View>: View {
    var radius: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let shape = theme.rounded(radius)
        let inner = content().frame(maxWidth: .infinity, alignment: .leading)
        Group {
            switch theme.cardChrome {
            case .filledStroke:
                inner
                    .background(theme.surface, in: shape)
                    .overlay { shape.strokeBorder(theme.line, lineWidth: theme.strokeWidth) }
            case .filled:
                inner
                    .background(theme.surface, in: shape)
            case .strokeOnly:
                inner
                    .background(theme.bg, in: shape)
                    .overlay { shape.strokeBorder(theme.line, lineWidth: theme.strokeWidth) }
            case .rail:
                HStack(spacing: 0) {
                    theme.text.opacity(0.2)
                        .frame(width: theme.railWidth)
                    inner
                }
                .background(theme.surface)
                .clipShape(shape)
                .overlay { shape.strokeBorder(theme.line, lineWidth: theme.strokeWidth) }
            }
        }
    }
}

/// Card: surface, 1px line border, 22pt radius on Classic, 20pt padding.
struct FFCard<Content: View>: View {
    var padding: CGFloat = FFMetric.cardPadding
    /// Rows in the mock are wider inside than they are tall inside.
    var horizontal: CGFloat? = nil
    var radius: CGFloat? = nil
    var tight = false
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFChrome(radius: radius ?? (tight ? theme.tightCardRadius : theme.cardRadius)) {
            content()
                .padding(.vertical, padding)
                .padding(.horizontal, horizontal ?? padding)
        }
    }
}

/// Card without padding: rows, tinted bands and footers run edge to edge.
struct FFPanel<Content: View>: View {
    var radius: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFChrome(radius: radius ?? theme.cardRadius) {
            VStack(spacing: 0) {
                content()
            }
        }
    }
}

/// The chip-tinted band at the top or bottom of a card.
struct FFBand<Content: View>: View {
    var vertical: CGFloat = 16.5
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        content()
            .padding(.horizontal, FFMetric.cardPadding)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.chip)
    }
}

struct FFHairline: View {
    var inset: CGFloat = 0
    @Environment(\.ffTheme) private var theme

    var body: some View {
        theme.hair
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

struct FFRankBadge: View {
    let rank: Int
    let of: Int
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let first = rank == 1
        VStack(spacing: 2) {
            Text("#\(rank)")
                .font(.ff(19, .bold))
                .foregroundStyle(first ? theme.ink : theme.text)
            Text("OF \(of)")
                .font(.ff(10, .semibold))
                .tracking(0.6)
                .foregroundStyle(first ? theme.ink.opacity(0.75) : theme.muted)
        }
        .frame(width: FFMetric.rankBadgeWidth, height: FFMetric.rankBadgeHeight)
        .background(
            first ? theme.accent : theme.chip,
            in: theme.rounded(theme.radius.lg)
        )
    }
}

/// "12 min behind Leo" — muted words around one bold value.
struct FFKicker: View {
    var prefix: String = ""
    var emphasis: String
    var rest: String = ""
    var size: CGFloat = 12
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix)
                    .font(.ff(size, .regular))
                    .foregroundStyle(theme.muted)
            }
            Text(emphasis)
                .font(.ff(size, .bold))
                .foregroundStyle(theme.text)
            if !rest.isEmpty {
                Text(rest)
                    .font(.ff(size, .regular))
                    .foregroundStyle(theme.muted)
            }
        }
    }
}

struct FFSegmented<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var title: (Item) -> String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let on = selection == item
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.ff(12, on ? .semibold : .medium))
                        .foregroundStyle(on ? theme.text : theme.faint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if on {
                                theme.rounded(theme.segmentThumbRadius)
                                    .fill(theme.surface)
                                    .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.chip, in: theme.rounded(theme.segmentRadius))
    }
}

struct FFSectionHeader: View {
    let title: String
    var action: String? = nil
    var actionMuted = false
    var inset: CGFloat = FFMetric.sectionTitleInset
    var onAction: (() -> Void)? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ff(13, .bold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 12)
            if let action {
                let label = Text(action)
                    .font(.ff(12, actionMuted ? .regular : .semibold))
                    .foregroundStyle(actionMuted ? theme.faint : theme.accent)
                if let onAction {
                    Button(action: onAction) { label }
                        .buttonStyle(.plain)
                } else {
                    label
                }
            }
        }
        .padding(.horizontal, inset)
    }
}

/// Stand-in for the web mock's photo avatars: a stable two-tone disc per person.
struct FFAvatar: View {
    let initials: String
    /// Asset name of the person's photo, cut from the design mocks. Falls back to a monogram.
    var photo: String? = nil
    var size: CGFloat = 24
    var ring = false
    var pending = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let shape = theme.blob(size, radius: theme.avatarRadius)
        face
            .frame(width: size, height: size)
            .clipShape(shape)
            .padding(ring ? 3 : 0)
            .overlay {
                if ring {
                    theme.blob(size + 6, radius: theme.avatarRadius + 3)
                        .strokeBorder(theme.accent, lineWidth: 2)
                }
            }
            .opacity(pending ? 0.5 : 1)
    }

    @ViewBuilder
    private var face: some View {
        let shape = theme.blob(size, radius: theme.avatarRadius)
        if let photo, UIImage(named: photo) != nil {
            Image(photo)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            shape
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(initials.prefix(1))
                        .font(.ff(size * 0.42, .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }

    private var gradient: [Color] {
        let seed = abs(initials.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 17 })
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.22, brightness: 0.52),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.30, brightness: 0.32)
        ]
    }
}

struct FFMoney: View {
    let dollars: Int
    var size: CGFloat = 13
    var evenText = "even"

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let color: Color = {
            if dollars > 0 { return theme.green }
            if dollars < 0 { return theme.red }
            return theme.faint
        }()
        let label: String = {
            if dollars > 0 { return "+$\(dollars)" }
            if dollars < 0 { return "−$\(abs(dollars))" }
            return evenText
        }()
        Text(label)
            .font(.ff(size, .bold))
            .foregroundStyle(color)
    }
}

struct FFProgressBar: View {
    var progress: CGFloat
    var fill: Color
    var height: CGFloat = FFMetric.barHeight

    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let filled = max(height, geo.size.width * min(1, max(0, progress)))
            let bar = theme.rounded(theme.progressRadius)
            // The track is knocked out under the fill: both are translucent white, and
            // stacking them would make every part-filled bar lighter than the mock.
            bar
                .fill(theme.track)
                .overlay(alignment: .leading) {
                    bar.frame(width: filled).blendMode(.destinationOut)
                }
                .compositingGroup()
                .overlay(alignment: .leading) {
                    bar.fill(fill).frame(width: filled)
                }
        }
        .frame(height: height)
    }
}

/// The big rank ring on a fight detail hero.
struct FFRing<Content: View>: View {
    var progress: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let cap: CGLineCap = theme.ringSquircle ? .square : .round
        let ring = theme.rounded(theme.ringSquircle ? 28 : 9999)
        ZStack {
            ring
                .stroke(theme.track, lineWidth: FFMetric.ringStroke)
            ring
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [theme.accent, theme.accent, theme.accentDim],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: FFMetric.ringStroke, lineCap: cap)
                )
                .rotationEffect(.degrees(-90))
            content()
        }
        .frame(width: FFMetric.ringSize, height: FFMetric.ringSize)
    }
}

struct FFStatTile: View {
    let value: String
    let label: String
    var color: Color? = nil
    var onSurface = false
    /// The profile grid runs two points taller than the row inside a fight hero.
    var height: CGFloat = FFMetric.statTileHeight

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ff(17, .bold))
                .foregroundStyle(color ?? theme.text)
            Text(label.uppercased())
                .font(.ff(9, .semibold))
                .tracking(0.2)
                .foregroundStyle(theme.faint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            onSurface ? theme.surface : theme.chip,
            in: theme.rounded(theme.radius.lg)
        )
        .overlay {
            if onSurface {
                theme.rounded(theme.radius.lg)
                    .strokeBorder(theme.line, lineWidth: theme.strokeWidth)
            }
        }
    }
}

struct FFBadge: View {
    let text: String
    var tone: Tone = .accent
    var style: Style = .tint

    enum Tone {
        case accent
        case amber
        case red
        case green
        case muted
        case blue
    }

    enum Style {
        case tint
        case solid
        case plain
    }

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let color = colorForTone
        Text(text.uppercased())
            .font(.ff(9, .bold))
            .tracking(0.4)
            .foregroundStyle(foreground(color))
            .padding(.horizontal, style == .plain ? 0 : 5)
            .padding(.vertical, style == .plain ? 0 : 3)
            .background {
                switch style {
                case .tint:
                    shape.fill(color.opacity(0.12))
                case .solid:
                    shape.fill(color)
                case .plain:
                    Color.clear
                }
            }
    }

    private var shape: RoundedRectangle {
        theme.rounded(4)
    }

    private func foreground(_ color: Color) -> Color {
        switch style {
        case .solid:
            return Color(hex: "#17181c")
        case .tint, .plain:
            return color
        }
    }

    private var colorForTone: Color {
        switch tone {
        case .accent: return theme.accent
        case .amber: return theme.amber
        case .red: return theme.red
        case .green: return theme.green
        case .muted: return theme.muted
        case .blue: return theme.blue
        }
    }
}

struct FFChip: View {
    let text: String
    var selected = false
    var suggestion = false
    var fill = false
    var action: (() -> Void)? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let label = Text(text)
            .font(.ff(15, .semibold))
            .foregroundStyle(selected ? theme.ink : (suggestion ? theme.accent : theme.text))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 46)
            .background(
                selected ? theme.accent : theme.surface,
                in: theme.rounded(theme.chipRadius)
            )
            .overlay {
                if !selected {
                    theme.rounded(theme.chipRadius)
                        .strokeBorder(theme.line, lineWidth: theme.strokeWidth)
                }
            }

        if let action {
            Button(action: action) { label }
                .buttonStyle(FFPressStyle(scale: 0.97))
        } else {
            label
        }
    }
}

enum FFTab: Hashable {
    case fights
    case newFight
    case requests
    case you
}

struct FFTabBar: View {
    @Binding var tab: FFTab
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let items = HStack(spacing: 0) {
            item(.fights, "Tab-fights", "Fights")
            item(.newFight, "Tab-new", "New")
            item(.requests, "Tab-requests", "Requests")
            item(.you, "Tab-you", "You")
        }

        switch theme.tabChrome {
        case .classic:
            items
                .padding(.horizontal, 13)
                .padding(.top, 15)
                .padding(.bottom, 8)
                .background {
                    theme.bg.opacity(0.9)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
                .overlay(alignment: .top) {
                    theme.line.frame(height: 1)
                }
        case .flush:
            items
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(theme.bg.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    theme.line.frame(height: theme.strokeWidth == 0 ? 1 : theme.strokeWidth)
                }
        case .pill:
            items
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(theme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(theme.line, lineWidth: theme.strokeWidth) }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(theme.bg.ignoresSafeArea(edges: .bottom))
        case .boxed:
            items
                .padding(6)
                .background(theme.bg.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    theme.line.frame(height: theme.strokeWidth)
                }
        }
    }

    private func item(_ value: FFTab, _ icon: String, _ title: String) -> some View {
        let on = tab == value
        return Button {
            tab = value
        } label: {
            VStack(spacing: 5) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(on ? theme.accent : theme.muted)
                    .overlay(alignment: .top) {
                        marker(on: on)
                            .offset(y: -7.5)
                    }
                Text(title)
                    .font(.ff(10, on ? .semibold : .regular))
                    .foregroundStyle(on ? theme.text : theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.tabChrome == .boxed ? 6 : 0)
            .background {
                if theme.tabChrome == .boxed && on {
                    theme.rounded(theme.chipRadius)
                        .strokeBorder(theme.line, lineWidth: theme.strokeWidth)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func marker(on: Bool) -> some View {
        switch theme.tabMarker {
        case .dot:
            Circle()
                .fill(on ? theme.accent : Color.clear)
                .frame(width: 4, height: 4)
        case .bar:
            theme.rounded(1)
                .fill(on ? theme.accent : Color.clear)
                .frame(width: 10, height: 2)
        case .none:
            Color.clear.frame(width: 4, height: 4)
        }
    }
}

struct FFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct VersionBanner: View {
    @Environment(\.ffTheme) private var theme
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(AppVersion.label)
                .font(theme.font(.micro))
                .foregroundStyle(theme.faint)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityIdentifier("app-version")
    }
}
