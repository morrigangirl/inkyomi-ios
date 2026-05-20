import Foundation
import os.log

private let migrationLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "AuthMigration")

/// Owns the "which auth repository do we hand to the rest of the app"
/// decision and the "this session is dead, drop the user back to OAuth
/// login" bounce.
///
/// Lifecycle
/// ---------
/// One instance per app launch, constructed inside
/// `DependencyContainer.init`. It inspects on-disk state and picks:
///
/// • **KeycloakAuthRepository** when an `OIDAuthState` archive exists
///   in the auth Keychain — this user already migrated, or signed in
///   fresh under the new OAuth flow.
/// • **NativeAuthRepository** when a legacy `refreshToken` is present
///   but no OIDAuthState yet — pre-migration user with a working
///   session. They stay on the legacy path until their next terminal
///   refresh failure, at which point `bounceToOAuth()` clears them
///   and forces a one-time OAuth sign-in.
/// • **KeycloakAuthRepository** (unauthenticated state) when neither
///   is present — fresh install / wiped device. The login screen
///   presents the OAuth button.
///
/// Bouncing
/// --------
/// `bounceToOAuth()` is the funnel for every "your session is gone"
/// path: NativeAuthRepository terminal failure during the lazy
/// transition, KeycloakAuthRepository error delegate firing for
/// `invalid_grant`, or middleware returning `device_revoked`. It
/// runs `UserDataWipe.wipe()` and flips `appState.authState` to
/// `.unauthenticated`. `pendingAuthMigration` is set so the login
/// screen can surface a friendlier "we upgraded your reader's
/// security — please sign in once more" instead of a generic
/// re-auth message.
///
/// Not an actor: all stored references are immutable after init, and
/// `bounceToOAuth` delegates everything mutable to either
/// `UserDataWipe` (its own async helpers) or `MainActor`-bound
/// `appState` updates. Marked `@unchecked Sendable` so the container
/// can capture it freely.
final class AuthMigrationCoordinator: @unchecked Sendable {
    /// The selected auth repository for this app launch. Pinned at
    /// construction; bouncing doesn't swap it (the unauthenticated
    /// branch already routes through Keycloak).
    let active: any AuthRepository

    /// Direct handle to the Keycloak repo. Always present (even when
    /// `active` resolves to the native one) because the OAuth login
    /// button + `InkYomiApp.onOpenURL` callback dispatch always
    /// route through Keycloak — there's no legacy path for new
    /// sign-ins.
    let keycloak: KeycloakAuthRepository

    /// The native legacy repo, if a legacy refresh token was found at
    /// launch. Held so the lazy-transition code path can also call
    /// `signOut()` on it during a bounce to clear its in-memory cache.
    let native: NativeAuthRepository?

    /// Weak reference to the container. Injected after construction
    /// via `attachContainer(_:)` to avoid the chicken-and-egg of the
    /// container's `let` properties not being fully initialized when
    /// the coordinator is built. Only read inside async paths
    /// (`bounceToOAuth`, `restoreSession`) that run after init has
    /// fully returned, so the late attachment is race-free in practice.
    private weak var container: DependencyContainer?

    /// Called by `DependencyContainer` once all its `let` properties
    /// are populated — gives the coordinator the back-reference it
    /// needs to drive `UserDataWipe` and `appState` updates.
    func attachContainer(_ container: DependencyContainer) {
        self.container = container
    }

    init(
        keycloak: KeycloakAuthRepository,
        native: NativeAuthRepository?,
        authKeychain: KeychainManager
    ) {
        self.keycloak = keycloak
        self.native = native

        // Pick the repo at construction time. The decision tree:
        //   1. New-world OIDAuthState archive present → Keycloak
        //   2. Legacy refresh token in Keychain (no OIDAuthState yet)
        //      → Native (lazy transition)
        //   3. Neither → Keycloak (unauthenticated; login screen
        //      shows the OAuth button)
        let hasOIDState = (try? authKeychain.readData(forKey: Constants.Keycloak.authStateKey)) != nil
        let hasLegacyRefresh = (try? authKeychain.readString(forKey: "refreshToken")) != nil
        if hasOIDState {
            self.active = keycloak
            migrationLogger.info("AuthMigrationCoordinator: routing to KeycloakAuthRepository (OIDAuthState present)")
        } else if hasLegacyRefresh, let native {
            self.active = native
            migrationLogger.info("AuthMigrationCoordinator: routing to NativeAuthRepository (legacy refresh token present, awaiting lazy migration)")
        } else {
            self.active = keycloak
            migrationLogger.info("AuthMigrationCoordinator: routing to KeycloakAuthRepository (unauthenticated; OAuth required)")
        }
    }

    /// Restore the session from whatever credentials we found at
    /// launch. Native does the actual refresh-or-fail dance;
    /// Keycloak's `getAccessToken()` is the equivalent (its
    /// `OIDAuthState` knows how to refresh itself). On either path,
    /// terminal failures flow through `bounceToOAuth()`.
    func restoreSession() async {
        if let nativeActive = active as? NativeAuthRepository {
            await nativeActive.restoreSession()
            return
        }
        guard let keycloakActive = active as? KeycloakAuthRepository else {
            await setUnauthenticated()
            return
        }
        // Probe for a token. Nil means either no archive or the
        // refresh chain is dead — the error delegate on OIDAuthState
        // would already have fired `bounceToOAuth()` if it was the
        // latter, but we still need to set the right auth state when
        // there was nothing to restore.
        let token = await keycloakActive.getAccessToken()
        if token != nil {
            let profile = await keycloakActive.currentProfile()
            await MainActor.run { [weak container] in
                guard let container else { return }
                if let profile {
                    container.appState.authState = .authenticated(profile)
                } else {
                    container.appState.authState = .unauthenticated
                }
            }
        } else {
            await setUnauthenticated()
        }
    }

    /// "Your session is dead, surface the OAuth login screen and
    /// scrub every shred of local state." Funnel for every terminal
    /// auth failure during the lazy transition.
    func bounceToOAuth(reason: String) async {
        migrationLogger.warning("bounceToOAuth: \(reason, privacy: .public) — wiping local state")
        guard let container else { return }
        // Mark before the wipe so the login screen reads the flag
        // even on the same render pass.
        await MainActor.run { [weak container] in
            container?.appState.pendingAuthMigration = true
        }
        await UserDataWipe.wipe(container: container)
        // UserDataWipe sets authState = .unauthenticated already, but
        // belt-and-braces in case wipe itself faulted before reaching
        // that step.
        await MainActor.run { [weak container] in
            container?.appState.authState = .unauthenticated
        }
    }

    private func setUnauthenticated() async {
        await MainActor.run { [weak container] in
            container?.appState.authState = .unauthenticated
        }
    }
}
