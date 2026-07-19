import SwiftUI
import TeeCircleDomain

struct CreateTripView: View {
    private enum Step: Int, CaseIterable {
        case basics, rounds, courseCard, roster, competition, review

        var title: String {
            switch self {
            case .basics: "The trip"
            case .rounds: "The rounds"
            case .courseCard: "Course cards"
            case .roster: "The roster"
            case .competition: "The competition"
            case .review: "Ready room"
            }
        }
    }

    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .basics
    @State private var draft = CreateTripDraft()
    @State private var selectedCourseRound = 0
    @State private var isCreating = false
    @State private var didSeedCaptain = false

    var body: some View {
        ZStack {
            BroadcastBackground()
            VStack(spacing: 0) {
                progressHeader
                ScrollView {
                    Group {
                        switch step {
                        case .basics: basics
                        case .rounds: rounds
                        case .courseCard: courseCard
                        case .roster: roster
                        case .competition: competition
                        case .review: review
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { actionBar }
        .onAppear {
            guard !didSeedCaptain else { return }
            didSeedCaptain = true
            if draft.playerNames.first == "You" {
                draft.playerNames[0] = store.currentDisplayName
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? TeeCircleBrand.signal : Color.secondary.opacity(0.16))
                        .frame(height: 4)
                }
            }
            Text("STEP \(step.rawValue + 1) OF \(Step.allCases.count)")
                .font(.caption2.weight(.black))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Name the weekend", detail: "This is what the group sees in every shared board and Live Activity.")
            VStack(spacing: 14) {
                TeeField(title: "TRIP NAME") {
                    TextField("Pinehurst Cup", text: $draft.name)
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("create.tripName")
                }
                TeeField(title: "START") {
                    DatePicker("Start date", selection: $draft.startDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                TeeField(title: "FINISH") {
                    DatePicker("End date", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var rounds: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Build the card", detail: "Add every round now. You can still adjust the schedule before the tournament goes live.")
            ForEach($draft.rounds) { $round in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Round name", text: $round.name)
                            .font(.headline.weight(.bold))
                        if draft.rounds.count > 1 {
                            Button(role: .destructive) {
                                draft.rounds.removeAll { $0.id == round.id }
                            } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove round")
                        }
                    }
                    TextField("Course name", text: $round.courseName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("create.courseName")
                    DatePicker("Tee time", selection: $round.scheduledAt)
                    Picker("Length", selection: $round.holeCount) {
                        Text("9 holes").tag(9)
                        Text("18 holes").tag(18)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: round.holeCount) { holeCount in
                        normalizeCourseCard(roundID: round.id, holeCount: holeCount)
                    }
                }
                .padding(17)
                .teeCard()
            }
            Button {
                let number = draft.rounds.count + 1
                draft.rounds.append(.init(name: "Round \(number)", scheduledAt: draft.endDate))
            } label: {
                Label("Add another round", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(TeeCircleBrand.signal)
                    .background(TeeCircleBrand.signal.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var courseCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Enter it once", detail: "Par and stroke index are copied into the round. Future edits never rewrite historical scoring.")

            if draft.rounds.count > 1 {
                Picker("Round", selection: $selectedCourseRound) {
                    ForEach(draft.rounds.indices, id: \.self) { index in
                        Text("R\(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text(draft.rounds[selectedCourseRound].courseName.uppercased())
                    .font(.caption.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(TeeCircleBrand.moss)
                Spacer()
                if !store.courseCards.isEmpty {
                    Menu("Use saved card") {
                        ForEach(store.courseCards) { card in
                            Button(card.teeName.map { "\(card.name) · \($0)" } ?? card.name) {
                                apply(card, toRoundAt: selectedCourseRound)
                            }
                        }
                    }
                    .font(.caption.weight(.bold))
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Text("HOLE").frame(width: 48, alignment: .leading)
                    Text("PAR").frame(maxWidth: .infinity)
                    Text("INDEX").frame(maxWidth: .infinity)
                }
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

                ForEach(
                    Array(draft.rounds[selectedCourseRound].holes.indices.prefix(
                        draft.rounds[selectedCourseRound].holeCount
                    )),
                    id: \.self
                ) { index in
                    HStack {
                        Text("\(index + 1)")
                            .font(.headline.monospaced().weight(.black))
                            .frame(width: 48, alignment: .leading)
                        Stepper(
                            "\(draft.rounds[selectedCourseRound].holes[index].par)",
                            value: Binding(
                                get: { draft.rounds[selectedCourseRound].holes[index].par },
                                set: { value in
                                    let old = draft.rounds[selectedCourseRound].holes[index]
                                    draft.rounds[selectedCourseRound].holes[index] = .init(number: old.number, par: value, strokeIndex: old.strokeIndex)
                                }
                            ),
                            in: 3...6
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Text("\(draft.rounds[selectedCourseRound].holes[index].par)")
                            .font(.headline.monospaced())
                            .frame(width: 22)

                        Stepper(
                            "\(draft.rounds[selectedCourseRound].holes[index].strokeIndex ?? index + 1)",
                            value: Binding(
                                get: { draft.rounds[selectedCourseRound].holes[index].strokeIndex ?? index + 1 },
                                set: { value in
                                    let old = draft.rounds[selectedCourseRound].holes[index]
                                    draft.rounds[selectedCourseRound].holes[index] = .init(number: old.number, par: old.par, strokeIndex: value)
                                }
                            ),
                            in: 1...draft.rounds[selectedCourseRound].holeCount
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Text("\(draft.rounds[selectedCourseRound].holes[index].strokeIndex ?? index + 1)")
                            .font(.headline.monospaced())
                            .frame(width: 22)
                    }
                    .padding(.vertical, 9)
                    if index < draft.rounds[selectedCourseRound].holes.count - 1 { Divider() }
                }
            }
            .padding(16)
            .teeCard()

            Text("This manual card is saved to your course-card library when the trip is created.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ card: CourseCard, toRoundAt index: Int) {
        guard draft.rounds.indices.contains(index) else { return }
        draft.rounds[index].courseName = card.name
        draft.rounds[index].holeCount = card.holes.count <= 9 ? 9 : 18
        draft.rounds[index].holes = card.holes.map {
            RoundHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
        }
        normalizeCourseCard(
            roundID: draft.rounds[index].id,
            holeCount: draft.rounds[index].holeCount
        )
    }

    /// Native v2 treats a nine-hole card as its own 1...9 allocation. Keep the
    /// draft structurally valid when the captain changes length or reuses a card.
    private func normalizeCourseCard(roundID: UUID, holeCount: Int) {
        guard let roundIndex = draft.rounds.firstIndex(where: { $0.id == roundID }),
              holeCount == 9 || holeCount == 18
        else { return }

        var holes = Array(draft.rounds[roundIndex].holes.prefix(holeCount))
        if holes.count < holeCount {
            holes.append(contentsOf: CreateTripDraft.standardHoles.dropFirst(holes.count).prefix(holeCount - holes.count))
        }

        let indexes = holes.compactMap(\.strokeIndex)
        let hasValidAllocation = indexes.count == holeCount && Set(indexes) == Set(1...holeCount)
        holes = holes.enumerated().map { offset, hole in
            RoundHole(
                number: offset + 1,
                par: hole.par,
                strokeIndex: hasValidAllocation ? hole.strokeIndex : offset + 1
            )
        }
        draft.rounds[roundIndex].holes = holes
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Put names on the board", detail: "Players claim their own open seat from the shared link. You can revoke or reassign it later.")

            ForEach(draft.playerNames.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospaced().weight(.black))
                        .foregroundStyle(index == 0 ? TeeCircleBrand.forest : .secondary)
                        .frame(width: 34, height: 34)
                        .background(index == 0 ? TeeCircleBrand.signal : Color.secondary.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(index == 0 ? "You" : "Player name", text: $draft.playerNames[index])
                            .font(.headline.weight(.bold))
                        HStack(spacing: 10) {
                            TextField(
                                "Handicap (required for net)",
                                value: $draft.playerHandicaps[index],
                                format: .number.precision(.fractionLength(1))
                            )
                            .font(.caption)
                            .keyboardType(.decimalPad)

                            if draft.playerHandicaps[index] != nil {
                                Button {
                                    draft.playerHandicaps[index] = -(draft.playerHandicaps[index] ?? 0)
                                } label: {
                                    Text((draft.playerHandicaps[index] ?? 0) < 0 ? "PLUS" : "REG")
                                        .font(.caption2.weight(.black))
                                        .tracking(0.7)
                                        .frame(minWidth: 42)
                                }
                                .buttonStyle(.bordered)
                                .tint((draft.playerHandicaps[index] ?? 0) < 0 ? TeeCircleBrand.signal : .secondary)
                                .accessibilityLabel(
                                    (draft.playerHandicaps[index] ?? 0) < 0
                                        ? "Plus handicap; tap for regular handicap"
                                        : "Regular handicap; tap for plus handicap"
                                )
                            }
                        }
                    }
                    if index > 0 {
                        Button(role: .destructive) {
                            draft.playerNames.remove(at: index)
                            draft.playerHandicaps.remove(at: index)
                        } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove player")
                    }
                }
                .padding(15)
                .teeCard()
            }

            Button {
                draft.playerNames.append("")
                draft.playerHandicaps.append(nil)
            } label: {
                Label("Add a roster seat", systemImage: "person.badge.plus")
                    .font(.headline)
            }
            .foregroundStyle(TeeCircleBrand.signal)
            .accessibilityIdentifier("create.addRosterSeat")
        }
    }

    private var competition: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Choose the signal", detail: "The primary format leads compact Messages cards. Players can still switch boards in TeeCircle.")

            VStack(alignment: .leading, spacing: 14) {
                Text("FORMATS").teeLabel()
                ForEach(TournamentFormat.allCases, id: \.self) { format in
                    Button {
                        if draft.enabledFormats.contains(format), draft.enabledFormats.count > 1 {
                            draft.enabledFormats.remove(format)
                        } else {
                            draft.enabledFormats.insert(format)
                        }
                        if !draft.enabledFormats.contains(draft.primaryFormat) {
                            draft.primaryFormat = draft.enabledFormats.first ?? .stableford
                        }
                    } label: {
                        HStack {
                            Image(systemName: draft.enabledFormats.contains(format) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.enabledFormats.contains(format) ? TeeCircleBrand.signal : .secondary)
                            VStack(alignment: .leading) {
                                Text(format == .stableford ? "Stableford" : "Skins")
                                    .font(.headline.weight(.bold))
                                Text(format == .stableford ? "Points against par" : "Low score wins the hole; ties carry")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                Text("PRIMARY BOARD").teeLabel()
                Picker("Primary board", selection: $draft.primaryFormat) {
                    ForEach(TournamentFormat.allCases.filter { draft.enabledFormats.contains($0) }, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                Text("SCORING").teeLabel()
                HStack(spacing: 4) {
                    scoringModeButton(.net, title: "Net")
                    scoringModeButton(.gross, title: "Gross")
                }
                .padding(4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(18)
            .teeCard()

            if draft.scoringMode == .net && draft.playerHandicaps.contains(where: { $0 == nil }) {
                Label("Add every handicap before the tournament can go live.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageLead("Your ready room", detail: "Build and share for free. The captain unlocks live scoring when the group is ready.")

            VStack(alignment: .leading, spacing: 18) {
                BroadcastStatusPill(title: "Draft")
                Text(draft.name.isEmpty ? "Untitled Golf Trip" : draft.name)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                HStack(spacing: 24) {
                    reviewMetric("ROUNDS", "\(draft.rounds.count)")
                    reviewMetric("PLAYERS", "\(draft.playerNames.filter { !$0.isEmpty }.count)")
                    reviewMetric("FORMAT", draft.primaryFormat.rawValue.uppercased())
                }
                Divider()
                ForEach(Array(draft.rounds.enumerated()), id: \.element.id) { index, round in
                    HStack {
                        Text("\(index + 1)").font(.headline.monospaced().weight(.black))
                        VStack(alignment: .leading) {
                            Text(round.name).font(.headline.weight(.bold))
                            Text(round.courseName.isEmpty ? "Course TBD" : round.courseName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(round.holeCount)H").font(.caption.weight(.black))
                    }
                }
            }
            .padding(20)
            .teeCard()
        }
    }

    private func scoringModeButton(_ mode: ScoringMode, title: String) -> some View {
        let selected = draft.scoringMode == mode
        return Button {
            draft.scoringMode = mode
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(
                    selected ? TeeCircleBrand.pine : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("create.scoring.\(mode.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if step != .basics {
                Button {
                    guard let previous = Step(rawValue: step.rawValue - 1) else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { step = previous }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 50, height: 50)
                        .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 15))
                }
            }

            Button {
                if step == .review {
                    isCreating = true
                    Task {
                        if let id = await store.submitTrip(from: draft) {
                            if !store.path.isEmpty { store.path.removeLast() }
                            store.path.append(.trip(id))
                        }
                        isCreating = false
                    }
                } else if let next = Step(rawValue: step.rawValue + 1) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { step = next }
                }
            } label: {
                HStack {
                    Text(step == .review ? (isCreating ? "Building trip…" : "Create trip") : "Continue")
                    Image(systemName: step == .review ? "flag.checkered" : "arrow.right")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(TeeCircleBrand.forest)
                .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(!canContinue || isCreating)
            .opacity(canContinue ? 1 : 0.45)
            .accessibilityIdentifier(step == .review ? "create.submit" : "create.continue")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canContinue: Bool {
        switch step {
        case .basics: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.endDate >= draft.startDate
        case .rounds: !draft.rounds.isEmpty && draft.rounds.allSatisfy { !$0.courseName.trimmingCharacters(in: .whitespaces).isEmpty }
        case .courseCard: true
        case .roster: draft.playerNames.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
        case .competition:
            !draft.enabledFormats.isEmpty && (draft.scoringMode == .gross || !draft.playerHandicaps.contains(where: { $0 == nil }))
        case .review: true
        }
    }

    private func pageLead(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 29, weight: .black, design: .rounded))
                .tracking(-0.8)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.black)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospaced().weight(.black))
        }
    }
}

private struct TeeField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).teeLabel()
            content
        }
        .padding(17)
        .teeCard()
    }
}

private extension Text {
    func teeLabel() -> some View {
        self
            .font(.caption2.weight(.black))
            .tracking(1.1)
            .foregroundStyle(TeeCircleBrand.moss)
    }
}
