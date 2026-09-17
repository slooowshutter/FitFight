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
    @State private var error: String?
    @State private var saving = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCompanions = false
    @State private var previewAudience = "stranger"
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Edit profile")).ffType(.heading)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.ffType(.label).frame(minHeight: 44)
            }.padding(.horizontal, theme.space.screenPadding).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if let error { FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle") }
                    if settings == nil {
                        if error == nil { ProgressView() }
                        else { FFButton(title: String(localized: "Retry"), kind: .secondary) { Task { await load() } } }
                    } else {
                        FFCard {
                            VStack(alignment: .leading, spacing: 16) {
                                TextField(String(localized: "Display name"), text: $displayName).textContentType(.name)
                                TextField(String(localized: "Username"), text: $handle)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                                PhotosPicker(selection: $pickerItem, matching: .images) {
                                    Text(String(localized: "Change profile photo"))
                                }.frame(minHeight: 44)
                                Button(String(localized: "Choose your companion")) { showingCompanions = true }.frame(minHeight: 44)
                            }.ffType(.body)
                        }
                        FFSection(title: String(localized: "Profile visibility")) {
                            FFCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    Toggle(String(localized: "Competitive"), isOn: Binding(
                                        get: { settings?.competitive == true },
                                        set: { settings?.competitive = $0 }
                                    ))
                                    Text(String(localized: "Show your competitive record and rivalry scores. Turning this off never erases results."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Toggle(String(localized: "Public profile"), isOn: Binding(
                                        get: { settings?.audience == "public" },
                                        set: {
                                            settings?.audience = $0 ? "public" : "private"
                                            if !$0 && settings?.activityAudience == "public" { settings?.activityAudience = "off" }
                                        }
                                    ))
                                    Text(String(localized: "Public means all signed-in FitFight users. Private means friends and current opponents. Your name and companion remain identifiable."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                }.ffType(.body).tint(theme.mossFill)
                            }
                        }
                        FFSection(title: String(localized: "Share Steps history")) {
                            FFCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(String(localized: "Optional. Choose who can see your stored daily Steps and for how long. Fight participation shares its own results separately."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Text(String(localized: "This also shares step records, averages, activity levels and streaks for that period. Your full recorded history stays private."))
                                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                                    Picker(String(localized: "Audience"), selection: Binding(
                                        get: { settings?.activityAudience ?? "off" }, set: { settings?.activityAudience = $0 }
                                    )) {
                                        Text(String(localized: "Off")).tag("off")
                                        Text(String(localized: "Friends")).tag("friends")
                                        Text(String(localized: "Friends and current opponents")).tag("opponents")
                                        if settings?.audience == "public" { Text(String(localized: "All signed-in users")).tag("public") }
                                    }
                                    Picker(String(localized: "Period"), selection: Binding(
                                        get: { settings?.activityDays ?? 7 }, set: { settings?.activityDays = $0 }
                                    )) {
                                        Text(String(localized: "7 days")).tag(7)
                                        Text(String(localized: "30 days")).tag(30)
                                    }.pickerStyle(.segmented)
                                }.ffType(.body)
                            }
                        }
                        FFButton(title: String(localized: "Save"), busy: saving, fullWidth: true) { Task { await save(close: true) } }
                        FFCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker(String(localized: "Preview audience"), selection: $previewAudience) {
                                    Text(String(localized: "Friend")).tag("friend")
                                    Text(String(localized: "Current opponent")).tag("opponent")
                                    Text(String(localized: "Past opponent")).tag("past_opponent")
                                    Text(String(localized: "Other signed-in user")).tag("stranger")
                                }.ffType(.body)
                                FFButton(title: String(localized: "Save and preview"), kind: .secondary, busy: saving) {
                                    Task { if await save(close: false) { showingPreview = true } }
                                }
                            }
                        }
                    }
                }.padding(theme.space.screenPadding).disabled(saving)
            }
        }
        .foregroundStyle(theme.text).background(theme.bg.ignoresSafeArea())
        .task { await load() }
        .onChange(of: session.authSession?.user.id) { _, _ in settings = nil; dismiss() }
        .onChange(of: pickerItem) { _, item in Task { await uploadPhoto(item) } }
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

    private func load() async {
        let accountID = session.authSession?.user.id
        do {
            let token = try await session.freshAccessToken()
            let loaded = try await FitFightAPI().profileSettings(accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            settings = loaded
            displayName = session.profile?.displayName ?? ""
            handle = session.profile?.handle ?? ""
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
            if displayName != session.profile?.displayName || handle != session.profile?.handle {
                try await session.updateIdentity(displayName: displayName, handle: handle)
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
                error = String(localized: "That photo could not be read.")
                return
            }
            let media = try await MediaUploader.upload(image, purpose: "profile", session: session)
            try await session.setAvatar(media)
        } catch { self.error = error.localizedDescription }
    }
}
