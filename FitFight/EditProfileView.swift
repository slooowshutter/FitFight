import PhotosUI
import SwiftUI
import UIKit

struct EditProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var settings: SharedProfileSettings?
    @State private var displayName = ""
    @State private var handle = ""
    @State private var timeZone = TimeZone.current
    @State private var error: String?
    @State private var saving = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCompanions = false
    @State private var showingPhotos = false
    @State private var previewAudience = "stranger"
    @State private var showingPreview = false
    @FocusState private var displayNameFocused: Bool
    @FocusState private var handleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Edit profile"), role: .heading) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if let error { FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle") }
                    if settings == nil {
                        if error == nil { ProgressView() }
                        else { FFButton(title: String(appLocalized: "Retry"), kind: .secondary) { Task { await load() } } }
                    } else {
                        // Your companion is your profile picture; a photo is the alternative behind the same button.
                        VStack(spacing: 10) {
                            CompanionAvatar(
                                personID: session.profile?.userId.uuidString, companionID: session.profile?.companionId, isYou: true,
                                monogram: session.profile?.initials ?? "FF", photoURL: session.profile?.photoURL, size: 104
                            )
                            Menu {
                                Button(String(appLocalized: "Choose your companion")) { showingCompanions = true }
                                Button(String(appLocalized: "Use a photo")) { showingPhotos = true }
                            } label: {
                                Text(String(appLocalized: "Change picture")).ffType(.label).foregroundStyle(theme.mossText).frame(minHeight: 44)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        FFCard {
                            VStack(alignment: .leading, spacing: 16) {
                                field(String(appLocalized: "Name")) {
                                    TextField(String(appLocalized: "Display name"), text: $displayName)
                                        .textContentType(.name)
                                        .focused($displayNameFocused)
                                }
                                field(String(appLocalized: "Username")) {
                                    HStack(spacing: 2) {
                                        Text(verbatim: "@").foregroundStyle(theme.textSecondary)
                                        TextField(String(appLocalized: "Username"), text: $handle)
                                            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                                            .focused($handleFocused)
                                    }
                                }
                                FFDivider()
                                FitFightTimeZonePicker(selection: $timeZone)
                                Text(String(appLocalized: "Your daily Steps and new Fights use this time zone, even when you travel."))
                                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                            }.ffType(.body)
                        }
                        FFSection(title: String(appLocalized: "Profile visibility")) {
                            FFCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    Toggle(String(appLocalized: "Competitive"), isOn: Binding(
                                        get: { settings?.competitive == true },
                                        set: { settings?.competitive = $0 }
                                    ))
                                    Text(String(appLocalized: "Show your competitive record and rivalry scores. Turning this off never erases results."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Toggle(String(appLocalized: "Public profile"), isOn: Binding(
                                        get: { settings?.audience == "public" },
                                        set: {
                                            settings?.audience = $0 ? "public" : "private"
                                            if !$0 && settings?.activityAudience == "public" { settings?.activityAudience = "off" }
                                        }
                                    ))
                                    Text(String(appLocalized: "Public means all signed-in FitFight users. Private means friends and current opponents. Your name and companion remain identifiable."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                }.ffType(.body).tint(theme.mossFill)
                            }
                        }
                        FFSection(title: String(appLocalized: "Share Steps history")) {
                            FFCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(String(appLocalized: "Optional. Choose who can see your stored daily Steps and for how long. Fight participation shares its own results separately."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Text(String(appLocalized: "This also shares step records, averages, activity levels and streaks for that period. Your full recorded history stays private."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Picker(String(appLocalized: "Audience"), selection: Binding(
                                        get: { settings?.activityAudience ?? "off" }, set: { settings?.activityAudience = $0 }
                                    )) {
                                        Text(String(appLocalized: "Off")).tag("off")
                                        Text(String(appLocalized: "Friends")).tag("friends")
                                        Text(String(appLocalized: "Friends and current opponents")).tag("opponents")
                                        if settings?.audience == "public" { Text(String(appLocalized: "All signed-in users")).tag("public") }
                                    }
                                    Picker(String(appLocalized: "Period"), selection: Binding(
                                        get: { settings?.activityDays ?? 7 }, set: { settings?.activityDays = $0 }
                                    )) {
                                        Text(String(appLocalized: "7 days")).tag(7)
                                        Text(String(appLocalized: "30 days")).tag(30)
                                    }.pickerStyle(.segmented)
                                }.ffType(.body)
                            }
                        }
                        FFButton(title: String(appLocalized: "Save"), busy: saving, fullWidth: true) { Task { await save(close: true) } }
                        FFCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker(String(appLocalized: "Preview audience"), selection: $previewAudience) {
                                    Text(String(appLocalized: "Friend")).tag("friend")
                                    Text(String(appLocalized: "Current opponent")).tag("opponent")
                                    Text(String(appLocalized: "Past opponent")).tag("past_opponent")
                                    Text(String(appLocalized: "Other signed-in user")).tag("stranger")
                                }.ffType(.body)
                                FFButton(title: String(appLocalized: "Save and preview"), kind: .secondary, busy: saving) {
                                    Task { if await save(close: false) { showingPreview = true } }
                                }
                            }
                        }
                    }
                }
                .padding(theme.space.screenPadding)
                .ffKeyboardDismissOnBackgroundTap()
                .disabled(saving)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(theme.text)
        .ffKeyboardDismissOnBackgroundTap()
        .background(theme.bg.ignoresSafeArea())
        .task { await load() }
        .onChange(of: session.authSession?.user.id) { _, _ in settings = nil; dismiss() }
        .onChange(of: pickerItem) { _, item in Task { await uploadPhoto(item) } }
        .photosPicker(isPresented: $showingPhotos, selection: $pickerItem, matching: .images)
        .sheet(isPresented: $showingCompanions) {
            CompanionPicker(selection: companions.selection, required: false, isCustom: companions.isCustom, prompt: companions.customPrompt)
                .fitFightTheme(theme).presentationBackground(theme.bg)
        }
        .sheet(isPresented: $showingPreview) {
            if let userID = session.authSession?.user.id {
                ProfileSheet(userID: userID, source: "friends", preview: previewAudience)
                    .fitFightTheme(theme).presentationBackground(theme.bg)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
            content()
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(theme.control, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        }
    }

    private func load() async {
        let accountID = session.authSession?.user.id
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            settings = try? JSONDecoder().decode(SharedProfileSettings.self, from: Data(#"{"competitive": true, "audience": "private", "activity_audience": "friends", "activity_days": 30, "artwork_allowed": true, "revision": 1}"#.utf8))
            displayName = session.profile?.displayName ?? ""
            handle = session.profile?.handle ?? ""
            return
        }
        #endif
        do {
            let token = try await session.freshAccessToken()
            let loaded = try await FitFightAPI().profileSettings(accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            settings = loaded
            displayName = session.profile?.displayName ?? ""
            handle = session.profile?.handle ?? ""
            timeZone = session.profile?.calendarTimeZone ?? .current
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    private func save(close: Bool) async -> Bool {
        guard let settings, !saving else { return false }
        let accountID = session.authSession?.user.id
        saving = true
        defer { saving = false }
        do {
            if displayName != session.profile?.displayName || handle != session.profile?.handle || timeZone.identifier != session.profile?.timeZone {
                try await session.updateIdentity(displayName: displayName, handle: handle, timeZone: timeZone)
            }
            let token = try await session.freshAccessToken()
            let saved = try await FitFightAPI().updateProfileSettings(settings, accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return false }
            self.settings = saved
            error = nil
            if close { dismiss() }
            return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, !saving else { return }
        saving = true
        defer { saving = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = String(appLocalized: "That photo could not be read.")
                return
            }
            let media = try await MediaUploader.upload(image, purpose: "profile", session: session)
            try await session.setAvatar(media)
        } catch { self.error = error.localizedDescription }
    }
}
