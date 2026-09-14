import SwiftUI

/// Marc-only playground for Slide to start vibrations. Hidden from every other account.
struct SlideHapticsLabView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FFSlideHapticRecipe.storageKey) private var selectedRecipeID = FFSlideHapticRecipe.shippedID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Slide haptics"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            Text(String(localized: "Only on your account. Intensity is strength. Sharpness is crisp versus dull. Ticks follow the track or a clock. Rumble is a continuous buzz. Use on Slide to start puts that recipe on New fight on this phone."))
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(FFSlideHapticRecipe.all) { recipe in
                        recipeCard(recipe)
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func recipeCard(_ recipe: FFSlideHapticRecipe) -> some View {
        let selected = recipe.id == selectedRecipeID
        return FFCard(padding: 16, stroke: selected ? theme.mossEdge : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: recipe.name)
                        .ffType(.heading)
                        .foregroundStyle(selected ? theme.mossText : theme.text)
                    if recipe.id == FFSlideHapticRecipe.shippedID {
                        FFPill(String(localized: "default"))
                    }
                    if selected {
                        FFPill(String(localized: "on Slide to start"))
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: recipe.summary)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FFSlideToConfirm(
                    title: String(localized: "Slide to test"),
                    recipe: recipe,
                    resetsAfterSuccess: true
                ) {
                    true
                }
                if !selected {
                    FFButton(title: String(localized: "Use on Slide to start"), kind: .ghost, size: .small) {
                        selectedRecipeID = recipe.id
                    }
                }
            }
        }
        .background(
            selected ? theme.mossWash : .clear,
            in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        )
    }
}
