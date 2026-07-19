import SwiftUI

/// The live-layout transcript view deliberately avoids language that suggests a
/// closed Messages bubble is receiving push updates. The static alternate layout
/// carries the exact send-time score snapshot.
struct MessagesTranscriptView: View {
    @ObservedObject var model: MessagesViewModel

    var body: some View {
        ZStack {
            MessagesTheme.deepFairway

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TEE CIRCLE")
                        .font(.caption2.weight(.black))
                        .tracking(1.3)
                        .foregroundStyle(MessagesTheme.lime)
                    Spacer()
                    Image(systemName: "figure.golf")
                        .foregroundStyle(MessagesTheme.lime)
                        .accessibilityHidden(true)
                }

                if let trip = model.selectedTrip {
                    Text(trip.trip.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if [.draft, .ready].contains(trip.trip.lifecycle) {
                        Text("You’re invited · tap to join")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.86))
                    } else if let leader = trip.snapshot.primaryBoard?.standings.first {
                        HStack(alignment: .firstTextBaseline) {
                            Text(leader.displayName)
                                .font(.title3.weight(.black))
                            Spacer()
                            Text("\(leader.value)")
                                .font(.title2.monospacedDigit().weight(.black))
                        }
                        .foregroundStyle(.white)
                    }

                    Text(
                        [.draft, .ready].contains(trip.trip.lifecycle)
                            ? "Private TeeCircle round link"
                            : "Saved snapshot · revision \(trip.snapshot.revision)"
                    )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.68))
                } else {
                    Text("Golf rounds, organized together.")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Open this card to see the standings link.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
