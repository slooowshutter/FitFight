import AppKit
import Combine
import SwiftUI

struct PreferencesViewTestUser { let id: UUID }
struct PreferencesViewTestSession { let user: PreferencesViewTestUser }
enum AppVersion { static let backend = "test" }

@MainActor
final class SessionStore: ObservableObject {
    @Published var authSession: PreferencesViewTestSession?

    func freshAccessToken() async throws -> String {
        guard let authSession else { throw CancellationError() }
        return authSession.user.id.uuidString
    }
}

@MainActor
struct FitFightAPI {
    static var preferences = AccountPreferences()

    func accountPreferences(accessToken: String) async throws -> AccountPreferences {
        Self.preferences
    }

    func updateAccountPreferences(_ update: AccountPreferencesUpdate, accessToken: String) async throws -> AccountPreferences {
        if let language = update.language { Self.preferences.language = language }
        if let appearance = update.appearance { Self.preferences.appearance = appearance }
        return Self.preferences
    }
}

@MainActor
final class DraftProbe {
    var title = ""
    var step = 0
    var label = ""
    var edit: ((String, Int) -> Void)?
}

private struct DraftEditor: View {
    let probe: DraftProbe
    @State private var title = ""
    @State private var step = 0

    var body: some View {
        let label = String(appLocalized: "Preferences")
        VStack {
            Text(label)
            TextField("Title", text: $title)
        }
        .onAppear {
            probe.title = title
            probe.step = step
            probe.label = label
            probe.edit = { title = $0; step = $1 }
        }
        .onChange(of: title) { _, value in probe.title = value }
        .onChange(of: step) { _, value in probe.step = value }
        .onChange(of: label) { _, value in probe.label = value }
    }
}

private struct PreferencesRoot: View {
    @ObservedObject var preferences: AccountPreferencesStore
    @ObservedObject var session: SessionStore
    let probe: DraftProbe

    var body: some View {
        signedInRoot.environment(\.locale, AppLocalization.locale)
    }

    private var signedInRoot: some View {
        // The runner inserts ContentView's actual signed-in identity modifiers here.
        PRODUCTION_SIGNED_IN_CONTENT
    }

    private var signedInApp: some View { DraftEditor(probe: probe) }
}

@main
struct PreferencesViewStateTests {
    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "fitfight-preference-view-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionStore()
        session.authSession = .init(user: .init(id: UUID()))
        let preferences = AccountPreferencesStore(defaults: defaults)
        await preferences.refresh(session: session)
        let probe = DraftProbe()
        let hosting = NSHostingView(rootView: PreferencesRoot(preferences: preferences, session: session, probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 393, height: 852),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        await render(hosting)
        precondition(probe.edit != nil, "The real SwiftUI draft must be mounted")
        probe.edit?("Evening steps", 3)
        await render(hosting)
        precondition(probe.title == "Evening steps" && probe.step == 3)

        FitFightAPI.preferences.language = .fr
        await preferences.refresh(session: session)
        await render(hosting)
        precondition(probe.title == "Evening steps" && probe.step == 3,
                     "A foreground language refresh must preserve the open draft and step")
        precondition(probe.label == "Préférences", "Open views must update their localized text")

        await preferences.save(.init(language: .en), session: session)
        await render(hosting)
        precondition(probe.title == "Evening steps" && probe.step == 3)
        precondition(probe.label == "Preferences")

        session.authSession = .init(user: .init(id: UUID()))
        await preferences.refresh(session: session)
        await render(hosting)
        precondition(probe.title.isEmpty && probe.step == 0,
                     "Changing accounts must still discard the previous account's draft")
        print("Preference view state: remote refresh, local save, live translation, and account isolation passed")
    }

    @MainActor
    private static func render(_ hosting: NSHostingView<PreferencesRoot>) async {
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}
