import SwiftUI

struct FightPostEngagement: View {
    let post: FitFightFightPost
    var targetCommentID: UUID? = nil
    var onTargetCommentLoaded: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var comments: [FitFightFightPostComment] = []
    @State private var nextCursor: String?
    @State private var commentSort = FightPostCommentSort.comments
    @State private var loadedCommentSort = FightPostCommentSort.comments
    @State private var loadedCommentPages = 0
    @State private var open = false
    @State private var showingReactions = false
    @State private var showingCustomEmoji = false
    @State private var replyTo: FitFightFightPostComment?
    @State private var draft = ""
    @State private var mentionPeople: [FitFightFightPost.Author] = []
    @State private var customEmoji = ""
    @State private var loading = false
    @State private var loadingComments = false
    @State private var reloadComments = false
    @State private var commentsVersion = 0
    @State private var didRevealTarget = false

    private let quickEmoji = ["🔥", "💪", "😂", "❤️", "👏", "😮"]
