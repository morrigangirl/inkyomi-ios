import Foundation
import WebKit
import SwiftData
import os.log

private let bridgeLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "SpanObserverBridge")

/// Receives `webkit.messageHandlers.spanObserver.postMessage(...)` calls
/// from `AccSpanObserverScript`'s `IntersectionObserver` and persists
/// each completed span observation as a `PendingSpanReadModel` row for
/// later upload by `SpanTelemetryRepository`.
///
/// Mirrors Android's `SpanTelemetryRepository.recordSpanObservation`
/// path but uses iOS's push model (one event per message) instead of
/// Android's poll-and-drain model. Same DB row layout, same
/// `accId → sequenceIndex` lookup, same upload contract.
///
/// Lifecycle:
///   • Created by `ReaderViewModel` when a borrowed book opens, once
///     the accounting manifest has been fetched.
///   • `setActiveLoan(loanId:accIdToSequence:)` is called with the
///     manifest's slug → sequence map; observations without a known
///     `accId` fall back to `sequenceIndex = -1` (matches Android).
///   • `installInto(_:)` is invoked by `EPUBHostViewController` from
///     `setupUserScripts(_:)` to register both the user script and
///     the message-handler channel on the WKWebView's
///     `WKUserContentController`.
///   • `detach()` clears active state on reader-close so a stale loan
///     never receives further observations.
///
/// Threading:
///   • `WKScriptMessageHandler.userContentController(_:didReceive:)`
///     is invoked on the main actor by WKWebKit; we hop straight to
///     a detached Task and perform the SwiftData write on a fresh
///     background `ModelContext` derived from the shared container.
final class SpanObserverBridge: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    static let messageHandlerName = "spanObserver"

    private let modelContainer: ModelContainer
    private let lock = NSLock()
    private var activeLoanId: String?
    private var accIdToSequence: [String: Int] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    /// Bind the bridge to a borrowed loan and provide the
    /// server-resolved `accId → sequenceIndex` lookup. Safe to call
    /// repeatedly — replaces the previous active loan + map.
    func setActiveLoan(loanId: String, accIdToSequence: [String: Int]) {
        lock.lock()
        self.activeLoanId = loanId
        self.accIdToSequence = accIdToSequence
        lock.unlock()
    }

    /// Clear active state. Subsequent JS-emitted messages are silently
    /// dropped (no loan to attribute them to).
    func detach() {
        lock.lock()
        activeLoanId = nil
        accIdToSequence = [:]
        lock.unlock()
    }

    /// Register the IntersectionObserver script and the message
    /// channel on the WKWebView's content controller. Called from
    /// `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)`.
    func installInto(_ contentController: WKUserContentController) {
        // Remove any prior registration so reloads don't duplicate the
        // handler (WKWebKit throws if the same name is added twice).
        contentController.removeScriptMessageHandler(forName: Self.messageHandlerName)

        let userScript = WKUserScript(
            source: AccSpanObserverScript.javascript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
        contentController.add(self, name: Self.messageHandlerName)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any],
              let accId = body["accId"] as? String,
              let enteredAtMs = numericMillis(body["enteredAt"]),
              let exitedAtMs = numericMillis(body["exitedAt"]),
              let dwellMs = numericMillis(body["dwellMs"]) else {
            return
        }

        lock.lock()
        let loanId = activeLoanId
        let sequenceIndex = accIdToSequence[accId] ?? -1
        lock.unlock()

        guard let loanId else { return }

        let entered = Date(timeIntervalSince1970: TimeInterval(enteredAtMs) / 1000)
        let exited = Date(timeIntervalSince1970: TimeInterval(exitedAtMs) / 1000)

        let container = modelContainer
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let row = PendingSpanReadModel(
                loanId: loanId,
                accId: accId,
                sequenceIndex: sequenceIndex,
                enteredAt: entered,
                exitedAt: exited,
                dwellMs: dwellMs,
                uploaded: false
            )
            context.insert(row)
            do {
                try context.save()
            } catch {
                bridgeLogger.error("Failed to persist span: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Coerce a JSON-bridged number value (NSNumber from JS) to Int64.
    /// JavaScript's `Date.now()` and dwell math both come over as
    /// doubles; cast safely without losing precision.
    private func numericMillis(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let d = value as? Double { return Int64(d) }
        return nil
    }
}
