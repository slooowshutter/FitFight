import AuthenticationServices
import SwiftUI

/// A watch or app whose steps reach FitFight through Apple Health. WHOOP also connects directly for
/// sleep, recovery, strain and workouts; Fight steps still come only from Apple Health.
enum Connector: String, CaseIterable, Identifiable {
    case garmin, whoop

    var id: String { rawValue }

    var name: String {
        switch self {
        case .garmin: "Garmin"
        case .whoop: "WHOOP"
        }
    }

    var logo: String {
        switch self {
        case .garmin: "Connector-Garmin"
        case .whoop: "Connector-WHOOP"
        }
    }

    var summary: String {
        switch self {
        case .garmin: String(appLocalized: "Steps and workouts")
        case .whoop: String(appLocalized: "Sleep, recovery, strain and workouts")
        }
    }
}

private let healthApp = URL(string: "x-apple-health://")!

/// Settings > Connectors: one watch or app, with its own logo. `status` replaces the summary once connected.
struct ConnectorRow: View {
    let connector: Connector
    var status: String? = nil
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(connector.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: connector.name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(status ?? connector.summary)
                        .ffType(.caption)
                        .foregroundStyle(status == nil ? theme.textSecondary : theme.mossText)
                }
                Spacer(minLength: 0)
                FFChevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(FFPressStyle(scale: 0.99))
    }
}

/// Apple Health's status row. In Settings it opens the Apple Health sheet; in the sheet it syncs.
struct AppleHealthRow: View {
    let action: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: HealthKitStepsStore

    var body: some View {
        let busy = steps.status == .reading || model.isRefreshingFights
        Button(action: action) {
            FFGroupedRow(
                title: String(appLocalized: "Apple Health activity"),
                subtitle: steps.detailText,
                systemImage: "heart",
                enabled: !busy,
                subtitleTone: subtitleTone,
                trailing: AnyView(pill)
            )
        }
        .buttonStyle(FFHapticPlainStyle())
        .disabled(busy)
    }

    private var subtitleTone: FFTone {
        switch steps.connection {
        case .syncFailed, .noAccessibleSteps: return .ember
        case .upToDate: return steps.diagnostics.activitySyncFailed == true ? .ember : .moss
        case .syncing, .notConnected: return .neutral
        }
    }

    private var pill: FFPill {
        switch steps.connection {
        case .syncFailed:
            return FFPill(String(appLocalized: "Retry"), style: .softEmber)
        case .syncing:
            return FFPill(String(appLocalized: "Syncing"), style: .neutral)
        case .upToDate:
            if steps.diagnostics.activitySyncFailed == true {
                return FFPill(String(appLocalized: "Retry"), style: .softEmber)
            }
            return FFPill(String(appLocalized: "Connected"), style: .softMoss)
        case .noAccessibleSteps:
            return FFPill(String(appLocalized: "Connected"), style: .softMoss)
        case .notConnected:
            return FFPill(String(appLocalized: "Connect"), style: .solidMoss)
        }
    }
}

/// Settings > Connectors > Apple Health: sync, what FitFight can read, and which device's steps count.
struct AppleHealthSheet: View {
    let sync: () -> Void
    let review: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let busy = steps.status == .reading || model.isRefreshingFights
        // What HealthKitActivityAggregates.readTypes asks for, grouped the way people say it.
        let reads: [(symbol: String, title: String, note: String?)] = [
            ("shoeprints.fill", String(appLocalized: "Steps"), String(appLocalized: "Used in your fights")),
            ("figure.run", String(appLocalized: "Workouts"), nil),
            ("flame.fill", String(appLocalized: "Active and resting energy"), nil),
            ("figure.walk", String(appLocalized: "Distance and pushes"), nil),
            ("clock", String(appLocalized: "Exercise, move and stand minutes"), nil),
            ("figure.stairs", String(appLocalized: "Flights climbed"), nil),
        ]
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Apple Health")) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    Text(String(appLocalized: "FitFight reads your activity from Apple Health. Any watch or app you connect to Apple Health counts too."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    FFGroupedRows {
                        AppleHealthRow(action: sync)
                    }
                    FFSection(title: String(appLocalized: "Access")) {
                        FFGroupedRows {
                            FFGroupedRow(
                                title: String(appLocalized: "Review access"),
                                subtitle: String(appLocalized: "Choose what FitFight can read."),
                                systemImage: "heart.circle",
                                enabled: !busy,
                                subtitleTone: .neutral,
                                trailing: AnyView(FFChevron()),
                                action: review
                            )
                            .disabled(busy)
                            FFDivider()
                            Link(destination: healthApp) {
                                FFGroupedRow(
                                    title: String(appLocalized: "Change access in Health"),
                                    subtitle: String(appLocalized: "In Health, tap your profile → Apps → FitFight."),
                                    systemImage: "hand.raised",
                                    subtitleTone: .neutral,
                                    trailing: AnyView(Image(systemName: "arrow.up.right"))
                                )
                            }
                            .buttonStyle(FFHapticPlainStyle())
                        }
                    }
                    FFSection(title: String(appLocalized: "FitFight asks to read")) {
                        FFGroupedRows {
                            ForEach(reads.indices, id: \.self) { index in
                                if index > 0 { FFDivider() }
                                FFGroupedRow(title: reads[index].title, subtitle: reads[index].note, systemImage: reads[index].symbol)
                            }
                        }
                    }
                    FFSection(title: String(appLocalized: "Which steps count")) {
                        Text(String(appLocalized: "Your iPhone counts steps, and so does your watch. When both count the same walk, Apple Health keeps one count, from the device at the top of its list. Put the one you wear all day at the top."))
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                        ConnectorSteps(steps: [
                            (String(appLocalized: "Open Health and tap Browse"), String(appLocalized: "Then tap Activity → Steps → Data Sources & Access.")),
                            (String(appLocalized: "Tap Edit"), String(appLocalized: "Drag the device you wear all day to the top, then tap Done.")),
                        ])
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

/// Settings > Connectors > a watch or app: how its activity reaches Apple Health, where FitFight reads it.
/// WHOOP's sheet starts with connecting the WHOOP account itself.
struct ConnectorGuideSheet: View {
    let connector: Connector
    @ObservedObject var whoop: WhoopConnectionStore
    let privacy: URL

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: connector.name) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    switch connector {
                    case .garmin:
                        FFNotice(
                            text: String(appLocalized: "Garmin stopped letting new apps connect to its data, so FitFight can’t link to Garmin directly. Your Garmin steps still count: Garmin Connect sends them to Apple Health, and FitFight reads them there."),
                            tone: .neutral,
                            systemImage: "info.circle"
                        )
                        ConnectorSteps(steps: [
                            (String(appLocalized: "Turn on Apple Health in Garmin Connect"), String(appLocalized: "In Garmin Connect, tap More → Settings → Connected Apps → Apple Health, then turn on Steps.")),
                            (String(appLocalized: "Open Garmin Connect to sync"), String(appLocalized: "Garmin sends steps to Apple Health only while Garmin Connect is open. After your watch syncs, open Garmin Connect, then FitFight. Do it once more before a fight ends.")),
                            (String(appLocalized: "Put Garmin first in Health"), String(appLocalized: "Your iPhone counts steps too. In Health, tap Browse → Activity → Steps → Data Sources & Access → Edit, then drag Garmin to the top.")),
                        ])
                    case .whoop:
                        Text(String(appLocalized: "Connect your WHOOP account and FitFight gets your sleep, recovery, strain and workouts straight from WHOOP, updated every hour."))
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                        whoopAccount
                        FFSection(title: String(appLocalized: "Steps")) {
                            Text(String(appLocalized: "WHOOP sends your steps and workouts to Apple Health, and FitFight reads them there."))
                                .ffType(.body)
                                .foregroundStyle(theme.textSecondary)
                            ConnectorSteps(steps: [
                                (String(appLocalized: "Turn on Apple Health in WHOOP"), String(appLocalized: "In the WHOOP app, turn on Apple Health and allow Steps.")),
                                (String(appLocalized: "Put WHOOP first in Health"), String(appLocalized: "Your iPhone counts steps too. In Health, tap Browse → Activity → Steps → Data Sources & Access → Edit, then drag WHOOP to the top.")),
                            ])
                        }
                    }
                    FFGroupedRows {
                        Link(destination: healthApp) {
                            FFGroupedRow(title: String(appLocalized: "Open Health"), trailing: AnyView(Image(systemName: "arrow.up.right")))
                        }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

extension ConnectorGuideSheet {
    /// The WHOOP account row, and the consent line until it is connected.
    private var whoopAccount: some View {
        let subtitle: String = whoop.connected
            ? whoop.connection?.lastSyncedAt.map {
                String(format: String(appLocalized: "whoop.last-update"),
                       $0.formatted(.relative(presentation: .named).locale(AppLocalization.locale)))
            } ?? String(appLocalized: "Updates every hour")
            : whoop.failed
                ? String(appLocalized: "Couldn’t connect WHOOP. Tap to try again.")
                : String(appLocalized: "Not connected")
        let pill: FFPill = whoop.busy ? FFPill(String(appLocalized: "Connecting"), style: .neutral)
            : whoop.connected ? FFPill(String(appLocalized: "Connected"), style: .softMoss)
            : whoop.failed ? FFPill(String(appLocalized: "Retry"), style: .softEmber)
            : FFPill(String(appLocalized: "Connect"), style: .solidMoss)
        return VStack(alignment: .leading, spacing: 10) {
            FFGroupedRows {
                Button {
                    Task {
                        await whoop.refresh(session: session, connectWith: whoop.connected ? nil : webAuthenticationSession)
                    }
                } label: {
                    FFGroupedRow(
                        title: String(appLocalized: "WHOOP account"),
                        subtitle: subtitle,
                        systemImage: "waveform.path.ecg",
                        enabled: !whoop.busy,
                        subtitleTone: whoop.connected ? .moss : whoop.failed ? .ember : .neutral,
                        trailing: AnyView(pill)
                    )
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(whoop.busy)
            }
            if !whoop.connected {
                Text(AttributedString(
                    localized: "By connecting, you agree to our [Privacy Policy](privacy).",
                    bundle: AppLocalization.bundle, locale: AppLocalization.locale
                ))
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .tint(theme.mossText)
                .environment(\.openURL, OpenURLAction { _ in .systemAction(privacy) })
                .padding(.horizontal, 16)
            }
        }
    }
}

/// The signed-in person's WHOOP connection. Settings loads it; the WHOOP sheet connects.
@MainActor
final class WhoopConnectionStore: ObservableObject {
    @Published private(set) var connection: FitFightWhoopConnection?
    /// True while WHOOP's sign-in is open or the status reloads.
    @Published private(set) var busy = false
    @Published private(set) var failed = false

    var connected: Bool { connection?.connected == true }

    /// Reloads the status. With a web session it first opens WHOOP's sign-in, which ends on
    /// fitfight://whoop?code=...&state=...; the app then finishes the link with its own sign-in.
    func refresh(session: SessionStore, connectWith webAuthentication: WebAuthenticationSession? = nil) async {
        guard !CompanionPreview.isEnabled, session.isSignedIn else { return }
        busy = true
        defer { busy = false }
        if let webAuthentication {
            failed = false
            do {
                let url = try await FitFightAPI().startWhoopConnection(accessToken: session.freshAccessToken())
                let callback = try await webAuthentication.authenticate(
                    using: url, callbackURLScheme: "fitfight", preferredBrowserSession: .shared
                )
                let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let code = items.first(where: { $0.name == "code" })?.value,
                   let state = items.first(where: { $0.name == "state" })?.value {
                    try await FitFightAPI().finishWhoopConnection(
                        code: code, state: state, accessToken: session.freshAccessToken()
                    )
                } else {
                    failed = true
                }
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            } catch {
                failed = true
            }
        }
        if let loaded = try? await FitFightAPI().whoopConnection(accessToken: session.freshAccessToken()) {
            connection = loaded
        }
    }
}

/// Numbered how-to steps in one card.
private struct ConnectorSteps: View {
    let steps: [(title: String, text: String)]

    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .ffType(.label)
                            .foregroundStyle(theme.text)
                            .frame(width: 26, height: 26)
                            .background(theme.control, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(steps[index].title)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text(steps[index].text)
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
