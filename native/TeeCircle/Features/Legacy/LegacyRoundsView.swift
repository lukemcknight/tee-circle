import SwiftUI
import TeeCircleDomain

struct LegacyRoundsView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @State private var conversionTarget: LegacyRoundSummary?

    var body: some View {
        ZStack {
            BroadcastBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        BroadcastStatusPill(title: "Read only")
                        Text("Your original rounds")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(-1.2)
                        Text("Nothing here is changed or deleted. Copy a round into a new trip when you want live scoring and Messages sharing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(store.legacyRounds) { round in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(round.courseName)
                                        .font(.title3.weight(.black))
                                    Text(round.startsAt.formatted(date: .long, time: .shortened))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(round.holes)H")
                                    .font(.caption.monospaced().weight(.black))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                            }

                            if !round.inviteeDisplayNames.isEmpty {
                                Label(round.inviteeDisplayNames.joined(separator: " · "), systemImage: "person.2.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Button {
                                conversionTarget = round
                            } label: {
                                Label("Copy into a new trip", systemImage: "doc.on.doc.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .foregroundStyle(TeeCircleBrand.forest)
                                    .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .accessibilityIdentifier("legacy.convert.\(round.id)")
                        }
                        .padding(18)
                        .teeCard()
                    }
                }
                .padding(18)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Previous rounds")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Create a new trip from this round?",
            isPresented: Binding(
                get: { conversionTarget != nil },
                set: { if !$0 { conversionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Create copy") {
                guard let legacyID = conversionTarget?.id else { return }
                conversionTarget = nil
                Task {
                    guard let id = await store.convertLegacyRoundProduction(legacyID) else { return }
                    if !store.path.isEmpty { store.path.removeLast() }
                    store.path.append(.trip(id))
                }
            }
            .accessibilityIdentifier("legacy.confirmCopy")
            Button("Cancel", role: .cancel) { conversionTarget = nil }
        } message: {
            Text("The original round stays untouched and read only.")
        }
    }
}
