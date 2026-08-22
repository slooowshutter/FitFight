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
    @Environment(\.ffTheme) private var theme

    var body: some View {
        theme.hair.frame(height: 1)
            .padding(.leading, 16)
    }
}

struct FFSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack {
            FFLabel(text: title, role: .label, color: theme.text)
            Spacer()
            if let action {
                if let onAction {
                    Button(action: onAction) {
                        FFLabel(text: action, role: .label, color: theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    FFLabel(text: action, role: .label, color: theme.accent)
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
        .frame(height: 4)
    }
}

struct FFBadge: View {
    let text: String
    var tone: Tone = .accent

    enum Tone {
        case accent
        case amber
        case red
        case green
        case muted
        case blue
    }

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let color = colorForTone
        Text(text.uppercased())
            .font(theme.font(.tiny))
            .tracking(theme.tracking(.tiny))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
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

struct FFTab: Hashable {
    case fights
    case newFight
    case requests
    case you
}

struct FFTabBar: View {
    @Binding var tab: FFTab
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack {
            item(.fights, "trophy", "Fights")
            item(.newFight, "plus", "New")
            item(.requests, "text.bubble", "Requests")
            item(.you, "person", "You")
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
        .padding(.horizontal, 8)
        .background(theme.bg.opacity(0.9))
        .overlay(alignment: .top) {
            theme.line.frame(height: 1)
        }
    }

    private func item(_ value: FFTab, _ icon: String, _ title: String) -> some View {
        let on = tab == value
        return Button {
            tab = value
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .top) {
                    if on {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 4, height: 4)
                            .offset(y: -6)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                }
                .frame(height: 24)
                Text(title)
                    .font(theme.font(.tiny))
                    .tracking(theme.tracking(.tiny))
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
