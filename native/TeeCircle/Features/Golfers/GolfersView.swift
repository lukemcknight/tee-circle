import SwiftUI

struct GolfersView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @State private var searchQuery = ""

    private var filtered: [GolferSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.golfers }
        return store.golfers.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            BroadcastBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.golfers.isEmpty {
                        TeeCircleUnavailableState(
                            title: "No golfers yet",
                            systemImage: "person.2",
                            message: "Play a round with someone and they'll show up here."
                        )
                        .padding(.top, 60)
                        .accessibilityIdentifier("golfers.empty")
                    } else if filtered.isEmpty {
                        Text("No golfers match “\(searchQuery)”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(filtered) { golfer in
                            if golfer.isOnTeeCircle {
                                NavigationLink(value: golfer) {
                                    GolferRow(golfer: golfer)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Nothing to drill into for an unclaimed seat.
                                GolferRow(golfer: golfer)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("My Golfers")
        .searchable(text: $searchQuery, prompt: "Search by name")
        .refreshable { await store.start() }
    }
}

struct GolferRow: View {
    let golfer: GolferSummary

    var body: some View {
        HStack(spacing: 14) {
            Text(golfer.initials)
                .font(.subheadline.weight(.black))
                .foregroundStyle(golfer.isOnTeeCircle ? TeeCircleBrand.forest : TeeCircleBrand.moss)
                .frame(width: 48, height: 48)
                .background(
                    golfer.isOnTeeCircle ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(golfer.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.ink)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if golfer.isOnTeeCircle {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .teeCard()
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard golfer.isOnTeeCircle else { return "Not on TeeCircle" }
        let rounds = "\(golfer.roundsTogether) round\(golfer.roundsTogether == 1 ? "" : "s")"
        guard let lastPlayed = golfer.lastPlayed else { return rounds }
        return "\(rounds)  ·  last \(lastPlayed.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
