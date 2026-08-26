import SwiftUI

/// First-run handle after Apple sign-in. Friends add you with this name.
struct OnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var handle = ""
    @State private var error = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Pick a username")
                .font(theme.font(.display))
                .foregroundStyle(theme.text)
            Text("Friends add you with this. Letters, numbers, underscore. 2–30 characters.")
                .font(.ff(15))
                .foregroundStyle(theme.muted)
                .padding(.top, 10)
            TextField("username", text: $handle)
                .font(.ff(17, .semibold))
                .foregroundStyle(theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                        .strokeBorder(theme.line, lineWidth: 1)
                }
                .padding(.top, 28)
            if !error.isEmpty {
                Text(error)
                    .font(.ff(11))
                    .foregroundStyle(theme.red)
                    .padding(.top, 10)
            }
            FFButton(title: isSaving ? "Saving…" : "Continue", enabled: canSave) {
                Task { await save() }
            }
            .padding(.top, 20)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
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
            await steps.connectAndSync(
                client: session.client,
                userId: session.authSession?.user.id
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
