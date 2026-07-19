import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Supabase
import TeeCircleAPI

struct NativeAuthSession: Equatable, Sendable {
    let userID: String
    let email: String?
    let expiresAt: Date
}

enum NativeAuthState: Equatable, Sendable {
    case restoring
    case signedOut
    case signedIn(NativeAuthSession)
}

enum NativeAuthServiceError: LocalizedError, Equatable, Sendable {
    case invalidIdentityToken
    case invalidNonce

    var errorDescription: String? {
        switch self {
        case .invalidIdentityToken:
            "The identity provider did not return a valid ID token."
        case .invalidNonce:
            "The sign-in request could not be verified. Please try again."
        }
    }
}

/// The nonce pair used for one Apple authorization attempt. Keep `rawValue`
/// in memory until the corresponding credential is returned; never persist it.
struct AppleSignInNonce: Equatable, Sendable {
    let rawValue: String
    let sha256Value: String

    static func make() -> AppleSignInNonce {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        let raw = String((0..<32).map { _ in alphabet.randomElement(using: &generator)! })
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hashed = digest.map { String(format: "%02x", $0) }.joined()
        return AppleSignInNonce(rawValue: raw, sha256Value: hashed)
    }
}

/// Owns the main-app Supabase session. Supabase's iOS default storage is
/// Keychain-backed; an app-specific service name prevents collision with other apps.
@MainActor
final class SupabaseSessionService: ObservableObject, BearerTokenProviding {
    @Published private(set) var state: NativeAuthState = .restoring
    @Published private(set) var lastErrorMessage: String?

    let client: SupabaseClient
    private var authObserverTask: Task<Void, Never>?

    init(supabaseURL: URL, publishableKey: String) {
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: KeychainLocalStorage(service: "com.teecircle.app.supabase-auth"),
            flowType: .pkce,
            emitLocalSessionAsInitialSession: false
        )
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
    }

    var currentUserID: String? {
        guard case let .signedIn(session) = state else { return nil }
        return session.userID
    }

    func restoreSession() async {
        startObservingAuthChanges()
        state = .restoring
        do {
            let session = try await client.auth.session
            apply(session)
        } catch {
            // A missing or irrecoverably expired local session is a normal fresh-start state.
            state = .signedOut
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> NativeAuthSession {
        let session = try await client.auth.signIn(email: email, password: password)
        return apply(session)
    }

    func sendEmailOTP(to email: String, shouldCreateUser: Bool = true) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: shouldCreateUser)
    }

    @discardableResult
    func verifyEmailOTP(email: String, code: String) async throws -> NativeAuthSession {
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        switch response {
        case let .session(session):
            return apply(session)
        case .user:
            return apply(try await client.auth.session)
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) -> AppleSignInNonce {
        let nonce = AppleSignInNonce.make()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.sha256Value
        return nonce
    }

    @discardableResult
    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        nonce: AppleSignInNonce
    ) async throws -> NativeAuthSession {
        guard !nonce.rawValue.isEmpty else { throw NativeAuthServiceError.invalidNonce }
        guard let data = credential.identityToken,
              let idToken = String(data: data, encoding: .utf8),
              !idToken.isEmpty
        else {
            throw NativeAuthServiceError.invalidIdentityToken
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce.rawValue
            )
        )
        return apply(session)
    }

    @discardableResult
    func signInWithGoogle(idToken: String, accessToken: String? = nil) async throws -> NativeAuthSession {
        guard !idToken.isEmpty else { throw NativeAuthServiceError.invalidIdentityToken }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
        return apply(session)
    }

    func signOut() async throws {
        try await client.auth.signOut()
        state = .signedOut
    }

    func bearerToken() async throws -> String? {
        try await client.auth.session.accessToken
    }

    private func startObservingAuthChanges() {
        guard authObserverTask == nil else { return }
        authObserverTask = Task { [weak self, client] in
            for await (_, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                self?.applyOptionalSession(session)
            }
        }
    }

    private func applyOptionalSession(_ session: Session?) {
        if let session {
            apply(session)
        } else {
            state = .signedOut
        }
    }

    @discardableResult
    private func apply(_ session: Session) -> NativeAuthSession {
        lastErrorMessage = nil
        let native = NativeAuthSession(
            userID: session.user.id.uuidString.lowercased(),
            email: session.user.email,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
        state = .signedIn(native)
        return native
    }
}
