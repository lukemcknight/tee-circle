import SwiftUI
import TeeCircleDesign
import TeeCircleDomain

struct MessagesExpandedView: View {
    @ObservedObject var model: MessagesViewModel
    let actions: MessagesHostActions

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    connectionBanner

                    if model.trips.isEmpty {
                        emptyState
                    } else if let trip = model.selectedTrip {
                        tripPicker(selected: trip)

                        TeeCircleMessageCard(snapshot: trip.snapshot, tripName: trip.trip.name)
                            .accessibilityLabel(snapshotAccessibilityLabel(trip))

                        postActions(trip)

                        if trip.trip.lifecycle == .live {
                            scoreEntry(trip)
                        } else if trip.trip.lifecycle == .completed {
                            finalCallout
                        }
                    }

                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MessagesTheme.fairway)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(MessagesTheme.lime.opacity(0.24), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(16)
            }
            .background(MessagesTheme.sand.ignoresSafeArea())
            .refreshable { await model.refreshSelected() }
            .navigationTitle("TeeCircle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image(systemName: "figure.golf")
                            .foregroundStyle(MessagesTheme.fairway)
                        Text("TEE CIRCLE")
                            .font(.subheadline.weight(.black))
                            .tracking(1.2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch model.connectionState {
        case .loading:
            HStack {
                ProgressView()
                Text("Checking for fresh standings…")
            }
            .bannerStyle(color: MessagesTheme.sand)
        case .offline:
            Label("Offline · showing the latest saved snapshot", systemImage: "wifi.slash")
                .bannerStyle(color: Color.orange.opacity(0.16))
        case .reconnectRequired:
            Button {
                actions.reconnect(model.selectedInviteURL)
            } label: {
                HStack {
                    Label("Open TeeCircle to reconnect", systemImage: "arrow.up.forward.app.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)
            .bannerStyle(color: Color.orange.opacity(0.16))
            .accessibilityHint("Your unsent score input will stay saved")
        case .connected:
            EmptyView()
        #if DEBUG
        case .fixture:
            Label("Simulator preview data", systemImage: "hammer.fill")
                .bannerStyle(color: MessagesTheme.lime.opacity(0.22))
        #endif
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message.badge.filled.fill")
                .font(.largeTitle)
                .foregroundStyle(MessagesTheme.fairway)
                .accessibilityHidden(true)
            Text("Your rounds belong here")
                .font(.title3.weight(.bold))
            Text("Open TeeCircle once to make or join a round, then send its invite here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func tripPicker(selected: CachedMessagesTripV1) -> some View {
        Menu {
            ForEach(model.trips) { trip in
                Button {
                    model.selectTrip(trip.id)
                } label: {
                    if trip.id == selected.id {
                        Label(trip.trip.name, systemImage: "checkmark")
                    } else {
                        Text(trip.trip.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHARING")
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(MessagesTheme.muted)
                    Text(selected.trip.name)
                        .font(.headline)
                        .foregroundStyle(MessagesTheme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Text(selected.trip.lifecycle.rawValue.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(MessagesTheme.fairway)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(MessagesTheme.lime.opacity(0.35), in: Capsule())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MessagesTheme.muted)
            }
            .padding(14)
            .background(MessagesTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected trip, \(selected.trip.name)")
        .accessibilityHint("Choose another trip")
    }

    private func postActions(_ trip: CachedMessagesTripV1) -> some View {
        VStack(spacing: 10) {
            Button {
                actions.postSnapshot(trip, false)
            } label: {
                Label(
                    isInvite(trip) ? "Send round invite" : "Post these standings",
                    systemImage: isInvite(trip) ? "paperplane.fill" : "arrow.up.message.fill"
                )
            }
            .buttonStyle(TeeCircleActionButtonStyle(prominent: true))
            .accessibilityHint("Adds the current snapshot to the message composer. It will not update after sending.")

            if trip.trip.lifecycle == .completed {
                Button {
                    actions.postSnapshot(trip, true)
                } label: {
                    Label("Post final result", systemImage: "flag.checkered")
                }
                .buttonStyle(TeeCircleActionButtonStyle(prominent: false))
            }

            Text(
                isInvite(trip)
                    ? "The card carries the private join link into this conversation."
                    : "The bubble captures revision \(trip.snapshot.revision) at send time. The link opens the current board."
            )
                .font(.caption)
                .foregroundStyle(MessagesTheme.muted)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func scoreEntry(_ trip: CachedMessagesTripV1) -> some View {
        if let player = trip.claimedPlayer, let input = model.pendingInput {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ENTER ONE HOLE")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(MessagesTheme.fairway)
                        Text("Scoring as \(player.displayName)")
                            .font(.headline)
                            .foregroundStyle(MessagesTheme.ink)
                    }
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(MessagesTheme.fairway)
                        .accessibilityHidden(true)
                }

                Divider()

                ScoreStepper(
                    title: "Hole",
                    value: input.holeNumber,
                    rangeDescription: "holes 1 through \(trip.holeCount)",
                    decrement: { model.adjustHole(by: -1) },
                    increment: { model.adjustHole(by: 1) }
                )
                ScoreStepper(
                    title: "Strokes",
                    value: input.strokes,
                    rangeDescription: "1 through 20 strokes",
                    decrement: { model.adjustStrokes(by: -1) },
                    increment: { model.adjustStrokes(by: 1) }
                )
                ScoreStepper(
                    title: "Penalties",
                    value: input.penalties,
                    rangeDescription: "0 through 10 penalty strokes",
                    decrement: { model.adjustPenalties(by: -1) },
                    increment: { model.adjustPenalties(by: 1) }
                )

                Button {
                    Task { await model.submitScore() }
                } label: {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(MessagesTheme.deepFairway)
                    } else {
                        Label("Save hole \(input.holeNumber)", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(TeeCircleActionButtonStyle(prominent: true))
                .disabled(model.isSubmitting || model.selectedTripNeedsReconnect)

                if model.selectedTripNeedsReconnect {
                    Text("Open TeeCircle to reconnect. This unsent score is preserved on your device.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
            .background(MessagesTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
        } else {
            Label(
                "Claim your roster seat in TeeCircle to enter a score here.",
                systemImage: "person.crop.circle.badge.questionmark"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MessagesTheme.ink)
            .bannerStyle(color: MessagesTheme.card)
        }
    }

    private var finalCallout: some View {
        Label(
            "This trip is complete. Post the final result above; scores are now read-only.",
            systemImage: "flag.checkered"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MessagesTheme.ink)
        .bannerStyle(color: MessagesTheme.card)
    }

    private func snapshotAccessibilityLabel(_ trip: CachedMessagesTripV1) -> String {
        if isInvite(trip) {
            return "Invitation to \(trip.trip.name). Open the card to join the round."
        }
        guard let leader = trip.snapshot.primaryBoard?.standings.first else {
            return "\(trip.trip.name), no standings available"
        }
        return "\(trip.trip.name), \(leader.displayName) is ranked first with \(leader.value), revision \(trip.snapshot.revision)"
    }

    private func isInvite(_ trip: CachedMessagesTripV1) -> Bool {
        [.draft, .ready].contains(trip.trip.lifecycle)
    }
}

private extension View {
    func bannerStyle(color: Color) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MessagesTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
