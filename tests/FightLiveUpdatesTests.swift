import Foundation

protocol ObservableObject {}
struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ message: String) {}
}
struct BroadcastConfig { var replicationReady = false }
struct ChannelConfig { var isPrivate = false; var broadcast = BroadcastConfig() }
enum ChannelStatus { case subscribed, unsubscribed }
enum SystemStatus { case ok, error }
struct SystemMessage { let status: SystemStatus }

@MainActor final class TestChannel {
    let topic: String
    let (messages, events) = AsyncStream<Void>.makeStream()
    let (statusChange, statuses) = AsyncStream<ChannelStatus>.makeStream()
    let (systemMessages, systemEvents) = AsyncStream<SystemMessage>.makeStream()
    init(topic: String) { self.topic = topic }
    func broadcastStream(event: String) -> AsyncStream<Void> {
        precondition(event == "fights_changed")
        return messages
    }
    func subscribeWithError() async throws { statuses.yield(.subscribed) }
    func system() -> AsyncStream<SystemMessage> { systemMessages }
}

@MainActor final class SupabaseClient {
    var channels: [String: TestChannel] = [:]
    var created = 0
    var removals = 0
    var holdRemoval = false
    var pendingRemoval: CheckedContinuation<Void, Never>?
    func channel(_ topic: String, options: (inout ChannelConfig) -> Void) -> TestChannel {
        if let existing = channels[topic] { return existing }
        var config = ChannelConfig()
        options(&config)
        precondition(config.isPrivate && config.broadcast.replicationReady)
        let channel = TestChannel(topic: topic)
        channels[topic] = channel
        created += 1
        return channel
    }
    func removeChannel(_ channel: TestChannel) async {
        if holdRemoval { await withCheckedContinuation { pendingRemoval = $0 } }
        channel.events.finish()
        channel.statuses.finish()
        channel.systemEvents.finish()
        channels[channel.topic] = nil
        removals += 1
    }
}

@main struct FightLiveUpdatesTests {
    @MainActor static func main() async throws {
        let client = SupabaseClient()
        let live = FightLiveUpdates()
        let userID = UUID()
        var refreshes = 0
        var holdRefresh = false
        var pendingRefresh: CheckedContinuation<Void, Never>?
        let refresh: @MainActor () async -> Void = {
            refreshes += 1
            if holdRefresh { await withCheckedContinuation { pendingRefresh = $0 } }
        }
        await live.activate(client: client, userID: userID, refresh: refresh)
        while refreshes < 1 { await Task.yield() }
        precondition(client.channels.count == 1)
        let channel = client.channels.values.first!
        precondition(channel.topic == "fitfight:fights:\(userID.uuidString.lowercased())")

        for _ in 0..<100 { channel.events.yield(()) }
        try await Task.sleep(for: .milliseconds(650))
        precondition(refreshes >= 2 && refreshes <= 3, "A burst must coalesce to at most two rereads")

        holdRefresh = true
        channel.events.yield(())
        while pendingRefresh == nil { await Task.yield() }
        let duringRead = refreshes
        for _ in 0..<100 { channel.events.yield(()) }
        holdRefresh = false
        pendingRefresh?.resume()
        pendingRefresh = nil
        while refreshes == duringRead { await Task.yield() }
        precondition(refreshes == duringRead + 1, "Events arriving during a read must schedule another read")

        let beforeReconnect = refreshes
        channel.statuses.yield(.unsubscribed)
        channel.statuses.yield(.subscribed)
        while refreshes == beforeReconnect { await Task.yield() }

        let beforeReplication = refreshes
        channel.systemEvents.yield(SystemMessage(status: .ok))
        while refreshes == beforeReplication { await Task.yield() }

        client.holdRemoval = true
        let inactive = Task { await live.activate(client: client, userID: nil, refresh: refresh) }
        while client.pendingRemoval == nil { await Task.yield() }
        let activeAgain = Task { await live.activate(client: client, userID: userID, refresh: refresh) }
        try await Task.sleep(for: .milliseconds(20))
        precondition(client.created == 1, "Reactivation must wait for old topic removal")
        client.holdRemoval = false
        client.pendingRemoval?.resume()
        client.pendingRemoval = nil
        await inactive.value
        await activeAgain.value
        while client.created < 2 { await Task.yield() }
        precondition(client.removals == 1 && client.channels.count == 1)

        await live.activate(client: client, userID: UUID(), refresh: refresh)
        while client.created < 3 { await Task.yield() }
        precondition(client.channels.count == 1 && client.removals == 2)
        await live.activate(client: client, userID: nil, refresh: refresh)
        let stopped = refreshes
        channel.events.yield(())
        try await Task.sleep(for: .milliseconds(300))
        precondition(client.channels.isEmpty && refreshes == stopped, "Sign-out must stop callbacks and remove the channel")
        print("Fight live updates: burst, in-flight event, reconnect, reactivation, account change, sign-out passed")
    }
}
