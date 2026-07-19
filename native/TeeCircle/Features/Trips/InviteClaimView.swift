import SwiftUI

struct InviteClaimView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.dismiss) private var dismiss
    let invite: PendingInviteSelection
    @State private var selectedSeatID: String?
    @State private var isClaiming = false

    var body: some View {
        NavigationStack {
            ZStack {
                BroadcastBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        BroadcastStatusPill(title: "Invitation")
                        Text(invite.trip.name)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(-1)
                        Text("Choose your roster seat. Your scores stay attached to this seat even if the captain later reassigns the account claim.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 10) {
                            ForEach(invite.seats) { seat in
                                Button {
                                    selectedSeatID = seat.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(seat.displayName).font(.headline.weight(.bold))
                                            Text(seat.role.rawValue.capitalized)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: selectedSeatID == seat.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedSeatID == seat.id ? TeeCircleBrand.moss : .secondary)
                                    }
                                    .padding(17)
                                    .teeCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            guard let selectedSeatID else { return }
                            isClaiming = true
                            Task {
                                await store.acceptPendingInvite(seatID: selectedSeatID)
                                isClaiming = false
                                dismiss()
                            }
                        } label: {
                            Text(isClaiming ? "Claiming…" : "Claim this seat")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .foregroundStyle(TeeCircleBrand.forest)
                                .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .disabled(selectedSeatID == nil || isClaiming)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Join trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}
