import Foundation
import TeeCircleAPI
import TeeCircleDomain

protocol TripPurchaseRepositoryProtocol: Sendable {
    func createPurchaseIntent(tripID: String, idempotencyKey: String) async throws -> PurchaseIntentV1
    func cancelPurchaseIntent(intentID: String) async throws -> PurchaseIntentCancellationResultV1
    func claimPurchase(intentID: String, transactionID: String, productID: String) async throws -> PurchaseClaimResultV1
}

protocol TeeCircleRepositoryProtocol: TripPurchaseRepositoryProtocol {
    func createTrip(_ input: CreateNativeTripInputV1, idempotencyKey: String) async throws -> CreateNativeTripResultV1
    func updateTrip(id: String, input: UpdateNativeTripInputV1, expectedUpdatedAt: Date?) async throws -> UpdateNativeTripResultV1
    func createCourseCard(_ input: CreateCourseCardInputV1, idempotencyKey: String) async throws -> CreateCourseCardResultV1
    func updateCourseCard(id: String, input: UpdateCourseCardInputV1, expectedUpdatedAt: Date?) async throws -> UpdateCourseCardResultV1
    func courseCards() async throws -> [NativeCourseCardV1]
    func addTripPlayer(tripID: String, input: AddTripPlayerInputV1, idempotencyKey: String) async throws -> AddTripPlayerResultV1
    func createTripRound(tripID: String, input: CreateTripRoundInputV1, idempotencyKey: String) async throws -> CreateTripRoundResultV1
    func updateTripRound(id: String, input: UpdateTripRoundInputV1, expectedNativeUpdatedAt: Date?) async throws -> UpdateTripRoundResultV1
    func deleteTripRound(id: String, idempotencyKey: String, expectedNativeUpdatedAt: Date?) async throws -> DeleteTripRoundResultV1
    func setRoundParticipation(roundID: String, tripPlayerID: String, courseHandicap: Int?, playingHandicap: Int?, status: RoundParticipationStatusV1) async throws -> SetRoundParticipationResultV1
    func releaseTripPlayerClaim(id: String) async throws -> TripPlayerClaimResultV1
    func updateTripPlayer(id: String, input: UpdateTripPlayerInputV1) async throws -> UpdateTripPlayerResultV1
    func deleteTripPlayer(id: String, idempotencyKey: String, expectedUpdatedAt: Date?) async throws -> DeleteTripPlayerResultV1
    func transitionTrip(id: String, from: TripLifecycle, to: TripLifecycle) async throws -> TripLifecycleResultV1
    func transitionRound(id: String, from: RoundLifecycle, to: RoundLifecycle, allowIncomplete: Bool) async throws -> RoundLifecycleResultV1
    func startTrip(id: String, expectedScoreRevision: Int) async throws -> StartTripResultV1
    func advanceTripRound(tripID: String, currentRoundID: String, expectedScoreRevision: Int, allowIncomplete: Bool) async throws -> AdvanceTripRoundResultV1
    func transferTripOwnership(tripID: String, newOwnerTripPlayerID: String) async throws -> TransferTripOwnershipResultV1
    func accountDeletionBlockers() async throws -> AccountDeletionBlockersV1
    func deleteAccount() async throws -> AccountDeletionResultV1
    func acceptInvite(token: String, tripPlayerID: String?) async throws -> InviteAcceptanceResultV1
    func myProfile() async throws -> NativeProfileV1
    func updateMyProfile(fullName: String, username: String) async throws -> NativeProfileV1
    func myTrips() async throws -> [NativeTripSummaryV1]
    func bootstrap(tripID: String) async throws -> NativeTripBootstrapV1
    func legacyRounds() async throws -> [NativeLegacyRoundV1]
    func convertLegacyRound(id: String, tripName: String, idempotencyKey: String) async throws -> LegacyConversionResultV1
    func recordHoleScore(_ command: ScoreHoleCommandV1, penalties: Int) async throws -> RecordHoleScoreResultV1
    func createInvite(tripID: String, expiresAt: Date?, maxUses: Int?, idempotencyKey: String) async throws -> TripInviteCredentialV1
    func listInvites(tripID: String) async throws -> [TripInviteMetadataV1]
    func rotateInvite(tripID: String, expiresAt: Date?, maxUses: Int?, idempotencyKey: String) async throws -> TripInviteCredentialV1
    func revokeInvite(inviteID: String) async throws
    func issueExtensionSession(tripID: String, deviceID: String) async throws -> ExtensionSessionIssueResultV1
    func revokeExtensionSession(sessionID: String) async throws
    func registerDevicePush(deviceID: String, token: String, environment: APNsEnvironment) async throws -> DevicePushRegistrationResultV1
    func unregisterDevicePush(deviceID: String, environment: APNsEnvironment) async throws
    func registerLiveActivity(_ registration: LiveActivityTokenRegistration) async throws -> LiveActivityRegistrationResultV1
    func endLiveActivity(activityID: String) async throws
    func resolveInvitePreview(token: String) async throws -> InvitePreviewPayloadV1
}

extension TeeCircleRepositoryProtocol {
    func transitionRound(
        id: String,
        from expected: RoundLifecycle,
        to next: RoundLifecycle
    ) async throws -> RoundLifecycleResultV1 {
        try await transitionRound(id: id, from: expected, to: next, allowIncomplete: false)
    }

    func acceptInvite(token: String) async throws -> InviteAcceptanceResultV1 {
        try await acceptInvite(token: token, tripPlayerID: nil)
    }

    func recordHoleScore(_ command: ScoreHoleCommandV1) async throws -> RecordHoleScoreResultV1 {
        try await recordHoleScore(command, penalties: 0)
    }
}

struct LiveActivityTokenRegistration: Equatable, Hashable, Sendable {
    let tripID: String
    let deviceID: String
    let activityID: String
    let pushToken: String
    let environment: APNsEnvironment
    let expiresAt: Date?
}

actor TeeCircleRepository: TeeCircleRepositoryProtocol {
    private let client: TeeCircleAPIClient
    private let publishableKey: String

    init(
        supabaseURL: URL,
        publishableKey: String,
        tokenProvider: any BearerTokenProviding,
        configuration: APIClientConfiguration = .init()
    ) {
        client = TeeCircleAPIClient(
            baseURL: supabaseURL,
            tokenProvider: tokenProvider,
            configuration: configuration
        )
        self.publishableKey = publishableKey
    }

    func createTrip(
        _ input: CreateNativeTripInputV1,
        idempotencyKey: String
    ) async throws -> CreateNativeTripResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.createTrip,
            body: IdempotentInputArguments(pInput: input, pIdempotencyKey: idempotencyKey),
            idempotencyKey: idempotencyKey
        )
    }

    func updateTrip(
        id: String,
        input: UpdateNativeTripInputV1,
        expectedUpdatedAt: Date?
    ) async throws -> UpdateNativeTripResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.updateTrip,
            body: UpdateTripArguments(
                pTripId: id,
                pInput: input,
                pExpectedUpdatedAt: expectedUpdatedAt
            )
        )
    }

    func createCourseCard(
        _ input: CreateCourseCardInputV1,
        idempotencyKey: String
    ) async throws -> CreateCourseCardResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.createCourseCard,
            body: IdempotentInputArguments(pInput: input, pIdempotencyKey: idempotencyKey),
            idempotencyKey: idempotencyKey
        )
    }

    func updateCourseCard(
        id: String,
        input: UpdateCourseCardInputV1,
        expectedUpdatedAt: Date?
    ) async throws -> UpdateCourseCardResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.updateCourseCard,
            body: UpdateCourseCardArguments(
                pCourseCardId: id,
                pInput: input,
                pExpectedUpdatedAt: expectedUpdatedAt
            )
        )
    }

    func courseCards() async throws -> [NativeCourseCardV1] {
        let payload: CourseCardListPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.courseCards,
            body: EmptyRPCArguments()
        )
        return payload.courseCards
    }

    func myProfile() async throws -> NativeProfileV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.myProfile,
            body: EmptyRPCArguments()
        )
    }

    func updateMyProfile(fullName: String, username: String) async throws -> NativeProfileV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.updateMyProfile,
            body: UpdateProfileArguments(pFullName: fullName, pUsername: username)
        )
    }

    func addTripPlayer(
        tripID: String,
        input: AddTripPlayerInputV1,
        idempotencyKey: String
    ) async throws -> AddTripPlayerResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.addTripPlayer,
            body: TripIdempotentInputArguments(
                pTripId: tripID,
                pInput: input,
                pIdempotencyKey: idempotencyKey
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func createTripRound(
        tripID: String,
        input: CreateTripRoundInputV1,
        idempotencyKey: String
    ) async throws -> CreateTripRoundResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.createTripRound,
            body: TripIdempotentInputArguments(
                pTripId: tripID,
                pInput: input,
                pIdempotencyKey: idempotencyKey
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func updateTripRound(
        id: String,
        input: UpdateTripRoundInputV1,
        expectedNativeUpdatedAt: Date?
    ) async throws -> UpdateTripRoundResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.updateTripRound,
            body: UpdateTripRoundArguments(
                pRoundId: id,
                pInput: input,
                pExpectedNativeUpdatedAt: expectedNativeUpdatedAt
            )
        )
    }

    func deleteTripRound(
        id: String,
        idempotencyKey: String,
        expectedNativeUpdatedAt: Date?
    ) async throws -> DeleteTripRoundResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.deleteTripRound,
            body: DeleteTripRoundArguments(
                pRoundId: id,
                pIdempotencyKey: idempotencyKey,
                pExpectedNativeUpdatedAt: expectedNativeUpdatedAt
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func setRoundParticipation(
        roundID: String,
        tripPlayerID: String,
        courseHandicap: Int?,
        playingHandicap: Int?,
        status: RoundParticipationStatusV1
    ) async throws -> SetRoundParticipationResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.setRoundParticipation,
            body: SetRoundParticipationArguments(
                pRoundId: roundID,
                pTripPlayerId: tripPlayerID,
                pCourseHandicap: courseHandicap,
                pPlayingHandicap: playingHandicap,
                pStatus: status
            )
        )
    }

    func releaseTripPlayerClaim(id: String) async throws -> TripPlayerClaimResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.releaseTripPlayer,
            body: TripPlayerIDArguments(pTripPlayerId: id)
        )
    }

    func updateTripPlayer(
        id: String,
        input: UpdateTripPlayerInputV1
    ) async throws -> UpdateTripPlayerResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.updateTripPlayer,
            body: TripPlayerInputArguments(pTripPlayerId: id, pInput: input)
        )
    }

    func deleteTripPlayer(
        id: String,
        idempotencyKey: String,
        expectedUpdatedAt: Date?
    ) async throws -> DeleteTripPlayerResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.deleteTripPlayer,
            body: DeleteTripPlayerArguments(
                pTripPlayerId: id,
                pIdempotencyKey: idempotencyKey,
                pExpectedUpdatedAt: expectedUpdatedAt
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func transitionTrip(
        id: String,
        from expected: TripLifecycle,
        to next: TripLifecycle
    ) async throws -> TripLifecycleResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.setTripStatus,
            body: SetTripStatusArguments(
                pTripId: id,
                pExpectedStatus: expected,
                pNewStatus: next
            )
        )
    }

    func transitionRound(
        id: String,
        from expected: RoundLifecycle,
        to next: RoundLifecycle,
        allowIncomplete: Bool = false
    ) async throws -> RoundLifecycleResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.setTripRoundStatus,
            body: SetRoundStatusArguments(
                pRoundId: id,
                pExpectedStatus: expected,
                pNewStatus: next,
                pAllowIncomplete: allowIncomplete
            )
        )
    }

    func startTrip(
        id: String,
        expectedScoreRevision: Int
    ) async throws -> StartTripResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.startTrip,
            body: StartTripArguments(
                pTripId: id,
                pExpectedScoreRevision: expectedScoreRevision
            )
        )
    }

    func advanceTripRound(
        tripID: String,
        currentRoundID: String,
        expectedScoreRevision: Int,
        allowIncomplete: Bool = false
    ) async throws -> AdvanceTripRoundResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.advanceTripRound,
            body: AdvanceTripRoundArguments(
                pTripId: tripID,
                pCurrentRoundId: currentRoundID,
                pExpectedScoreRevision: expectedScoreRevision,
                pAllowIncomplete: allowIncomplete
            )
        )
    }

    func transferTripOwnership(
        tripID: String,
        newOwnerTripPlayerID: String
    ) async throws -> TransferTripOwnershipResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.transferTripOwnership,
            body: TransferOwnershipArguments(
                pTripId: tripID,
                pNewOwnerTripPlayerId: newOwnerTripPlayerID
            )
        )
    }

    func accountDeletionBlockers() async throws -> AccountDeletionBlockersV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.accountDeletionBlockers,
            body: EmptyRPCArguments()
        )
    }

    func deleteAccount() async throws -> AccountDeletionResultV1 {
        try await callEdgeFunction(
            path: TeeCircleEndpointCatalog.deleteAccount,
            body: DeleteAccountArguments(schemaVersion: 1)
        )
    }

    func acceptInvite(
        token: String,
        tripPlayerID: String? = nil
    ) async throws -> InviteAcceptanceResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.acceptTripInvite,
            body: AcceptInviteArguments(
                pInviteToken: token,
                pTripPlayerId: tripPlayerID
            )
        )
    }

    func myTrips() async throws -> [NativeTripSummaryV1] {
        let payload: TripListPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.myTrips,
            body: EmptyRPCArguments()
        )
        return payload.trips
    }

    func bootstrap(tripID: String) async throws -> NativeTripBootstrapV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.tripBootstrap,
            body: TripIDArguments(pTripId: tripID)
        )
    }

    func legacyRounds() async throws -> [NativeLegacyRoundV1] {
        let payload: LegacyRoundListPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.legacyRounds,
            body: EmptyRPCArguments()
        )
        return payload.rounds
    }

    func convertLegacyRound(
        id: String,
        tripName: String,
        idempotencyKey: String
    ) async throws -> LegacyConversionResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.convertLegacyRound,
            body: ConvertLegacyArguments(
                pLegacyRoundId: id,
                pTripName: tripName,
                pIdempotencyKey: idempotencyKey
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func recordHoleScore(
        _ command: ScoreHoleCommandV1,
        penalties: Int = 0
    ) async throws -> RecordHoleScoreResultV1 {
        try await callEdgeFunction(
            path: TeeCircleEndpointCatalog.recordHoleScore,
            body: AuthenticatedScoreArguments(
                schemaVersion: 1,
                roundId: command.roundId,
                tripPlayerId: command.tripPlayerId,
                holeNumber: command.hole,
                strokes: command.strokes,
                penalties: penalties,
                idempotencyKey: command.idempotencyKey,
                expectedScoreRevision: command.expectedRevision
            ),
            idempotencyKey: command.idempotencyKey
        )
    }

    func createInvite(
        tripID: String,
        expiresAt: Date?,
        maxUses: Int?,
        idempotencyKey: String
    ) async throws -> TripInviteCredentialV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.createInvite,
            body: CreateInviteArguments(
                pTripId: tripID,
                pExpiresAt: expiresAt,
                pMaxUses: maxUses,
                pIdempotencyKey: idempotencyKey
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func listInvites(tripID: String) async throws -> [TripInviteMetadataV1] {
        let payload: InviteListPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.listInvites,
            body: TripIDArguments(pTripId: tripID)
        )
        return payload.invites
    }

    func rotateInvite(
        tripID: String,
        expiresAt: Date?,
        maxUses: Int?,
        idempotencyKey: String
    ) async throws -> TripInviteCredentialV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.rotateInvite,
            body: CreateInviteArguments(
                pTripId: tripID,
                pExpiresAt: expiresAt,
                pMaxUses: maxUses,
                pIdempotencyKey: idempotencyKey
            ),
            idempotencyKey: idempotencyKey
        )
    }

    func revokeInvite(inviteID: String) async throws {
        let _: InviteRevocationPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.revokeInvite,
            body: InviteIDArguments(pInviteId: inviteID)
        )
    }

    func issueExtensionSession(tripID: String, deviceID: String) async throws -> ExtensionSessionIssueResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.issueExtensionSession,
            body: IssueExtensionSessionArguments(pTripId: tripID, pDeviceId: deviceID)
        )
    }

    func revokeExtensionSession(sessionID: String) async throws {
        let _: SessionRevocationPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.revokeExtensionSession,
            body: SessionIDArguments(pSessionId: sessionID)
        )
    }

    func registerDevicePush(
        deviceID: String,
        token: String,
        environment: APNsEnvironment
    ) async throws -> DevicePushRegistrationResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.registerDevicePush,
            body: RegisterDevicePushArguments(
                pDeviceId: deviceID,
                pToken: token,
                pEnvironment: environment,
                pBundleId: "com.teecircle.app"
            )
        )
    }

    func unregisterDevicePush(deviceID: String, environment: APNsEnvironment) async throws {
        let _: DevicePushUnregistrationPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.unregisterDevicePush,
            body: UnregisterDevicePushArguments(
                pDeviceId: deviceID,
                pEnvironment: environment,
                pBundleId: "com.teecircle.app"
            )
        )
    }

    func registerLiveActivity(
        _ registration: LiveActivityTokenRegistration
    ) async throws -> LiveActivityRegistrationResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.registerLiveActivity,
            body: RegisterLiveActivityArguments(
                pTripId: registration.tripID,
                pDeviceId: registration.deviceID,
                pActivityId: registration.activityID,
                pPushToken: registration.pushToken,
                pEnvironment: registration.environment,
                pExpiresAt: registration.expiresAt
            )
        )
    }

    func endLiveActivity(activityID: String) async throws {
        let _: EndLiveActivityPayload = try await callRPC(
            path: TeeCircleEndpointCatalog.endLiveActivity,
            body: EndLiveActivityArguments(pActivityId: activityID)
        )
    }

    func createPurchaseIntent(
        tripID: String,
        idempotencyKey: String
    ) async throws -> PurchaseIntentV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.createPurchaseIntent,
            body: PurchaseIntentArguments(pTripId: tripID, pIdempotencyKey: idempotencyKey),
            idempotencyKey: idempotencyKey
        )
    }

    func cancelPurchaseIntent(intentID: String) async throws -> PurchaseIntentCancellationResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.cancelPurchaseIntent,
            body: CancelPurchaseIntentArguments(pPurchaseIntentId: intentID)
        )
    }

    func claimPurchase(
        intentID: String,
        transactionID: String,
        productID: String
    ) async throws -> PurchaseClaimResultV1 {
        try await callEdgeFunction(
            path: TeeCircleEndpointCatalog.claimPurchase,
            body: ClaimPurchaseArguments(
                schemaVersion: 1,
                purchaseIntentId: intentID,
                transactionId: transactionID,
                productId: productID
            ),
            idempotencyKey: transactionID
        )
    }

    func resolveInvitePreview(token: String) async throws -> InvitePreviewPayloadV1 {
        try await callEdgeFunction(
            path: TeeCircleEndpointCatalog.previewInvite,
            body: PreviewInviteArguments(schemaVersion: 1, inviteToken: token),
            requiresAuthentication: false
        )
    }

    private func callRPC<Body: Encodable & Sendable, Payload: Codable & Sendable>(
        path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> Payload {
        try await call(
            path: path,
            body: body,
            idempotencyKey: idempotencyKey,
            headers: ["apikey": publishableKey, "Content-Profile": "public"]
        )
    }

    private func callEdgeFunction<Body: Encodable & Sendable, Payload: Codable & Sendable>(
        path: String,
        body: Body,
        idempotencyKey: String? = nil,
        requiresAuthentication: Bool = true
    ) async throws -> Payload {
        try await call(
            path: path,
            body: body,
            idempotencyKey: idempotencyKey,
            headers: ["apikey": publishableKey],
            requiresAuthentication: requiresAuthentication
        )
    }

    private func call<Body: Encodable & Sendable, Payload: Codable & Sendable>(
        path: String,
        body: Body,
        idempotencyKey: String?,
        headers: [String: String],
        requiresAuthentication: Bool = true
    ) async throws -> Payload {
        let request = try APIRequest<VersionedServerEnvelope<Payload>>.json(
            method: .post,
            path: path,
            headers: headers,
            body: body,
            requiresAuthentication: requiresAuthentication,
            idempotencyKey: idempotencyKey
        )
        let envelope: VersionedServerEnvelope<Payload>
        do {
            envelope = try await client.send(request)
        } catch let error as TeeCircleAPIClientError {
            if case let .server(_, serverEnvelope?) = error {
                throw TeeCircleRepositoryError.server(serverEnvelope.error)
            }
            throw TeeCircleRepositoryError.transport(error)
        }
        guard envelope.schemaVersion == 1 else {
            throw TeeCircleRepositoryError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        if let error = envelope.error {
            throw TeeCircleRepositoryError.server(error)
        }
        guard let data = envelope.data else {
            throw TeeCircleRepositoryError.malformedEnvelope
        }
        return data
    }
}

private struct VersionedServerEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let requestId: String
    let data: Payload?
    let error: APIErrorPayload?
}

private struct EmptyRPCArguments: Codable, Sendable {}
private struct TripListPayload: Codable, Sendable { let trips: [NativeTripSummaryV1] }
private struct LegacyRoundListPayload: Codable, Sendable { let rounds: [NativeLegacyRoundV1] }
private struct CourseCardListPayload: Codable, Sendable { let courseCards: [NativeCourseCardV1] }

private struct UpdateProfileArguments: Encodable, Sendable {
    let pFullName: String
    let pUsername: String
    enum CodingKeys: String, CodingKey {
        case pFullName = "p_full_name"
        case pUsername = "p_username"
    }
}
private struct InviteListPayload: Codable, Sendable { let invites: [TripInviteMetadataV1] }

private struct IdempotentInputArguments<Input: Encodable & Sendable>: Encodable, Sendable {
    let pInput: Input
    let pIdempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case pInput = "p_input"
        case pIdempotencyKey = "p_idempotency_key"
    }
}

private struct TripIdempotentInputArguments<Input: Encodable & Sendable>: Encodable, Sendable {
    let pTripId: String
    let pInput: Input
    let pIdempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pInput = "p_input"
        case pIdempotencyKey = "p_idempotency_key"
    }
}

private struct UpdateTripArguments: Encodable, Sendable {
    let pTripId: String
    let pInput: UpdateNativeTripInputV1
    let pExpectedUpdatedAt: Date?
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pInput = "p_input"
        case pExpectedUpdatedAt = "p_expected_updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTripId, forKey: .pTripId)
        try container.encode(pInput, forKey: .pInput)
        if let pExpectedUpdatedAt {
            try container.encode(pExpectedUpdatedAt, forKey: .pExpectedUpdatedAt)
        } else {
            try container.encodeNil(forKey: .pExpectedUpdatedAt)
        }
    }
}

struct UpdateCourseCardArguments: Encodable, Sendable {
    let pCourseCardId: String
    let pInput: UpdateCourseCardInputV1
    let pExpectedUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case pCourseCardId = "p_course_card_id"
        case pInput = "p_input"
        case pExpectedUpdatedAt = "p_expected_updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pCourseCardId, forKey: .pCourseCardId)
        try container.encode(pInput, forKey: .pInput)
        if let pExpectedUpdatedAt {
            try container.encode(pExpectedUpdatedAt, forKey: .pExpectedUpdatedAt)
        } else {
            try container.encodeNil(forKey: .pExpectedUpdatedAt)
        }
    }
}

struct UpdateTripRoundArguments: Encodable, Sendable {
    let pRoundId: String
    let pInput: UpdateTripRoundInputV1
    let pExpectedNativeUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case pRoundId = "p_round_id"
        case pInput = "p_input"
        case pExpectedNativeUpdatedAt = "p_expected_native_updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pRoundId, forKey: .pRoundId)
        try container.encode(pInput, forKey: .pInput)
        if let pExpectedNativeUpdatedAt {
            try container.encode(pExpectedNativeUpdatedAt, forKey: .pExpectedNativeUpdatedAt)
        } else {
            try container.encodeNil(forKey: .pExpectedNativeUpdatedAt)
        }
    }
}

struct DeleteTripRoundArguments: Encodable, Sendable {
    let pRoundId: String
    let pIdempotencyKey: String
    let pExpectedNativeUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case pRoundId = "p_round_id"
        case pIdempotencyKey = "p_idempotency_key"
        case pExpectedNativeUpdatedAt = "p_expected_native_updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pRoundId, forKey: .pRoundId)
        try container.encode(pIdempotencyKey, forKey: .pIdempotencyKey)
        if let pExpectedNativeUpdatedAt {
            try container.encode(pExpectedNativeUpdatedAt, forKey: .pExpectedNativeUpdatedAt)
        } else {
            try container.encodeNil(forKey: .pExpectedNativeUpdatedAt)
        }
    }
}

struct DeleteTripPlayerArguments: Encodable, Sendable {
    let pTripPlayerId: String
    let pIdempotencyKey: String
    let pExpectedUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case pTripPlayerId = "p_trip_player_id"
        case pIdempotencyKey = "p_idempotency_key"
        case pExpectedUpdatedAt = "p_expected_updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTripPlayerId, forKey: .pTripPlayerId)
        try container.encode(pIdempotencyKey, forKey: .pIdempotencyKey)
        if let pExpectedUpdatedAt {
            try container.encode(pExpectedUpdatedAt, forKey: .pExpectedUpdatedAt)
        } else {
            try container.encodeNil(forKey: .pExpectedUpdatedAt)
        }
    }
}

private struct SetRoundParticipationArguments: Encodable, Sendable {
    let pRoundId: String
    let pTripPlayerId: String
    let pCourseHandicap: Int?
    let pPlayingHandicap: Int?
    let pStatus: RoundParticipationStatusV1
    enum CodingKeys: String, CodingKey {
        case pRoundId = "p_round_id"
        case pTripPlayerId = "p_trip_player_id"
        case pCourseHandicap = "p_course_handicap"
        case pPlayingHandicap = "p_playing_handicap"
        case pStatus = "p_status"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pRoundId, forKey: .pRoundId)
        try container.encode(pTripPlayerId, forKey: .pTripPlayerId)
        if let pCourseHandicap {
            try container.encode(pCourseHandicap, forKey: .pCourseHandicap)
        } else {
            try container.encodeNil(forKey: .pCourseHandicap)
        }
        if let pPlayingHandicap {
            try container.encode(pPlayingHandicap, forKey: .pPlayingHandicap)
        } else {
            try container.encodeNil(forKey: .pPlayingHandicap)
        }
        try container.encode(pStatus, forKey: .pStatus)
    }
}

private struct TripPlayerIDArguments: Codable, Sendable {
    let pTripPlayerId: String
    enum CodingKeys: String, CodingKey { case pTripPlayerId = "p_trip_player_id" }
}

private struct TripPlayerInputArguments: Encodable, Sendable {
    let pTripPlayerId: String
    let pInput: UpdateTripPlayerInputV1
    enum CodingKeys: String, CodingKey {
        case pTripPlayerId = "p_trip_player_id"
        case pInput = "p_input"
    }
}

private struct SetTripStatusArguments: Codable, Sendable {
    let pTripId: String
    let pExpectedStatus: TripLifecycle
    let pNewStatus: TripLifecycle
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pExpectedStatus = "p_expected_status"
        case pNewStatus = "p_new_status"
    }
}

private struct SetRoundStatusArguments: Codable, Sendable {
    let pRoundId: String
    let pExpectedStatus: RoundLifecycle
    let pNewStatus: RoundLifecycle
    let pAllowIncomplete: Bool
    enum CodingKeys: String, CodingKey {
        case pRoundId = "p_round_id"
        case pExpectedStatus = "p_expected_status"
        case pNewStatus = "p_new_status"
        case pAllowIncomplete = "p_allow_incomplete"
    }
}

struct StartTripArguments: Codable, Sendable {
    let pTripId: String
    let pExpectedScoreRevision: Int
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pExpectedScoreRevision = "p_expected_score_revision"
    }
}

struct AdvanceTripRoundArguments: Codable, Sendable {
    let pTripId: String
    let pCurrentRoundId: String
    let pExpectedScoreRevision: Int
    let pAllowIncomplete: Bool
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pCurrentRoundId = "p_current_round_id"
        case pExpectedScoreRevision = "p_expected_score_revision"
        case pAllowIncomplete = "p_allow_incomplete"
    }
}

private struct TransferOwnershipArguments: Codable, Sendable {
    let pTripId: String
    let pNewOwnerTripPlayerId: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pNewOwnerTripPlayerId = "p_new_owner_trip_player_id"
    }
}

private struct AcceptInviteArguments: Encodable, Sendable {
    let pInviteToken: String
    let pTripPlayerId: String?
    enum CodingKeys: String, CodingKey {
        case pInviteToken = "p_invite_token"
        case pTripPlayerId = "p_trip_player_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pInviteToken, forKey: .pInviteToken)
        if let pTripPlayerId {
            try container.encode(pTripPlayerId, forKey: .pTripPlayerId)
        } else {
            try container.encodeNil(forKey: .pTripPlayerId)
        }
    }
}

private struct TripIDArguments: Codable, Sendable {
    let pTripId: String
    enum CodingKeys: String, CodingKey { case pTripId = "p_trip_id" }
}

private struct ConvertLegacyArguments: Codable, Sendable {
    let pLegacyRoundId: String
    let pTripName: String
    let pIdempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case pLegacyRoundId = "p_legacy_round_id"
        case pTripName = "p_trip_name"
        case pIdempotencyKey = "p_idempotency_key"
    }
}

/// The authenticated score Edge command writes under the caller's JWT, runs
/// the canonical TypeScript engine, persists the snapshot, and dispatches it.
struct AuthenticatedScoreArguments: Codable, Sendable {
    let schemaVersion: Int
    let roundId: String
    let tripPlayerId: String
    let holeNumber: Int
    let strokes: Int
    let penalties: Int
    let idempotencyKey: String
    let expectedScoreRevision: Int
}

private struct CreateInviteArguments: Codable, Sendable {
    let pTripId: String
    let pExpiresAt: Date?
    let pMaxUses: Int?
    let pIdempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pExpiresAt = "p_expires_at"
        case pMaxUses = "p_max_uses"
        case pIdempotencyKey = "p_idempotency_key"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTripId, forKey: .pTripId)
        if let pExpiresAt { try container.encode(pExpiresAt, forKey: .pExpiresAt) }
        else { try container.encodeNil(forKey: .pExpiresAt) }
        if let pMaxUses { try container.encode(pMaxUses, forKey: .pMaxUses) }
        else { try container.encodeNil(forKey: .pMaxUses) }
        try container.encode(pIdempotencyKey, forKey: .pIdempotencyKey)
    }
}

private struct InviteIDArguments: Codable, Sendable {
    let pInviteId: String
    enum CodingKeys: String, CodingKey { case pInviteId = "p_invite_id" }
}

private struct InviteRevocationPayload: Codable, Sendable {
    let inviteId: String
    let revoked: Bool
}

private struct IssueExtensionSessionArguments: Codable, Sendable {
    let pTripId: String
    let pDeviceId: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pDeviceId = "p_device_id"
    }
}

private struct SessionIDArguments: Codable, Sendable {
    let pSessionId: String
    enum CodingKeys: String, CodingKey { case pSessionId = "p_session_id" }
}

private struct SessionRevocationPayload: Codable, Sendable {
    let sessionId: String
    let revoked: Bool
}

private struct RegisterDevicePushArguments: Codable, Sendable {
    let pDeviceId: String
    let pToken: String
    let pEnvironment: APNsEnvironment
    let pBundleId: String
    enum CodingKeys: String, CodingKey {
        case pDeviceId = "p_device_id"
        case pToken = "p_token"
        case pEnvironment = "p_environment"
        case pBundleId = "p_bundle_id"
    }
}

private struct UnregisterDevicePushArguments: Codable, Sendable {
    let pDeviceId: String
    let pEnvironment: APNsEnvironment
    let pBundleId: String
    enum CodingKeys: String, CodingKey {
        case pDeviceId = "p_device_id"
        case pEnvironment = "p_environment"
        case pBundleId = "p_bundle_id"
    }
}

private struct DevicePushUnregistrationPayload: Codable, Sendable { let disabled: Bool }

private struct RegisterLiveActivityArguments: Codable, Sendable {
    let pTripId: String
    let pDeviceId: String
    let pActivityId: String
    let pPushToken: String
    let pEnvironment: APNsEnvironment
    let pExpiresAt: Date?
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pDeviceId = "p_device_id"
        case pActivityId = "p_activity_id"
        case pPushToken = "p_push_token"
        case pEnvironment = "p_environment"
        case pExpiresAt = "p_expires_at"
    }
}

private struct EndLiveActivityArguments: Codable, Sendable {
    let pActivityId: String
    enum CodingKeys: String, CodingKey { case pActivityId = "p_activity_id" }
}

private struct EndLiveActivityPayload: Codable, Sendable {
    let activityId: String
    let ended: Bool
}

private struct PurchaseIntentArguments: Codable, Sendable {
    let pTripId: String
    let pIdempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pIdempotencyKey = "p_idempotency_key"
    }
}

struct CancelPurchaseIntentArguments: Codable, Sendable {
    let pPurchaseIntentId: String
    enum CodingKeys: String, CodingKey {
        case pPurchaseIntentId = "p_purchase_intent_id"
    }
}

private struct ClaimPurchaseArguments: Codable, Sendable {
    let schemaVersion: Int
    let purchaseIntentId: String
    let transactionId: String
    let productId: String
}

private struct PreviewInviteArguments: Codable, Sendable {
    let schemaVersion: Int
    let inviteToken: String
}

private struct DeleteAccountArguments: Codable, Sendable {
    let schemaVersion: Int
}
