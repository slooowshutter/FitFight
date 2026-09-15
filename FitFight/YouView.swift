import PhotosUI
import SwiftUI
import UIKit

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var photoError = ""
    @State private var showingOnboardingPreview = false
    @State private var showingSlideHapticsLab = false
    @State private var showingHealthDetails = false
    @State private var showingCompanionPreviewControls = false

    var body: some View {
        FFScreen(refresh: fightsRefresh) {
            profile
            CompanionIntroduction(surface: .you)
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled {
                Text("Companion design preview · this session only")
                    .ffType(.micro)
                    .foregroundStyle(theme.textSecondary)
            }
            #endif
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if !photoError.isEmpty {
                FFNotice(text: photoError, tone: .ember, systemImage: "exclamationmark.triangle")
            }

            FFSection(title: String(localized: "Apple Health")) {
                health
            }

            FFSection(title: String(localized: "Bugs & requests")) {
                requests
            }

            FFSection(title: String(localized: "Settings")) {
                settings
            }

            FFSection(title: String(localized: "Look")) {
                appearance
            }

            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled {
                FFButton(title: String(localized: "Companion preview"), kind: .ghost, fullWidth: true) {
                    showingCompanionPreviewControls = true
                }
                .sheet(isPresented: $showingCompanionPreviewControls) {
                    CompanionPreviewControls()
                        .fitFightTheme(themeStore.theme)
                        .presentationBackground(themeStore.theme.bg)
                }
            }
            #endif

            if session.isFitFightAdmin {
                FFSection(title: String(localized: "Developer")) {
                    developer
                }
            }
        }
        .task {
            guard !staticRender else { return }
            await model.refreshFights(session: session, steps: steps)
        }
        .sheet(isPresented: $showingOnboardingPreview) {
            OnboardingPreviewView()
                .environmentObject(session)
                .environmentObject(steps)
                .environmentObject(themeStore)
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $showingSlideHapticsLab) {
            SlideHapticsLabView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
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
                            let cleanupMessage = String(localized: "Your account was deleted. FitFight will retry removing its local Health cache when you reopen the app.")
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
            Text("This permanently deletes your profile, photos, uploaded Steps, referrals, invitations, fights you created, and bugs or requests you posted; removes you from other fights; and signs you out. This can’t be undone.")
        }
    }

    private var fightsRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            action: {
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
            }
        )
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            HStack(spacing: 14) {
                if companions.animal(for: session.profile?.userId.uuidString, companionID: session.profile?.companionId, isYou: true) != nil {
                    Button { companions.showingPicker = true } label: {
                        CompanionAvatar(
                            personID: session.profile?.userId.uuidString,
                            companionID: session.profile?.companionId,
                            isYou: true,
                            monogram: session.profile?.initials ?? "FF",
                            size: 68
                        )
                            .overlay { Circle().strokeBorder(theme.mossEdge, lineWidth: 3) }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(String(localized: "Choose your companion"))
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        FFAvatar(
                            monogram: session.profile?.initials ?? "FF",
                            size: 68,
                            selected: true,
                            photoURL: session.profile?.avatar?.url
                        )
                        .overlay {
                            if isUploadingPhoto {
                                ZStack {
                                    Circle().fill(theme.bg.opacity(0.45))
                                    ProgressView().tint(theme.text)
                                }
                            }
                        }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(isUploadingPhoto)
                    .onChange(of: pickerItem) { _, item in
                        Task { await uploadPhoto(item) }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: session.profile?.displayName ?? String(localized: "Signed in"))
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                    Text(verbatim: session.profile?.atHandle ?? String(localized: "Profile isn’t ready yet"))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if session.profile != nil {
                        Button {
                            UIPasteboard.general.string = session.profile?.atHandle ?? ""
                            copied = true
                        } label: {
                            Text(copied ? String(localized: "Copied") : String(localized: "Copy username"))
                                .ffType(.micro)
                                .fontWeight(.heavy)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
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
                    await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: !steps.hasAsked)
                }
            } label: {
                FFGroupedRow(
                    title: String(localized: "Apple Health Steps"),
                    subtitle: steps.connection == .upToDate ? String(localized: "Up to date") : steps.detailText,
                    systemImage: "heart",
                    enabled: steps.status != .reading && !model.isRefreshingFights,
                    subtitleTone: healthSubtitleTone,
                    trailing: AnyView(healthPill)
                )
            }
            .buttonStyle(FFHapticPlainStyle())
            .disabled(steps.status == .reading || model.isRefreshingFights)
            FFDivider()
            FFGroupedRow(
                title: showingHealthDetails ? String(localized: "Fewer settings") : String(localized: "More settings"),
                systemImage: "slider.horizontal.3",
                trailing: AnyView(
                    Image(systemName: showingHealthDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                ),
                action: { showingHealthDetails.toggle() }
            )
            if showingHealthDetails {
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Request Health access"),
                    subtitle: String(localized: "Ask for access to Health types you haven’t reviewed yet. Fights use Steps only."),
                    systemImage: "heart.circle",
                    enabled: steps.status != .reading && !model.isRefreshingFights,
                    subtitleTone: .neutral,
                    trailing: AnyView(
                        FFPill(String(localized: "Review"), style: .softMoss)
                    ),
                    action: {
                        Task {
                            await model.refreshFights(
                                session: session,
                                steps: steps,
                                trigger: .manual,
                                requestAccess: true
                            )
                        }
                    }
                )
                .disabled(steps.status == .reading || model.isRefreshingFights)
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Change Health permissions"),
                    subtitle: String(localized: "In Health, tap your profile → Apps → FitFight to turn each type of access on or off."),
                    systemImage: "hand.raised",
                    subtitleTone: .neutral
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Background App Refresh"),
                    subtitle: steps.backgroundRefreshText,
                    systemImage: "arrow.clockwise",
                    subtitleTone: steps.diagnostics.backgroundRefreshStatus == .available ? .moss : .neutral,
                    trailing: steps.diagnostics.backgroundRefreshStatus == .denied
                        ? AnyView(FFPill(String(localized: "Open Settings"), style: .softMoss)) : nil,
                    action: steps.diagnostics.backgroundRefreshStatus == .denied
                        ? { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        : nil
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "HealthKit background delivery"),
                    subtitle: steps.backgroundDeliveryText,
                    systemImage: "heart.text.square",
                    subtitleTone: steps.diagnostics.deliveryRegistrationStatus == .enabled ? .moss : .neutral
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Last automatic sync"),
                    subtitle: diagnosticDate(steps.diagnostics.lastAutomaticSync),
                    systemImage: "bolt"
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Last manual or foreground sync"),
                    subtitle: diagnosticDate(steps.diagnostics.lastManualSync),
                    systemImage: "hand.tap"
                )
                if let failure = steps.currentFailureText {
                    FFDivider()
                    FFGroupedRow(
                        title: String(localized: "Current sync issue"),
                        subtitle: failure,
                        systemImage: "exclamationmark.triangle",
                        subtitleTone: .ember
                    )
                }
                if let reference = steps.diagnostics.failureReference {
                    FFDivider()
                    FFGroupedRow(
                        title: String(localized: "Sync error reference"),
                        subtitle: reference,
                        systemImage: "number",
                        subtitleTone: .neutral
                    )
                }
            }
        }
    }

    private var healthSubtitleTone: FFTone {
        switch steps.connection {
        case .syncFailed, .noAccessibleSteps: return .ember
        case .upToDate: return .moss
        case .syncing, .notConnected: return .neutral
        }
    }

    private var healthPill: FFPill {
        switch steps.connection {
        case .syncFailed:
            return FFPill(String(localized: "Retry"), style: .softEmber)
        case .syncing:
            return FFPill(String(localized: "Syncing"), style: .neutral)
        case .upToDate, .noAccessibleSteps:
            return FFPill(String(localized: "Connected"), style: .softMoss)
        case .notConnected:
            return FFPill(String(localized: "Connect"), style: .solidMoss)
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        defer { pickerItem = nil }
        guard let item else { return }
        guard !CompanionPreview.isEnabled else { photoError = CompanionPreview.writeUnavailable; return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            photoError = String(localized: "That photo could not be read.")
            return
        }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let media = try await MediaUploader.upload(image, purpose: "profile", session: session)
            try await session.setAvatar(media)
            photoError = ""
        } catch {
            photoError = error.localizedDescription
        }
    }

    private func diagnosticDate(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not yet") }
        return date.formatted(.relative(presentation: .named))
    }

    private var requests: some View {
        FFGroupedRows {
            FFGroupedRow(
                title: String(localized: "Bugs & requests"),
                subtitle: String(localized: "Post a bug or a feature request. Other people can upvote and comment with their username."),
                systemImage: "bubble.left.and.bubble.right",
                trailing: AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                ),
                action: {
                    model.feedbackPane = .bugs
                    model.tab = .feedback
                }
            )
            .disabled(session.isBusy)
        }
    }

    private var settings: some View {
        FFGroupedRows {
            if let code = session.profile?.referralCode {
                ShareLink(item: APIConfig.publicOrigin.appending(path: "r/\(code.uuidString.lowercased())")) {
                    rowLabel(title: String(localized: "Refer a friend"), destructive: false)
                }
                .buttonStyle(FFHapticPlainStyle())
                FFDivider()
            }
            linkRow(String(localized: "Privacy"), destination: sitePage("privacy"))
            FFDivider()
            linkRow(String(localized: "Support"), destination: sitePage("support"))
            FFDivider()
            navRow(String(localized: "Versions")) { model.showingVersions = true }
            if session.isSignedIn {
                FFDivider()
                navRow(String(localized: "Sign out")) {
                    Task { await session.signOut() }
                }
                FFDivider()
                navRow(String(localized: "Delete account"), destructive: true) {
                    confirmDelete = true
                }
            }
        }
    }

    private var developer: some View {
        FFGroupedRows {
            FFGroupedRow(
                title: String(localized: "Replay onboarding"),
                subtitle: String(localized: "Health, challenge reminders, and Bugs & requests. Your account and fights stay."),
                systemImage: "arrow.counterclockwise",
                subtitleTone: .neutral,
                trailing: AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                ),
                action: { showingOnboardingPreview = true }
            )
            FFDivider()
            FFGroupedRow(
                title: "Slide haptics",
                subtitle: "Twenty Slide to start vibrations. This page is only on your account.",
                systemImage: "iphone.radiowaves.left.and.right",
                subtitleTone: .neutral,
                trailing: AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                ),
                action: { showingSlideHapticsLab = true }
            )
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

    private func sitePage(_ path: String) -> URL {
        let root = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
            ? siteURL.appending(path: "fr")
            : siteURL
        return root.appending(path: path)
    }

    private func linkRow(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            rowLabel(title: title, destructive: false)
        }
        .buttonStyle(FFHapticPlainStyle())
    }

    private func navRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(title: title, destructive: destructive)
        }
        .buttonStyle(FFHapticPlainStyle())
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
