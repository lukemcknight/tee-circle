import Foundation
import Messages
import TeeCircleAPI
import TeeCircleDomain

@MainActor
final class MessagesViewModel: ObservableObject {
    enum PresentationMode: Equatable {
        case compact
        case expanded
        case transcript
    }

    enum ConnectionState: Equatable {
        case loading
        case connected
        case offline
        case reconnectRequired
        #if DEBUG
        case fixture
        #endif
    }

    @Published private(set) var trips: [CachedMessagesTripV1] = []
    @Published var selectedTripID: String?
    @Published private(set) var pendingInput: PendingHoleInputV1?
    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var reconnectTripIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSubmitting = false
    @Published var presentationMode: PresentationMode = .compact
    @Published var notice: String?

    private let configuration: MessagesConfiguration
    private let store: MessagesSharedStore
    private let service: MessagesService?
    private var credentials: [String: ExtensionSessionCredentialV1] = [:]
    private var refreshTask: Task<Void, Never>?

    init(configuration: MessagesConfiguration = .current) {
        self.configuration = configuration
        self.store = MessagesSharedStore(configuration: configuration)
        self.service = MessagesService(configuration: configuration)
    }

    var selectedTrip: CachedMessagesTripV1? {
        guard let selectedTripID else { return trips.first }
        return trips.first(where: { $0.id == selectedTripID })
    }

    var selectedTripNeedsReconnect: Bool {
        guard let selectedTrip else { return false }
        return reconnectTripIDs.contains(selectedTrip.id)
    }

    var selectedInviteURL: URL? {
        guard let selectedTrip else { return nil }
        return configuration.inviteURL(token: selectedTrip.inviteToken)
    }

    func activate(selectedMessageURL: URL?) {
        trips = store.loadTrips()
        credentials = store.loadCredentials()

        if let selectedMessageURL {
            selectTrip(from: selectedMessageURL)
        }
        if selectedTrip == nil {
            selectedTripID = trips.first?.id
        }
        preparePendingInput()
        classifyCredentials()

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshAll()
        }
    }

    func selectTrip(_ id: String) {
        guard trips.contains(where: { $0.id == id }) else { return }
        selectedTripID = id
        notice = nil
        preparePendingInput()
    }

    func selectTrip(from url: URL) {
        guard url.host?.lowercased() == configuration.webHost.lowercased(),
              url.pathComponents.count >= 3,
              url.pathComponents.dropFirst().first == "t",
              let token = url.pathComponents.last,
              let match = trips.first(where: { $0.inviteToken == token })
        else { return }
        selectedTripID = match.id
        preparePendingInput()
    }

    func refreshSelected() async {
        guard let selectedTrip else { return }
        await refresh(trip: selectedTrip)
    }

    func adjustHole(by delta: Int) {
        guard var input = pendingInput else { return }
        input.holeNumber = min(
            max(input.holeNumber + delta, 1),
            selectedTrip?.holeCount ?? 18
        )
        input.markEdited()
        save(input)
    }

    func adjustStrokes(by delta: Int) {
        guard var input = pendingInput else { return }
        input.strokes = min(max(input.strokes + delta, 1), 20)
        input.markEdited()
        save(input)
    }

    func adjustPenalties(by delta: Int) {
        guard var input = pendingInput else { return }
        input.penalties = min(max(input.penalties + delta, 0), 10)
        input.markEdited()
        save(input)
    }

    func submitScore() async {
        guard !isSubmitting,
              let trip = selectedTrip,
              let player = trip.claimedPlayer,
              let input = pendingInput
        else { return }

        guard !selectedTripNeedsReconnect else {
            notice = "Open TeeCircle to reconnect. Your score is saved here."
            return
        }

        #if DEBUG
        if trip.id == MessagesFixtures.trip.id, credentials[trip.id] == nil {
            acceptFixtureScore(input, trip: trip, player: player)
            return
        }
        #endif

        guard let credential = validCredential(for: trip.id), let service else {
            reconnectTripIDs.insert(trip.id)
            connectionState = .reconnectRequired
            notice = "Open TeeCircle to reconnect. Your score is saved here."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let command = ExtensionScoreCommandV1(
            roundId: input.roundId,
            tripPlayerId: input.tripPlayerId,
            holeNumber: input.holeNumber,
            strokes: input.strokes,
            penalties: input.penalties,
            idempotencyKey: input.idempotencyKey,
            expectedScoreRevision: trip.snapshot.revision
        )

        do {
            let result = try await service.recordScore(command, credential: credential)
            replaceTrip(trip.replacing(snapshot: result.snapshot))
            store.clearPendingInput(tripId: trip.id)
            preparePendingInput()
            notice = "Hole \(input.holeNumber) saved. Revision \(result.revision)."
            connectionState = .connected
        } catch let error as TeeCircleAPIClientError {
            await handleAPIError(error, trip: trip)
        } catch {
            connectionState = .offline
            notice = "Couldn’t reach TeeCircle. Your score is saved and ready to retry."
        }
    }

    func didQueueMessage(final: Bool, lifecycle: TripLifecycle) {
        if !final, [.draft, .ready].contains(lifecycle) {
            notice = "Round invite added to your message. Tap Send when the group is ready."
        } else {
            notice = final
                ? "Final result added to your message. Tap Send to post it."
                : "Standings added to your message. Tap Send to post this snapshot."
        }
    }

    func didFailToQueueMessage() {
        notice = "Messages couldn’t prepare that card. Try again."
    }

    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var attemptedNetwork = false
        for trip in trips {
            guard !Task.isCancelled else { return }
            if validCredential(for: trip.id) != nil {
                attemptedNetwork = true
                await refresh(trip: trip)
            }
        }

        #if DEBUG
        if !attemptedNetwork, trips.contains(where: { $0.id == MessagesFixtures.trip.id }) {
            connectionState = .fixture
            return
        }
        #endif

        if attemptedNetwork, reconnectTripIDs.count < trips.count, connectionState != .offline {
            connectionState = .connected
        }
    }

    private func refresh(trip: CachedMessagesTripV1) async {
        guard let credential = validCredential(for: trip.id), let service else {
            reconnectTripIDs.insert(trip.id)
            classifyCredentials()
            return
        }

        do {
            let payload = try await service.bootstrap(tripId: trip.id, credential: credential)
            guard payload.trip.id == trip.id else { return }
            let updated = trip.replacing(
                trip: payload.trip,
                player: .some(payload.player),
                scoringRoundId: .some(payload.scoringRoundId ?? trip.scoringRoundId),
                scoringRoundHoleCount: .some(
                    payload.scoringRoundHoleCount ?? trip.scoringRoundHoleCount
                ),
                snapshot: payload.snapshot
            )
            replaceTrip(updated)
            reconnectTripIDs.remove(trip.id)
            if selectedTripID == trip.id {
                preparePendingInput()
            }
            connectionState = .connected
        } catch let error as TeeCircleAPIClientError {
            await handleAPIError(error, trip: trip, refreshing: true)
        } catch {
            connectionState = .offline
        }
    }

    private func handleAPIError(
        _ error: TeeCircleAPIClientError,
        trip: CachedMessagesTripV1,
        refreshing: Bool = false
    ) async {
        if case let .server(statusCode, _) = error, statusCode == 401 || statusCode == 403 {
            reconnectTripIDs.insert(trip.id)
            connectionState = .reconnectRequired
            if !refreshing {
                notice = "Open TeeCircle to reconnect. Your score is still here."
            }
            return
        }

        if case let .server(_, envelope) = error,
           envelope?.error.currentRevision != nil,
           !refreshing {
            notice = "The score changed elsewhere. We refreshed the board; review and retry."
            await refresh(trip: trip)
            return
        }

        connectionState = .offline
        if !refreshing {
            notice = error.localizedDescription.isEmpty
                ? "Couldn’t save yet. Your score is ready to retry."
                : "Couldn’t save yet. Your score is ready to retry."
        }
    }

    private func validCredential(for tripId: String) -> ExtensionSessionCredentialV1? {
        guard let credential = credentials[tripId],
              credential.isUsable(deviceId: store.deviceIdentifier)
        else { return nil }
        return credential
    }

    private func classifyCredentials() {
        reconnectTripIDs = Set(trips.compactMap { trip in
            #if DEBUG
            if trip.id == MessagesFixtures.trip.id, credentials[trip.id] == nil {
                return nil
            }
            #endif
            return validCredential(for: trip.id) == nil ? trip.id : nil
        })

        #if DEBUG
        if trips.contains(where: { $0.id == MessagesFixtures.trip.id }), credentials.isEmpty {
            connectionState = .fixture
            return
        }
        #endif
        connectionState = reconnectTripIDs.isEmpty ? .connected : .reconnectRequired
    }

    private func preparePendingInput() {
        guard let trip = selectedTrip,
              let roundId = trip.scoringRoundId,
              let playerId = trip.claimedPlayer?.id,
              trip.trip.lifecycle == .live
        else {
            pendingInput = nil
            return
        }

        if var stored = store.pendingInput(for: trip) {
            stored.holeNumber = min(max(stored.holeNumber, 1), trip.holeCount)
            pendingInput = stored
        } else {
            pendingInput = PendingHoleInputV1(
                schemaVersion: 1,
                tripId: trip.id,
                roundId: roundId,
                tripPlayerId: playerId,
                holeNumber: trip.nextHole,
                strokes: 4,
                penalties: 0,
                idempotencyKey: UUID().uuidString.lowercased(),
                updatedAt: .now
            )
        }
    }

    private func save(_ input: PendingHoleInputV1) {
        pendingInput = input
        store.savePendingInput(input)
        notice = nil
    }

    private func replaceTrip(_ replacement: CachedMessagesTripV1) {
        guard let index = trips.firstIndex(where: { $0.id == replacement.id }) else { return }
        trips[index] = replacement
        store.saveTrips(trips)
    }

    #if DEBUG
    private func acceptFixtureScore(
        _ input: PendingHoleInputV1,
        trip: CachedMessagesTripV1,
        player: TripPlayer
    ) {
        isSubmitting = true
        let earned = max(0, 6 - input.strokes - input.penalties)
        let boards = trip.snapshot.boards.map { board in
            let updated = board.standings.map { standing in
                LeaderboardStandingV1(
                    playerId: standing.playerId,
                    displayName: standing.displayName,
                    rank: standing.rank,
                    value: standing.value + (
                        board.format == .stableford && standing.playerId == player.id ? earned : 0
                    ),
                    tied: standing.tied,
                    holesPlayed: standing.playerId == player.id
                        ? max(standing.holesPlayed, input.holeNumber)
                        : standing.holesPlayed
                )
            }
            let sorted = updated.sorted { $0.value == $1.value ? $0.displayName < $1.displayName : $0.value > $1.value }
            let ranked = sorted.enumerated().map { index, standing in
                LeaderboardStandingV1(
                    playerId: standing.playerId,
                    displayName: standing.displayName,
                    rank: index + 1,
                    value: standing.value,
                    tied: sorted.filter { $0.value == standing.value }.count > 1,
                    holesPlayed: standing.holesPlayed
                )
            }
            return LeaderboardBoardV1(format: board.format, scoring: board.scoring, standings: ranked)
        }
        let snapshot = LeaderboardSnapshotV1(
            tripId: trip.snapshot.tripId,
            revision: trip.snapshot.revision + 1,
            status: trip.snapshot.status,
            primaryFormat: trip.snapshot.primaryFormat,
            currentRound: trip.snapshot.currentRound.map {
                SnapshotRoundV1(
                    publicId: $0.publicId,
                    name: $0.name,
                    throughHole: max($0.throughHole, input.holeNumber)
                )
            },
            boards: boards,
            moment: .init(kind: .leadChange, summary: "\(player.displayName)’s score was accepted"),
            generatedAt: .now
        )
        replaceTrip(trip.replacing(snapshot: snapshot))
        store.clearPendingInput(tripId: trip.id)
        preparePendingInput()
        notice = "Hole \(input.holeNumber) saved in the simulator fixture."
        isSubmitting = false
    }
    #endif
}
