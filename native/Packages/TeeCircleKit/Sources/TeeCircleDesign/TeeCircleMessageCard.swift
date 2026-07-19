#if canImport(SwiftUI)
import SwiftUI
import TeeCircleDomain

/// Compact send-time snapshot used inside the Messages extension compose view.
public struct TeeCircleMessageCard: View {
    private let snapshot: LeaderboardSnapshotV1
    private let tripName: String

    public init(snapshot: LeaderboardSnapshotV1, tripName: String) {
        self.snapshot = snapshot
        self.tripName = tripName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInvite ? "TEE CIRCLE  ·  ROUND INVITE" : "TEE CIRCLE")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(TeeCirclePalette.lime)
                    Text(tripName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: snapshot.status == .completed || snapshot.status == .archived ? "flag.checkered" : "figure.golf")
                    .font(.title2)
                    .foregroundStyle(TeeCirclePalette.lime)
                    .accessibilityHidden(true)
            }

            if isInvite {
                HStack(spacing: 13) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle(TeeCirclePalette.lime)
                        .frame(width: 42, height: 42)
                        .background(TeeCirclePalette.lime.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You’re invited.")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Open the card to see the tee time and join the round.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TeeCirclePalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                TeeCircleLeaderboardCard(snapshot: snapshot, maxRows: 3)
                    .background(TeeCirclePalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Text(isInvite ? "Private link · tap to join" : "Open TeeCircle for live scores")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(TeeCirclePalette.deepFairway, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TeeCirclePalette.fairway.opacity(0.16))
        }
        .accessibilityElement(children: .contain)
    }

    private var isInvite: Bool {
        snapshot.status == .draft || snapshot.status == .ready
    }
}
#endif
