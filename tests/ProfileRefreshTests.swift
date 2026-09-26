import Foundation

@MainActor final class SessionStore {}
@MainActor final class HealthKitStepsStore {
    enum SyncTrigger { case foreground, manual }
    let hasAsked = true
}
@MainActor final class YouActivityStore {
    func load() async {}
}
@MainActor final class AppModel {
    var upload: CheckedContinuation<Void, Never>?
    var uploads = 0
    var confirmedSteps = 100
    var refreshTask: Task<Void, Never>?
    func refreshFights(session: SessionStore, steps: HealthKitStepsStore,
                       trigger: HealthKitStepsStore.SyncTrigger = .foreground, requestAccess: Bool = false) async {
        uploads += 1
        await withCheckedContinuation { upload = $0 }
        confirmedSteps = 9000
    }
    func waitForRefresh() async {
        // WAIT_FOR_REFRESH
    }
}

@MainActor final class YouState {
    let model = AppModel()
    let session = SessionStore()
    let steps = HealthKitStepsStore()
    let activity = YouActivityStore()
    let staticRender = false
    var visibleSteps = 100
    var profileLoads = 0
    func loadOwnProfile() async {
        visibleSteps = model.confirmedSteps
        profileLoads += 1
    }
    func initialRefresh() async {
        // INITIAL_REFRESH
    }
    func manualRefresh() async {
        // MANUAL_REFRESH
    }
    func healthRefresh() async {
        // HEALTH_REFRESH
    }
    func foregroundRefresh() async {
        // FOREGROUND_REFRESH
    }
    // REFRESH_HELPER
}

@main struct ProfileRefreshTests {
    @MainActor static func main() async {
        var failures: [String] = []
        for action in 0..<4 {
            let view = YouState()
            // Opening You and returning to the foreground reuse the upload FitFightApp started.
            let appearing = action == 0 || action == 3
            if appearing {
                view.model.refreshTask = Task { await view.model.refreshFights(session: view.session, steps: view.steps) }
            }
            let refresh = Task {
                switch action {
                case 0: await view.initialRefresh()
                case 1: await view.manualRefresh()
                case 2: await view.healthRefresh()
                default: await view.foregroundRefresh()
                }
            }
            for _ in 0..<10_000 {
                if view.model.upload != nil { break }
                await Task.yield()
            }
            precondition(view.model.upload != nil, "Refresh must reach the HealthKit boundary")
            for _ in 0..<1_000 { await Task.yield() }
            precondition(view.profileLoads == 0, "Profile reads must wait for the pending upload")
            view.model.upload?.resume()
            await refresh.value
            if view.profileLoads != 1 || view.visibleSteps != 9000 {
                failures.append("Refresh action \(action) must publish the newly uploaded statistics")
            }
            if view.model.uploads != 1 {
                failures.append("Refresh action \(action) must upload Steps exactly once")
            }
        }
        for action in [0, 3] {
            let view = YouState()
            if action == 0 { await view.initialRefresh() } else { await view.foregroundRefresh() }
            if view.profileLoads != 1 || view.model.uploads != 0 {
                failures.append("Refresh action \(action) must read the profile without uploading Steps again")
            }
        }
        for failure in failures { print("FAIL: \(failure)") }
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("You statistics: opening, foreground, pull-to-refresh, and Health sync wait for the upload; opening never uploads again")
    }
}
