import Foundation

struct QueuedHoleScore: Codable, Equatable, Identifiable, Sendable {
    var id: String { idempotencyKey }
    let tripID: String
    let userID: String
    let roundID: String
    let playerID: String
    let holeNumber: Int
    let strokes: Int
    let penalties: Int
    /// The authoritative global revision visible when the user entered this score.
    /// Retrying with a newer revision would silently defeat conflict detection.
    let expectedRevision: Int
    let idempotencyKey: String
    let queuedAt: Date
}

/// A small, device-local retry ledger. Scores remain idempotent because retries
/// retain both the original command key and concurrency token. Entries are also
/// bound to the Supabase user that created them so a later login cannot submit
/// another person's offline score.
actor PendingScoreQueue {
    private let defaults: UserDefaults
    private let key = "teecircle.native.pending-scores.v2"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(appGroupIdentifier: String = TeeCircleSharedSecurity.appGroupIdentifier) {
        defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func all() -> [QueuedHoleScore] {
        guard let data = defaults.data(forKey: key),
              let values = try? decoder.decode([QueuedHoleScore].self, from: data)
        else { return [] }
        return values.sorted { $0.queuedAt < $1.queuedAt }
    }

    func enqueue(_ score: QueuedHoleScore) {
        var values = all().filter { existing in
            !(existing.tripID == score.tripID
              && existing.roundID == score.roundID
              && existing.playerID == score.playerID
              && existing.holeNumber == score.holeNumber)
        }
        values.append(score)
        persist(values)
    }

    func remove(id: String) {
        persist(all().filter { $0.id != id })
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ values: [QueuedHoleScore]) {
        guard !values.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? encoder.encode(values) {
            defaults.set(data, forKey: key)
        }
    }
}
