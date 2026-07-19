import SwiftUI
import TeeCircleDomain

struct LeaderboardView: View {
    @EnvironmentObject private var store: TeeCircleStore
    let tripID: String
    @State private var selectedFormat: TournamentFormat = .stableford

    var body: some View {
        ZStack {
            TeeCircleBrand.forest.ignoresSafeArea()
            if let experience = store.trip(id: tripID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(experience)
                        formatPicker(experience)
                        if let board = board(for: experience) {
                            standings(board, experience: experience)
                        } else {
                            TeeCircleUnavailableState(title: "Waiting for the first score", systemImage: "figure.golf")
                                .foregroundStyle(.white)
                        }
                        if let moment = experience.latestSnapshot?.moment {
                            momentCard(moment)
                        }
                        freshness(experience)
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            } else {
                TeeCircleUnavailableState(title: "Board unavailable", systemImage: "list.number")
                    .foregroundStyle(.white)
            }
        }
        .toolbarBackground(TeeCircleBrand.forest, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("Live standings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let primary = store.trip(id: tripID)?.trip.primaryFormat {
                selectedFormat = primary
            }
        }
    }

    private func header(_ experience: LocalTripExperience) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                BroadcastStatusPill(title: experience.trip.lifecycle.rawValue, live: experience.trip.lifecycle == .live)
                Spacer()
                Text("REVISION \(experience.latestSnapshot?.revision ?? 0)")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text(experience.trip.name)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(.white)
            if let round = experience.latestSnapshot?.currentRound {
                Text("\(round.name) · Through hole \(round.throughHole)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private func formatPicker(_ experience: LocalTripExperience) -> some View {
        HStack(spacing: 7) {
            ForEach(experience.trip.enabledFormats, id: \.self) { format in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { selectedFormat = format }
                } label: {
                    Text(format.rawValue.uppercased())
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selectedFormat == format ? TeeCircleBrand.forest : .white.opacity(0.62))
                        .background(selectedFormat == format ? TeeCircleBrand.signal : .white.opacity(0.07), in: Capsule())
                }
            }
        }
    }

    private func standings(_ board: LeaderboardBoardV1, experience: LocalTripExperience) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(board.standings.enumerated()), id: \.element.id) { index, standing in
                HStack(spacing: 13) {
                    Text(standing.tied ? "T\(standing.rank)" : "\(standing.rank)")
                        .font(.headline.monospaced().weight(.black))
                        .foregroundStyle(index == 0 ? TeeCircleBrand.signal : .white.opacity(0.4))
                        .frame(width: 35, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(standing.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("THRU \(standing.holesPlayed)")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                    ScoreboardNumber(value: "\(standing.value)", size: 27)
                        .foregroundStyle(.white)
                    Text(board.format == .skins ? "SKINS" : "PTS")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.36))
                        .frame(width: 39, alignment: .leading)
                }
                .padding(.vertical, 16)
                if index < board.standings.count - 1 {
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .padding(.horizontal, 17)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.08)) }
    }

    private func momentCard(_ moment: LeaderboardMomentV1) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(TeeCircleBrand.forest)
                .frame(width: 38, height: 38)
                .background(TeeCircleBrand.signal, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("LATEST MOMENT")
                    .font(.caption2.weight(.black)).tracking(1).foregroundStyle(.white.opacity(0.4))
                Text(moment.summary)
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
        .background(TeeCircleBrand.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private func freshness(_ experience: LocalTripExperience) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(TeeCircleBrand.signal)
            Text("Canonical server snapshot")
            Spacer()
            if let date = experience.latestSnapshot?.generatedAt {
                Text(date, style: .relative)
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.46))
    }

    private func board(for experience: LocalTripExperience) -> LeaderboardBoardV1? {
        experience.latestSnapshot?.boards.first(where: { $0.format == selectedFormat })
    }
}
