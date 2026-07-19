#if canImport(SwiftUI)
import SwiftUI
import TeeCircleDomain

public enum TeeCirclePalette {
    public static let fairway = Color(red: 25 / 255, green: 235 / 255, blue: 102 / 255)
    public static let deepFairway = Color(red: 4 / 255, green: 10 / 255, blue: 7 / 255)
    public static let lime = fairway
    public static let sand = Color(red: 6 / 255, green: 14 / 255, blue: 9 / 255)
    public static let surface = Color(red: 17 / 255, green: 35 / 255, blue: 23 / 255)
}

public struct TeeCircleLeaderboardCard: View {
    private let presentation: LeaderboardCardPresentation

    public init(snapshot: LeaderboardSnapshotV1, maxRows: Int = 5) {
        presentation = LeaderboardCardPresentation(snapshot: snapshot, maxRows: maxRows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if presentation.rows.isEmpty {
                Text("Scores will appear here as the round gets underway.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                        TeeCircleLeaderboardRow(row: row)
                        if index < presentation.rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            if let moment = presentation.moment {
                Label(moment, systemImage: presentation.isFinal ? "flag.checkered" : "bolt.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TeeCirclePalette.fairway)
                    .accessibilityLabel(moment)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(presentation.isFinal ? Color.secondary : TeeCirclePalette.lime)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(presentation.eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }
            Text(presentation.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(presentation.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

public struct TeeCircleLeaderboardRow: View {
    private let row: LeaderboardCardPresentation.Row

    public init(row: LeaderboardCardPresentation.Row) {
        self.row = row
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(row.rankText)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(row.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(row.valueText)
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(TeeCirclePalette.fairway)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.rankText), \(row.displayName), \(row.valueText), \(row.progressText)")
    }
}
#endif
