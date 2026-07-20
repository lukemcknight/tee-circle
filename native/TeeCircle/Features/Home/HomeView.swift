import SwiftUI
import TeeCircleDomain

struct HomeView: View {
    @EnvironmentObject private var store: TeeCircleStore

    private var liveExperiences: [LocalTripExperience] {
        store.trips.filter { $0.trip.lifecycle == .live }
    }

    private var upcomingRounds: [LocalTripExperience] {
        store.trips.filter {
            [.draft, .ready].contains($0.trip.lifecycle) && $0.rounds.count == 1
        }
    }

    private var plannedTrips: [LocalTripExperience] {
        store.trips.filter {
            [.draft, .ready].contains($0.trip.lifecycle) && $0.rounds.count > 1
        }
    }

    private var completedExperiences: [LocalTripExperience] {
        store.trips.filter { [.completed, .archived].contains($0.trip.lifecycle) }
    }

    var body: some View {
        ZStack {
            BroadcastBackground()

            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        header
                        createRoundCard

                        if let live = liveExperiences.first {
                            liveRoundCard(live)
                        }

                        scheduleSection

                        if !plannedTrips.isEmpty {
                            tripSection
                        }

                        tripPlanner

                        if !completedExperiences.isEmpty {
                            recentSection
                        }

                        if !store.legacyRounds.isEmpty {
                            legacySection
                        }

                        messagesCallout
                    }
                    .frame(width: max(geometry.size.width - 36, 0), alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 48)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.start() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TeeCircleWordmark()
                    .accessibilityIdentifier("home.wordmark")

                Text("\(daypart), \(store.currentDisplayName).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 12)
    }

    private var createRoundCard: some View {
        Button {
            store.path.append(.createRound)
        } label: {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("THE FAST WAY TO THE FIRST TEE")
                        .font(.caption2.weight(.black))
                        .tracking(1.35)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.headline.weight(.black))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Make a round")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1.1)
                    Text("Course. Time. Friends. Done.")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.72)
                }

                HStack(spacing: 8) {
                    quickFact("calendar", "Pick a time")
                    quickFact("person.2.fill", "Send the link")
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(TeeCircleBrand.forest)
            .background(
                TeeCircleBrand.signal,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.createRound")
        .accessibilityHint("Create a single golf round and invite friends")
    }

    private func quickFact(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(TeeCircleBrand.forest.opacity(0.08), in: Capsule())
    }

    private func liveRoundCard(_ experience: LocalTripExperience) -> some View {
        Button {
            store.path.append(.trip(experience.id))
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    BroadcastStatusPill(title: "Live", live: true)
                    Spacer()
                    Text("REV \(experience.trip.scoreRevision)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(experience.trip.name)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(-0.9)

                    if let round = experience.latestSnapshot?.currentRound {
                        Text("\(round.name)  ·  Through \(round.throughHole)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                if let standings = experience.latestSnapshot?.primaryBoard?.standings {
                    HStack(spacing: 18) {
                        ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, standing in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(index == 0 ? "LEADER" : "#\(standing.rank)")
                                    .font(.caption2.weight(.black))
                                    .tracking(0.8)
                                    .foregroundStyle(index == 0 ? TeeCircleBrand.signal : .white.opacity(0.42))
                                Text(standing.displayName)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                                Text("\(standing.value)")
                                    .font(.title3.monospaced().weight(.black))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack {
                    Text(experience.latestSnapshot?.moment?.summary ?? "Open the live round")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(TeeCircleBrand.signal)
                }
            }
            .padding(20)
            .foregroundStyle(.white)
            .background(
                TeeCircleBrand.raisedCard,
                in: RoundedRectangle(cornerRadius: 27, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .stroke(TeeCircleBrand.signal.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the live round")
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ON DECK", detail: "Your next rounds")

            if upcomingRounds.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(TeeCircleBrand.signal)
                        .frame(width: 38, height: 38)
                        .background(TeeCircleBrand.signal.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing scheduled yet")
                            .font(.subheadline.weight(.bold))
                        Text("Make a round above and get the group moving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(17)
                .teeCard()
            } else {
                ForEach(upcomingRounds) { experience in
                    experienceButton(experience)
                }
            }
        }
    }

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TRIPS", detail: "Multi-round weekends")
            ForEach(plannedTrips) { experience in
                experienceButton(experience)
            }
        }
    }

    private var tripPlanner: some View {
        Button {
            store.path.append(.createTrip)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "map.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.moss)
                    .frame(width: 48, height: 48)
                    .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Planning a golf weekend?")
                            .font(.subheadline.weight(.bold))
                        Text("PLANNER")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(TeeCircleBrand.moss)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(TeeCircleBrand.raisedCard, in: Capsule())
                    }
                    Text("Build a multi-round trip when you need one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(TeeCircleBrand.ink)
            .padding(16)
            .background(TeeCircleBrand.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TeeCircleBrand.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.createTrip")
        .accessibilityHint("Opens the advanced multi-round trip planner")
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RECENT", detail: "Rounds on the record")
            ForEach(completedExperiences.prefix(2)) { experience in
                experienceButton(experience)
            }
        }
    }

    private var legacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("ROUND HISTORY", detail: "Rounds you’ve already played")
                Spacer()
                Button("See all") { store.path.append(.legacyRounds) }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.signal)
            }

            ForEach(store.legacyRounds.prefix(1)) { round in
                HStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundStyle(TeeCircleBrand.moss)
                        .frame(width: 42, height: 42)
                        .background(TeeCircleBrand.raisedCard, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(round.courseName).font(.subheadline.weight(.bold))
                        Text(round.startsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("READ ONLY")
                        .font(.caption2.weight(.black))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .teeCard()
            }
        }
    }

    private var messagesCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "message.fill")
                    .foregroundStyle(TeeCircleBrand.signal)
                Text("THE GROUP CHAT IS THE CLUBHOUSE")
                    .font(.caption2.weight(.black))
                    .tracking(1.15)
                    .foregroundStyle(TeeCircleBrand.moss)
            }

            Text("Invite from Messages. Keep the round here.")
                .font(.title3.weight(.black))

            Text("After you make a round, send its private link to the thread. TeeCircle keeps the roster and live board synced without replacing the conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(19)
        .background(
            TeeCircleBrand.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TeeCircleBrand.signal.opacity(0.25))
        }
    }

    private func experienceButton(_ experience: LocalTripExperience) -> some View {
        Button {
            store.path.append(.trip(experience.id))
        } label: {
            RoundScheduleCard(experience: experience)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.black))
                .tracking(1.35)
                .foregroundStyle(TeeCircleBrand.moss)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var daypart: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct RoundScheduleCard: View {
    let experience: LocalTripExperience

    private var firstRound: TripRound? { experience.rounds.sorted { $0.order < $1.order }.first }

    var body: some View {
        HStack(spacing: 15) {
            VStack(spacing: 2) {
                Text(month)
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(TeeCircleBrand.signal)
                Text(day)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(TeeCircleBrand.ink)
            }
            .frame(width: 48, height: 58)
            .background(TeeCircleBrand.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(experience.trip.lifecycle.rawValue.uppercased())
                    if experience.rounds.count > 1 { Text("· \(experience.rounds.count) ROUNDS") }
                }
                .font(.caption2.weight(.black))
                .tracking(0.65)
                .foregroundStyle(TeeCircleBrand.moss)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .teeCard()
    }

    private var displayTitle: String {
        if experience.rounds.count == 1, let course = firstRound?.courseName, !course.isEmpty {
            return course
        }
        return experience.trip.name
    }

    private var detail: String {
        let playerText = "\(experience.players.count) player\(experience.players.count == 1 ? "" : "s")"
        guard let teeTime = firstRound?.scheduledAt else { return playerText }
        return "\(teeTime.formatted(date: .omitted, time: .shortened))  ·  \(playerText)"
    }

    private var parsedDate: Date? {
        firstRound?.scheduledAt ?? DateFormatter.tripDate.date(from: experience.trip.startDate)
    }

    private var month: String {
        parsedDate?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "ROUND"
    }

    private var day: String { parsedDate?.formatted(.dateTime.day()) ?? "—" }
}

private extension DateFormatter {
    static let tripDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
