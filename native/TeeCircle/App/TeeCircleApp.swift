import GoogleSignIn
import SwiftUI
import UIKit

@main
struct TeeCircleApp: App {
    @UIApplicationDelegateAdaptor(TeeCircleApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: TeeCircleStore

    init() {
        let configuration = AppConfiguration.load()
        _store = StateObject(wrappedValue: TeeCircleStore(configuration: configuration))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(TeeCircleBrand.signal)
                .preferredColorScheme(.dark)
                .task { await store.start() }
                .onAppear { applicationDelegate.store = store }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    switch IncomingAppRoute(url: url) {
                    case let .invite(token):
                        Task { await store.handleInviteToken(token) }
                    case let .trip(id):
                        Task { await store.handleInternalTripRoute(id) }
                    case nil:
                        store.production?.auth.client.handle(url)
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active, store.isAuthenticated {
                        Task { await store.retryPendingScores() }
                    }
                }
        }
    }
}

@MainActor
final class TeeCircleApplicationDelegate: NSObject, UIApplicationDelegate {
    weak var store: TeeCircleStore?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        store?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        store?.didFailToRegisterForRemoteNotifications(error: error)
    }
}

enum IncomingAppRoute: Equatable {
    case invite(String)
    case trip(String)

    init?(url: URL) {
        if url.scheme?.lowercased() == "teecircle",
           url.host?.lowercased() == "trip"
        {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 1, !parts[0].isEmpty else { return nil }
            self = .trip(parts[0])
            return
        }

        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "t", !parts[1].isEmpty else { return nil }
        self = .invite(parts[1])
    }
}
