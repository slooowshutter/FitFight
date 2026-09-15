import SwiftUI

enum FeedbackPane: Hashable, CaseIterable {
    case feed, bugs, top, report

    var title: String {
        switch self {
        case .feed: return String(localized: "Feed")
        case .bugs: return String(localized: "Bugs")
        case .top: return String(localized: "Top")
        case .report: return String(localized: "Report")
        }
    }
}

struct FeedbackTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var requests = FeedbackStore()
    @State private var composingPost = false

    var body: some View {
        VStack(spacing: 0) {
            hubBar
            ZStack {
                switch model.feedbackPane {
                case .feed:
                    FeedView(showsChrome: false)
                case .bugs:
                    RequestsView(
                        store: requests,
                        chrome: .tab,
                        filter: $model.feedbackRequestFilter,
                        onCompose: { model.feedbackPane = .report }
                    )
                case .top:
                    RequestsView(
                        store: requests,
                        chrome: .tab,
                        lockedFilter: .top,
                        onCompose: { model.feedbackPane = .report }
                    )
                case .report:
                    Color.clear
                }
                ComposeRequestView(
                    store: requests,
                    heading: String(localized: "Report"),
                    embedded: true,
                    onPosted: { filter in
                        model.feedbackRequestFilter = filter
                        model.feedbackPane = .bugs
                    }
                )
                .environmentObject(session)
                .opacity(model.feedbackPane == .report ? 1 : 0)
                .allowsHitTesting(model.feedbackPane == .report)
                .accessibilityHidden(model.feedbackPane != .report)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .sheet(isPresented: $composingPost) {
            FeedComposeSheet()
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(feed)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var hubBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Feedback"))
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                    Text(String(localized: "Posts, bugs, and reports."))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                composeMenu
            }
            FFTabs(items: FeedbackPane.allCases, selection: $model.feedbackPane) { pane in
                pane.title
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var composeMenu: some View {
        Menu {
            Button {
                composingPost = true
            } label: {
                Label(String(localized: "New post"), systemImage: "square.and.pencil")
            }
            Button {
                model.feedbackPane = .report
            } label: {
                Label(String(localized: "New request"), systemImage: "bubble.left.and.bubble.right")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.mossOn)
                .frame(width: 36, height: 36)
                .background(theme.mossFill, in: Circle())
        }
        .menuOrder(.fixed)
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "New post"))
    }
}
