import SwiftUI

enum FFButtonKind {
    case primary
    case secondary
    case ghost
    case danger
}

struct FFButton: View {
    let title: String
    var kind: FFButtonKind = .primary
    var action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.bodyFont(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(foreground)
                .background(background, in: shape)
                .overlay {
                    if kind == .secondary || kind == .ghost {
                        shape.strokeBorder(stroke, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return theme.colors.accentText
        case .secondary, .ghost:
            return theme.colors.text
        case .danger:
            return theme.colors.dangerText
        }
    }

    private var background: Color {
        switch kind {
        case .primary:
            return theme.colors.accent
        case .secondary:
            return theme.colors.surface
        case .ghost:
            return Color.clear
        case .danger:
            return theme.colors.danger
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary, .danger:
            return Color.clear
        case .secondary:
            return theme.colors.border
        case .ghost:
            return theme.colors.border
        }
    }
}

struct FFCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        content()
            .padding(theme.metrics.spaceMd)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: cardShape)
            .overlay {
                cardShape.strokeBorder(theme.colors.border, lineWidth: 1)
            }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.metrics.radiusLg, style: theme.metrics.cornerStyle)
    }
}

struct FFChip: View {
    let text: String
    var emphasized = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(text)
            .font(theme.bodyFont(13, weight: .semibold))
            .foregroundStyle(emphasized ? theme.colors.accentText : theme.colors.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                emphasized ? theme.colors.accent : theme.colors.raised,
                in: RoundedRectangle(cornerRadius: theme.metrics.radiusSm, style: theme.metrics.cornerStyle)
            )
    }
}

struct FFStat: View {
    let label: String
    let value: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(theme.bodyFont(22, weight: .bold))
                .foregroundStyle(theme.colors.text)
            Text(label)
                .font(theme.bodyFont(12, weight: .medium))
                .foregroundStyle(theme.colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.metrics.spaceMd)
        .background(
            theme.colors.surface,
            in: RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        }
    }
}

struct FFRow: View {
    let title: String
    let subtitle: String
    var trailing: String? = nil

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.colors.raised)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(title.prefix(1)))
                        .font(theme.bodyFont(16, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont(16, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                Text(subtitle)
                    .font(theme.bodyFont(13, weight: .regular))
                    .foregroundStyle(theme.colors.muted)
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(theme.monoFont(13, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .padding(theme.metrics.spaceMd)
        .background(
            theme.colors.surface,
            in: RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        }
    }
}

struct FFField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.colors.muted))
            .font(theme.bodyFont(17, weight: .regular))
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                theme.colors.surface,
                in: RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.metrics.radiusMd, style: theme.metrics.cornerStyle)
                    .strokeBorder(theme.colors.border, lineWidth: 1)
            }
    }
}

struct FFSectionHeader: View {
    let title: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Text(title.uppercased())
            .font(theme.monoFont(11, weight: .bold))
            .foregroundStyle(theme.colors.muted)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
