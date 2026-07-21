import AuthenticationServices
import Foundation
import GoogleSignIn
import TeeCircleDomain
import UIKit

struct PendingInviteSelection: Identifiable, Equatable {
    let token: String
    let trip: InviteAcceptanceTripV1
    let seats: [OpenInviteSeatV1]

    var id: String { token }
}

enum ScoreSubmissionOutcome: Equatable {
    case saved
    case queued
    case conflict(String)
    case failed(String)
}

@MainActor
extension TeeCircleStore {
    // MARK: Session

    func restoreProductionSession() async {
        guard let production else {
            isAuthenticated = false
            errorMessage = "This build is missing its Supabase public configuration."
            return
        }
        isRestoringSession = true
        defer { isRestoringSession = false }
        await production.auth.restoreSession()
        guard case let .signedIn(session) = production.auth.state else {
            isAuthenticated = false
            return
        }
        await finishAuthentication(session)
    }

    func signIn(email: String, password: String) async {
        guard let production else { return reportConfigurationError() }
        await performAuth {
            try await production.auth.signIn(email: email, password: password)
        }
    }

    func sendEmailOTP(to email: String) async -> Bool {
        guard let production else {
            reportConfigurationError()
            return false
        }
        do {
            try await production.auth.sendEmailOTP(to: email)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func verifyEmailOTP(email: String, code: String) async {
        guard let production else { return reportConfigurationError() }
        await performAuth {
            try await production.auth.verifyEmailOTP(email: email, code: code)
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) -> AppleSignInNonce? {
        production?.auth.prepareAppleRequest(request)
    }

    func finishAppleSignIn(
        result: Result<ASAuthorization, Error>,
        nonce: AppleSignInNonce?
    ) async {
        guard let production else { return reportConfigurationError() }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce
            else { throw NativeAuthServiceError.invalidIdentityToken }
            // Apple returns fullName only on the very first authorization for an
            // account and never again, so it has to be read here rather than
            // recovered later from the session.
            pendingAppleFullName = PlayerName.fromAppleComponents(credential.fullName)
            let session = try await production.auth.signInWithApple(
                credential: credential,
                nonce: nonce
            )
            await finishAuthentication(session)
        } catch {
            report(error)
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async {
        guard let production else { return reportConfigurationError() }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw NativeAuthServiceError.invalidIdentityToken
            }
            let session = try await production.auth.signInWithGoogle(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            await finishAuthentication(session)
        } catch {
            report(error)
        }
    }

    func signOutProductionSession() async {
        guard let production else { return }
        do {
            await production.realtime.stopAll()
            for trip in trips {
                if let sessionID = try await production.sharedStore.serverSessionID(for: trip.id) {
                    try? await production.repository.revokeExtensionSession(sessionID: sessionID)
                }
            }
            try? await production.sharedStore.revokeAllLocally()
            await production.pendingScores.removeAll()
            await production.push.unregisterFromServer()
            await production.liveActivity.endAll()
            await production.purchases.clearRevenueCatUser()
            try await production.auth.signOut()
        } catch {
            report(error)
        }
        production.analytics.reset()
        isAuthenticated = false
        currentDisplayName = "Player"
        currentUsername = nil
        needsProfileSetup = nil
        trips = []
        legacyRounds = []
        courseCards = []
        pendingScoreKeys = []
        inviteCredentials = [:]
        inviteMetadataByTrip = [:]
        path.removeAll()
        golfersPath.removeAll()
        selectedTab = .rounds
    }

    private func performAuth(_ action: () async throws -> NativeAuthSession) async {
        do {
            await finishAuthentication(try await action())
        } catch {
            report(error)
        }
    }

    private func finishAuthentication(_ session: NativeAuthSession) async {
        guard let production else { return }
        isAuthenticated = true
        // The email guess is only a placeholder until the server answers. Apple
        // hands over a real name exactly once, on first authorization, so it is
        // seeded here before anything can overwrite it.
        currentDisplayName = pendingAppleFullName ?? displayName(from: session.email)
        production.analytics.identify(supabaseUserID: session.userID)
        await loadProfile(seedingFullName: pendingAppleFullName)
        pendingAppleFullName = nil
        do {
            try await production.purchases.configure(forSupabaseUserID: session.userID)
        } catch {
            // A missing StoreKit sandbox product must not block trip access.
        }
        await loadProductionData()
        await production.liveActivity.restoreExistingActivity()
        let queuedScores = await production.pendingScores.all().filter { $0.userID == session.userID }
        pendingScoreKeys = Set(queuedScores.map {
            HoleScoreKey(roundID: $0.roundID, playerID: $0.playerID, hole: $0.holeNumber)
        })
        await retryPendingScores()
        if let pendingDeepLinkToken {
            self.pendingDeepLinkToken = nil
            await acceptInvite(token: pendingDeepLinkToken, seatID: nil)
        }
        if let pendingInternalTripID {
            self.pendingInternalTripID = nil
            await handleInternalTripRoute(pendingInternalTripID)
        }
        if let outcome = await production.purchases.reconcilePendingClaim(),
           case let .unlocked(claim) = outcome {
            await refreshTripFromServer(claim.tripId)
        }
    }

    // MARK: Reads and mapping

    func loadProductionData() async {
        guard let production, isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let cachedTrips = try? await production.sharedStore.trips() {
                for cached in cachedTrips where !cached.inviteToken.isEmpty {
                    inviteCredentials[cached.trip.id] = TripInviteCredentialV1(
                        inviteId: "locally-cached-link",
                        inviteToken: cached.inviteToken,
                        url: configuration.webBaseURL
                            .appending(path: "t")
                            .appending(path: cached.inviteToken),
                        expiresAt: nil
                    )
                }
            }
            let summaries = try await production.repository.myTrips()
            for summary in summaries {
                if let credential = try? await production.invites.credential(for: summary.tripId) {
                    inviteCredentials[summary.tripId] = credential
                }
            }
            var loaded: [LocalTripExperience] = []
            for summary in summaries {
                let bootstrap = try await production.repository.bootstrap(tripID: summary.tripId)
                loaded.append(makeLocalExperience(from: bootstrap))
            }
            trips = loaded.sorted(by: sortTrips)
            courseCards = try await production.repository.courseCards().map {
                CourseCard(
                    id: $0.courseCardId,
                    ownerId: currentUserID,
                    name: $0.courseName,
                    teeName: $0.name == $0.courseName ? nil : $0.name,
                    holes: $0.holes.map {
                        CourseCardHole(
                            number: $0.holeNumber,
                            par: $0.par,
                            strokeIndex: $0.strokeIndex
                        )
                    }
                )
            }
            legacyRounds = try await production.repository.legacyRounds().map {
                LegacyRoundSummary(
                    id: $0.roundId,
                    courseName: $0.courseName,
                    startsAt: $0.teeTime,
                    holes: $0.holeCount,
                    inviteeDisplayNames: []
                )
            }
            try await synchronizeMessagesBridge()
        } catch {
            report(error)
        }
    }

    func refreshTripFromServer(_ tripID: String) async {
        guard let production, isAuthenticated, !configuration.useMockData else { return }
        do {
            let bootstrap = try await production.repository.bootstrap(tripID: tripID)
            let refreshed = makeLocalExperience(from: bootstrap)
            if let index = trips.firstIndex(where: { $0.id == tripID }) {
                trips[index] = refreshed
            } else {
                trips.append(refreshed)
            }
            trips.sort(by: sortTrips)
            await endLiveActivityIfCanonicalFinal(refreshed)
            try await synchronizeMessagesBridge()
        } catch {
            report(error)
        }
    }

    func beginObservingTrip(_ tripID: String) {
        production?.realtime.observe(tripID: tripID) { [weak self] in
            await self?.refreshTripFromServer(tripID)
        }
    }

    func stopObservingTrip(_ tripID: String) {
        production?.realtime.stopObserving(tripID: tripID)
    }

    private func makeLocalExperience(from bootstrap: NativeTripBootstrapV1) -> LocalTripExperience {
        let detail = bootstrap.trip
        let userID = currentUserID
        let ownerID = detail.isCaptain ? userID : "server-owner"
        let trip = Trip(
            id: detail.tripId,
            publicId: detail.publicId,
            ownerId: ownerID,
            name: detail.name,
            startDate: detail.startsOn,
            endDate: detail.endsOn,
            timeZone: detail.timezone,
            lifecycle: detail.status,
            enabledFormats: detail.enabledFormats,
            primaryFormat: detail.primaryFormat,
            scoringMode: detail.scoringMode,
            scoreRevision: detail.scoreRevision,
            isEntitled: detail.isUnlocked
        )
        let players = bootstrap.roster.enumerated().map { index, seat in
            TripPlayer(
                id: seat.tripPlayerId,
                tripId: detail.tripId,
                claimedUserId: seat.isCurrentUser ? userID : (seat.claimed ? "claimed-user" : nil),
                displayName: seat.displayName,
                role: seat.role,
                rsvp: seat.rsvp.domainValue,
                handicapSnapshot: seat.handicapSnapshot,
                sortOrder: index
            )
        }
        let rounds = bootstrap.rounds.map { round in
            TripRound(
                id: round.roundId,
                publicId: round.publicId,
                tripId: detail.tripId,
                name: round.courseName,
                courseName: round.courseName,
                order: round.tripOrder,
                scheduledAt: round.teeTime,
                lifecycle: round.status,
                holeCount: round.holeCount,
                holes: round.holes.map {
                    RoundHole(number: $0.holeNumber, par: $0.par, strokeIndex: $0.strokeIndex)
                }
            )
        }
        let roundPlayers = bootstrap.rounds.flatMap { round in
            round.players.map {
                TripRoundPlayer(
                    roundId: round.roundId,
                    tripPlayerId: $0.tripPlayerId,
                    isActive: $0.status == "active",
                    courseHandicap: $0.courseHandicap,
                    playingHandicap: $0.playingHandicap
                )
            }
        }
        var scores: [HoleScoreKey: LocalHoleScore] = [:]
        for round in bootstrap.rounds {
            for score in round.scores {
                scores[HoleScoreKey(
                    roundID: round.roundId,
                    playerID: score.tripPlayerId,
                    hole: score.holeNumber
                )] = LocalHoleScore(strokes: score.strokes, penalties: score.penalties)
            }
        }
        return LocalTripExperience(
            trip: trip,
            players: players,
            rounds: rounds.sorted { $0.order < $1.order },
            roundPlayers: roundPlayers,
            scores: scores,
            latestSnapshot: bootstrap.snapshot,
            inviteToken: inviteCredentials[detail.tripId]?.inviteToken ?? self.trip(id: detail.tripId)?.inviteToken ?? ""
        )
    }

    // MARK: Trip setup and lifecycle

    func submitTrip(from draft: CreateTripDraft) async -> String? {
        guard !configuration.useMockData else { return createTrip(from: draft) }
        guard let production else {
            reportConfigurationError()
            return nil
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let formats = TournamentFormat.allCases.filter { draft.enabledFormats.contains($0) }
            let result = try await production.repository.createTrip(
                CreateNativeTripInputV1(
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    startsOn: Self.tripDateFormatter.string(from: draft.startDate),
                    endsOn: Self.tripDateFormatter.string(from: draft.endDate),
                    timezone: TimeZone.current.identifier,
                    enabledFormats: formats,
                    primaryFormat: formats.contains(draft.primaryFormat) ? draft.primaryFormat : (formats.first ?? .stableford),
                    scoringMode: draft.scoringMode,
                    captainDisplayName: draft.playerNames.first?.nonEmpty ?? currentDisplayName,
                    captainHandicap: draft.playerHandicaps.first ?? nil
                ),
                idempotencyKey: UUID().uuidString.lowercased()
            )

            for index in draft.playerNames.indices.dropFirst() {
                guard let displayName = draft.playerNames[index].nonEmpty else { continue }
                _ = try await production.repository.addTripPlayer(
                    tripID: result.tripId,
                    input: AddTripPlayerInputV1(
                        displayName: displayName,
                        role: .player,
                        rsvp: .pending,
                        handicap: draft.playerHandicaps.indices.contains(index) ? draft.playerHandicaps[index] : nil
                    ),
                    idempotencyKey: UUID().uuidString.lowercased()
                )
            }

            for round in draft.rounds {
                let holes = Array(round.holes.prefix(round.holeCount))
                let matchingCard = courseCards.first { card in
                    card.name.caseInsensitiveCompare(round.courseName) == .orderedSame
                        && card.holes == holes.map {
                            CourseCardHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
                        }
                }
                let cardID: String
                if let matchingCard {
                    cardID = matchingCard.id
                } else {
                    let card = try await production.repository.createCourseCard(
                        CreateCourseCardInputV1(
                            name: round.courseName.nonEmpty ?? round.name.nonEmpty ?? "Manual course card",
                            courseName: round.courseName.nonEmpty ?? "Course TBD",
                            holes: holes.map {
                                CreateCourseCardHoleInputV1(
                                    holeNumber: $0.number,
                                    par: $0.par,
                                    strokeIndex: $0.strokeIndex,
                                    yards: nil
                                )
                            }
                        ),
                        idempotencyKey: UUID().uuidString.lowercased()
                    )
                    cardID = card.courseCardId
                    courseCards.append(
                        CourseCard(
                            id: card.courseCardId,
                            ownerId: currentUserID,
                            name: round.courseName.nonEmpty ?? "Course",
                            teeName: nil,
                            holes: holes.map {
                                CourseCardHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
                            }
                        )
                    )
                }
                _ = try await production.repository.createTripRound(
                    tripID: result.tripId,
                    input: CreateTripRoundInputV1(
                        courseCardId: cardID,
                        teeTime: round.scheduledAt,
                        walkRide: round.walkRide
                    ),
                    idempotencyKey: UUID().uuidString.lowercased()
                )
            }

            _ = try await production.repository.transitionTrip(id: result.tripId, from: .draft, to: .ready)
            let invite = try await production.repository.createInvite(
                tripID: result.tripId,
                expiresAt: nil,
                maxUses: nil,
                idempotencyKey: UUID().uuidString.lowercased()
            )
            inviteCredentials[result.tripId] = invite
            try await production.invites.save(invite, tripID: result.tripId)
            await refreshTripFromServer(result.tripId)
            production.analytics.capture(.tripCreated(
                roundCount: draft.rounds.count,
                playerCount: draft.playerNames.filter { $0.nonEmpty != nil }.count
            ))
            return result.tripId
        } catch {
            report(error)
            // Successfully-created partial drafts remain visible and recoverable.
            await loadProductionData()
            return nil
        }
    }

    func convertLegacyRoundProduction(_ legacyID: String) async -> String? {
        guard !configuration.useMockData else { return convertLegacyRound(legacyID) }
        guard let production,
              let legacy = legacyRounds.first(where: { $0.id == legacyID })
        else { return nil }
        do {
            let result = try await production.repository.convertLegacyRound(
                id: legacyID,
                tripName: "\(legacy.courseName) Trip",
                idempotencyKey: UUID().uuidString.lowercased()
            )
            await refreshTripFromServer(result.tripId)
            return result.tripId
        } catch {
            report(error)
            return nil
        }
    }

    func finishLegacyConversionProduction(
        tripID: String,
        roundID: String,
        savedCourseCardID: String?,
        courseName: String,
        holes: [RoundHole],
        handicaps: [String: Double]
    ) async -> Bool {
        guard !configuration.useMockData else { return true }
        guard let production,
              let experience = trip(id: tripID),
              experience.trip.ownerId == currentUserID,
              experience.trip.lifecycle == .draft,
              let round = experience.rounds.first(where: { $0.id == roundID })
        else {
            errorMessage = "This converted round is no longer editable."
            return false
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let cardID: String
            if let savedCourseCardID {
                guard let card = courseCards.first(where: { $0.id == savedCourseCardID }),
                      card.holes.count == round.holeCount
                else {
                    errorMessage = "Choose a saved card with the same number of holes."
                    return false
                }
                cardID = savedCourseCardID
            } else {
                let normalizedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedName.isEmpty, holes.count == round.holeCount else {
                    errorMessage = "Complete the course name and every hole before continuing."
                    return false
                }
                let created = try await production.repository.createCourseCard(
                    CreateCourseCardInputV1(
                        name: normalizedName,
                        courseName: normalizedName,
                        holes: holes.map {
                            CreateCourseCardHoleInputV1(
                                holeNumber: $0.number,
                                par: $0.par,
                                strokeIndex: $0.strokeIndex,
                                yards: nil
                            )
                        }
                    ),
                    idempotencyKey: UUID().uuidString.lowercased()
                )
                cardID = created.courseCardId
                courseCards.append(
                    CourseCard(
                        id: created.courseCardId,
                        ownerId: currentUserID,
                        name: normalizedName,
                        teeName: nil,
                        holes: holes.map {
                            CourseCardHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
                        }
                    )
                )
            }

            _ = try await production.repository.updateTripRound(
                id: roundID,
                input: UpdateTripRoundInputV1(courseCardId: cardID),
                expectedNativeUpdatedAt: nil
            )

            for player in experience.players where player.rsvp != .declined {
                guard let handicap = handicaps[player.id], (-10...54).contains(handicap) else {
                    errorMessage = "Enter a handicap from -10 to 54 for every active player."
                    return false
                }
                _ = try await production.repository.updateTripPlayer(
                    id: player.id,
                    input: UpdateTripPlayerInputV1(handicap: .set(handicap))
                )
                let playing = Int(handicap.rounded())
                _ = try await production.repository.setRoundParticipation(
                    roundID: roundID,
                    tripPlayerID: player.id,
                    courseHandicap: playing,
                    playingHandicap: playing,
                    status: .active
                )
            }

            _ = try await production.repository.transitionTrip(
                id: tripID,
                from: .draft,
                to: .ready
            )
            do {
                let invite = try await production.repository.createInvite(
                    tripID: tripID,
                    expiresAt: nil,
                    maxUses: nil,
                    idempotencyKey: UUID().uuidString.lowercased()
                )
                inviteCredentials[tripID] = invite
                try await production.invites.save(invite, tripID: tripID)
            } catch {
                // The trip is fully usable even if initial link creation needs a retry.
            }
            await refreshTripFromServer(tripID)
            return true
        } catch {
            report(error)
            await refreshTripFromServer(tripID)
            return false
        }
    }

    func claimPlayerProduction(tripID: String, playerID: String) async {
        guard !configuration.useMockData else {
            claimPlayer(tripID: tripID, playerID: playerID)
            return
        }
        guard let production else { return }
        guard let inviteToken = inviteCredentials[tripID]?.inviteToken else {
            errorMessage = "Open the current TeeCircle invitation link to claim this seat."
            return
        }
        do {
            let result = try await production.repository.acceptInvite(
                token: inviteToken,
                tripPlayerID: playerID
            )
            guard result.accepted else {
                errorMessage = "That invitation can no longer claim this roster seat."
                return
            }
            production.analytics.capture(.rosterClaimed)
            await refreshTripFromServer(tripID)
        } catch { report(error) }
    }

    func revokePlayerClaimProduction(tripID: String, playerID: String) async {
        guard !configuration.useMockData else {
            revokePlayerClaim(tripID: tripID, playerID: playerID)
            return
        }
        guard let production else { return }
        do {
            _ = try await production.repository.releaseTripPlayerClaim(id: playerID)
            await refreshTripFromServer(tripID)
        } catch { report(error) }
    }

    func setTripPlayerRoleProduction(
        tripID: String,
        playerID: String,
        role: TripPlayerRole
    ) async {
        guard role == .player || role == .scorer else { return }
        guard !configuration.useMockData else {
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                  let playerIndex = trips[tripIndex].players.firstIndex(where: { $0.id == playerID })
            else { return }
            let player = trips[tripIndex].players[playerIndex]
            trips[tripIndex].players[playerIndex] = TripPlayer(
                id: player.id,
                tripId: player.tripId,
                claimedUserId: player.claimedUserId,
                displayName: player.displayName,
                role: role,
                rsvp: player.rsvp,
                handicapSnapshot: player.handicapSnapshot,
                sortOrder: player.sortOrder
            )
            return
        }
        guard let production else { return }
        do {
            _ = try await production.repository.updateTripPlayer(
                id: playerID,
                input: UpdateTripPlayerInputV1(role: role)
            )
            await refreshTripFromServer(tripID)
        } catch { report(error) }
    }

    func startTournamentProduction(_ tripID: String) async {
        guard !configuration.useMockData else {
            startTournament(tripID)
            return
        }
        guard let production, let experience = trip(id: tripID) else { return }
        do {
            _ = try await production.repository.startTrip(
                id: tripID,
                expectedScoreRevision: experience.trip.scoreRevision
            )
            await refreshTripFromServer(tripID)
        } catch { report(error) }
    }

    func completeCurrentRoundProduction(tripID: String) async {
        guard !configuration.useMockData else {
            completeCurrentRound(tripID: tripID)
            return
        }
        guard let production, let experience = trip(id: tripID),
              let current = experience.rounds.first(where: { $0.lifecycle == .live })
        else { return }
        do {
            _ = try await production.repository.advanceTripRound(
                tripID: tripID,
                currentRoundID: current.id,
                expectedScoreRevision: experience.trip.scoreRevision,
                allowIncomplete: false
            )
            await refreshTripFromServer(tripID)
        } catch { report(error) }
    }

    // MARK: Scoring and offline retry

    func submitScore(
        tripID: String,
        roundID: String,
        playerID: String,
        hole: Int,
        strokes: Int,
        penalties: Int = 0
    ) async -> ScoreSubmissionOutcome {
        guard !configuration.useMockData else {
            recordScore(
                tripID: tripID,
                roundID: roundID,
                playerID: playerID,
                hole: hole,
                strokes: strokes,
                penalties: penalties
            )
            return .saved
        }
        guard let production, let experience = trip(id: tripID) else {
            return .failed("Trip unavailable.")
        }
        let key = HoleScoreKey(roundID: roundID, playerID: playerID, hole: hole)
        let idempotencyKey = UUID().uuidString.lowercased()
        let startedAt = Date()
        do {
            let result = try await production.repository.recordHoleScore(
                ScoreHoleCommandV1(
                    roundId: roundID,
                    tripPlayerId: playerID,
                    hole: hole,
                    strokes: strokes,
                    expectedRevision: experience.trip.scoreRevision,
                    idempotencyKey: idempotencyKey
                ),
                penalties: penalties
            )
            pendingScoreKeys.remove(key)
            applyAcceptedScore(
                tripID: tripID,
                score: result.score,
                revision: result.revision,
                snapshot: result.snapshot
            )
            production.analytics.capture(.scoreAccepted(
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                offlineRetry: false
            ))
            if let updated = trip(id: tripID) {
                try? await production.liveActivity.updateAfterAcceptedScore(
                    tripID: tripID,
                    snapshot: result.snapshot,
                    viewerPlayerID: currentPlayerID(in: updated)
                )
            }
            Task { @MainActor [weak self] in await self?.refreshTripFromServer(tripID) }
            return .saved
        } catch let TeeCircleRepositoryError.server(payload) where payload.code == "score_conflict" {
            await refreshTripFromServer(tripID)
            production.analytics.capture(.scoreFailed(code: payload.code, retryable: payload.retryable))
            return .conflict(scoreConflictMessage(payload))
        } catch {
            if isRetryable(error) {
                let queued = QueuedHoleScore(
                    tripID: tripID,
                    userID: currentUserID,
                    roundID: roundID,
                    playerID: playerID,
                    holeNumber: hole,
                    strokes: strokes,
                    penalties: penalties,
                    expectedRevision: experience.trip.scoreRevision,
                    idempotencyKey: idempotencyKey,
                    queuedAt: .now
                )
                await production.pendingScores.enqueue(queued)
                pendingScoreKeys.insert(key)
                return .queued
            }
            report(error)
            return .failed(error.localizedDescription)
        }
    }

    func retryPendingScores() async {
        guard let production, isAuthenticated else { return }
        for queued in await production.pendingScores.all() where queued.userID == currentUserID {
            do {
                let result = try await production.repository.recordHoleScore(
                    ScoreHoleCommandV1(
                        roundId: queued.roundID,
                        tripPlayerId: queued.playerID,
                        hole: queued.holeNumber,
                        strokes: queued.strokes,
                        expectedRevision: queued.expectedRevision,
                        idempotencyKey: queued.idempotencyKey
                    ),
                    penalties: queued.penalties
                )
                await production.pendingScores.remove(id: queued.id)
                pendingScoreKeys.remove(HoleScoreKey(
                    roundID: queued.roundID,
                    playerID: queued.playerID,
                    hole: queued.holeNumber
                ))
                applyAcceptedScore(
                    tripID: queued.tripID,
                    score: result.score,
                    revision: result.revision,
                    snapshot: result.snapshot
                )
                production.analytics.capture(.scoreAccepted(latencyMilliseconds: 0, offlineRetry: true))
            } catch let TeeCircleRepositoryError.server(payload) where payload.code == "score_conflict" {
                await production.pendingScores.remove(id: queued.id)
                pendingScoreKeys.remove(HoleScoreKey(
                    roundID: queued.roundID,
                    playerID: queued.playerID,
                    hole: queued.holeNumber
                ))
                await refreshTripFromServer(queued.tripID)
                errorMessage = "Offline retry stopped. \(scoreConflictMessage(payload))"
            } catch {
                // Connectivity failures keep the original command key and revision.
            }
        }
    }

    private func applyAcceptedScore(
        tripID: String,
        score: AcceptedHoleScoreV1,
        revision: Int,
        snapshot: LeaderboardSnapshotV1
    ) {
        replaceTrip(tripID) { experience in
            experience.scores[HoleScoreKey(
                roundID: score.roundId,
                playerID: score.tripPlayerId,
                hole: score.holeNumber
            )] = LocalHoleScore(strokes: score.strokes, penalties: score.penalties)
            experience.trip = experience.trip.replacing(scoreRevision: revision)
            experience.latestSnapshot = snapshot
        }
    }

    // MARK: Invite, Messages and sharing

    func prepareShareURL(for tripID: String) async -> URL? {
        guard !configuration.useMockData else { return shareURL(for: tripID) }
        guard let production else { return nil }
        if let credential = inviteCredentials[tripID] {
            return credential.url
        }
        do {
            let credential = try await production.repository.createInvite(
                tripID: tripID,
                expiresAt: nil,
                maxUses: nil,
                idempotencyKey: UUID().uuidString.lowercased()
            )
            inviteCredentials[tripID] = credential
            try await production.invites.save(credential, tripID: tripID)
            replaceTrip(tripID) { $0.inviteToken = credential.inviteToken }
            production.analytics.capture(.inviteCreated)
            try await synchronizeMessagesBridge()
            return credential.url
        } catch {
            report(error)
            return nil
        }
    }

    func rotateInviteProduction(tripID: String) async {
        guard !configuration.useMockData else {
            rotateInvite(tripID: tripID)
            return
        }
        guard let production else { return }
        do {
            let credential = try await production.repository.rotateInvite(
                tripID: tripID,
                expiresAt: nil,
                maxUses: nil,
                idempotencyKey: UUID().uuidString.lowercased()
            )
            inviteCredentials[tripID] = credential
            try? await production.invites.remove(tripID: tripID)
            try await production.invites.save(credential, tripID: tripID)
            replaceTrip(tripID) { experience in
                experience.inviteToken = credential.inviteToken
            }
            try await synchronizeMessagesBridge()
            await refreshInviteMetadataProduction(tripID: tripID)
        } catch { report(error) }
    }

    func refreshInviteMetadataProduction(tripID: String) async {
        guard !configuration.useMockData, let production else { return }
        do {
            inviteMetadataByTrip[tripID] = try await production.repository.listInvites(tripID: tripID)
        } catch {
            // Metadata is an operational control; a transient read failure must
            // not hide or invalidate the locally-held share link.
        }
    }

    func revokeInviteProduction(tripID: String, inviteID: String) async {
        guard !configuration.useMockData, let production else { return }
        do {
            try await production.repository.revokeInvite(inviteID: inviteID)
            if inviteCredentials[tripID]?.inviteId == inviteID {
                inviteCredentials.removeValue(forKey: tripID)
                try? await production.invites.remove(tripID: tripID)
                replaceTrip(tripID) { $0.inviteToken = "" }
            }
            await refreshInviteMetadataProduction(tripID: tripID)
            try? await synchronizeMessagesBridge()
        } catch { report(error) }
    }

    func handleInviteToken(_ token: String) async {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard (40...128).contains(token.count),
              token.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            errorMessage = "That TeeCircle link is invalid."
            return
        }
        guard isAuthenticated else {
            pendingDeepLinkToken = token
            return
        }
        await acceptInvite(token: token, seatID: nil)
    }

    func acceptPendingInvite(seatID: String) async {
        guard let pendingInvite else { return }
        self.pendingInvite = nil
        await acceptInvite(token: pendingInvite.token, seatID: seatID)
    }

    private func acceptInvite(token: String, seatID: String?) async {
        guard let production else { return }
        do {
            let result = try await production.repository.acceptInvite(token: token, tripPlayerID: seatID)
            if result.accepted, let bootstrap = result.bootstrap {
                let tripID = result.tripId ?? bootstrap.trip.tripId
                let synthetic = TripInviteCredentialV1(
                    inviteId: "accepted-link",
                    inviteToken: token,
                    url: configuration.webBaseURL.appending(path: "t").appending(path: token),
                    expiresAt: nil
                )
                inviteCredentials[tripID] = synthetic
                let experience = makeLocalExperience(from: bootstrap)
                trips.removeAll { $0.id == tripID }
                trips.insert(experience, at: 0)
                try await synchronizeMessagesBridge()
                path = [.trip(tripID)]
                return
            }
            if let trip = result.trip, let seats = result.openSeats, !seats.isEmpty {
                pendingInvite = PendingInviteSelection(token: token, trip: trip, seats: seats)
                return
            }
            errorMessage = "No open roster seat is available for this invitation."
        } catch { report(error) }
    }

    private func synchronizeMessagesBridge() async throws {
        guard let production else { return }
        let deviceID = try await production.sharedStore.stableDeviceID()
        var cached: [CachedMessagesTripV1] = []
        for experience in trips {
            guard !experience.inviteToken.isEmpty,
                  let snapshot = experience.latestSnapshot,
                  let claimedPlayer = experience.players.first(where: { $0.claimedUserId == currentUserID })
            else { continue }

            let credential = try? await production.sharedStore.credential(for: experience.id)
            if credential == nil {
                let issue = try await production.repository.issueExtensionSession(
                    tripID: experience.id,
                    deviceID: deviceID
                )
                try await production.sharedStore.save(issue: issue, deviceID: deviceID)
            }
            let scoringRound = experience.rounds.first(where: { $0.lifecycle == .live })
            cached.append(
                CachedMessagesTripV1(
                    schemaVersion: 1,
                    trip: experience.trip,
                    inviteToken: experience.inviteToken,
                    claimedPlayer: claimedPlayer,
                    scoringRoundId: scoringRound?.id,
                    scoringRoundHoleCount: scoringRound?.holes.count,
                    snapshot: snapshot,
                    cachedAt: .now
                )
            )
        }
        try await production.sharedStore.saveTrips(cached)
    }

    // MARK: Purchases, ActivityKit and notifications

    func loadTripUnlockProduct() async -> TripUnlockProduct? {
        guard let production else { return nil }
        do { return try await production.purchases.loadProduct() }
        catch { report(error); return nil }
    }

    func purchaseTripUnlock(_ tripID: String) async -> TripUnlockOutcome? {
        guard !configuration.useMockData else {
            if ProcessInfo.processInfo.arguments.contains("-ui-purchase-cancel") {
                return .cancelled(purchaseIntentID: "fixture-cancelled-intent")
            }
            unlockTrip(tripID)
            return nil
        }
        guard let production else { return nil }
        guard trip(id: tripID)?.trip.ownerId == currentUserID else {
            errorMessage = "Only the trip captain can unlock live scoring."
            return nil
        }
        production.analytics.capture(.purchaseStarted)
        do {
            let outcome = try await production.purchases.purchaseTripUnlock(tripID: tripID)
            switch outcome {
            case .cancelled:
                production.analytics.capture(.purchaseCancelled)
            case .pendingServerVerification:
                production.analytics.capture(.purchasePendingVerification)
            case .unlocked:
                production.analytics.capture(.purchaseVerified)
                await refreshTripFromServer(tripID)
            }
            return outcome
        } catch {
            report(error)
            return nil
        }
    }

    func reconcileTripPurchase(_ tripID: String) async {
        guard let production else { return }
        if let outcome = await production.purchases.reconcilePendingClaim(),
           case .unlocked = outcome {
            await refreshTripFromServer(tripID)
            return
        }
        await refreshTripFromServer(tripID)
        if trip(id: tripID)?.trip.isEntitled != true {
            errorMessage = "No verified unlock is attached to this trip yet."
        }
    }

    func followLive(_ tripID: String) async {
        guard let production, let experience = trip(id: tripID),
              experience.trip.lifecycle == .live,
              let snapshot = experience.latestSnapshot
        else {
            errorMessage = "Follow Live becomes available when the tournament starts."
            return
        }
        do {
            _ = try await production.liveActivity.follow(
                tripID: tripID,
                tripName: experience.trip.name,
                viewerPlayerID: currentPlayerID(in: experience),
                snapshot: snapshot
            )
            production.analytics.capture(.liveActivityStarted)
        } catch { report(error) }
    }

    func requestNotificationPermission() async {
        await production?.push.requestAuthorizationAndRegister()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        production?.push.didRegister(deviceToken: deviceToken)
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        production?.push.didFailToRegister(error: error)
    }

    func accountDeletionBlockers() async -> AccountDeletionBlockersV1? {
        guard let production else { return nil }
        do { return try await production.repository.accountDeletionBlockers() }
        catch { report(error); return nil }
    }

    /// Runs the server-side deletion, then clears all local state. The server
    /// account no longer exists on success, so server-bound sign-out calls are
    /// best-effort only.
    func deleteAccountProduction() async -> Bool {
        guard let production else {
            reportConfigurationError()
            return false
        }
        do {
            let result = try await production.repository.deleteAccount()
            guard result.deleted else {
                errorMessage = "The account could not be deleted. Try again."
                return false
            }
        } catch {
            report(error)
            return false
        }
        await production.realtime.stopAll()
        try? await production.sharedStore.revokeAllLocally()
        await production.pendingScores.removeAll()
        await production.liveActivity.endAll()
        await production.purchases.clearRevenueCatUser()
        try? await production.auth.signOut()
        production.analytics.reset()
        isAuthenticated = false
        currentDisplayName = "Player"
        currentUsername = nil
        needsProfileSetup = nil
        trips = []
        legacyRounds = []
        courseCards = []
        pendingScoreKeys = []
        inviteCredentials = [:]
        inviteMetadataByTrip = [:]
        path.removeAll()
        golfersPath.removeAll()
        selectedTab = .rounds
        return true
    }

    // MARK: Helpers

    private func endLiveActivityIfCanonicalFinal(_ experience: LocalTripExperience) async {
        guard let production,
              let finalSnapshot = experience.canonicalTerminalSnapshot
        else { return }
        await production.liveActivity.end(
            tripID: experience.id,
            finalSnapshot: finalSnapshot,
            viewerPlayerID: currentPlayerID(in: experience)
        )
    }

    func handleInternalTripRoute(_ tripID: String) async {
        guard isAuthenticated else {
            pendingInternalTripID = tripID
            return
        }
        if trip(id: tripID) == nil {
            await refreshTripFromServer(tripID)
        }
        guard trip(id: tripID) != nil else {
            errorMessage = "That TeeCircle trip is no longer available on this account."
            return
        }
        showTrip(tripID)
    }

    private static let tripDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func currentPlayerID(in experience: LocalTripExperience) -> String? {
        experience.players.first(where: { $0.claimedUserId == currentUserID })?.id
    }

    /// Reads the signed-in identity and decides whether setup is still owed.
    /// A failure leaves `needsProfileSetup` nil so a flaky network never pushes an
    /// established user into the setup gate.
    func loadProfile(seedingFullName seed: String? = nil) async {
        guard let production, !configuration.useMockData else { return }
        do {
            let profile = try await production.repository.myProfile()
            applyProfile(profile, fallbackFullName: seed)
        } catch {
            needsProfileSetup = nil
        }
    }

    @discardableResult
    func saveProfile(fullName: String, username: String) async -> ProfileSaveOutcome {
        guard let production, !configuration.useMockData else {
            currentDisplayName = fullName
            currentUsername = username
            needsProfileSetup = false
            return .saved
        }
        do {
            let profile = try await production.repository.updateMyProfile(
                fullName: fullName,
                username: username
            )
            applyProfile(profile, fallbackFullName: nil)
            return .saved
        } catch {
            return profileSaveFailure(for: error)
        }
    }

    private func applyProfile(_ profile: NativeProfileV1, fallbackFullName: String?) {
        // username is shown with a leading @ only at the point of display, so the
        // stored value stays the canonical handle.
        currentUsername = profile.username
        if let name = profile.fullName, !name.isEmpty {
            currentDisplayName = name
        } else if let fallbackFullName, !fallbackFullName.isEmpty {
            currentDisplayName = fallbackFullName
        }
        needsProfileSetup = !profile.isComplete
    }

    /// Server-authored copy is preferred so a taken handle reads the same in both
    /// clients; transport failures get a generic retry message instead of leaking
    /// URLSession wording into a form field.
    private func profileSaveFailure(for error: Error) -> ProfileSaveOutcome {
        guard case let .server(payload)? = error as? TeeCircleRepositoryError else {
            return .failed(code: nil, message: "Could not save your profile. Check your connection and try again.")
        }
        return .failed(code: payload.code, message: payload.message)
    }

    private func displayName(from email: String?) -> String {
        guard let localPart = email?.split(separator: "@").first, !localPart.isEmpty else {
            return "Player"
        }
        return String(localPart).replacingOccurrences(of: ".", with: " ").capitalized
    }

    private func sortTrips(_ lhs: LocalTripExperience, _ rhs: LocalTripExperience) -> Bool {
        let order: [TripLifecycle: Int] = [.live: 0, .ready: 1, .draft: 2, .completed: 3, .archived: 4]
        if lhs.trip.lifecycle != rhs.trip.lifecycle {
            return (order[lhs.trip.lifecycle] ?? 9) < (order[rhs.trip.lifecycle] ?? 9)
        }
        return lhs.trip.startDate > rhs.trip.startDate
    }

    private func isRetryable(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case let TeeCircleRepositoryError.server(payload) = error { return payload.retryable }
        if case let TeeCircleRepositoryError.transport(transport) = error {
            switch transport {
            case .nonHTTPResponse:
                return true
            case let .server(statusCode, _):
                return statusCode == 408 || statusCode == 429 || statusCode >= 500
            default:
                return false
            }
        }
        return false
    }

    private func scoreConflictMessage(_ payload: APIErrorPayload) -> String {
        guard case let .object(score)? = payload.details?["currentScore"],
              let strokes = score["strokes"]?.intValue
        else {
            return "The leaderboard changed. The current server score was reloaded; review it before saving again."
        }
        let penalties = score["penalties"]?.intValue ?? 0
        let gross = strokes + penalties
        let breakdown = penalties > 0
            ? "\(gross) gross (\(strokes) strokes + \(penalties) penalty)"
            : "\(gross) gross"
        return "The score changed on another device. The server kept \(breakdown); review it before saving again."
    }

    private func reportConfigurationError() {
        errorMessage = "This build is missing its public Supabase configuration."
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private extension NativeRSVPStatus {
    var domainValue: RSVPStatus {
        switch self {
        case .yes: .accepted
        case .no: .declined
        case .pending: .pending
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
