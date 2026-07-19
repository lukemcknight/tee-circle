import Foundation
import TeeCircleDomain

/// A person you have shared a roster with. TeeCircle 2.0 has no friend graph —
/// this is derived entirely from trips already in memory, so there is nothing to
/// request, accept, or keep in sync.
struct GolferSummary: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    /// False for a seat the captain named that nobody ever claimed. Those people
    /// are still real playing partners, they just have no account behind them.
    let isOnTeeCircle: Bool
    let sharedTripIDs: [String]
    let roundsTogether: Int
    let lastPlayed: Date?

    var initials: String {
        let parts = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

extension TeeCircleStore {
    /// Aggregated across every loaded trip. Claimed seats merge on user id;
    /// unclaimed seats merge on lowercased name, so the same buddy typed into two
    /// different trips still lands as one row.
    var golfers: [GolferSummary] {
        var accumulator: [String: GolferSummary] = [:]

        for experience in trips {
            let mySeatID = experience.players
                .first(where: { $0.claimedUserId == currentUserID })?
                .id
            let playedOn = lastPlayedDate(for: experience)

            for player in experience.players where player.id != mySeatID {
                guard player.claimedUserId != currentUserID else { continue }

                let key = player.claimedUserId ?? "name:\(player.displayName.lowercased())"
                let existing = accumulator[key]

                accumulator[key] = GolferSummary(
                    id: key,
                    displayName: existing?.displayName ?? player.displayName,
                    isOnTeeCircle: (existing?.isOnTeeCircle ?? false) || player.claimedUserId != nil,
                    sharedTripIDs: (existing?.sharedTripIDs ?? []) + [experience.id],
                    roundsTogether: (existing?.roundsTogether ?? 0) + experience.rounds.count,
                    lastPlayed: [existing?.lastPlayed, playedOn].compactMap { $0 }.max()
                )
            }
        }

        return accumulator.values.sorted { left, right in
            switch (left.lastPlayed, right.lastPlayed) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
        }
    }

    func trips(for golfer: GolferSummary) -> [LocalTripExperience] {
        golfer.sharedTripIDs.compactMap { trip(id: $0) }
    }

    private func lastPlayedDate(for experience: LocalTripExperience) -> Date? {
        let scheduled = experience.rounds.compactMap(\.scheduledAt).max()
        return scheduled ?? DateFormatter.golferTripDate.date(from: experience.trip.startDate)
    }
}

extension DateFormatter {
    static let golferTripDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
