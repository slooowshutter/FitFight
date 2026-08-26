import SwiftUI
import UIKit

/// You → Data sources → Apple Health. Connection, last sync, and 31-day Steps history.
struct AppleHealthSourceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        FFScreen(top: AnyView(nav)) {
            VStack(alignment: .leading, spacing: 0) {
                statusPanel
                todayPanel
                    .padding(.top, theme.space.sectionGap)
                if let error = steps.uploadError, !error.isEmpty {
                    Text(error)
                        .font(.ff(11))
                        .foregroundStyle(theme.red)
                        .padding(.top, 10)
                }
                FFSectionHeader(title: "History", action: "\(steps.history.count) days")
                    .padding(.top, theme.space.sectionGap)
                    .padding(.bottom, 10)
                historyPanel
                FFButton(
                    title: steps.isSyncing ? "Syncing…" : "Sync now",
                    enabled: !steps.isSyncing && session.isSignedIn,
                    busy: steps.isSyncing
                ) {
                    Task { await sync() }
                }
                .padding(.top, theme.space.sectionGap)
                FFButton(title: "Open Settings", kind: .quiet) {
                    openSettings()
                }
                .padding(.top, 10)
                Text("FitFight only reads Steps. Turn them on in the Health app: Sharing → Apps → FitFight. Empty reads say “No accessible data” — HealthKit does not tell us if you tapped Don’t Allow.")
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .padding(.top, 12)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.xl)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !staticRender else { return }
            await steps.connectAndSync(
                client: session.client,
                userId: session.authSession?.user.id
            )
            if steps.history.isEmpty, let userId = session.authSession?.user.id {
                await steps.loadServerHistory(client: session.client, userId: userId)
            }
        }
    }

    private var nav: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("You")
                        .font(.ff(13, .semibold))
                }
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }
            .buttonStyle(FFPressStyle(scale: 0.97))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 16)
        .background(theme.bg)
    }

    private var statusPanel: some View {
        FFPanel {
            HStack(spacing: 12) {
                Circle()
                    .fill(steps.isConnected ? theme.green : theme.faint)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Health")
                        .font(.ff(13, .semibold))
                        .foregroundStyle(theme.text)
                    Text(statusLine)
                        .font(.ff(11))
                        .foregroundStyle(theme.faint)
                }
                Spacer(minLength: 8)
                Text(steps.metaText)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, FFMetric.rowPaddingX)
            .frame(minHeight: 61)
        }
    }

    private var statusLine: String {
        if steps.isSyncing { return "Syncing last 31 days…" }
        if !steps.todaySources.isEmpty {
            return steps.todaySources.joined(separator: ", ")
        }
        return steps.detailText
    }

    private var todayPanel: some View {
        FFPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(.ff(10, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.faint)
                Text(HealthKitStepsStore.format(steps.todayCount))
                    .font(.ff(28, .bold))
                    .foregroundStyle(theme.text)
                Text("steps")
                    .font(.ff(12))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, FFMetric.rowPaddingX)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historyPanel: some View {
        if steps.history.isEmpty {
            FFPanel {
                Text(steps.hasAsked ? "No accessible data" : "Connect to load the last 31 days.")
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
                    .padding(.horizontal, FFMetric.rowPaddingX)
                    .frame(minHeight: 56, alignment: .leading)
            }
        } else {
            FFPanel {
                ForEach(Array(steps.history.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { FFHairline() }
                    HStack {
                        Text(HealthKitStepsStore.dayLabel(day.date))
                            .font(.ff(13, .semibold))
                            .foregroundStyle(theme.text)
                        Spacer(minLength: 8)
                        Text(HealthKitStepsStore.format(day.steps))
                            .font(.ff(13, .bold))
                            .foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, FFMetric.rowPaddingX)
                    .frame(height: 44)
                }
            }
        }
    }

    private func sync() async {
        await steps.connectAndSync(
            client: session.client,
            userId: session.authSession?.user.id
        )
        await model.refreshFromServer(session: session)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
