@preconcurrency import ActivityKit
import Combine
import Foundation
import TeeCircleActivities
import TeeCircleDomain

enum LiveActivityServiceState: Equatable, Sendable {
    case idle
    case unavailable
    case starting
    case following(tripID: String, activityID: String)
    case failed(String)
}

enum LiveActivityServiceError: LocalizedError, Equatable, Sendable {
    case unavailable
    case payloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Live Activities are disabled on this iPhone."
        case let .payloadTooLarge(size):
            "The Live Activity update is too large (\(size) bytes)."
        }
    }
}

@MainActor
final class TeeCircleLiveActivityService: ObservableObject {
    @Published private(set) var state: LiveActivityServiceState = .idle

    private let repository: any TeeCircleRepositoryProtocol
    private let sharedStore: SharedExtensionSessionStore
    private var tokenTasks: [String: Task<Void, Never>] = [:]

    init(
        repository: any TeeCircleRepositoryProtocol,
        sharedStore: SharedExtensionSessionStore
    ) {
        self.repository = repository
        self.sharedStore = sharedStore
    }

    /// Reconciles activities retained by the OS after an app relaunch and ends
    /// extras, preserving TeeCircle v1's one-active-trip-per-device contract.
    func restoreExistingActivity() async {
        let activities = Activity<TeeCircleLiveActivityAttributes>.activities
        guard let retained = activities.first else {
            state = .idle
            return
        }

        for extra in activities.dropFirst() {
            let content = ActivityContent(state: extra.content.state, staleDate: nil)
            await extra.end(content, dismissalPolicy: .immediate)
            try? await repository.endLiveActivity(activityID: extra.id)
        }
        state = .following(tripID: retained.attributes.tripId, activityID: retained.id)
        monitorTokens(for: retained)
    }

    @discardableResult
    func follow(
        tripID: String,
        tripName: String,
        viewerPlayerID: String?,
        snapshot: LeaderboardSnapshotV1,
        skinsCarry: Int? = nil
    ) async throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .unavailable
            throw LiveActivityServiceError.unavailable
        }
        state = .starting
        let contentState = TeeCircleActivityMapper.contentState(
            from: snapshot,
            viewerPlayerId: viewerPlayerID,
            skinsCarry: skinsCarry
        )
        guard contentState.fitsActivityKitPushLimit else {
            let error = LiveActivityServiceError.payloadTooLarge(contentState.encodedSize)
            state = .failed(error.localizedDescription)
            throw error
        }

        // End any previous TeeCircle trip before starting the explicitly chosen one.
        for existing in Activity<TeeCircleLiveActivityAttributes>.activities {
            let finalContent = ActivityContent(state: existing.content.state, staleDate: nil)
            await existing.end(finalContent, dismissalPolicy: .immediate)
            tokenTasks.removeValue(forKey: existing.id)?.cancel()
            try? await repository.endLiveActivity(activityID: existing.id)
        }

        let attributes = TeeCircleLiveActivityAttributes(
            tripId: tripID,
            tripName: tripName,
            viewerPlayerId: viewerPlayerID
        )
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(20 * 60)
            ),
            pushType: .token
        )
        state = .following(tripID: tripID, activityID: activity.id)

        if let token = activity.pushToken {
            do {
                try await register(token: token, for: activity)
            } catch {
                await abandon(activity, because: error)
                throw error
            }
        }
        monitorTokens(for: activity)
        return activity.id
    }

    /// Mirrors a just-accepted local score while the server's authoritative APNs
    /// update is in flight. Revisions prevent an older local value from winning.
    func updateAfterAcceptedScore(
        tripID: String,
        snapshot: LeaderboardSnapshotV1,
        viewerPlayerID: String?,
        skinsCarry: Int? = nil
    ) async throws {
        guard let activity = Activity<TeeCircleLiveActivityAttributes>.activities.first(
            where: { $0.attributes.tripId == tripID }
        ) else { return }
        guard snapshot.revision >= activity.content.state.revision else { return }
        let next = TeeCircleActivityMapper.contentState(
            from: snapshot,
            viewerPlayerId: viewerPlayerID,
            skinsCarry: skinsCarry
        )
        guard next.fitsActivityKitPushLimit else {
            throw LiveActivityServiceError.payloadTooLarge(next.encodedSize)
        }
        await activity.update(
            ActivityContent(state: next, staleDate: Date().addingTimeInterval(20 * 60))
        )
    }

    func end(
        tripID: String,
        finalSnapshot: LeaderboardSnapshotV1?,
        viewerPlayerID: String?
    ) async {
        let matches = Activity<TeeCircleLiveActivityAttributes>.activities.filter {
            $0.attributes.tripId == tripID
        }
        for activity in matches {
            let finalState = finalSnapshot.map {
                TeeCircleActivityMapper.contentState(from: $0, viewerPlayerId: viewerPlayerID)
            } ?? activity.content.state
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
            tokenTasks.removeValue(forKey: activity.id)?.cancel()
            try? await repository.endLiveActivity(activityID: activity.id)
        }
        state = .idle
    }

    /// Ends every TeeCircle activity retained by the OS. This is intentionally
    /// independent of the in-memory trip list so sign-out cannot leak another
    /// user's standings after a relaunch or after a trip reaches a final state.
    func endAll() async {
        let activities = Activity<TeeCircleLiveActivityAttributes>.activities
        for activity in activities {
            let content = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            tokenTasks.removeValue(forKey: activity.id)?.cancel()
            try? await repository.endLiveActivity(activityID: activity.id)
        }
        tokenTasks.values.forEach { $0.cancel() }
        tokenTasks.removeAll()
        state = .idle
    }

    private func monitorTokens(for activity: Activity<TeeCircleLiveActivityAttributes>) {
        guard tokenTasks[activity.id] == nil else { return }
        tokenTasks[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.register(token: token, for: activity)
                } catch {
                    await self.abandon(activity, because: error)
                    return
                }
            }
        }
    }

    private func abandon(
        _ activity: Activity<TeeCircleLiveActivityAttributes>,
        because error: Error
    ) async {
        let content = ActivityContent(state: activity.content.state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        tokenTasks.removeValue(forKey: activity.id)?.cancel()
        try? await repository.endLiveActivity(activityID: activity.id)
        state = .failed(error.localizedDescription)
    }

    private func register(
        token: Data,
        for activity: Activity<TeeCircleLiveActivityAttributes>
    ) async throws {
        let deviceID = try await sharedStore.stableDeviceID()
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        _ = try await repository.registerLiveActivity(
            LiveActivityTokenRegistration(
                tripID: activity.attributes.tripId,
                deviceID: deviceID,
                activityID: activity.id,
                pushToken: tokenString,
                environment: APNsRegistrationService.environment,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60)
            )
        )
    }
}
