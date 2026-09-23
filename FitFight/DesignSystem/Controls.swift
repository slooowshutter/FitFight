import SwiftUI

// Sections 06, 07 and 11 of the kit: controls, empty state, navigation and pickers.

// MARK: - Switch & segmented

struct FFSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.mossFill : theme.switchOff)
                Circle().fill(theme.text).frame(width: 24, height: 24)
            }
            .frame(width: 50, height: 30)
            .padding(3)
            .frame(width: 50, height: 30)
        }
        .buttonStyle(FFHapticPlainStyle())
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.15), value: isOn)
    }
}

struct FFSegmented<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var count: ((Item) -> Int?)? = nil
    let title: (Item) -> String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                let name = title(item)
                let raw = count?(item)
                let badge: Int? = (raw ?? 0) > 0 ? raw : nil
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 3) {
                        Text(name)
                            .ffType(.caption)
                            .fontWeight(.heavy)
                        if let badge {
                            Text("\(badge)")
                                .ffType(.micro)
                                .fontWeight(.heavy)
                                .opacity(0.7)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(on ? theme.mossOn : theme.textSecondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    .background(on ? theme.mossFill : .clear, in: Capsule())
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityLabel(badge.map { "\(name), \($0)" } ?? name)
            }
        }
        .padding(3)
        .background(theme.chip, in: Capsule())
    }
}

// MARK: - Form field

enum FFFieldState {
    case normal, focused, error, disabled
}

/// Form field — label, box, help line. Every state comes from the kit.
struct FFField<Content: View>: View {
    let label: String
    var state: FFFieldState = .normal
    var help: String?
    var counter: String?
    var minHeight: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .ffType(.label)
                .foregroundStyle(labelInk)
                .padding(.bottom, 7)
            content
                .font(.ff(15, 700))
                .foregroundStyle(state == .disabled ? theme.disabledText : theme.text)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: minHeight == nil ? .leading : .topLeading)
                .background(fill, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(border, radius: theme.radius.field)
                .overlay {
                    // The focus ring is a 3pt halo outside the border, not a thicker border.
                    if state == .focused {
                        RoundedRectangle(cornerRadius: theme.radius.field + 3, style: .continuous)
                            .strokeBorder(theme.mossEdge.opacity(0.22), lineWidth: 3)
                            .padding(-3)
                    }
                }
            if let help {
                HStack(spacing: 7) {
                    if state == .error {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.emberText)
                    }
                    Text(help)
                        .ffType(.caption)
                        .fontWeight(state == .error ? .heavy : .bold)
                        .foregroundStyle(state == .error ? theme.emberText : theme.textTertiary)
                }
                .padding(.top, 7)
            }
            if let counter {
                Text(counter)
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 7)
            }
        }
    }

    private var labelInk: Color {
        switch state {
        case .error: return theme.emberText
        case .disabled: return theme.textTertiary
        default: return theme.text
        }
    }

    private var fill: Color {
        switch state {
        case .error: return theme.emberFill.opacity(0.12)
        case .disabled: return theme.disabledBg
        default: return theme.card
        }
    }

    private var border: Color {
        switch state {
        case .focused: return theme.mossEdge
        case .error: return theme.emberFill
        case .disabled: return theme.disabledLine
        case .normal: return theme.line
        }
    }
}

struct FFEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.mossText)
                .frame(width: 64, height: 64)
                .background(theme.mossFill.opacity(0.20), in: Circle())
            Text(title)
                .font(.ff(19, 800))
                .tracking(19 * -0.02)
                .foregroundStyle(theme.text)
                .padding(.top, 18)
            Text(message)
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 7)
            if let actionTitle, let action {
                FFButton(title: actionTitle, action: action)
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Navigation

/// Nav header: back and a centred title.
struct FFNavDetail: View {
    let title: String
    var onBack: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let onBack { FFNavGlyph(systemName: "chevron.left", action: onBack) }
            Text(title)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

struct FFNavGlyph: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 38, height: 38)
                .background(theme.control, in: Circle())
                .overlay { Circle().strokeBorder(theme.track, lineWidth: 1) }
        }
        .buttonStyle(FFPressStyle())
    }
}

// MARK: - Pickers

struct FFDurationPicker: View {
    let options: [String]
    @Binding var selection: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .ffType(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(on ? theme.mossOn : theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            on ? theme.mossFill : theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.field)
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }
}
