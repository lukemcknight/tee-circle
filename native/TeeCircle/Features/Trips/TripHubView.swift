import SwiftUI
import TeeCircleDomain
import UIKit

struct TripHubView: View {
    @EnvironmentObject private var store: TeeCircleStore
    let tripID: String
    @State private var shareText: String?
    @State private var showingShareSheet = false
    @State private var setupRound: TripRound?

    var body: some View {
        ZStack {
            BroadcastBackground()
            if let experience = store.trip(id: tripID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero(experience)
                        convertedDraftSetup(experience)
                        actionStrip(experience)
                        leaderboardPreview(experience)
                        rounds(experience)
                        roster(experience)
                        captainControls(experience)
                    }
                    .padding(18)
                    .padding(.bottom, 36)
                }
            } else {
                TeeCircleUnavailableState(
                    title: "Trip unavailable",
                    systemImage: "flag.slash",
                    message: "The invitation may be revoked or the trip may no longer exist."
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { TeeCircleWordmark(compact: true) }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareText {
                ActivityShareSheet(items: [shareText])
            }
        }
        .sheet(item: $setupRound) { round in
            LegacyTripSetupView(tripID: tripID, roundID: round.id)
                .environmentObject(store)
        }
        .task(id: tripID) {
            guard !store.configuration.useMockData else { return }
            await store.refreshInviteMetadataProduction(tripID: tripID)
            store.beginObservingTrip(tripID)
            defer { store.stopObservingTrip(tripID) }
            while !Task.isCancelled {
                await store.refreshTripFromServer(tripID)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    @ViewBuilder
    private func convertedDraftSetup(_ experience: LocalTripExperience) -> some View {
        if experience.trip.ownerId == store.currentUserID,
           experience.trip.lifecycle == .draft,
           let round = experience.rounds.first(where: { $0.holes.count != $0.holeCount })
        {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("SETUP REQUIRED")
                Text("Finish the copied round")
                    .font(.title3.weight(.black))
                Text("Add a manual course card and confirm handicaps before this trip can be shared or scored.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    setupRound = round
                } label: {
                    Label("Continue setup", systemImage: "square.and.pencil")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(TeeCircleBrand.pine)
                .accessibilityIdentifier("trip.continueSetup")
            }
            .padding(18)
            .teeCard()
        }
    }

    private func hero(_ experience: LocalTripExperience) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                BroadcastStatusPill(title: experience.trip.lifecycle.rawValue, live: experience.trip.lifecycle == .live)
                Spacer()
                Text(experience.trip.scoringMode.rawValue.uppercased())
                    .font(.caption2.weight(.black)).tracking(1)
                    .foregroundStyle(.white.opacity(0.48))
            }
            Text(experience.trip.name)
                .font(.system(size: 35, weight: .black, design: .rounded))
                .tracking(-1.2)
            Text("\(experience.rounds.count) round\(experience.rounds.count == 1 ? "" : "s") · \(experience.players.count) player\(experience.players.count == 1 ? "" : "s") · \(experience.trip.enabledFormats.map(\.rawValue).joined(separator: " + ").capitalized)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
            if let moment = experience.latestSnapshot?.moment {
                Label(moment.summary, systemImage: "bolt.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.signal)
            }
        }
        .foregroundStyle(.white)
        .padding(21)
        .background(
            TeeCircleBrand.raisedCard,
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(TeeCircleBrand.hairline)
        }
    }

    private func actionStrip(_ experience: LocalTripExperience) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    if let url = await store.prepareShareURL(for: tripID) {
                        shareText = inviteMessage(for: experience, url: url)
                        showingShareSheet = true
                    }
                }
            } label: { action("Invite", icon: "paperplane.fill") }
            .disabled(experience.trip.lifecycle == .draft)
            .opacity(experience.trip.lifecycle == .draft ? 0.45 : 1)
            .accessibilityIdentifier("trip.invite")
            Button {
                store.path.append(.leaderboard(tripID))
            } label: { action("Standings", icon: "list.number") }
            .accessibilityIdentifier("trip.standings")
            Button {
                Task { await store.followLive(tripID) }
            } label: { action("Follow", icon: "dot.radiowaves.left.and.right") }
            .disabled(experience.trip.lifecycle != .live)
            .opacity(experience.trip.lifecycle == .live ? 1 : 0.45)
        }
    }

    private func action(_ title: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.headline)
            Text(title).font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .foregroundStyle(TeeCircleBrand.signal)
        .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(TeeCircleBrand.hairline) }
    }

    private func inviteMessage(for experience: LocalTripExperience, url: URL) -> String {
        let round = experience.rounds.sorted { $0.order < $1.order }.first
        let title = round?.courseName.nonEmpty ?? experience.trip.name
        let schedule = round?.scheduledAt?.formatted(date: .abbreviated, time: .shortened)
            ?? "Tee time coming soon"
        let length = round.map { "\($0.holeCount) holes" } ?? "Golf round"
        return "I made a round at \(title) — \(schedule), \(length). Are you in? Join us on TeeCircle: \(url.absoluteString)"
    }

    @ViewBuilder
    private func leaderboardPreview(_ experience: LocalTripExperience) -> some View {
        if let board = experience.latestSnapshot?.primaryBoard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionLabel("LIVE BOARD")
                    Spacer()
                    Text(board.format.rawValue.uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundStyle(TeeCircleBrand.moss)
                }
                VStack(spacing: 0) {
                    ForEach(board.standings.prefix(4)) { standing in
                        HStack(spacing: 12) {
                            Text("\(standing.rank)")
                                .font(.headline.monospaced().weight(.black))
                                .foregroundStyle(standing.rank == 1 ? TeeCircleBrand.signal : .secondary)
                                .frame(width: 25)
                            Text(standing.displayName).font(.headline.weight(.bold))
                            Spacer()
                            Text("THRU \(standing.holesPlayed)")
                                .font(.caption2.monospaced().weight(.bold)).foregroundStyle(.secondary)
                            ScoreboardNumber(value: "\(standing.value)", size: 20)
                        }
                        .padding(.vertical, 11)
                        if standing.id != board.standings.prefix(4).last?.id { Divider() }
                    }
                }
            }
            .padding(18)
            .teeCard()
        } else {
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("LEADERBOARD SHELL")
                Text("The board appears when the first hole is scored.")
                    .font(.headline.weight(.bold))
                Text("Players can see the format before the captain unlocks live scoring.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .teeCard()
        }
    }

    private func rounds(_ experience: LocalTripExperience) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ROUNDS")
            ForEach(experience.rounds) { round in
                HStack(spacing: 14) {
                    BroadcastStatusPill(title: round.lifecycle.rawValue, live: round.lifecycle == .live)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(round.name).font(.headline.weight(.bold))
                        Text(round.courseName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if round.lifecycle == .live, let player = experience.players.first(where: { $0.claimedUserId == store.currentUserID }) {
                        Button("Score") {
                            store.path.append(.score(tripID: tripID, roundID: round.id, playerID: player.id))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TeeCircleBrand.pine)
                        .accessibilityIdentifier("trip.score.\(round.id)")
                    }
                }
                .padding(15)
                .teeCard()
            }
        }
    }

    private func roster(_ experience: LocalTripExperience) -> some View {
        let currentUserHasSeat = experience.players.contains { $0.claimedUserId == store.currentUserID }
        let isCaptain = experience.trip.ownerId == store.currentUserID
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ROSTER")
            VStack(spacing: 0) {
                ForEach(experience.players) { player in
                    HStack(spacing: 12) {
                        Text(player.displayName.prefix(1).uppercased())
                            .font(.subheadline.weight(.black))
                            .frame(width: 36, height: 36)
                            .background(TeeCircleBrand.signal.opacity(0.16), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.displayName).font(.subheadline.weight(.bold))
                            Text(player.role.rawValue.capitalized)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isCaptain, player.role != .captain {
                            Menu {
                                Button {
                                    Task { await store.setTripPlayerRoleProduction(tripID: tripID, playerID: player.id, role: .player) }
                                } label: {
                                    Label("Player", systemImage: player.role == .player ? "checkmark" : "person")
                                }
                                Button {
                                    Task { await store.setTripPlayerRoleProduction(tripID: tripID, playerID: player.id, role: .scorer) }
                                } label: {
                                    Label("Designated scorer", systemImage: player.role == .scorer ? "checkmark" : "pencil.and.list.clipboard")
                                }
                                if player.claimedUserId != nil {
                                    Divider()
                                    Button("Revoke claim", role: .destructive) {
                                        Task { await store.revokePlayerClaimProduction(tripID: tripID, playerID: player.id) }
                                    }
                                }
                            } label: {
                                Label(
                                    player.claimedUserId == nil ? "Manage" : "Claimed",
                                    systemImage: player.claimedUserId == nil ? "ellipsis.circle" : "checkmark.seal.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TeeCircleBrand.moss)
                            }
                            .disabled(![.draft, .ready].contains(experience.trip.lifecycle))
                        } else if player.claimedUserId == nil, !currentUserHasSeat {
                            Button("Claim") {
                                Task { await store.claimPlayerProduction(tripID: tripID, playerID: player.id) }
                            }
                                .font(.caption.weight(.bold))
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("trip.claim.\(player.id)")
                        } else if player.claimedUserId == nil {
                            Text("Open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if player.claimedUserId == store.currentUserID, player.role != .captain {
                            Menu {
                                Button("Can’t make it", role: .destructive) {
                                    Task { await store.declineSeatProduction(tripID: tripID, playerID: player.id) }
                                }
                            } label: {
                                Label("You", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TeeCircleBrand.moss)
                            }
                            .accessibilityIdentifier("trip.decline.\(player.id)")
                        } else {
                            Label("Claimed", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TeeCircleBrand.moss)
                        }
                    }
                    .padding(.vertical, 10)
                    if player.id != experience.players.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .teeCard()
        }
    }

    @ViewBuilder
    private func captainControls(_ experience: LocalTripExperience) -> some View {
        if experience.trip.ownerId == store.currentUserID,
           experience.trip.lifecycle == .ready || experience.trip.lifecycle == .live
        {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("CAPTAIN")
                if !experience.trip.isEntitled {
                    Button {
                        store.path.append(.paywall(tripID))
                    } label: {
                        Label("Unlock live scoring for everyone", systemImage: "lock.open.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(TeeCircleBrand.forest)
                            .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("trip.openPaywall")
                } else if experience.trip.lifecycle != .live {
                    Button {
                        Task { await store.startTournamentProduction(tripID) }
                    } label: {
                        Label(experience.rounds.count == 1 ? "Start round" : "Start tournament", systemImage: "play.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(TeeCircleBrand.pine, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("trip.startTournament")
                } else {
                    Button {
                        Task { await store.completeCurrentRoundProduction(tripID: tripID) }
                    } label: {
                        Label(
                            experience.rounds.contains(where: { $0.lifecycle == .scheduled }) ? "Complete round & start next" : "Publish final result",
                            systemImage: "flag.checkered"
                        )
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(TeeCircleBrand.pine, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("trip.advanceRound")
                }

                Button(role: .destructive) {
                    Task {
                        await store.rotateInviteProduction(tripID: tripID)
                        store.errorMessage = "The previous invite is revoked. Share the new link when you are ready."
                    }
                } label: {
                    Label("Revoke all links & create a new one", systemImage: "link.badge.plus")
                        .font(.subheadline.weight(.bold))
                }

                let inviteMetadata = store.inviteMetadataByTrip[tripID] ?? []
                if !inviteMetadata.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INVITATION HISTORY")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                        ForEach(inviteMetadata.prefix(5)) { invite in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invite.status.rawValue.capitalized)
                                        .font(.caption.weight(.bold))
                                    Text(invite.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if invite.status == .active {
                                    Button("Revoke", role: .destructive) {
                                        Task {
                                            await store.revokeInviteProduction(
                                                tripID: tripID,
                                                inviteID: invite.inviteId
                                            )
                                        }
                                    }
                                    .font(.caption.weight(.bold))
                                }
                            }
                        }
                    }
                    .padding(13)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .tracking(1.2)
            .foregroundStyle(TeeCircleBrand.moss)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
