import Foundation
import TeeCircleDomain

/// Deterministic scoring helpers mirrored from the production TypeScript engine.
public enum TeeCircleScoring {
    public static func strokesReceived(
        on strokeIndex: Int,
        courseHandicap: Int,
        holeCount: Int = 18
    ) -> Int {
        guard (holeCount == 9 || holeCount == 18),
              (1...holeCount).contains(strokeIndex),
              courseHandicap != 0
        else { return 0 }

        let magnitude = abs(courseHandicap)
        let base = magnitude / holeCount
        let remainder = magnitude % holeCount
        if courseHandicap > 0 {
            return base + (strokeIndex <= remainder ? 1 : 0)
        }

        // Plus handicaps give strokes back from the highest allocation index.
        return -(base + (remainder > 0 && strokeIndex > holeCount - remainder ? 1 : 0))
    }

    public static func netStrokes(
        for hole: HoleScore,
        courseHandicap: Int,
        scoring: ScoringMode,
        holeCount: Int = 18
    ) -> Int? {
        guard let strokes = hole.strokes else { return nil }
        let gross = strokes + hole.penalties
        guard scoring == .net else { return gross }
        return gross - strokesReceived(
            on: hole.strokeIndex,
            courseHandicap: courseHandicap,
            holeCount: holeCount
        )
    }

    public static func stablefordPoints(netStrokes: Int?, par: Int) -> Int {
        guard let netStrokes else { return 0 }
        return max(0, 2 - (netStrokes - par))
    }

    public static func stableford(
        players: [PlayerRound],
        scoring: ScoringMode = .net,
        holeCount: Int = 18
    ) -> [PlayerStanding] {
        players.enumerated()
            .map { index, player in
                let value = player.holes.reduce(into: 0) { total, hole in
                    total += stablefordPoints(
                        netStrokes: netStrokes(
                            for: hole,
                            courseHandicap: player.courseHandicap,
                            scoring: scoring,
                            holeCount: holeCount
                        ),
                        par: hole.par
                    )
                }
                return IndexedStanding(index: index, standing: PlayerStanding(playerId: player.playerId, value: value))
            }
            .sorted(by: standingSort)
            .map(\.standing)
    }

    public static func skins(
        players: [PlayerRound],
        scoring: ScoringMode = .net,
        holeCount: Int = 18
    ) -> SkinsResult {
        skinsRound(
            players: players,
            scoring: scoring,
            holeCount: holeCount,
            initialCarry: 1
        )
    }

    private static func skinsRound(
        players: [PlayerRound],
        scoring: ScoringMode,
        holeCount: Int,
        initialCarry: Int
    ) -> SkinsResult {
        let holeNumbers = Set(players.flatMap { $0.holes.map(\.hole) }).sorted()
        var won: [String: Int] = [:]
        players.forEach { won[$0.playerId] = 0 }
        var resolvedHoles: [SkinsHoleResult] = []
        var carry = initialCarry

        for holeNumber in holeNumbers {
            let scores: [(playerId: String, net: Int?)] = players.map { player in
                let hole = player.holes.first(where: { $0.hole == holeNumber })
                return (
                    player.playerId,
                    hole.flatMap {
                        netStrokes(
                            for: $0,
                            courseHandicap: player.courseHandicap,
                            scoring: scoring,
                            holeCount: holeCount
                        )
                    }
                )
            }

            // The live board cannot resolve beyond the first hole missing any active player.
            guard scores.allSatisfy({ $0.net != nil }) else { break }
            guard let lowest = scores.compactMap(\.net).min() else { continue }
            let winners = scores.filter { $0.net == lowest }

            if winners.count == 1, let winner = winners.first {
                won[winner.playerId, default: 0] += carry
                resolvedHoles.append(.won(hole: holeNumber, winnerId: winner.playerId, skins: carry))
                carry = 1
            } else {
                resolvedHoles.append(.carried(hole: holeNumber, carried: carry))
                carry += 1
            }
        }

        let standings = players.enumerated()
            .map { index, player in
                IndexedStanding(
                    index: index,
                    standing: PlayerStanding(playerId: player.playerId, value: won[player.playerId, default: 0])
                )
            }
            .sorted(by: standingSort)
            .map(\.standing)

        return SkinsResult(holes: resolvedHoles, standings: standings, carry: carry)
    }

    /// Aggregates trip skins while retaining unresolved carry between rounds.
    public static func tripSkins(
        rounds: [[PlayerRound]],
        scoring: ScoringMode = .net,
        holeCounts: [Int] = []
    ) -> SkinsResult {
        var totals: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var nextIndex = 0
        var carry = 1
        var holes: [SkinsHoleResult] = []

        for (roundIndex, players) in rounds.enumerated() {
            for player in players where firstSeen[player.playerId] == nil {
                firstSeen[player.playerId] = nextIndex
                nextIndex += 1
            }
            let holeCount = holeCounts.indices.contains(roundIndex) ? holeCounts[roundIndex] : 18
            let result = skinsRound(
                players: players,
                scoring: scoring,
                holeCount: holeCount,
                initialCarry: carry
            )
            carry = result.carry
            holes.append(contentsOf: result.holes)
            for standing in result.standings {
                totals[standing.playerId, default: 0] += standing.value
            }
        }

        let standings = totals.map { playerId, value in
            IndexedStanding(
                index: firstSeen[playerId, default: .max],
                standing: PlayerStanding(playerId: playerId, value: value)
            )
        }
        .sorted(by: standingSort)
        .map(\.standing)

        return SkinsResult(holes: holes, standings: standings, carry: carry)
    }

    public static func tripStandings(
        rounds: [[PlayerRound]],
        format: TournamentFormat,
        scoring: ScoringMode = .net,
        holeCounts: [Int] = []
    ) -> [PlayerStanding] {
        if format == .skins {
            return tripSkins(
                rounds: rounds,
                scoring: scoring,
                holeCounts: holeCounts
            ).standings
        }

        var totals: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var nextIndex = 0

        for (roundIndex, players) in rounds.enumerated() {
            for player in players where firstSeen[player.playerId] == nil {
                firstSeen[player.playerId] = nextIndex
                nextIndex += 1
            }
            let holeCount = holeCounts.indices.contains(roundIndex) ? holeCounts[roundIndex] : 18
            let roundStandings = stableford(
                players: players,
                scoring: scoring,
                holeCount: holeCount
            )

            for standing in roundStandings {
                totals[standing.playerId, default: 0] += standing.value
            }
        }

        return totals.map { playerId, value in
            IndexedStanding(
                index: firstSeen[playerId, default: .max],
                standing: PlayerStanding(playerId: playerId, value: value)
            )
        }
        .sorted(by: standingSort)
        .map(\.standing)
    }

    private struct IndexedStanding {
        let index: Int
        let standing: PlayerStanding
    }

    private static func standingSort(_ lhs: IndexedStanding, _ rhs: IndexedStanding) -> Bool {
        if lhs.standing.value != rhs.standing.value {
            return lhs.standing.value > rhs.standing.value
        }
        return lhs.index < rhs.index
    }
}
