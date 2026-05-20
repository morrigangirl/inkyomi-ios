import Foundation
import SwiftData
import os.log

private let wipeLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "UserDataWipe")

/// Centralised "remove every shred of the signed-in user's local
/// state" routine. Called from two places:
///
///   1. Settings → "Remove this device" — explicit user action,
///      after the backend revoke succeeds (or fails offline; we
///      still wipe locally and queue the revoke for later).
///   2. `AuthMigrationCoordinator.bounceToOAuth()` — automatic, when
///      Keycloak or our middleware reports the device's session is
///      revoked / the refresh token is dead.
///
/// Wipes:
///   • Keychain — every service we own (auth refresh + access token,
///     LCP transport secrets, LCP passphrases, device EC keypair).
///   • UserDefaults — every key the app writes via Constants helpers,
///     plus the appearance preference (kept as a comment-defined
///     constant) to avoid bleeding settings across accounts.
///   • SwiftData — every @Model in `InkyomiModelContainer.modelTypes`.
///   • Filesystem — downloaded books (owned + borrowed) and the
///     reader debug log.
///
/// Resets `appState.authState = .unauthenticated` last so the
/// AppRouter switches to the login flow. Idempotent: safe to call
/// multiple times.
enum UserDataWipe {
    /// Snapshot of what was cleared. Logged for diagnostics; not
    /// shown to the user.
    struct Result {
        var keychainServicesCleared: Int = 0
        var userDefaultsKeysCleared: Int = 0
        var swiftDataRowsCleared: Int = 0
        var filesRemoved: Int = 0
    }

    /// Wipe every user-scoped local artifact. Safe to call from any
    /// context — internally hops to the right actors as needed.
    @discardableResult
    static func wipe(container: DependencyContainer) async -> Result {
        var result = Result()

        // 1. Keychain — clear each service we own. Failures are
        // logged + swallowed; one un-clearable item must not block
        // the rest of the wipe.
        let services = [
            Constants.Keychain.authService,
            Constants.Keychain.transportService,
            Constants.Keychain.passphraseService,
            Constants.Keychain.deviceKeyService,
        ]
        for service in services {
            let km = KeychainManager(service: service)
            do {
                try km.deleteAll()
                result.keychainServicesCleared += 1
            } catch {
                wipeLogger.error("Keychain wipe for service \(service, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2. UserDefaults — known per-user keys. The deviceId is
        // intentionally cleared too: a fresh OAuth login will mint
        // a new device row server-side rather than re-binding the
        // old one (mirrors the spec: "App reinstall → treat as new
        // device registration; old device record remains until user
        // removes it from the web account page" — same effect).
        let defaults = UserDefaults.standard
        let userDefaultsKeys = [
            Constants.UserDefaultsKeys.accessToken,
            Constants.UserDefaultsKeys.accessTokenExpiry,
            Constants.UserDefaultsKeys.deviceId,
            Constants.UserDefaultsKeys.userProfileId,
            Constants.UserDefaultsKeys.userProfileEmail,
            Constants.UserDefaultsKeys.userProfileDisplayName,
            AppearancePreference.storageKey,
        ]
        for key in userDefaultsKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            result.userDefaultsKeysCleared += 1
        }

        // 3. SwiftData — iterate every persistent model and delete
        // its rows. Uses the existing shared ModelContainer; a
        // fresh background ModelContext is created here to keep
        // the wipe off any UI-bound context.
        let modelContainer = container.modelContainer
        let cleared = await Task.detached(priority: .userInitiated) { () -> Int in
            let context = ModelContext(modelContainer)
            var deleted = 0
            for modelType in InkyomiModelContainer.modelTypes {
                deleted += deleteAll(modelType, in: context)
            }
            try? context.save()
            return deleted
        }.value
        result.swiftDataRowsCleared = cleared

        // 4. Filesystem — borrowed + owned book caches, plus the
        // reader debug log written by ReaderViewModel.debugLog.
        let freed = await container.storageRepository.clearAllDownloads()
        if freed > 0 {
            wipeLogger.info("Cleared \(freed, privacy: .public) bytes of cached downloads")
        }
        // Reader debug log lives in Documents — outside the cache
        // directories that StorageRepository.clearAllDownloads
        // handles. Remove it explicitly.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logURL = docs.appendingPathComponent("reader_debug.log")
            if FileManager.default.fileExists(atPath: logURL.path) {
                try? FileManager.default.removeItem(at: logURL)
                result.filesRemoved += 1
            }
        }

        // 5. Reset auth state on the main actor so SwiftUI redraws
        // and the AppRouter bounces to the login screen.
        await MainActor.run {
            container.appState.authState = .unauthenticated
        }

        wipeLogger.info("UserDataWipe complete: services=\(result.keychainServicesCleared) userDefaults=\(result.userDefaultsKeysCleared) rows=\(result.swiftDataRowsCleared) files=\(result.filesRemoved)")
        return result
    }

    /// Type-erased "fetch + delete all" helper. SwiftData's
    /// `FetchDescriptor` is generic over the model type, which
    /// makes this kind of iteration a small dance.
    private static func deleteAll<M: PersistentModel>(_ type: M.Type, in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<M>()
        let rows = (try? context.fetch(descriptor)) ?? []
        for row in rows { context.delete(row) }
        return rows.count
    }

    /// Same as `deleteAll<M>` but accepting `any PersistentModel.Type`
    /// (the only thing we can express in the model-list array). Uses
    /// a runtime existential opener to dispatch to the typed
    /// implementation.
    private static func deleteAll(_ type: any PersistentModel.Type, in context: ModelContext) -> Int {
        // Swift 6 opens existentials automatically inside this
        // generic helper; we just need a free generic to land in.
        func _open<T: PersistentModel>(_ t: T.Type) -> Int {
            return deleteAll(t, in: context)
        }
        return _open(type)
    }
}
