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
            RequestsView(store: requests, filter: $model.feedbackRequestFilter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .sheet(isPresented: $composingRequest, onDismiss: {
            Task { await requests.load(session: session, kind: model.feedbackRequestFilter.kind, status: model.feedbackRequestFilter.status.rawValue, sort: model.feedbackRequestFilter.sort.rawValue) }
        }) {
            ComposeRequestView(store: requests, onPosted: {
                model.feedbackRequestFilter.status = .open
                composingRequest = false
            })
            .fitFightTheme(theme)
            .presentationBackground(theme.bg)
        }
    }

    private var hubBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(appLocalized: "Feedback"))
                .ffType(.title)
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            FFComposeButton(label: String(appLocalized: "New request")) { composingRequest = true }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
