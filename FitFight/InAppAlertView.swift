import SwiftUI

/// One in-app alert as a centered dialog over the dimmed app. Tapping outside it closes it.
struct InAppAlertView: View {
    let inAppAlert: InAppAlert
    let onChoose: (InAppAlert.Choice) -> Void
    let onDismiss: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        ZStack {
            theme.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if let url = inAppAlert.imageURL {
                    // Companion art stands free: no box behind it, even while it loads.
                    RemotePhoto(url: url) { Color.clear }
                        .frame(width: 132, height: 150)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)
                }
                Text(inAppAlert.title)
                    .font(.ff(22, 800))
                    .tracking(22 * -0.015)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(inAppAlert.body)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                VStack(spacing: 10) {
                    ForEach(Array(inAppAlert.buttons.enumerated()), id: \.offset) { _, choice in
                        FFButton(title: choice.title, kind: choice.primary ? .primary : .secondary, fullWidth: true) {
                            onChoose(choice)
                        }
                    }
                }
                .padding(.top, 22)
            }
            .padding(24)
            .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.overlayLine, radius: theme.radius.card)
            .padding(.horizontal, theme.space.screenPadding)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onDismiss)
        }
        .accessibilityIdentifier("in-app-alert")
    }
}
