import Foundation

enum AppRoute: Hashable {
    case createRound
    case createTrip
    case trip(String)
    case leaderboard(String)
    case score(tripID: String, roundID: String, playerID: String)
    case paywall(String)
    case legacyRounds
    case profile
}

/// Top-level tabs. Trip detail lives only in `.rounds`, so anything that opens a
/// trip from another tab must select this one first.
enum AppTab: Hashable, CaseIterable {
    case rounds
    case golfers
    case account

    var title: String {
        switch self {
        case .rounds: "Rounds"
        case .golfers: "Golfers"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .rounds: "flag.fill"
        case .golfers: "person.2.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}
