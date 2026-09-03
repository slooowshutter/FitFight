import SwiftUI
import UIKit

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var confirmDelete = false
    @State private var copied = false

    var body: some View {
        FFScreen {
            profile
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }

            FFSectionHeader(title: "Apple Health").padding(.top, theme.space.lg)
            health

            FFSectionHeader(title: "Settings").padding(.top, theme.space.lg)
            settings

            if AppVersion.exploresNewFightLayouts {
                FFSectionHeader(title: "New fight").padding(.top, theme.space.lg)
                FFGroupedRows {
                    navRow("Try 10 layouts") { model.showingNewFightLayouts = true }
                }
            }

            FFSectionHeader(title: "Look").padding(.top, theme.space.lg)
            appearance
        }
        .task {
            guard !staticRender else { return }
            await steps.refresh(requestAccess: false)
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    let userId = session.authSession?.user.id
                    if await session.deleteAccount(), let userId {
                        model.removeCachedFights(for: userId)
                        if !(await steps.deleteLocalData(userId: userId)) {
                            let cleanupMessage = "Your account was deleted. FitFight will retry removing its local Health cache when you reopen the app."
                            if let authError = session.authError {
                                session.authError = "\(authError) \(cleanupMessage)"
                            } else {
                                session.authError = cleanupMessage
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, uploaded Steps, invitations, and fights you created; removes you from other fights; and signs you out. This can’t be undone.")
        }
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            HStack(spacing: 14) {
                FFAvatar(monogram: session.profile?.initials ?? "FF", size: 68, selected: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.profile?.displayName ?? "Signed in")
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                    Text(session.profile?.atHandle ?? "Profile isn’t ready yet")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if session.profile != nil {
                        Button {
                            UIPasteboard.general.string = session.profile?.atHandle ?? ""
                            copied = true
                        } label: {
                            Text(copied ? "Copied" : "Copy username")
                                .ffType(.micro)
                                .fontWeight(.heavy)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
            }
        } else {
            AppleSignInControl()
        }
    }

    private var health: some View {
        FFGroupedRows {
            Button {
                Task {
                    await steps.refresh(requestAccess: true)
                    if session.authSession != nil {
                        await steps.syncToBackend(session: session)
                    }
                }
            } label: {
                FFGroupedRow(
                    title: "Apple Health Steps",
                    subtitle: steps.metaText.isEmpty
                        ? steps.detailText
                        : "\(steps.detailText) · \(steps.metaText)",
                    systemImage: "heart",
                    subtitleTone: steps.isConnected ? .moss : .neutral,
                    trailing: AnyView(
                        FFPill(
                            steps.isConnected ? "On" : "Connect",
                            style: steps.isConnected ? .softMoss : .solidMoss
                        )
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(steps.status == .reading)
        }
    }

    private var settings: some View {
        FFGroupedRows {
            linkRow("Privacy", destination: siteURL.appending(path: "privacy"))
            FFDivider()
            linkRow("Support", destination: siteURL.appending(path: "support"))
            FFDivider()
            navRow("Versions") { model.showingVersions = true }
            if session.isSignedIn {
                FFDivider()
                navRow("Sign out") {
                    Task { await session.signOut() }
                }
                FFDivider()
                navRow("Delete account", destructive: true) {
                    confirmDelete = true
                }
            }
        }
    }

    private var appearance: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases) { mode in
                let on = themeStore.mode == mode
                Button {
                    themeStore.mode = mode
                } label: {
                    Text(mode.label)
                        .ffType(.label)
                        .foregroundStyle(on ? theme.mossOn : theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            on ? theme.mossFill : theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.field)
                }
                .buttonStyle(FFPressStyle(scale: 0.97))
            }
        }
    }

    private var siteURL: URL {
        URL(string: AppVersion.backend == "prod" ? "https://fitfight.app" : "https://staging.fitfight.app")!
    }

    private func linkRow(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            rowLabel(title: title, destructive: false)
        }
        .buttonStyle(.plain)
    }

    private func navRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(title: title, destructive: destructive)
        }
        .buttonStyle(.plain)
        .disabled(session.isBusy)
    }

    private func rowLabel(title: String, destructive: Bool) -> some View {
        HStack {
            Text(title)
                .ffType(.rowTitle)
                .foregroundStyle(destructive ? theme.emberText : theme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.textFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
