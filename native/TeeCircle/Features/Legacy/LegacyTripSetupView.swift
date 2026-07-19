import SwiftUI
import TeeCircleDomain

struct LegacyTripSetupView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.dismiss) private var dismiss

    let tripID: String
    let roundID: String

    @State private var selectedCourseCardID: String?
    @State private var courseName = ""
    @State private var holes: [RoundHole] = []
    @State private var handicapText: [String: String] = [:]
    @State private var didLoad = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                BroadcastBackground()
                if let experience = store.trip(id: tripID),
                   let round = experience.rounds.first(where: { $0.id == roundID })
                {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 7) {
                                BroadcastStatusPill(title: "Finish copy")
                                Text("Add the scoring card")
                                    .font(.system(size: 31, weight: .black, design: .rounded))
                                Text("The original round did not store par and stroke indexes. Choose a saved card or enter them once; TeeCircle copies them into this new trip.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            savedCards(round: round)
                            if selectedCourseCardID == nil {
                                manualCard(round: round)
                            }
                            handicaps(experience)

                            Button {
                                isSaving = true
                                Task {
                                    let finished = await store.finishLegacyConversionProduction(
                                        tripID: tripID,
                                        roundID: roundID,
                                        savedCourseCardID: selectedCourseCardID,
                                        courseName: courseName,
                                        holes: holes,
                                        handicaps: parsedHandicaps
                                    )
                                    isSaving = false
                                    if finished { dismiss() }
                                }
                            } label: {
                                HStack {
                                    Text(isSaving ? "Finishing trip…" : "Finish trip setup")
                                    Image(systemName: "checkmark.seal.fill")
                                }
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .foregroundStyle(TeeCircleBrand.forest)
                                .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 17))
                            }
                            .disabled(!canFinish(experience, round: round) || isSaving)
                            .opacity(canFinish(experience, round: round) ? 1 : 0.45)
                            .accessibilityIdentifier("legacy.finishSetup")
                        }
                        .padding(18)
                        .padding(.bottom, 30)
                    }
                    .onAppear { loadIfNeeded(experience, round: round) }
                } else {
                    TeeCircleUnavailableState(
                        title: "Setup unavailable",
                        systemImage: "flag.slash",
                        message: "Reload the trip and try again."
                    )
                }
            }
            .navigationTitle("Converted round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func savedCards(round: TripRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("COURSE CARD")
            Picker("Course card", selection: $selectedCourseCardID) {
                Text("Enter a new manual card").tag(String?.none)
                ForEach(store.courseCards.filter { $0.holes.count == round.holeCount }) { card in
                    Text(card.teeName.map { "\(card.name) · \($0)" } ?? card.name)
                        .tag(Optional(card.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("legacy.courseCardPicker")
            Text("Only \(round.holeCount)-hole cards are shown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .teeCard()
    }

    private func manualCard(round: TripRound) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("MANUAL CARD")
            TextField("Course name", text: $courseName)
                .textInputAutocapitalization(.words)
                .font(.headline)
                .padding(13)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("HOLE").frame(width: 42, alignment: .leading)
                Text("PAR").frame(maxWidth: .infinity)
                Text("INDEX").frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)

            ForEach(holes.indices, id: \.self) { index in
                HStack {
                    Text("\(holes[index].number)")
                        .font(.headline.monospaced().weight(.black))
                        .frame(width: 42, alignment: .leading)
                    Stepper(
                        "Par \(holes[index].par)",
                        value: Binding(
                            get: { holes[index].par },
                            set: { holes[index] = .init(number: index + 1, par: $0, strokeIndex: holes[index].strokeIndex) }
                        ),
                        in: 3...6
                    )
                    .labelsHidden()
                    Text("\(holes[index].par)").font(.headline.monospaced()).frame(width: 24)
                    Stepper(
                        "Index \(holes[index].strokeIndex ?? index + 1)",
                        value: Binding(
                            get: { holes[index].strokeIndex ?? index + 1 },
                            set: { holes[index] = .init(number: index + 1, par: holes[index].par, strokeIndex: $0) }
                        ),
                        in: 1...round.holeCount
                    )
                    .labelsHidden()
                    Text("\(holes[index].strokeIndex ?? index + 1)")
                        .font(.headline.monospaced())
                        .frame(width: 24)
                }
                .padding(.vertical, 5)
                if index < holes.count - 1 { Divider() }
            }
        }
        .padding(17)
        .teeCard()
    }

    private func handicaps(_ experience: LocalTripExperience) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PLAYING HANDICAPS")
            Text("Net Stableford needs a snapshot for every active player. These values stay attached to this trip.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(experience.players.filter { $0.rsvp != .declined }) { player in
                HStack {
                    Text(player.displayName).font(.subheadline.weight(.bold))
                    Spacer()
                    TextField("0.0", text: handicapBinding(player.id))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 76)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Handicap for \(player.displayName)")
                        .accessibilityIdentifier("legacy.handicap.\(player.id)")
                }
            }
        }
        .padding(17)
        .teeCard()
    }

    private var parsedHandicaps: [String: Double] {
        handicapText.reduce(into: [:]) { result, item in
            if let value = Double(item.value.trimmingCharacters(in: .whitespaces)) {
                result[item.key] = value
            }
        }
    }

    private func handicapBinding(_ playerID: String) -> Binding<String> {
        Binding(
            get: { handicapText[playerID, default: ""] },
            set: { handicapText[playerID] = $0 }
        )
    }

    private func canFinish(_ experience: LocalTripExperience, round: TripRound) -> Bool {
        let activePlayers = experience.players.filter { $0.rsvp != .declined }
        let validHandicaps = activePlayers.allSatisfy {
            guard let value = parsedHandicaps[$0.id] else { return false }
            return (-10...54).contains(value)
        }
        let savedCardIsValid = selectedCourseCardID.flatMap { id in
            store.courseCards.first(where: { $0.id == id })
        }?.holes.count == round.holeCount
        let indexes = holes.compactMap(\.strokeIndex)
        let manualCardIsValid = !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && holes.count == round.holeCount
            && Set(indexes) == Set(1...round.holeCount)
        return validHandicaps && (savedCardIsValid || manualCardIsValid)
    }

    private func loadIfNeeded(_ experience: LocalTripExperience, round: TripRound) {
        guard !didLoad else { return }
        didLoad = true
        courseName = round.courseName
        holes = Array(CreateTripDraft.standardHoles.prefix(round.holeCount)).enumerated().map {
            RoundHole(number: $0.offset + 1, par: $0.element.par, strokeIndex: $0.offset + 1)
        }
        handicapText = Dictionary(uniqueKeysWithValues: experience.players.map { player in
            let value = player.handicapSnapshot.map { String(format: "%.1f", $0) } ?? ""
            return (player.id, value)
        })
        selectedCourseCardID = store.courseCards.first(where: {
            $0.holes.count == round.holeCount && $0.name.caseInsensitiveCompare(round.courseName) == .orderedSame
        })?.id
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .tracking(1.1)
            .foregroundStyle(TeeCircleBrand.moss)
    }
}
