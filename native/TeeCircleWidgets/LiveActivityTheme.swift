import SwiftUI

enum LiveActivityTheme {
    static let fairway = Color(red: 0.035, green: 0.18, blue: 0.12)
    static let deepFairway = Color(red: 0.018, green: 0.095, blue: 0.07)
    static let lime = Color(red: 0.78, green: 0.94, blue: 0.29)
    static let sand = Color(red: 0.96, green: 0.94, blue: 0.87)
}

extension View {
    func teeCircleActivityAccessibility(
        tripName: String,
        leaderName: String?,
        leaderValue: Int?,
        throughHole: Int,
        viewerRank: Int?,
        skinsCarry: Int?,
        isFinal: Bool
    ) -> some View {
        var pieces = [tripName]
        if isFinal { pieces.append("final results") }
        if let leaderName, let leaderValue {
            pieces.append("\(leaderName) leads with \(leaderValue)")
        }
        pieces.append("through hole \(throughHole)")
        if let viewerRank { pieces.append("you are ranked \(viewerRank)") }
        if let skinsCarry, skinsCarry > 0 { pieces.append("next pot is worth \(skinsCarry) skins") }
        return accessibilityElement(children: .ignore)
            .accessibilityLabel(pieces.joined(separator: ", "))
    }
}
