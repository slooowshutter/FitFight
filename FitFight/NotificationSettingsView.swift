import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var push = PushNotificationService.shared
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = FitFightNotificationPreferences()
    @State private var hydrated = false
    @State private var saving = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Notifications")) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if !error.isEmpty {
                        FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    }
                    if push.permissionStatus == .denied {
                        FFNotice(
                            text: String(appLocalized: "iPhone has notifications off for FitFight. Open Settings to allow alerts."),
                            tone: .ember,
                            systemImage: "bell.slash"
                        )
                        FFButton(
                            title: String(appLocalized: "Open Settings"),
                            kind: .ghost,
                            fullWidth: true
                        ) {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                    FFSection(title: String(appLocalized: "Feed")) {
                        FFGroupedRows {
                            toggleRow(
                                title: String(appLocalized: "Fight posts"),
                                subtitle: String(appLocalized: "When someone posts in a fight you’re in."),
                                isOn: $prefs.feedPost
                            )
                            FFDivider()
                            toggleRow(
                                title: String(appLocalized: "Comments on your posts"),
                                subtitle: String(appLocalized: "When someone comments on a post you wrote."),
                                isOn: $prefs.postComment
                            )
                            FFDivider()
                            toggleRow(
                                title: String(appLocalized: "Replies to your comments"),
                                subtitle: String(appLocalized: "When someone replies to a comment you left."),
                                isOn: $prefs.commentReply
                            )
                            FFDivider()
                            toggleRow(
                                title: String(appLocalized: "Reactions on your posts"),
                                subtitle: String(appLocalized: "When someone reacts to a post you wrote."),
                                isOn: $prefs.postReaction
                            )
                        }
                    }
                    FFSection(title: String(appLocalized: "Fights")) {
                        FFGroupedRows {
                            toggleRow(
                                title: String(appLocalized: "Challenge reminders"),
                                subtitle: String(appLocalized: "When a fight ends, when to sync, and when the result is in."),
                                isOn: $prefs.challengeReminder
                            )
                            FFDivider()
                            toggleRow(
                                title: String(appLocalized: "Daily status"),
                                subtitle: String(appLocalized: "A daily update on a live fight."),
                                isOn: $prefs.dailyStatus
                            )
                        }
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
                .disabled(!hydrated || saving)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task {
            await push.refreshAuthorizationStatus()
            await load()
        }
        .onChange(of: prefs) { old, new in
            guard hydrated, !saving, old != new else { return }
            Task { await save(from: old, to: new) }
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        FFGroupedRow(
            title: title,
            subtitle: subtitle,
            subtitleTone: .neutral,
            trailing: AnyView(FFSwitch(isOn: isOn))
        )
    }

    private func load() async {
        guard let token = try? await session.freshAccessToken() else {
            error = String(appLocalized: "Sign in to change notification settings.")
            return
        }
        do {
            prefs = try await FitFightAPI().notificationPreferences(accessToken: token)
            error = ""
            hydrated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(from old: FitFightNotificationPreferences, to new: FitFightNotificationPreferences) async {
        guard let token = try? await session.freshAccessToken() else { return }
        saving = true
        defer { saving = false }
        do {
            prefs = try await FitFightAPI().updateNotificationPreferences(
                FitFightNotificationPreferencesUpdate(
                    feedPost: new.feedPost == old.feedPost ? nil : new.feedPost,
                    postComment: new.postComment == old.postComment ? nil : new.postComment,
                    commentReply: new.commentReply == old.commentReply ? nil : new.commentReply,
                    postReaction: new.postReaction == old.postReaction ? nil : new.postReaction,
                    challengeReminder: new.challengeReminder == old.challengeReminder ? nil : new.challengeReminder,
                    dailyStatus: new.dailyStatus == old.dailyStatus ? nil : new.dailyStatus
                ),
                accessToken: token
            )
            error = ""
        } catch {
            prefs = old
            self.error = error.localizedDescription
        }
    }
}
