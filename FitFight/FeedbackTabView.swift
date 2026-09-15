import SwiftUI

struct FeedbackTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var requests = FeedbackStore()
    @State private var composingRequest = false

    var body: some View {
        VStack(spacing: 0) {
            hubBar
            RequestsView(
                store: requests,
                chrome: .tab,
                filter: $model.feedbackRequestFilter,
                onCompose: { composingRequest = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .sheet(isPresented: $composingRequest, onDismiss: {
            Task { await requests.load(session: session, kind: model.feedbackRequestFilter.kind) }
        }) {
            ComposeRequestView(store: requests, onPosted: { filter in
                model.feedbackRequestFilter = filter
                composingRequest = false
            })
            .environmentObject(session)
            .fitFightTheme(theme)
            .presentationBackground(theme.bg)
        }
    }

    private var hubBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(localized: "Feedback"))
                .ffType(.title)
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            composeButton
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var composeButton: some View {
        Button {
            composingRequest = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.mossOn)
                .frame(width: 36, height: 36)
                .background(theme.mossFill, in: Circle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "New request"))
    }
}
