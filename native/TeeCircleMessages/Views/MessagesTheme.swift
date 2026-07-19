import SwiftUI

enum MessagesTheme {
    static let fairway = Color(red: 25 / 255, green: 235 / 255, blue: 102 / 255)
    static let deepFairway = Color(red: 4 / 255, green: 10 / 255, blue: 7 / 255)
    static let lime = fairway
    static let sand = Color(red: 6 / 255, green: 14 / 255, blue: 9 / 255)
    static let card = Color(red: 17 / 255, green: 35 / 255, blue: 23 / 255)
    static let ink = Color(red: 241 / 255, green: 246 / 255, blue: 238 / 255)
    static let muted = Color(red: 134 / 255, green: 174 / 255, blue: 145 / 255)
}

struct TeeCircleActionButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(prominent ? MessagesTheme.deepFairway : MessagesTheme.fairway)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                prominent ? MessagesTheme.lime : MessagesTheme.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MessagesTheme.fairway.opacity(0.15))
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ScoreStepper: View {
    let title: String
    let value: Int
    let rangeDescription: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MessagesTheme.muted)
                    .textCase(.uppercase)
                Text("\(value)")
                    .font(.title2.monospacedDigit().weight(.black))
                    .foregroundStyle(MessagesTheme.ink)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .frame(width: 34, height: 34)
                    .background(MessagesTheme.card, in: Circle())
                }
                .accessibilityLabel("Decrease \(title)")

                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                        .background(MessagesTheme.fairway, in: Circle())
                        .foregroundStyle(MessagesTheme.deepFairway)
                }
                .accessibilityLabel("Increase \(title)")
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value), \(rangeDescription)")
    }
}
