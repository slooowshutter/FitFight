import SwiftUI
import UIKit

/// Hidden admin/debug sheet. Opened only by username `marc` from the version label on You.
struct DebugMenuView: View {
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showDesign = false

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                Text(showDesign ? String(appLocalized: "Design system") : String(appLocalized: "Debug"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                if showDesign {
                    Button(String(appLocalized: "Back")) { showDesign = false }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                Button(String(appLocalized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            if showDesign {
                DesignSystemView()
            } else {
                menu
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FFSection(title: String(appLocalized: "Apple Health")) {
                    diagnostics
                }
                FFSection(title: String(appLocalized: "Look")) {
                    FFGroupedRows {
                        FFGroupedRow(
                            title: String(appLocalized: "Design system"),
                            subtitle: String(appLocalized: "Internal kit. Not shown to other people."),
                            systemImage: "paintpalette",
                            trailing: AnyView(FFChevron()),
                            action: { showDesign = true }
                        )
                    }
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 24)
        }
    }

    private var diagnostics: some View {
        FFGroupedRows {
            FFGroupedRow(
                title: String(appLocalized: "Background App Refresh"),
                subtitle: steps.backgroundRefreshText,
                systemImage: "arrow.clockwise",
                subtitleTone: steps.diagnostics.backgroundRefreshStatus == .available ? .moss : .neutral,
                trailing: steps.diagnostics.backgroundRefreshStatus == .denied
                    ? AnyView(FFPill(String(appLocalized: "Open Settings"), style: .softMoss)) : nil,
                action: steps.diagnostics.backgroundRefreshStatus == .denied
                    ? { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    : nil
            )
            FFDivider()
            FFGroupedRow(
                title: String(appLocalized: "HealthKit background delivery"),
                subtitle: steps.backgroundDeliveryText,
                systemImage: "heart.text.square",
                subtitleTone: steps.diagnostics.deliveryRegistrationStatus == .enabled ? .moss : .neutral
            )
            FFDivider()
            FFGroupedRow(
                title: String(appLocalized: "Last automatic sync"),
                subtitle: diagnosticDate(steps.diagnostics.lastAutomaticSync),
                systemImage: "bolt"
            )
            FFDivider()
            FFGroupedRow(
                title: String(appLocalized: "Last manual or foreground sync"),
                subtitle: diagnosticDate(steps.diagnostics.lastManualSync),
                systemImage: "hand.tap"
            )
            if let failure = steps.currentFailureText {
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Current sync issue"),
                    subtitle: failure,
                    systemImage: "exclamationmark.triangle",
                    subtitleTone: .ember
                )
            }
            if let reference = steps.diagnostics.failureReference {
                FFDivider()
                FFGroupedRow(
                    title: String(appLocalized: "Sync error reference"),
                    subtitle: reference,
                    systemImage: "number",
                    subtitleTone: .neutral
                )
            }
        }
    }

    private func diagnosticDate(_ date: Date?) -> String {
        guard let date else { return String(appLocalized: "Not yet") }
        return date.formatted(.relative(presentation: .named).locale(AppLocalization.locale))
    }
}
