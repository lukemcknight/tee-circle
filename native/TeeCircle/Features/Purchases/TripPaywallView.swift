import SwiftUI

struct TripPaywallView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.dismiss) private var dismiss
    let tripID: String
    @State private var purchasing = false
    @State private var product: TripUnlockProduct?

    var body: some View {
        ZStack {
            TeeCircleBrand.forest.ignoresSafeArea()
            LinearGradient(colors: [TeeCircleBrand.signal.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 25) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(TeeCircleBrand.forest)
                        .frame(width: 82, height: 82)
                        .background(TeeCircleBrand.signal, in: Circle())
                        .shadow(color: TeeCircleBrand.signal.opacity(0.3), radius: 24)

                    VStack(spacing: 10) {
                        Text("One captain.\nThe whole trip.")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .tracking(-1.3)
                            .multilineTextAlignment(.center)
                        Text("Unlock live scoring and every tournament board for everyone on the roster.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 0) {
                        feature("Live hole-by-hole standings", "dot.radiowaves.left.and.right")
                        feature("Stableford and carryover skins", "list.number")
                        feature("Messages broadcast cards", "message.fill")
                        feature("Live Activity for every player", "iphone.radiowaves.left.and.right")
                    }
                    .padding(.horizontal, 17)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))

                    VStack(spacing: 10) {
                        Button {
                            purchasing = true
                            Task {
                                let outcome = await store.purchaseTripUnlock(tripID)
                                purchasing = false
                                switch outcome {
                                case .unlocked:
                                    dismiss()
                                case .cancelled:
                                    break
                                case .pendingServerVerification:
                                    store.errorMessage = "Purchase received. TeeCircle is confirming it with the server; your trip setup is safe."
                                case nil:
                                    if store.configuration.useMockData { dismiss() }
                                }
                            }
                        } label: {
                            HStack {
                                Text(purchasing ? "Verifying…" : "Unlock trip")
                                Spacer()
                                Text(product?.localizedPrice ?? "$29.99").font(.headline.monospaced().weight(.black))
                            }
                            .font(.headline.weight(.bold))
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(TeeCircleBrand.forest)
                            .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .disabled(purchasing)
                        .accessibilityIdentifier("paywall.unlock")

                        Button("Restore purchase") {
                            Task { await store.reconcileTripPurchase(tripID) }
                        }
                        .accessibilityIdentifier("paywall.restore")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    }

                    Text("One-time trip purchase. No subscription. Purchase cancellation leaves your complete trip setup intact.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(24)
                .padding(.top, 34)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(TeeCircleBrand.forest, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard !store.configuration.useMockData else { return }
            product = await store.loadTripUnlockProduct()
        }
    }

    private func feature(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(TeeCircleBrand.signal)
                .frame(width: 26)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "checkmark").font(.caption.weight(.black)).foregroundStyle(TeeCircleBrand.signal)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
    }
}
