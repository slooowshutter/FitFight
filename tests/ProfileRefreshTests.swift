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
    var confirmedSteps = 100
    func refreshFights(session: SessionStore, steps: HealthKitStepsStore,
                       trigger: HealthKitStepsStore.SyncTrigger = .foreground, requestAccess: Bool = false) async {
        await withCheckedContinuation { upload = $0 }
        confirmedSteps = 9000
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
    // REFRESH_HELPER
}

@main struct ProfileRefreshTests {
    @MainActor static func main() async {
        var failures: [String] = []
        for action in 0..<3 {
            let view = YouState()
            let refresh = Task {
                switch action {
                case 0: await view.initialRefresh()
                case 1: await view.manualRefresh()
                default: await view.healthRefresh()
                }
            }
            for _ in 0..<10_000 {
                if view.model.upload != nil { break }
                await Task.yield()
            }
            precondition(view.model.upload != nil, "Refresh must reach the HealthKit boundary")
            precondition(view.profileLoads == 0, "Profile reads must wait for the pending upload")
            view.model.upload?.resume()
            await refresh.value
            if view.profileLoads != 1 || view.visibleSteps != 9000 {
                failures.append("Refresh action \(action) must publish the newly uploaded statistics")
            }
        }
        for failure in failures { print("FAIL: \(failure)") }
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("You statistics: initial, pull-to-refresh, and Health sync wait for the upload")
    }
}
