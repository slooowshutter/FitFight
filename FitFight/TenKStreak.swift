import SwiftUI

func formattedSteps(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale))
}

private let profileDayFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter
}()

/// A server calendar day such as "2026-08-14", at midnight UTC so it formats as that same day.
func profileDay(_ raw: String) -> Date? {
    profileDayFormatter.date(from: raw)
}

func streakDayCount(_ days: Int) -> String {
    String(appLocalized: "streak.day-count", defaultValue: "\(days) days")
}

func profileFightCount(_ fights: Int) -> String {
    String(appLocalized: "profile.fight-count", defaultValue: "\(fights) Fights")
}

/// The flame and day count: next to Fights for you, on a friend's Player card for them.
struct TenKStreakPill: View {
    let days: Int
    let action: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill").font(.system(size: 12, weight: .bold))
                Text(verbatim: "\(days)").font(.ff(12, 800)).monospacedDigit()
            }
            .foregroundStyle(days > 0 ? theme.gold : theme.textSecondary)
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(days > 0 ? theme.gold.opacity(0.14) : theme.chip, in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(format: String(appLocalized: "profile.their-streak-title"), streakDayCount(days)))
    }
}

/// Your 10K streak next to the Fights title. It starts from the profile You saved, then reads a fresh one.
struct TenKStreakBadge: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ffStaticRender) private var staticRender
    @State private var streak: ProfileTenKStreak?
    @State private var showing = false

    var body: some View {
        Group {
            if let streak {
                TenKStreakPill(days: TenKStreakDrawer.current(streak, today: todaySteps)) { showing = true }
            }
        }
        .task(id: session.authSession?.user.id) { await load(fromCache: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(fromCache: false) } }
        }
        .sheet(isPresented: $showing) {
            if let streak {
                TenKStreakDrawer(streak: streak, todaySteps: todaySteps)
                    .fitFightTheme(theme)
                    .presentationBackground(theme.overlay)
                    .presentationCornerRadius(theme.radius.shell)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            }
        }
    }

    private var todaySteps: Int? {
        if case .steps(let count) = steps.status { count } else { nil }
    }

    private func load(fromCache: Bool) async {
        guard !staticRender, let userID = session.authSession?.user.id else {
            streak = nil
            return
        }
        if fromCache {
            streak = UserDefaults.standard.data(forKey: YouView.profileCachePrefix + userID.uuidString)
                .flatMap { try? JSONDecoder().decode(SharedProfile.self, from: $0) }?.tenKStreak
        }
        // Steps upload at launch and on return; reading after it keeps yesterday's final day in the count.
        await model.waitForRefresh()
        guard !Task.isCancelled, let token = try? await session.freshAccessToken(),
              let profile = try? await FitFightAPI().sharedProfile(userID: userID, accessToken: token),
              session.authSession?.user.id == userID else { return }
        streak = profile.tenKStreak
    }
}

/// Your streak, today's progress, the last two weeks, and your best run with its dates.
struct TenKStreakDrawer: View {
    let streak: ProfileTenKStreak
    let todaySteps: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffTheme) private var theme

    /// Today counts once either the server or this phone's Apple Health reaches the goal.
    static func current(_ streak: ProfileTenKStreak, today: Int?) -> Int {
        let todayHit = streak.todayCounted || (today ?? 0) >= streak.goal
        return streak.current - (streak.todayCounted ? 1 : 0) + (todayHit ? 1 : 0)
    }

    var body: some View {
        let current = Self.current(streak, today: todaySteps)
        let today = todaySteps ?? 0
        let todayHit = streak.todayCounted || today >= streak.goal
        let progress = todayHit ? 1 : min(1, Double(today) / Double(streak.goal))
        let best = max(streak.best?.days ?? 0, current)
        let goal = formattedSteps(Double(streak.goal))
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(theme.gold)
                        .frame(width: 64, height: 64)
                        .background(theme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current > 0 ? streakDayCount(current) : String(appLocalized: "No streak"))
                            .font(.ff(30, 800)).monospacedDigit().foregroundStyle(theme.text)
                        Group {
                            if current == 0 {
                                Text(String(format: String(appLocalized: "streak.start"), goal))
                            } else if todayHit {
                                Text(String(format: String(appLocalized: "streak.today-counts"), streakDayCount(current), goal))
                            } else {
                                Text(String(format: String(appLocalized: "streak.to-go"), formattedSteps(Double(streak.goal - today)), current + 1))
                            }
                        }
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: 6) {
                    HStack {
                        Text(String(appLocalized: "Today"))
                        Spacer()
                        Text(String(format: String(appLocalized: "streak.today-progress"), formattedSteps(Double(today)), goal))
                            .monospacedDigit()
                    }
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                    GeometryReader { proxy in
                        Capsule().fill(theme.track)
                            .overlay(alignment: .leading) {
                                Capsule().fill(theme.gold).frame(width: proxy.size.width * progress)
                            }
                    }
                    .frame(height: 8)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(streak.recent ?? [], id: \.day) { day in
                            cell(hit: (day.steps ?? 0) >= Double(streak.goal))
                        }
                        if todayHit {
                            cell(hit: true)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.chip)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .trim(from: 0, to: progress)
                                        .stroke(theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                }
                        }
                    }
                    HStack {
                        Text(String(appLocalized: "2 weeks ago"))
                        Spacer()
                        Text(String(appLocalized: "Today"))
                    }
                    .font(.ff(11, 700)).foregroundStyle(theme.textFaint)
                }
                .accessibilityHidden(true)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(current)").font(.ff(18, 800)).monospacedDigit()
                        Text(String(appLocalized: "current streak")).ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(theme.overlayLine).frame(width: 1)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "\(best)").font(.ff(18, 800)).monospacedDigit()
                            // Only you see when your best run happened.
                            if let run = streak.best, run.days == best, let from = profileDay(run.from), let through = profileDay(run.through) {
                                Text(String(format: String(appLocalized: "streak.best-dates"),
                                            from.formatted(Date.FormatStyle(locale: AppLocalization.locale, timeZone: .gmt).day().month(.abbreviated)),
                                            through.formatted(Date.FormatStyle(locale: AppLocalization.locale, timeZone: .gmt).day().month(.abbreviated).year())))
                                    .font(.ff(12, 700)).foregroundStyle(theme.textSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        Text(String(appLocalized: "best streak")).ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.overlayLine, lineWidth: 1) }
                Text(String(format: String(appLocalized: "streak.explanation"), goal, goal))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FFButton(title: String(appLocalized: "Got it"), kind: .secondary, fullWidth: true) { dismiss() }
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 34)
        }
    }

    private func cell(hit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(hit ? theme.gold : theme.chip)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if hit { Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.goldInk) }
            }
    }
}
