import SwiftUI
import UIKit

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var friends: FriendshipStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var confirmDelete = false
    @State private var friendHandle = ""
    @State private var copied = false
    @State private var showingAppleHealth = false

    var body: some View {
        if staticRender {
            youBody
        } else {
            NavigationStack {
                youBody
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(isPresented: $showingAppleHealth) {
                        AppleHealthSourceView()
                    }
            }
        }
    }

    private var youBody: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                profile
                    .padding(.bottom, 15)
                if session.isSignedIn, let authError = session.authError {
                    Text(authError)
                        .font(.ff(11))
                        .foregroundStyle(theme.red)
                        .padding(.bottom, 10)
                }
                stats
                sectionHeader("Friends")
                friendsPanel
                sectionHeader("Fight history", action: "All \(model.history.count)") { model.tab = .fights }
                history
                sectionHeader("Data sources")
                sources
                sectionHeader("Settings")
                settings
                sectionHeader("Look")
                appearance
                sectionHeader("This build")
                buildPanel
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 2)
            .padding(.bottom, theme.space.xl)
        }
        .refreshable {
            await steps.refresh(requestAccess: false)
            if let userId = session.authSession?.user.id {
                await steps.syncToSupabase(client: session.client, userId: userId)
                try? await friends.load(userId: userId)
            }
            await model.refreshFromServer(session: session)
        }
        .task {
            guard !staticRender else { return }
            await steps.refresh(requestAccess: false)
            if let userId = session.authSession?.user.id {
                if steps.history.isEmpty {
                    await steps.loadServerHistory(client: session.client, userId: userId)
                }
                try? await friends.load(userId: userId)
            }
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await session.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out and deletes your FitFight account.")
        }
    }

    private func sectionHeader(_ title: String, action: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        FFSectionHeader(title: title, action: action, onAction: onAction)
            .padding(.top, theme.space.sectionGap)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            signedInProfile
        } else {
            AppleSignInControl()
        }
    }

    private var signedInProfile: some View {
        HStack(spacing: 12) {
            FFAvatar(
                initials: session.profile?.initials ?? "FF",
                size: 56,
                ring: true
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(session.profile?.displayName ?? "Signed in")
                    .font(.ff(17, .bold))
                    .foregroundStyle(theme.text)
                Text(session.profile?.atHandle ?? "Profile isn’t ready yet")
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .fixedSize()
                if session.profile != nil {
                    Button {
                        UIPasteboard.general.string = session.profile?.atHandle ?? ""
                        copied = true
                    } label: {
                        Text(copied ? "Copied" : "Copy username")
                            .font(.ff(11, .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button {} label: {
                Text("Edit")
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
            }
            .buttonStyle(FFPressStyle(scale: 0.97))
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            FFStatTile(value: "\(youStats.fights)", label: "Fights", onSurface: true, height: 60)
            FFStatTile(value: "\(youStats.wins)", label: "Wins", onSurface: true, height: 60)
            FFStatTile(value: youStats.winRate, label: "Win rate", onSurface: true, height: 60)
            FFStatTile(value: youStats.won, label: "Won", onSurface: true, height: 60)
        }
    }

    /// Finished fights from history plus any finished rows not already listed there.
    private var youStats: (fights: Int, wins: Int, winRate: String, won: String) {
        var seen = Set<String>()
        var fights = 0
        var wins = 0
        var wonMoney = 0

        for item in model.history {
            seen.insert(item.id)
            fights += 1
            if item.won {
                wins += 1
                if item.net > 0 { wonMoney += item.net }
            }
        }
        for fight in model.fights where fight.status == .finished {
            guard seen.insert(fight.id).inserted else { continue }
            fights += 1
            if fight.rank == 1 {
                wins += 1
                if let you = model.youStanding(in: fight), you.projectedNet > 0 {
                    wonMoney += you.projectedNet
                }
            }
        }

        let rate = fights == 0 ? "0%" : "\(Int((Double(wins) / Double(fights) * 100).rounded()))%"
        return (fights, wins, rate, "$\(wonMoney)")
    }

    private var history: some View {
        FFPanel {
            ForEach(Array(model.history.enumerated()), id: \.element.id) { index, item in
                if index > 0 { FFHairline() }
                Button {
                    model.tab = .fights
                    model.openFightID = item.id
                } label: {
                    HStack(spacing: 12) {
                        Text(item.won ? "W" : "L")
                            .font(.ff(13, .bold))
                            .foregroundStyle(item.won ? theme.green : theme.red)
                            .frame(width: 36, height: 36)
                            .background(
                                (item.won ? theme.green : theme.red).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.ff(13, .bold))
                                .foregroundStyle(theme.text)
                            Text(item.detail)
                                .font(.ff(11))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer(minLength: 8)
                        FFMoney(dollars: item.net, size: 13)
                    }
                    .padding(.horizontal, FFMetric.rowPaddingX)
                    .frame(height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sources: some View {
        FFPanel {
            Button {
                showingAppleHealth = true
            } label: {
                sourceRow(
                    "Apple Health",
                    steps.detailText,
                    steps.metaText,
                    connected: steps.isConnected
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sourceRow(
        _ name: String,
        _ detail: String,
        _ time: String,
        connected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Circle().fill(connected ? theme.green : theme.faint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.ff(11))
                .foregroundStyle(theme.faint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.faint)
        }
        .padding(.horizontal, FFMetric.rowPaddingX)
        .frame(minHeight: 61)
        .contentShape(Rectangle())
    }

    private var friendsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People add you with \(session.profile?.atHandle ?? "your username"). Add them the same way.")
                .font(.ff(12))
                .foregroundStyle(theme.faint)
            HStack(spacing: 8) {
                TextField("@username", text: $friendHandle)
                    .font(.ff(15))
                    .foregroundStyle(theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    }
                    .onSubmit { addFriend() }
                FFButton(title: "Add", kind: .small, enabled: !friendHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    addFriend()
                }
            }
            if !friends.incoming.isEmpty {
                FFPanel {
                    ForEach(Array(friends.incoming.enumerated()), id: \.element.userId) { index, person in
                        if index > 0 { FFHairline() }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.displayName)
                                    .font(.ff(13, .semibold))
                                    .foregroundStyle(theme.text)
                                Text(person.atHandle)
                                    .font(.ff(11))
                                    .foregroundStyle(theme.faint)
                            }
                            Spacer()
                            FFButton(title: "Accept", kind: .small) {
                                Task {
                                    guard let me = session.authSession?.user.id else { return }
                                    try? await friends.accept(requesterId: person.userId, addresseeId: me)
                                    try? await friends.load(userId: me)
                                }
                            }
                        }
                        .padding(.horizontal, FFMetric.rowPaddingX)
                        .frame(height: 56)
                    }
                }
            }
            if !model.people.isEmpty {
                FFPanel {
                    ForEach(Array(model.people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { FFHairline() }
                        HStack(spacing: 12) {
                            FFAvatar(person, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.ff(13, .semibold))
                                    .foregroundStyle(theme.text)
                                Text(person.handle)
                                    .font(.ff(11))
                                    .foregroundStyle(theme.faint)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, FFMetric.rowPaddingX)
                        .frame(height: 56)
                    }
                }
            }
            if let error = model.createError, !error.isEmpty {
                Text(error)
                    .font(.ff(11))
                    .foregroundStyle(theme.red)
            }
        }
    }

    private func addFriend() {
        let handle = FriendshipStore.strippedHandle(friendHandle)
        guard !handle.isEmpty else { return }
        friendHandle = ""
        Task {
            await model.addFriend(handle: handle)
            if let userId = session.authSession?.user.id {
                try? await friends.load(userId: userId)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(BaseID.allCases) { base in
                    let on = themeStore.baseID == base
                    Button {
                        themeStore.baseID = base
                    } label: {
                        Text(base.rawValue.capitalized)
                            .font(.ff(13, .semibold))
                            .foregroundStyle(on ? theme.ink : theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                on ? theme.accent : theme.surface,
                                in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                            )
                            .overlay {
                                if !on {
                                    RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                                        .strokeBorder(theme.line, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(FFPressStyle(scale: 0.97))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(AccentID.allCases) { accent in
                    let color = ThemeCatalog.theme(base: themeStore.baseID, accent: accent).accent
                    Button {
                        themeStore.accentID = accent
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if themeStore.accentID == accent {
                                    Circle().strokeBorder(theme.text, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.rawValue)
                }
            }
        }
    }

    private var buildPanel: some View {
        FFPanel {
            navRow("Versions") { model.showingVersions = true }
        }
    }

    private var settings: some View {
        FFPanel {
            navRow("Units & goals") {}
            FFHairline()
            navRow("Notifications") {}
            FFHairline()
            navRow("Privacy") {}
            FFHairline()
            navRow("Payouts") {}
            if session.isSignedIn {
                FFHairline()
                navRow("Sign out") {
                    Task { await session.signOut() }
                }
                FFHairline()
                navRow("Delete account", destructive: true) {
                    confirmDelete = true
                }
            }
        }
    }

    private func navRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.ff(13, .semibold))
                    .foregroundStyle(destructive ? theme.red : theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, FFMetric.rowPaddingX)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.isBusy)
    }
}
