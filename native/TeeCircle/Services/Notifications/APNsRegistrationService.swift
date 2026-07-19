import Combine
import Foundation
import UIKit
import UserNotifications

enum PushRegistrationState: Equatable, Sendable {
    case idle
    case denied
    case registering
    case registered
    case failed(String)
}

@MainActor
final class APNsRegistrationService: ObservableObject {
    @Published private(set) var state: PushRegistrationState = .idle

    private let repository: any TeeCircleRepositoryProtocol
    private let sharedStore: SharedExtensionSessionStore
    private var lastUploadedToken: String?

    init(
        repository: any TeeCircleRepositoryProtocol,
        sharedStore: SharedExtensionSessionStore
    ) {
        self.repository = repository
        self.sharedStore = sharedStore
    }

    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            guard granted else {
                state = .denied
                return
            }
            state = .registering
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Forward `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// here from the application delegate.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != lastUploadedToken else {
            state = .registered
            return
        }
        state = .registering
        Task { [weak self] in
            guard let self else { return }
            do {
                let deviceID = try await sharedStore.stableDeviceID()
                _ = try await repository.registerDevicePush(
                    deviceID: deviceID,
                    token: token,
                    environment: Self.environment
                )
                lastUploadedToken = token
                state = .registered
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Forward `application(_:didFailToRegisterForRemoteNotificationsWithError:)` here.
    func didFailToRegister(error: Error) {
        state = .failed(error.localizedDescription)
    }

    func unregisterFromServer() async {
        do {
            let deviceID = try await sharedStore.stableDeviceID()
            try await repository.unregisterDevicePush(
                deviceID: deviceID,
                environment: Self.environment
            )
            lastUploadedToken = nil
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static var environment: APNsEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}
