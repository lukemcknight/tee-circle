import SwiftUI
import TeeCircleDomain
import TeeCircleScoring

struct ScorecardView: View {
    @EnvironmentObject private var store: TeeCircleStore
    let tripID: String
    let roundID: String
    let initialPlayerID: String

    @State private var playerID: String
    @State private var holeNumber = 1
    @State private var stagedScore = 4
    @State private var stagedPenalties = 0
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, failed
    }

    init(tripID: String, roundID: String, initialPlayerID: String) {
        self.tripID = tripID
        self.roundID = roundID
        self.initialPlayerID = initialPlayerID
        _playerID = State(initialValue: initialPlayerID)
    }

    var body: some View {
        ZStack {
            BroadcastBackground()
            if let experience = store.trip(id: tripID), let round = experience.rounds.first(where: { $0.id == roundID }) {
                ScrollView {
                    VStack(spacing: 20) {
                        scoreHeader(experience, round: round)
                        if canScoreAnyPlayer(experience) { playerPicker(experience) }
                        holeRail(round)
                        scoreControl(experience, round: round)
                        scoreContext(experience, round: round)
                        saveButton
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            } else {
                TeeCircleUnavailableState(title: "Scorecard unavailable", systemImage: "square.grid.3x3")
            }
        }
        .navigationTitle("Score hole")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { loadExistingScore() }
    }

    private func scoreHeader(_ experience: LocalTripExperience, round: TripRound) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                BroadcastStatusPill(title: "Live", live: true)
                Spacer()
                Text(experience.trip.scoringMode.rawValue.uppercased())
                    .font(.caption2.weight(.black)).tracking(1).foregroundStyle(.secondary)
            }
            Text(round.courseName)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-0.8)
            Text(round.name).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerPicker(_ experience: LocalTripExperience) -> some View {
        Picker("Scoring for", selection: $playerID) {
            ForEach(experience.players) { player in
                Text(player.displayName).tag(player.id)
            }
        }
        .pickerStyle(.menu)
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .teeCard()
        .onChange(of: playerID) { _ in loadExistingScore() }
    }

    private func holeRail(_ round: TripRound) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(round.holes) { hole in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { holeNumber = hole.number }
                            loadExistingScore()
                        } label: {
                            VStack(spacing: 3) {
                                Text("H\(hole.number)").font(.caption2.weight(.black))
                                Text("\(hole.par)").font(.headline.monospaced().weight(.black))
                            }
                            .foregroundStyle(holeNumber == hole.number ? TeeCircleBrand.forest : .secondary)
                            .frame(width: 49, height: 52)
                            .background(holeNumber == hole.number ? TeeCircleBrand.signal : .white, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .id(hole.number)
                    }
                }
            }
            .onChange(of: holeNumber) { newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func scoreControl(_ experience: LocalTripExperience, round: TripRound) -> some View {
        let hole = currentHole(round)
        return VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HOLE \(hole.number)").font(.caption.weight(.black)).tracking(1.2).foregroundStyle(TeeCircleBrand.moss)
                    Text("Par \(hole.par) · Index \(hole.strokeIndex ?? hole.number)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                saveStatus
            }

            HStack(spacing: 28) {
                scoreButton("minus") { stagedScore = max(1, stagedScore - 1) }
                VStack(spacing: 1) {
                    ScoreboardNumber(value: "\(grossScore)", size: 72)
                    Text(relativeToPar(grossScore, par: hole.par))
                        .font(.caption.weight(.black)).tracking(1).foregroundStyle(.secondary)
                }
                scoreButton("plus") { stagedScore += 1 }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PENALTY STROKES")
                        .font(.caption2.weight(.black))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                    Text("Included in the gross score above")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                scoreButton("minus") { stagedPenalties = max(0, stagedPenalties - 1) }
                ScoreboardNumber(value: "\(stagedPenalties)", size: 28)
                    .frame(minWidth: 34)
                scoreButton("plus") { stagedPenalties = min(10, stagedPenalties + 1) }
            }
        }
        .padding(21)
        .teeCard()
    }

    private func scoreContext(_ experience: LocalTripExperience, round: TripRound) -> some View {
        let hole = currentHole(round)
        let participation = experience.roundPlayers.first {
            $0.roundId == roundID && $0.tripPlayerId == playerID
        }
        let handicap = participation?.playingHandicap ?? participation?.courseHandicap ?? 0
        let received = TeeCircleScoring.strokesReceived(
            on: hole.strokeIndex ?? hole.number,
            courseHandicap: handicap,
            holeCount: round.holes.count
        )
        let net = experience.trip.scoringMode == .net ? grossScore - received : grossScore
        let points = TeeCircleScoring.stablefordPoints(netStrokes: net, par: hole.par)

        return HStack(spacing: 0) {
            contextMetric("STROKES", "\(received)")
            Divider().frame(height: 38)
            contextMetric("NET", "\(net)")
            Divider().frame(height: 38)
            contextMetric("POINTS", "\(points)")
        }
        .padding(.vertical, 15)
        .teeCard()
    }

    private var saveButton: some View {
        Button {
            saveState = .saving
            Task {
                let outcome = await store.submitScore(
                    tripID: tripID,
                    roundID: roundID,
                    playerID: playerID,
                    hole: holeNumber,
                    strokes: stagedScore,
                    penalties: stagedPenalties
                )
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    switch outcome {
                    case .saved: saveState = .saved
                    case .queued: saveState = .failed
                    case let .conflict(message), let .failed(message):
                        saveState = .idle
                        store.errorMessage = message
                        loadExistingScore()
                    }
                }
            }
        } label: {
            HStack {
                Text(saveState == .saving ? "Saving…" : "Save hole \(holeNumber)")
                Image(systemName: saveState == .saved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
            }
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(TeeCircleBrand.forest)
            .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 17))
        }
        .disabled(saveState == .saving)
        .accessibilityIdentifier("score.saveHole")
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch saveState {
        case .idle: EmptyView()
        case .saving: ProgressView().controlSize(.small)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold)).foregroundStyle(TeeCircleBrand.moss)
        case .failed:
            Label("Pending", systemImage: "wifi.exclamationmark")
                .font(.caption.weight(.bold)).foregroundStyle(.orange)
        }
    }

    private func scoreButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.black))
                .frame(width: 55, height: 55)
                .foregroundStyle(TeeCircleBrand.signal)
                .background(TeeCircleBrand.signal.opacity(0.14), in: Circle())
        }
    }

    private func contextMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2.weight(.black)).tracking(0.9).foregroundStyle(.secondary)
            ScoreboardNumber(value: value, size: 22)
        }
        .frame(maxWidth: .infinity)
    }

    private func currentHole(_ round: TripRound) -> RoundHole {
        round.holes.first(where: { $0.number == holeNumber }) ?? round.holes[0]
    }

    private func loadExistingScore() {
        guard let experience = store.trip(id: tripID) else { return }
        let key = HoleScoreKey(roundID: roundID, playerID: playerID, hole: holeNumber)
        let stored = experience.scores[key]
        stagedScore = stored?.strokes ?? experience.rounds
            .first(where: { $0.id == roundID })?.holes
            .first(where: { $0.number == holeNumber })?.par ?? 4
        stagedPenalties = stored?.penalties ?? 0
        saveState = .idle
        if store.pendingScoreKeys.contains(key) {
            saveState = .failed
        }
    }

    private var grossScore: Int { stagedScore + stagedPenalties }

    private func canScoreAnyPlayer(_ experience: LocalTripExperience) -> Bool {
        experience.trip.ownerId == store.currentUserID || experience.players.contains {
            $0.claimedUserId == store.currentUserID && $0.role == .scorer
        }
    }

    private func relativeToPar(_ strokes: Int, par: Int) -> String {
        switch strokes - par {
        case ...(-2): "EAGLE OR BETTER"
        case -1: "BIRDIE"
        case 0: "PAR"
        case 1: "BOGEY"
        default: "+\(strokes - par)"
        }
    }
}
