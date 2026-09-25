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
            if let postID = requests.openDetailID,
               let post = requests.detail?.id == postID ? requests.detail : requests.posts.first(where: { $0.id == postID }),
               !post.mine || requests.canDelete || requests.canArchive {
                RequestPostMenu(
                    canReport: !post.mine,
                    onReport: {
                        Task { await requests.report(session: session, post: post) }
                    },
                    onHide: { requests.menuAction = .hide },
                    onDelete: requests.canDelete ? { requests.menuAction = .delete } : nil,
                    onArchive: requests.canArchive ? { requests.menuAction = .archive } : nil,
                    archived: post.archived
                )
                .disabled(requests.isDeleting || requests.isArchiving || requests.isSaving || requests.isLaunchingFix)
            }
            FFComposeButton(label: String(appLocalized: "New request")) { composingRequest = true }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
