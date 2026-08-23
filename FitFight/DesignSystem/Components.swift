import SwiftUI

// Geometry measured from docs/design/source/screenshots (393pt canvas, 2x captures).
enum FFMetric {
    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let rowPaddingX: CGFloat = 20
    static let rowPaddingY: CGFloat = 14
    static let barHeight: CGFloat = 6
    static let miniRowHeight: CGFloat = 24
    static let miniRowGap: CGFloat = 10
    static let miniRankWidth: CGFloat = 22
    static let miniAvatar: CGFloat = 22
    static let miniNameWidth: CGFloat = 74
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
            VStack(spacing: 0) {
                if let top { top }
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .foregroundStyle(color ?? theme.text)
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
            HStack(spacing: 8) {
                if let icon, !iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: kind == .small ? 12 : 15, weight: .semibold))
                }
                Text(title)
                    .font(.ff(kind == .small ? 14 : 17, kind == .small ? .semibold : .bold))
                if let icon, iconTrailing {
                    Image(systemName: icon)
                        .font(.system(size: kind == .small ? 12 : 15, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: kind == .small ? nil : .infinity)
            .padding(.horizontal, kind == .small ? 14 : 16)
            .frame(height: kind == .small ? 36 : 58)
            .background(background, in: Capsule())
            .overlay {
                if kind == .quiet {
                    Capsule().strokeBorder(theme.line, lineWidth: 1)
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
                .background(theme.chip, in: Circle())
                .overlay {
                    Circle().strokeBorder(theme.line, lineWidth: 1)
                }
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
    }
}

/// Card: surface, 1px line border, 24pt radius, 20pt padding.
struct FFCard<Content: View>: View {
    var padding: CGFloat = FFMetric.cardPadding
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: shape)
            .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FFMetric.cardRadius, style: .continuous)
    }
}

/// Card without padding: rows, tinted bands and footers run edge to edge.
struct FFPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FFMetric.cardRadius, style: .continuous)
    }
}

/// The chip-tinted band at the top or bottom of a card.
struct FFBand<Content: View>: View {
    var vertical: CGFloat = 17
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        content()
            .padding(.horizontal, FFMetric.rowPaddingX)
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
            in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
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
                        .foregroundStyle(on ? theme.text : theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 37)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(theme.surface)
                                    .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FFSectionHeader: View {
    let title: String
    var action: String? = nil
    var actionMuted = false
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
                    .foregroundStyle(actionMuted ? theme.muted : theme.accent)
                if let onAction {
                    Button(action: onAction) { label }
                        .buttonStyle(.plain)
                } else {
                    label
                }
            }
        }
    }
}

/// Stand-in for the web mock's photo avatars: a stable two-tone disc per person.
struct FFAvatar: View {
    let initials: String
    var size: CGFloat = 24
    var ring = false
    var pending = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(initials.prefix(1))
                    .font(.ff(size * 0.42, .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            }
            .padding(ring ? 3 : 0)
            .overlay {
                if ring {
                    Circle().strokeBorder(theme.accent, lineWidth: 2)
                }
            }
            .opacity(pending ? 0.5 : 1)
    }

    private var gradient: [Color] {
        let seed = abs(initials.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 17 })
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.32, brightness: 0.62),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.42, brightness: 0.38)
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
            Capsule()
                .fill(theme.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
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
        ZStack {
            Circle()
                .stroke(theme.track, lineWidth: FFMetric.ringStroke)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [theme.accent, theme.accent, theme.accentDim],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: FFMetric.ringStroke, lineCap: .round)
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

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ff(17, .bold))
                .foregroundStyle(color ?? theme.text)
            Text(label.uppercased())
                .font(.ff(9, .semibold))
                .tracking(0.2)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FFMetric.statTileHeight)
        .background(
            onSurface ? theme.surface : theme.chip,
            in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
        )
        .overlay {
            if onSurface {
                RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
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
            .padding(.horizontal, style == .plain ? 0 : 7)
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
        RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
            )
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                        .strokeBorder(theme.line, lineWidth: 1)
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
        HStack(spacing: 0) {
            item(.fights, "figure.run", "Fights")
            item(.newFight, "plus", "New")
            item(.requests, "bubble.left", "Requests")
            item(.you, "person", "You")
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            theme.bg.opacity(0.9)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            theme.line.frame(height: 1)
        }
    }

    private func item(_ value: FFTab, _ icon: String, _ title: String) -> some View {
        let on = tab == value
        return Button {
            tab = value
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(on ? theme.accent : theme.muted)
                    .frame(height: 22)
                Text(title)
                    .font(.ff(12, on ? .semibold : .regular))
                    .foregroundStyle(on ? theme.text : theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
