import Foundation
import Combine
import Supabase
import OSLog

@MainActor
final class FightLiveUpdates: ObservableObject {
    private var task: Task<Void, Never>?
    private var generation = 0
    private static let logger = Logger(subsystem: "com.fitfight.mvp", category: "FightLiveUpdates")

    func activate(
        client: SupabaseClient,
        userID: UUID?,
        refresh: @escaping @MainActor () async -> Void,
        refreshFeed: @escaping @MainActor () async -> Void = {}
    ) async {
        generation += 1
        let activation = generation
        task?.cancel()
        // The SDK reuses topics. Finish removing the old channel before joining again.
        await task?.value
        guard generation == activation, !Task.isCancelled else { return }
        task = nil
        guard let userID else { return }
        task = Task {
            let channel = client.channel("fitfight:fights:\(userID.uuidString.lowercased())") {
                $0.isPrivate = true
                $0.broadcast.replicationReady = true
            }
            let messages = channel.broadcastStream(event: "fights_changed")
            let feedMessages = channel.broadcastStream(event: "feed_changed")
            let statuses = channel.statusChange
            let systemMessages = channel.system()
            let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let (feedChanges, feedContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in messages { continuation.yield(()) }
                }
                group.addTask {
                    for await _ in feedMessages { feedContinuation.yield(()) }
                }
                group.addTask {
                    for await status in statuses where status == .subscribed {
                        // A reconnect can have missed any number of broadcasts.
                        continuation.yield(())
                        feedContinuation.yield(())
                    }
                }
                group.addTask {
                    // Joining the socket can finish before database replication is ready.
                    for await message in systemMessages where message.status == .ok {
                        continuation.yield(())
                        feedContinuation.yield(())
                    }
                }
                group.addTask { @MainActor in
                    for await _ in changes {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard !Task.isCancelled else { return }
                        await refresh()
                    }
                }
                group.addTask { @MainActor in
                    for await _ in feedChanges {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard !Task.isCancelled else { return }
                        await refreshFeed()
                    }
                }
                do {
                    try await channel.subscribeWithError()
                    await group.waitForAll()
                } catch {
                    if !Task.isCancelled {
                        Self.logger.error("fight_live_subscription_failed")
                    }
                    group.cancelAll()
                }
                continuation.finish()
                feedContinuation.finish()
            }
            await client.removeChannel(channel)
        }
    }
}
