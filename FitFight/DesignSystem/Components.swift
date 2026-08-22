import SwiftUI

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
            .monospacedDigit()
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
    var enabled = true
    var action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: kind == .small ? 13 : 16, weight: .semibold))
                }
                Text(title)
                    .font(theme.font(kind == .small ? .caption : .bodyStrong))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: kind == .small ? nil : .infinity)
            .padding(.horizontal, kind == .small ? 14 : 16)
            .padding(.vertical, kind == .small ? 8 : 14)
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
        case .quiet: return theme.muted
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
    var destructive = false
    var action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructive ? theme.red : theme.text)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle().strokeBorder(theme.line, lineWidth: 1)
                }
        }
        .buttonStyle(FFPressStyle(scale: 0.97))
    }
}

struct FFChip: View {
    let text: String
    var selected = false
    var suggestion = false
    var action: (() -> Void)? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let label = Text(text)
            .font(theme.font(.bodyStrong))
            .foregroundStyle(selected ? theme.ink : (suggestion ? theme.accent : theme.text))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selected ? theme.accent : (suggestion ? theme.chip : theme.surface),
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

struct FFCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        content()
            .padding(theme.space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }
}

struct FFGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }
}

struct FFHairline: View {
    var inset: CGFloat = 16
    @Environment(\.ffTheme) private var theme

    var body: some View {
        theme.hair.frame(height: 1)
            .padding(.leading, inset)
    }
}

struct FFRankBadge: View {
    let rank: Int
    let of: Int
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let first = rank == 1
        VStack(spacing: 1) {
            Text("#\(rank)")
                .font(theme.font(.headline))
                .foregroundStyle(first ? theme.ink : theme.text)
            Text("OF \(of)")
                .font(theme.font(.tiny))
                .tracking(theme.tracking(.tiny))
                .foregroundStyle(first ? theme.ink.opacity(0.8) : theme.muted)
        }
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            first ? theme.accent : theme.chip,
            in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
        )
    }
}

struct FFKicker: View {
    var prefix: String = ""
    var emphasis: String
    var rest: String = ""
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.muted)
            }
            Text(emphasis)
                .font(theme.font(.bodyStrong))
                .foregroundStyle(theme.text)
                .monospacedDigit()
            if !rest.isEmpty {
                Text(rest)
                    .font(theme.font(.caption))
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
                        .font(theme.font(.bodyStrong))
                        .foregroundStyle(on ? theme.text : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? theme.surface : Color.clear, in: Capsule())
                        .shadow(color: on ? Color.black.opacity(0.25) : Color.clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.chip, in: Capsule())
    }
}

struct FFSectionHeader: View {
    let title: String
    var action: String? = nil
    var actionMuted = false
    var onAction: (() -> Void)? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack {
            FFLabel(text: title, role: .label, color: theme.text)
            Spacer()
            if let action {
                let color = actionMuted ? theme.muted : theme.accent
                let role: TypeRole = actionMuted ? .caption : .label
                if let onAction {
                    Button(action: onAction) {
                        FFLabel(text: action, role: role, color: color)
                    }
                    .buttonStyle(.plain)
                } else {
                    FFLabel(text: action, role: role, color: color)
                }
            }
        }
    }
}

struct FFAvatar: View {
    let initials: String
    var size: CGFloat = 32
    var ring = false
    var pending = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(theme.text)
            .frame(width: size, height: size)
            .background(theme.surface2, in: Circle())
            .padding(ring ? 1.5 : 0)
            .overlay {
                if ring {
                    Circle().strokeBorder(theme.accent, lineWidth: 2)
                }
            }
            .opacity(pending ? 0.5 : 1)
    }
}

struct FFMoney: View {
    let dollars: Int
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
            .font(theme.font(.bodyStrong))
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

struct FFProgressBar: View {
    var progress: CGFloat
    var fill: Color
    var height: CGFloat = 8

    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(theme.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(6, geo.size.width * min(1, max(0, progress))))
                }
        }
        .frame(height: height)
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
            .font(theme.font(.tiny))
            .tracking(theme.tracking(.tiny))
            .foregroundStyle(foreground(color))
            .padding(.horizontal, style == .plain ? 0 : 8)
            .padding(.vertical, style == .plain ? 0 : 4)
            .background {
                switch style {
                case .tint:
                    Capsule().fill(color.opacity(0.12))
                case .solid:
                    Capsule().fill(color)
                case .plain:
                    Color.clear
                }
            }
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
        HStack(alignment: .bottom) {
            item(.fights, "trophy", "Fights")
            item(.newFight, "plus", "New")
            item(.requests, "bubble.left", "Requests", chevron: true)
            item(.you, "person", "You")
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .padding(.horizontal, 8)
        .background {
            Rectangle()
                .fill(theme.bg.opacity(0.9))
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            theme.hair.frame(height: 1)
        }
    }

    private func item(_ value: FFTab, _ icon: String, _ title: String, chevron: Bool = false) -> some View {
        let on = tab == value
        return Button {
            tab = value
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .top) {
                    Circle()
                        .fill(on ? theme.accent : Color.clear)
                        .frame(width: 3, height: 3)
                        .offset(y: -7)
                    ZStack {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .regular))
                        if chevron {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 7, weight: .bold))
                                .offset(y: 1)
                        }
                    }
                }
                .frame(height: 24)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(on ? theme.accent : theme.muted)
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
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityIdentifier("app-version")
    }
}
