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
    @State private var showingDesignSystem = false

    var body: some View {
        FFScreen {
            profile
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            stats

            FFSectionHeader(title: "Friends").padding(.top, theme.space.lg)
            friendsPanel

            FFSectionHeader(title: "Fight history").padding(.top, theme.space.lg)
            history

            FFSectionHeader(title: "Data sources").padding(.top, theme.space.lg)
            sources

            FFSectionHeader(title: "Settings").padding(.top, theme.space.lg)
            settings

            FFSectionHeader(title: "Look").padding(.top, theme.space.lg)
            appearance

        }
        .task {
            guard !staticRender else { return }
            await steps.refresh(requestAccess: false)
            if let userId = session.authSession?.user.id {
                try? await friends.load(userId: userId)
            }
        }
        .sheet(isPresented: $showingDesignSystem) {
            NavigationStack {
                DesignSystemView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showingDesignSystem = false }
                                .foregroundStyle(theme.mossText)
                        }
                    }
            }
            .environmentObject(themeStore)
            .fitFightTheme(themeStore.theme)
            .presentationBackground(themeStore.theme.bg)
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

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            signedInProfile
        } else {
            AppleSignInControl()
        }
    }

    private var signedInProfile: some View {
        HStack(spacing: 14) {
            FFAvatar(monogram: session.profile?.initials ?? "FF", size: 68, selected: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.profile?.displayName ?? "Signed in")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(session.profile?.atHandle ?? "Profile isn’t ready yet")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                if session.profile != nil {
                    Button {
                        UIPasteboard.general.string = session.profile?.atHandle ?? ""
                        copied = true
                    } label: {
                        Text(copied ? "Copied" : "Copy username")
                            .ffType(.micro)
                            .fontWeight(.heavy)
                            .foregroundStyle(theme.mossText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
        }
    }

    /// Four numbers in one strip — smaller than the kit's stat tile, which is built
    /// for a grid of two with its own progress bar.
    private var stats: some View {
        HStack(spacing: 0) {
            statCell("\(youStats.fights)", "Fights")
            Rectangle().fill(theme.hairline).frame(width: 1, height: 34)
            statCell("\(youStats.wins)", "Wins")
            Rectangle().fill(theme.hairline).frame(width: 1, height: 34)
            statCell(youStats.winRate, "Win rate")
            Rectangle().fill(theme.hairline).frame(width: 1, height: 34)
            statCell(youStats.won, "Won")
        }
        .padding(.vertical, 15)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ff(20, 800))
                .tracking(20 * -0.025)
                .foregroundStyle(theme.text)
            Text(label)
                .ffType(.micro)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
        FFGroupedRows {
            ForEach(Array(model.history.enumerated()), id: \.element.id) { index, item in
                if index > 0 { FFDivider() }
                Button {
                    model.tab = .fights
                    model.openFightID = item.id
                } label: {
                    HStack(spacing: 12) {
                        FFResultGlyph(item.won ? .win : .loss)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text(item.detail)
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        FFMoney(dollars: item.net)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sources: some View {
        FFGroupedRows {
            Button {
                Task {
                    await steps.refresh(requestAccess: true)
                    if session.authSession != nil {
                        await steps.syncToBackend(session: session)
                    }
                }
            } label: {
                FFGroupedRow(
                    title: "Apple Health",
                    subtitle: steps.metaText.isEmpty
                        ? steps.detailText
                        : "\(steps.detailText) · \(steps.metaText)",
                    systemImage: "heart",
                    subtitleTone: steps.isConnected ? .moss : .neutral,
                    trailing: AnyView(
                        FFPill(
                            steps.isConnected ? "On" : "Connect",
                            style: steps.isConnected ? .softMoss : .solidMoss
                        )
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(steps.status == .reading)
        }
    }

    private var friendsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People add you with \(session.profile?.atHandle ?? "your username"). Add them the same way.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
            HStack(spacing: 8) {
                TextField("@username", text: $friendHandle)
                    .font(.ff(15, 700))
                    .foregroundStyle(theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                    .ffBorder(theme.line, radius: theme.radius.field)
                    .onSubmit { addFriend() }
                FFButton(
                    title: "Add",
                    size: .small,
                    enabled: !friendHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    addFriend()
                }
            }
            if !friends.incoming.isEmpty {
                FFGroupedRows {
                    ForEach(Array(friends.incoming.enumerated()), id: \.element.userId) { index, person in
                        if index > 0 { FFDivider() }
                        FFGroupedRow(
                            title: person.displayName,
                            subtitle: person.atHandle,
                            subtitleTone: .neutral,
                            trailing: AnyView(
                                Button {
                                    Task {
                                        guard let me = session.authSession?.user.id else { return }
                                        try? await friends.accept(requesterId: person.userId, addresseeId: me)
                                        try? await friends.load(userId: me)
                                    }
                                } label: {
                                    FFPill("Accept", style: .solidMoss)
                                }
                                .buttonStyle(FFPressStyle())
                            )
                        )
                    }
                }
            }
            if !model.people.isEmpty {
                FFGroupedRows {
                    ForEach(Array(model.people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(person, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .ffType(.rowTitle)
                                    .foregroundStyle(theme.text)
                                Text(person.handle)
                                    .ffType(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }
            }
            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
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

    private var settings: some View {
        FFGroupedRows {
            navRow("Units & goals") {}
            FFDivider()
            navRow("Notifications") {}
            FFDivider()
            navRow("Privacy") {}
            FFDivider()
            navRow("Payouts") {}
            FFDivider()
            navRow("Design system") { showingDesignSystem = true }
            FFDivider()
            navRow("Versions") { model.showingVersions = true }
            if session.isSignedIn {
                FFDivider()
                navRow("Sign out") {
                    Task { await session.signOut() }
                }
                FFDivider()
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
        .buttonStyle(.plain)
        .disabled(session.isBusy)
    }
}
