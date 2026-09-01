import SwiftUI

/// First-run handle after Apple sign-in. People challenge you with this name.
struct OnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    @State private var handle = ""
    @State private var error = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Pick a username")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("People challenge you with this. Letters, numbers, underscore. 2–30 characters.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            FFField(
                label: "Username",
                state: fieldState,
                help: error.isEmpty ? nil : error
            ) {
                TextField("username", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focused)
            }
            .padding(.top, 28)
            FFScreenCTA(title: isSaving ? "Saving…" : "Continue", enabled: canSave) {
                Task { await save() }
            }
            .padding(.top, 20)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }

    private var fieldState: FFFieldState {
        if !error.isEmpty { return .error }
        return focused ? .focused : .normal
    }

    private var canSave: Bool {
        !isSaving && SessionStore.isValidHandle(handle)
    }

    private func save() async {
        error = ""
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.setHandle(handle)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
