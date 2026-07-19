import SwiftUI

struct GolferDetailView: View {
    @EnvironmentObject private var store: TeeCircleStore
    let golfer: GolferSummary

    private var sharedTrips: [LocalTripExperience] {
        store.trips(for: golfer)
    }

    var body: some View {
        ZStack {
            BroadcastBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identity
                    stats

                    if !sharedTrips.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PLAYED TOGETHER")
                                .font(.caption.weight(.black))
                                .tracking(1.35)
                                .foregroundStyle(TeeCircleBrand.moss)

                            ForEach(sharedTrips) { experience in
                                Button {
                                    store.showTrip(experience.id)
                                } label: {
                                    sharedTripRow(experience)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(golfer.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var identity: some View {
        HStack(spacing: 15) {
            Text(golfer.initials)
                .font(.title2.weight(.black))
                .foregroundStyle(TeeCircleBrand.forest)
                .frame(width: 62, height: 62)
                .background(TeeCircleBrand.signal, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(golfer.displayName)
                    .font(.title3.weight(.black))
                    .foregroundStyle(TeeCircleBrand.ink)
                Text("TeeCircle player")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statTile("ROUNDS", value: "\(golfer.roundsTogether)")
            statTile("TRIPS", value: "\(sharedTrips.count)")
            statTile("LAST", value: golfer.lastPlayed.map {
                $0.formatted(.dateTime.month(.abbreviated).day())
            } ?? "—")
        }
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.black))
                .tracking(0.9)
                .foregroundStyle(TeeCircleBrand.moss)
            // A formatted date is much wider than a round count, so it scales
            // down rather than wrapping and making this tile taller than its
            // neighbours.
            ScoreboardNumber(value: value, size: 22)
                .foregroundStyle(TeeCircleBrand.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(16)
        .teeCard()
    }

    private func sharedTripRow(_ experience: LocalTripExperience) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TeeCircleBrand.signal)
                .frame(width: 42, height: 42)
                .background(TeeCircleBrand.signal.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(experience.trip.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.ink)
                    .lineLimit(1)
                Text("\(experience.rounds.count) round\(experience.rounds.count == 1 ? "" : "s")  ·  \(experience.trip.lifecycle.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .teeCard()
    }
}
