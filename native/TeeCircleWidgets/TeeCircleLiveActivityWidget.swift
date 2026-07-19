import ActivityKit
import Foundation
import SwiftUI
import TeeCircleActivities
import TeeCircleDomain
import WidgetKit

struct TeeCircleLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeeCircleLiveActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(LiveActivityTheme.deepFairway)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLink(tripId: context.attributes.tripId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandBrandView(isFinal: context.state.status.isTerminal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandThroughView(hole: context.state.throughHole)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandLeaderView(
                        name: context.state.leaderName,
                        value: context.state.leaderValue
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottomView(context: context)
                }
            } compactLeading: {
                Image(systemName: context.state.status.isTerminal ? "flag.checkered" : "figure.golf")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiveActivityTheme.lime)
                    .accessibilityHidden(true)
            } compactTrailing: {
                if context.state.status.isTerminal {
                    Text("FINAL")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(LiveActivityTheme.lime)
                } else {
                    Text("H\(context.state.throughHole)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
            } minimal: {
                ZStack {
                    Circle().fill(LiveActivityTheme.fairway)
                    Text(context.state.status.isTerminal ? "F" : "\(context.state.throughHole)")
                        .font(.caption2.monospacedDigit().weight(.black))
                        .foregroundStyle(LiveActivityTheme.lime)
                }
                .accessibilityLabel(
                    context.state.status.isTerminal
                        ? "TeeCircle final"
                        : "TeeCircle through hole \(context.state.throughHole)"
                )
            }
            .keylineTint(LiveActivityTheme.lime)
            .widgetURL(deepLink(tripId: context.attributes.tripId))
        }
    }

    private func deepLink(tripId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "teecircle"
        components.host = "trip"
        components.path = "/\(tripId)"
        return components.url
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<TeeCircleLiveActivityAttributes>

    private var state: TeeCircleActivityContentState { context.state }
    private var isFinal: Bool { state.status.isTerminal }

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: isFinal ? "flag.checkered" : "figure.golf")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiveActivityTheme.lime)
                    .accessibilityHidden(true)
                Text("TEE CIRCLE")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(LiveActivityTheme.lime)
                Text(isFinal ? "FINAL" : "LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isFinal ? LiveActivityTheme.deepFairway : .white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isFinal ? LiveActivityTheme.lime : Color.white.opacity(0.13), in: Capsule())
                Spacer()
                Text(state.updatedAt, style: .relative)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.tripName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                    Text(state.leaderName ?? "Standings pending")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                if let value = state.leaderValue {
                    Text("\(value)")
                        .font(.title.monospacedDigit().weight(.black))
                        .foregroundStyle(LiveActivityTheme.lime)
                }
            }

            HStack(spacing: 12) {
                ThroughProgress(hole: state.throughHole)
                if let viewerRank = state.viewerRank {
                    statPill(label: "YOU", value: "#\(viewerRank)")
                }
                if let carry = state.skinsCarry, carry > 0 {
                    statPill(label: "POT", value: "\(carry)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .teeCircleActivityAccessibility(
            tripName: context.attributes.tripName,
            leaderName: state.leaderName,
            leaderValue: state.leaderValue,
            throughHole: state.throughHole,
            viewerRank: state.viewerRank,
            skinsCarry: state.skinsCarry,
            isFinal: isFinal
        )
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.caption2.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
}

private struct ThroughProgress: View {
    let hole: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("THROUGH")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("H \(hole)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [LiveActivityTheme.lime, LiveActivityTheme.lime.opacity(0.18)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IslandBrandView: View {
    let isFinal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: isFinal ? "flag.checkered" : "figure.golf")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(LiveActivityTheme.lime)
                .accessibilityHidden(true)
            Text(isFinal ? "FINAL" : "LIVE")
                .font(.system(size: 9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct IslandThroughView: View {
    let hole: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("THRU")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(hole)")
                .font(.title3.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Through hole \(hole)")
    }
}

private struct IslandLeaderView: View {
    let name: String?
    let value: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name ?? "Standings pending")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let value {
                Text("\(value)")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(LiveActivityTheme.lime)
            }
        }
    }
}

private struct IslandBottomView: View {
    let context: ActivityViewContext<TeeCircleLiveActivityAttributes>

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                Text(context.attributes.tripName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                if let rank = context.state.viewerRank {
                    Text("You #\(rank)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
                if let carry = context.state.skinsCarry, carry > 0 {
                    Text("\(carry)-skin pot")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(LiveActivityTheme.lime)
                }
            }
            ThroughProgress(hole: context.state.throughHole)
        }
        .teeCircleActivityAccessibility(
            tripName: context.attributes.tripName,
            leaderName: context.state.leaderName,
            leaderValue: context.state.leaderValue,
            throughHole: context.state.throughHole,
            viewerRank: context.state.viewerRank,
            skinsCarry: context.state.skinsCarry,
            isFinal: context.state.status.isTerminal
        )
    }
}

private extension TripLifecycle {
    var isTerminal: Bool { self == .completed || self == .archived }
}

#if DEBUG
enum TeeCircleLiveActivityFixtures {
    static let attributes = TeeCircleLiveActivityAttributes(
        tripId: "summer-cup-2026",
        tripName: "Pinehurst Summer Cup",
        viewerPlayerId: "fixture-seat-sean"
    )

    static let live = TeeCircleActivityContentState(
        revision: 42,
        status: .live,
        roundName: "Pinehurst No. 2",
        throughHole: 12,
        leaderName: "Sean",
        leaderValue: 28,
        viewerRank: 1,
        viewerValue: 28,
        skinsCarry: 2,
        updatedAt: .now.addingTimeInterval(-48)
    )
}
#endif
