import SwiftUI
import TeeCircleDomain

struct MessagesCompactView: View {
    @ObservedObject var model: MessagesViewModel
    let actions: MessagesHostActions

    var body: some View {
        ZStack {
            MessagesTheme.deepFairway.ignoresSafeArea()

            if let trip = model.selectedTrip {
                HStack(spacing: 14) {
                    snapshotSummary(trip)

                    VStack(spacing: 8) {
                        Button {
                            actions.postSnapshot(trip, trip.trip.lifecycle == .completed)
                        } label: {
                            Label(
                                compactActionTitle(for: trip),
                                systemImage: isInvite(trip) ? "paperplane.fill" : "arrow.up.message.fill"
                            )
                        }
                        .buttonStyle(TeeCircleActionButtonStyle(prominent: true))
                        .accessibilityHint("Adds a send-time score snapshot to this conversation")

                        Button(action: actions.requestExpanded) {
                            Label("Open round options", systemImage: "chevron.up")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.86))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 172)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.golf")
                        .font(.title2)
                        .foregroundStyle(MessagesTheme.lime)
                        .accessibilityHidden(true)
                    Text("Open TeeCircle to share a round")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Rounds you make or join will appear here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding()
            }
        }
    }

    private func snapshotSummary(_ trip: CachedMessagesTripV1) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(trip.trip.lifecycle == .live ? MessagesTheme.lime : .white.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(isInvite(trip) ? "ROUND INVITE" : (trip.trip.lifecycle == .completed ? "FINAL" : "TEE CIRCLE"))
                    .font(.caption2.weight(.black))
                    .tracking(1.1)
                    .foregroundStyle(MessagesTheme.lime)
            }
            Text(trip.trip.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let leader = trip.snapshot.primaryBoard?.standings.first {
                Text("\(leader.displayName) leads with \(leader.value)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            } else if isInvite(trip) {
                Text("Tap send to invite the group")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            if let round = trip.snapshot.currentRound, !isInvite(trip) {
                Text("Through \(round.throughHole) · revision \(trip.snapshot.revision)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func isInvite(_ trip: CachedMessagesTripV1) -> Bool {
        [.draft, .ready].contains(trip.trip.lifecycle)
    }

    private func compactActionTitle(for trip: CachedMessagesTripV1) -> String {
        if isInvite(trip) { return "Send invite" }
        return trip.trip.lifecycle == .completed ? "Post final" : "Post standings"
    }
}
