import Foundation
import Supabase

/// Realtime events are deliberately treated as hints. The app always reloads
/// the versioned bootstrap so a websocket payload can never become a second
/// leaderboard contract.
@MainActor
final class TripRealtimeHintService {
    private let client: SupabaseClient
    private var channels: [String: RealtimeChannelV2] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    init(client: SupabaseClient) {
        self.client = client
    }

    func observe(tripID: String, onHint: @escaping @MainActor @Sendable () async -> Void) {
        guard tasks[tripID] == nil else { return }
        let channel = client.channel("tee-trip-snapshot-\(tripID)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "trip_leaderboard_snapshots",
            filter: .eq("trip_id", value: tripID)
        )
        channels[tripID] = channel
        tasks[tripID] = Task { [weak self] in
            do {
                try await channel.subscribeWithError()
                for await _ in changes {
                    guard !Task.isCancelled else { break }
                    await onHint()
                }
            } catch {
                // The visible-screen refresh timer remains the network fallback.
            }
            await channel.unsubscribe()
            self?.channels.removeValue(forKey: tripID)
            self?.tasks.removeValue(forKey: tripID)
        }
    }

    func stopObserving(tripID: String) {
        tasks.removeValue(forKey: tripID)?.cancel()
        if let channel = channels.removeValue(forKey: tripID) {
            Task { await channel.unsubscribe() }
        }
    }

    func stopAll() async {
        let activeChannels = Array(channels.values)
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        channels.removeAll()
        for channel in activeChannels { await channel.unsubscribe() }
    }
}
