import Foundation
import UIKit
import AppAuth
import os.log

private let kcLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "KeycloakAuth")

/// Authorization Code + PKCE flow against the
/// `inkcolors-reader-mobile` Keycloak realm client. Replaces the
/// legacy `NativeAuthRepository` for users who sign in via OAuth on
/// the new build. The legacy class stays alive to serve already-
/// signed-in users until their next terminal failure — see
/// `AuthMigrationCoordinator`.
///
/// State model
/// ----------
/// AppAuth's `OIDAuthState` is the source of truth for tokens + the
/// refresh chain. We persist it (NSKeyedArchiver) under the
/// `Constants.Keycloak.authStateKey` slot in Keychain. The archive
/// includes the offline refresh token, access token, ID token, and
/// last service configuration — restoring it on launch means
/// `getAccessToken()` can resume without re-discovering the issuer.
///
/// Threading
/// ---------
/// `actor`-isolated like `NativeAuthRepository`. The OAuth login call
/// hops to the MainActor to drive `ASWebAuthenticationSession`; the
/// refresh path stays on the actor.
actor KeycloakAuthRepository: AuthRepository {
    private let keychain: KeychainManager
    private let appState: AppState

    /// The in-memory OIDAuthState. Lazily restored from Keychain on
    /// first access, then mutated in place as tokens refresh.
    /// Updates are persisted back to Keychain via the state-change
    /// delegate registered in `restoreOrCreate`.
    private var authState: OIDAuthState?

    /// Service configuration (auth + token endpoints). Cached
    /// in-memory after first discovery so the second-and-subsequent
    /// refresh doesn't need to re-hit `/.well-known/openid-configuration`.
    /// Persisted as part of `OIDAuthState` once login completes.
    private var cachedConfig: OIDServiceConfiguration?

    /// Pending external-user-agent session for the in-flight
    /// authorization request. Held so `InkYomiApp.onOpenURL` can
    /// resume the flow when the OAuth callback URL arrives.
    nonisolated(unsafe) private static var pendingSession: OIDExternalUserAgentSession?

    /// Strong references to the delegate instances we install on
    /// `OIDAuthState`. The library declares both delegate properties
    /// as `weak`, so without these stored properties the delegates
    /// would dealloc immediately after `attach(state:)` returns and
    /// silently never fire. Keep them alive for the actor's lifetime.
    private var stateChangeDelegate: StateChangeDelegate?
    private var stateErrorDelegate: StateErrorDelegate?

    init(keychain: KeychainManager, appState: AppState) {
        self.keychain = keychain
        self.appState = appState
    }

    // MARK: - AuthRepository

    /// Legacy email/password login is not part of the OAuth flow.
    /// New sign-ins must go through `loginWithOAuth(presenter:)`;
    /// the protocol method exists only so the type can satisfy
    /// the existing `AuthRepository` shape during migration.
    func login(email: String, password: String) async throws {
        throw KeycloakAuthError.passwordLoginNotSupported
    }

    func forgotPassword(email: String) async throws {
        // Keycloak's hosted password-reset page lives at
        // <issuer>/login-actions/reset-credentials — surface it via
        // a system browser link from the UI rather than POSTing
        // here. Throwing keeps the protocol satisfied without
        // implying a fake success.
        throw KeycloakAuthError.useHostedForgotPassword
    }

    func refresh() async throws {
        guard let state = try await loadStateIfPresent() else {
            throw AuthFailure.noRefreshToken
        }
        do {
            _ = try await freshAccessToken(state: state)
        } catch let failure as AuthFailure {
            throw failure
        } catch {
            throw AuthFailure.classify(error)
        }
    }

    /// Called by APIClient on every request that needs an
    /// Authorization header. Returns nil on terminal failure so
    /// individual API calls fall back to anonymous (and the auth
    /// state machine handles bouncing the user out separately —
    /// `AuthMigrationCoordinator.bounceToOAuth` is wired in
    /// `freshAccessToken` below).
    func getAccessToken() async -> String? {
        do {
            let state = try await loadStateIfPresent()
            guard let state else { return nil }
            return try await freshAccessToken(state: state)
        } catch {
            return nil
        }
    }

    /// Local sign-out — clears the OIDAuthState archive only. The
    /// "full wipe" path (Keychain everywhere, SwiftData, files) is
    /// owned by `UserDataWipe` and called from the device-remove
    /// surfaces. signOut() exists for the rare programmatic path
    /// (e.g. AppRouter switching account) that wants only the
    /// auth-state cleared.
    func signOut() async {
        try? keychain.delete(forKey: Constants.Keycloak.authStateKey)
        authState = nil
        cachedConfig = nil
        await MainActor.run {
            appState.authState = .unauthenticated
        }
    }

    // MARK: - OAuth login

    /// Drives the Authorization Code + PKCE flow.
    ///
    /// 1. Discovers the OIDC service configuration if not cached.
    /// 2. Builds an `OIDAuthorizationRequest` with PKCE (the library
    ///    generates the verifier + challenge automatically when
    ///    `additionalParameters` is omitted from the init we use).
    /// 3. Presents `ASWebAuthenticationSession` on the supplied
    ///    UIViewController. AppAuth handles the redirect + code
    ///    exchange.
    /// 4. Persists the resulting `OIDAuthState` to Keychain.
    /// 5. Promotes the app to `.authenticated` so AppRouter swaps
    ///    in the main shell.
    ///
    /// Must be called on the MainActor — `OIDAuthorizationService`
    /// owns the presenting view controller.
    @MainActor
    func loginWithOAuth(presenter: UIViewController) async throws {
        let config = try await discoverConfiguration()

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: Constants.Keycloak.clientId,
            clientSecret: nil,
            scopes: Constants.Keycloak.scopes,
            redirectURL: Constants.Keycloak.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let state: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            let session = OIDAuthState.authState(
                byPresenting: request,
                presenting: presenter
            ) { authState, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let authState else {
                    continuation.resume(throwing: KeycloakAuthError.missingAuthState)
                    return
                }
                continuation.resume(returning: authState)
            }
            // Stash the in-flight session so `.onOpenURL` in
            // InkYomiApp can hand the callback URL to AppAuth.
            // Cleared when the continuation resumes (either path).
            KeycloakAuthRepository.pendingSession = session
        }
        KeycloakAuthRepository.pendingSession = nil

        try await persist(state: state)
        await self.setLoggedIn(profile: profileFrom(state: state))
    }

    /// Resume the OAuth flow when the OS hands the app the
    /// `shop.inkcolors.inkyomi://auth/callback` URL. Called from
    /// `InkYomiApp.onOpenURL`. Returns true if the URL was
    /// consumed by an in-flight session.
    @discardableResult
    nonisolated static func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        guard let session = pendingSession else { return false }
        let consumed = session.resumeExternalUserAgentFlow(with: url)
        if consumed { pendingSession = nil }
        return consumed
    }

    // MARK: - Internals

    private func discoverConfiguration() async throws -> OIDServiceConfiguration {
        if let cachedConfig { return cachedConfig }
        let config: OIDServiceConfiguration = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: Constants.Keycloak.issuerURL) { configuration, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let configuration else {
                    continuation.resume(throwing: KeycloakAuthError.discoveryFailed)
                    return
                }
                continuation.resume(returning: configuration)
            }
        }
        cachedConfig = config
        return config
    }

    /// Restore the OIDAuthState archive from Keychain if it exists.
    /// Stores the result in `self.authState` and registers the
    /// state-change callback that re-persists on every refresh.
    private func loadStateIfPresent() async throws -> OIDAuthState? {
        if let authState { return authState }
        guard let archive = try? keychain.readData(forKey: Constants.Keycloak.authStateKey) else {
            return nil
        }
        // OIDAuthState conforms to NSSecureCoding. Decode in a
        // restricted-class allowlist — anything else in the
        // archive is rejected.
        guard let state = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OIDAuthState.self,
            from: archive
        ) else {
            kcLogger.warning("OIDAuthState archive present but decode returned nil — discarding")
            try? keychain.delete(forKey: Constants.Keycloak.authStateKey)
            return nil
        }
        attach(state: state)
        return state
    }

    /// Wire the state-change + error callbacks so any refresh in
    /// flight gets persisted, and any terminal error triggers the
    /// migration coordinator's bounce-to-login.
    ///
    /// Note: `OIDAuthState` holds both delegate properties weakly, so
    /// we stash strong references on the actor (`stateChangeDelegate`
    /// + `stateErrorDelegate`) — otherwise the freshly-constructed
    /// delegates dealloc the instant this function returns.
    private func attach(state: OIDAuthState) {
        authState = state
        let errorDelegate = StateErrorDelegate(repo: self)
        let changeDelegate = StateChangeDelegate(repo: self)
        stateErrorDelegate = errorDelegate
        stateChangeDelegate = changeDelegate
        state.errorDelegate = errorDelegate
        state.stateChangeDelegate = changeDelegate
    }

    /// Refresh-if-needed wrapper. Returns a fresh access token (or
    /// throws an `AuthFailure` classified by terminal-ness so the
    /// caller can decide whether to bounce to OAuth or keep the
    /// user signed in offline).
    private func freshAccessToken(state: OIDAuthState) async throws -> String {
        if authState !== state { attach(state: state) }
        return try await withCheckedThrowingContinuation { continuation in
            state.performAction { accessToken, _, error in
                if let error {
                    // Distinguish a server-side "this refresh token
                    // is dead" (invalid_grant — terminal) from a
                    // transient network failure. AppAuth surfaces
                    // OAuth token-error codes via NSError userInfo
                    // under OIDOAuthErrorResponseErrorKey.
                    let failure = Self.classify(error: error)
                    continuation.resume(throwing: failure)
                    return
                }
                guard let accessToken else {
                    continuation.resume(throwing: AuthFailure.network(underlying: KeycloakAuthError.missingAccessToken))
                    return
                }
                continuation.resume(returning: accessToken)
            }
        }
    }

    private static func classify(error: Error) -> AuthFailure {
        let ns = error as NSError
        // OIDOAuthErrorResponse domain — token endpoint returned an
        // OAuth-shaped error body. The `error` field in the body is
        // surfaced under userInfo[OIDOAuthErrorResponseErrorKey].
        if ns.domain == OIDOAuthTokenErrorDomain || ns.domain == OIDOAuthAuthorizationErrorDomain {
            let oauthErr = (ns.userInfo[OIDOAuthErrorResponseErrorKey] as? String)
                ?? (ns.userInfo[NSLocalizedDescriptionKey] as? String)
                ?? ""
            let terminal = ["invalid_grant", "unauthorized_client", "invalid_token", "invalid_client"]
                .contains { oauthErr.contains($0) }
            return .remoteRejected(terminal: terminal, statusCode: ns.code, body: oauthErr)
        }
        return .network(underlying: error)
    }

    /// Persist the current OIDAuthState archive to Keychain.
    private func persist(state: OIDAuthState) async throws {
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: state,
            requiringSecureCoding: true
        )
        try keychain.save(data: archive, forKey: Constants.Keycloak.authStateKey)
        attach(state: state)
    }

    fileprivate func didChangeState() {
        guard let state = authState else { return }
        // Re-archive on every refresh-token rotation. Best-effort —
        // a failure here just means we'll re-fetch the same state
        // from disk next launch, which is harmless.
        if let archive = try? NSKeyedArchiver.archivedData(
            withRootObject: state,
            requiringSecureCoding: true
        ) {
            try? keychain.save(data: archive, forKey: Constants.Keycloak.authStateKey)
        }
    }

    fileprivate func didReceiveAuthError(_ error: Error) {
        kcLogger.warning("OIDAuthState surfaced auth error: \(error.localizedDescription, privacy: .public)")
        // The error delegate fires when AppAuth detects that the
        // current refresh attempt failed with a terminal OAuth
        // error. The migration coordinator owns the wipe + bounce —
        // we invoke it via the closure the container installed.
        Task { @MainActor [appState] in
            appState.pendingAuthError = error.localizedDescription
        }
        if let onTerminalFailure {
            Task { await onTerminalFailure() }
        }
    }

    /// Hook the coordinator wires up so terminal OAuth errors trigger
    /// the wipe-and-bounce path. Set once at container init.
    nonisolated(unsafe) var onTerminalFailure: (@Sendable () async -> Void)?

    /// Read-only access to the current user profile, derived from
    /// claims in the stored OIDAuthState. Returns nil if no archive
    /// is restored or the claims can't be parsed. Used by
    /// `AuthMigrationCoordinator.restoreSession()` to seed
    /// `appState.authState = .authenticated(profile)`.
    func currentProfile() async -> UserProfile? {
        guard let state = try? await loadStateIfPresent() else { return nil }
        return profileFrom(state: state)
    }

    @MainActor
    private func setLoggedIn(profile: UserProfile) {
        appState.authState = .authenticated(profile)
        appState.pendingAuthError = nil
    }

    private func profileFrom(state: OIDAuthState) -> UserProfile {
        // ID token claims — parsed by AppAuth's lastTokenResponse if
        // present. Fall back to the access-token claims (Keycloak
        // includes email + preferred_username there too).
        let claims = decodedClaims(from: state.lastTokenResponse?.idToken)
            ?? decodedClaims(from: state.lastTokenResponse?.accessToken)
            ?? [:]
        let sub = (claims["sub"] as? String) ?? UUID().uuidString
        let email = (claims["email"] as? String) ?? ""
        let displayName = (claims["name"] as? String)
            ?? (claims["preferred_username"] as? String)
        return UserProfile(id: sub, email: email, displayName: displayName)
    }

    /// Cheap JWT payload decode. Doesn't verify the signature —
    /// AppAuth has already validated the token by the time we look
    /// at it; we just need the claims for UI display.
    private func decodedClaims(from token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
        // JWT segments are base64url, no padding. Pad it for Data.
        let pad = 4 - payload.count % 4
        if pad < 4 { payload.append(String(repeating: "=", count: pad)) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

/// OAuth-specific failure cases that can't be expressed as
/// `AuthFailure` — surfaced to UI for the rare paths that show a
/// dedicated message (e.g. "use the website to reset your password").
enum KeycloakAuthError: Error, LocalizedError {
    case passwordLoginNotSupported
    case useHostedForgotPassword
    case discoveryFailed
    case missingAuthState
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .passwordLoginNotSupported:
            return "Password login is not supported on this device. Use Sign in with InkColors."
        case .useHostedForgotPassword:
            return "Reset your password from inkcolors.shop."
        case .discoveryFailed:
            return "Couldn't reach the Inkcolors login server."
        case .missingAuthState:
            return "Login completed without returning a session. Try again."
        case .missingAccessToken:
            return "Couldn't get an access token from the login server."
        }
    }
}

// MARK: - OIDAuthState delegates

/// AppAuth fires `didChange` after each successful refresh + after
/// initial code exchange. We use it to re-archive the state to
/// Keychain so the rotated refresh token survives a kill.
private final class StateChangeDelegate: NSObject, OIDAuthStateChangeDelegate {
    weak var repo: KeycloakAuthRepository?
    init(repo: KeycloakAuthRepository) { self.repo = repo; super.init() }
    func didChange(_ state: OIDAuthState) {
        guard let repo else { return }
        Task { await repo.didChangeState() }
    }
}

/// AppAuth fires `didEncounterAuthorizationError` for terminal
/// failures (refresh token rejected). We forward to the migration
/// coordinator so it can wipe + bounce.
private final class StateErrorDelegate: NSObject, OIDAuthStateErrorDelegate {
    weak var repo: KeycloakAuthRepository?
    init(repo: KeycloakAuthRepository) { self.repo = repo; super.init() }
    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        guard let repo else { return }
        Task { await repo.didReceiveAuthError(error) }
    }
}

// MARK: - Sendable conformances for AppAuth types
//
// AppAuth's types aren't marked Sendable in their Objective-C
// headers, but the library uses GCD internally and the reference
// semantics we rely on (mutating OIDAuthState in place via its
// delegates, reading lastTokenResponse for claims) are safe to share
// across our actor and the MainActor that drives the browser session.
// `@unchecked` because we're vouching for the library's thread-safety
// guarantees rather than proving them to the compiler.
extension OIDAuthState: @unchecked @retroactive Sendable {}
extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}
