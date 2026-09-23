import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var push = PushNotificationService.shared
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffStaticRender) private var staticRender

    @State private var prefs = FitFightNotificationPreferences()
    @State private var hydrated = false
    @State private var saving = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Notifications")) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            if staticRender {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        settingsContent.fixedSize(horizontal: false, vertical: true)
                    }
                    .clipped()
            } else {
                ScrollView { settingsContent }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task {
            guard !staticRender else { return }
            await push.refreshAuthorizationStatus()
            await load()
        }
    }

    private var settingsContent: some View {
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
            FFGroupedRows {
                toggleRow(
                    title: String(appLocalized: "Allow notifications"),
                    subtitle: String(appLocalized: "Turn off every push while keeping your choices below."),
                    isOn: setting(\.enabled)
                )
            }
            Text(String(appLocalized: "Evening summaries arrive around 8 pm in your saved time zone, only when there is new activity. Posts remain in Feed when notifications are off."))
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            FFSection(title: String(appLocalized: "Fights")) {
                FFGroupedRows {
                    toggleRow(
                        title: String(appLocalized: "Fight invitations"),
                        subtitle: String(appLocalized: "When someone invites you to a fight."),
                        isOn: setting(\.fightInvite)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "24-hour ending reminder"),
                        subtitle: String(appLocalized: "Once, one day before a fight ends."),
                        isOn: setting(\.ending24h)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "One-week ending reminder"),
                        subtitle: String(appLocalized: "One week before the end of one-month fights only."),
                        isOn: setting(\.endingWeek)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Fight ended"),
                        subtitle: String(appLocalized: "When the fight closes, before results are confirmed."),
                        isOn: setting(\.fightEnded)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Final sync needed"),
                        subtitle: String(appLocalized: "Once after the end, only if your final steps are missing."),
                        isOn: setting(\.finalSync)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Final results"),
                        subtitle: String(appLocalized: "When the final standings are confirmed."),
                        isOn: setting(\.fightFinalized)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Daily status"),
                        subtitle: String(appLocalized: "A daily update on each live fight."),
                        isOn: setting(\.dailyStatus)
                    )
                }
            }
            .disabled(!prefs.enabled)
            FFSection(title: String(appLocalized: "Feed")) {
                FFGroupedRows {
                    toggleRow(
                        title: String(appLocalized: "Fight posts"),
                        subtitle: String(appLocalized: "New posts are included in one evening summary."),
                        isOn: setting(\.feedPost)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Comments on your posts"),
                        subtitle: String(appLocalized: "When someone comments on a post you wrote."),
                        isOn: setting(\.postComment)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Replies to your comments"),
                        subtitle: String(appLocalized: "When someone replies to a comment you left."),
                        isOn: setting(\.commentReply)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Reactions on your posts"),
                        subtitle: String(appLocalized: "Reactions are combined into one evening summary."),
                        isOn: setting(\.postReaction)
                    )
                    FFDivider()
                    toggleRow(
                        title: String(appLocalized: "Mentions"),
                        subtitle: String(appLocalized: "When someone mentions your username in a post or comment."),
                        isOn: setting(\.mention)
                    )
                }
            }
            .disabled(!prefs.enabled)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 24)
        .disabled((!hydrated && !staticRender) || saving)
    }

    private func setting(_ keyPath: WritableKeyPath<FitFightNotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { value in
                guard hydrated, !saving else { return }
                let old = prefs
                prefs[keyPath: keyPath] = value
                let new = prefs
                saving = true
                Task { await save(from: old, to: new) }
            }
        )
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        FFGroupedRow(
            title: title,
            subtitle: subtitle,
            subtitleTone: .neutral,
            trailing: AnyView(FFSwitch(isOn: isOn))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? String(appLocalized: "Enabled") : String(appLocalized: "Disabled"))
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOn.wrappedValue.toggle() }
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
        defer { saving = false }
        guard let token = try? await session.freshAccessToken() else {
            prefs = old
            error = String(appLocalized: "Sign in to change notification settings.")
            return
        }
        do {
            prefs = try await FitFightAPI().updateNotificationPreferences(
                FitFightNotificationPreferencesUpdate(
                    enabled: new.enabled == old.enabled ? nil : new.enabled,
                    fightInvite: new.fightInvite == old.fightInvite ? nil : new.fightInvite,
                    ending24h: new.ending24h == old.ending24h ? nil : new.ending24h,
                    endingWeek: new.endingWeek == old.endingWeek ? nil : new.endingWeek,
                    fightEnded: new.fightEnded == old.fightEnded ? nil : new.fightEnded,
                    finalSync: new.finalSync == old.finalSync ? nil : new.finalSync,
                    fightFinalized: new.fightFinalized == old.fightFinalized ? nil : new.fightFinalized,
                    mention: new.mention == old.mention ? nil : new.mention,
                    feedPost: new.feedPost == old.feedPost ? nil : new.feedPost,
                    postComment: new.postComment == old.postComment ? nil : new.postComment,
                    commentReply: new.commentReply == old.commentReply ? nil : new.commentReply,
                    postReaction: new.postReaction == old.postReaction ? nil : new.postReaction,
                    dailyStatus: new.dailyStatus == old.dailyStatus ? nil : new.dailyStatus
                ),
                accessToken: token
            )
            error = ""
            if !old.enabled && new.enabled && push.permissionStatus == .notDetermined {
                await push.requestSystemPermission()
            }
        } catch {
            prefs = old
            self.error = error.localizedDescription
        }
    }
}
