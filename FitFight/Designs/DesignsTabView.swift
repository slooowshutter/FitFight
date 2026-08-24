import SwiftUI
import UIKit

/// The Design tab: every direction rendered live, at the same moment, from the
/// same data. One tap swaps the whole app over — no sheet, no confirm, no nesting.
struct DesignsTabView: View {
    @EnvironmentObject private var designStore: DesignStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(DesignVariant.allCases) { variant in
                        DesignTile(
                            variant: variant,
                            active: designStore.variant == variant,
                            width: tileWidth
                        ) {
                            select(variant)
                        }
                    }
                }
                .padding(.top, 18)

                Text("Every design shows the same fights, the same names and the same money. Only the look changes. The Fights tab uses whichever one is ticked; the other tabs keep its colours.")
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg)
    }

    /// 393pt screen, 16pt gutters, 10pt between columns.
    private var tileWidth: CGFloat {
        (UIScreen.main.bounds.width - 32 - 10) / 2
    }

    private func select(_ variant: DesignVariant) {
        guard designStore.variant != variant else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.18)) {
            designStore.variant = variant
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Designs")
                .font(.ff(26, .bold))
                .foregroundStyle(theme.text)
            HStack(spacing: 5) {
                Text("Tap one. Currently")
                    .font(.ff(13))
                    .foregroundStyle(theme.faint)
                Text(designStore.variant.title)
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.top, 4)
    }
}

private struct DesignTile: View {
    let variant: DesignVariant
    let active: Bool
    let width: CGFloat
    let action: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        // Not a Button. Each preview is a full Fights screen full of Buttons;
        // iOS then treats the outer Button as nested and drops the tap. The
        // scaled preview also keeps a phone-sized hit box, so the first tile
        // can swallow the rest of the grid. A transparent overlay on the
        // *layout* size is the tap target instead.
        VStack(alignment: .leading, spacing: 8) {
            DesignPreview(variant: variant, width: width)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(active ? theme.accent : theme.line, lineWidth: active ? 2 : 1)
                }

            HStack(spacing: 5) {
                Text(variant.title)
                    .font(.ff(13, .bold))
                    .foregroundStyle(theme.text)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                }
                Spacer(minLength: 0)
                swatches
            }

            Text(variant.blurb)
                .font(.ff(10.5))
                .foregroundStyle(theme.faint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .onTapGesture(perform: action)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityLabel("\(variant.title) design\(active ? ", selected" : "")")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// Background, surface and accent — enough to read the palette at a glance.
    private var swatches: some View {
        let skin = variant.theme(themeStore.theme)
        return HStack(spacing: -3) {
            ForEach(Array([skin.bg, skin.surface, skin.accent].enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().strokeBorder(theme.line, lineWidth: 0.5) }
            }
        }
    }
}

/// A whole Fights screen, rendered small. `ffStaticRender` swaps the scroll view
/// for a plain stack — a nested ScrollView renders blank at this size.
private struct DesignPreview: View {
    let variant: DesignVariant
    let width: CGFloat

    @EnvironmentObject private var themeStore: ThemeStore

    private static let source = CGSize(width: 393, height: 620)

    var body: some View {
        let scale = width / Self.source.width
        let skin = variant.theme(themeStore.theme)
        return variant.fightsScreen
            .environment(\.ffStaticRender, true)
            .ffThemeOnly(skin)
            .frame(width: Self.source.width, height: Self.source.height, alignment: .top)
            .background(skin.bg)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: Self.source.height * scale, alignment: .topLeading)
            .clipped()
            .contentShape(.interaction, Rectangle())
            .allowsHitTesting(false)
    }
}
