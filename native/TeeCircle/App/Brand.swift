import SwiftUI

enum TeeCircleBrand {
    // TeeCircle is intentionally dark-first. These are semantic aliases rather
    // than light/dark pairs so the app and its extensions keep one recognizable
    // identity. The neutrals are deliberately untinted: signal green is the only
    // hue in the palette, so scoreboard content carries every screen on its own.
    static let signal = Color(red: 25 / 255, green: 235 / 255, blue: 102 / 255)
    static let night = Color.black
    static let forest = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)
    static let pine = Color(red: 17 / 255, green: 61 / 255, blue: 33 / 255)
    static let moss = Color(red: 134 / 255, green: 174 / 255, blue: 145 / 255)
    static let paper = Color.black
    static let card = Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
    static let raisedCard = Color(red: 22 / 255, green: 22 / 255, blue: 22 / 255)
    static let ink = Color(red: 241 / 255, green: 246 / 255, blue: 238 / 255)
    static let sand = Color(red: 225 / 255, green: 221 / 255, blue: 204 / 255)
    // Pure black gives a hairline nothing to sit against, so it carries a little
    // more opacity here than it would over a tinted surface.
    static let hairline = Color.white.opacity(0.12)
}

struct BroadcastBackground: View {
    var body: some View {
        TeeCircleBrand.paper
            .ignoresSafeArea()
    }
}

struct TeeCircleMark: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(TeeCircleBrand.signal)
                .shadow(color: TeeCircleBrand.signal.opacity(0.28), radius: 12, y: 5)

            Image(systemName: "flag.fill")
                .font(.system(size: size * 0.39, weight: .black))
                .foregroundStyle(TeeCircleBrand.forest)
                .offset(y: -size * 0.025)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TeeCircleWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            TeeCircleMark(size: compact ? 29 : 36)

            Text("TEE CIRCLE")
                .font(.system(size: compact ? 14 : 17, weight: .black, design: .rounded))
                .tracking(1.25)
                .foregroundStyle(TeeCircleBrand.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TeeCircle")
    }
}

struct BroadcastStatusPill: View {
    let title: String
    var live = false

    var body: some View {
        HStack(spacing: 6) {
            if live {
                Circle()
                    .fill(TeeCircleBrand.signal)
                    .frame(width: 7, height: 7)
                    .shadow(color: TeeCircleBrand.signal.opacity(0.7), radius: 4)
            }
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.1)
        }
        .foregroundStyle(live ? TeeCircleBrand.forest : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(live ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard, in: Capsule())
        .overlay {
            if !live { Capsule().stroke(TeeCircleBrand.hairline) }
        }
    }
}

struct ScoreboardNumber: View {
    let value: String
    var size: CGFloat = 24

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: .black, design: .monospaced))
    }
}

struct TeeCircleUnavailableState: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(TeeCircleBrand.signal)
            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The default tab bar material renders as grey over pure black, which
    /// reintroduces exactly the muddiness this palette removes.
    /// `toolbarColorScheme(.dark,…)` is deliberately absent: it forces the tab
    /// bar's own selection colour and would override the signal-green tint.
    func teeTabBar() -> some View {
        self
            .toolbarBackground(TeeCircleBrand.paper, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }

    // No shadow: a black shadow over a black background reads as nothing, so the
    // hairline is what separates a card from the page.
    func teeCard() -> some View {
        self
            .background(TeeCircleBrand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TeeCircleBrand.hairline, lineWidth: 1)
            }
    }
}
