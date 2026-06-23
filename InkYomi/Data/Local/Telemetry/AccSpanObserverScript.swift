import Foundation
import WebKit
import os.log

private let bridgeLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "Telemetry")

/// JavaScript IntersectionObserver script injected into Readium WebView.
/// Monitors `<span data-acc-id="...">` elements for dwell tracking.
/// This is identical to the Android version — both inject the same JS.
enum AccSpanObserverScript {
    static let javascript = """
    (function() {
        if (window.__accSpanObserverInstalled) return;
        window.__accSpanObserverInstalled = true;

        const DEBOUNCE_EXIT_MS = 750;
        const THRESHOLD = 0.5;
        const pending = new Map();

        function report(accId, enteredAt, exitedAt, dwellMs) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.spanObserver) {
                window.webkit.messageHandlers.spanObserver.postMessage({
                    type: 'span',
                    accId: accId,
                    enteredAt: enteredAt,
                    exitedAt: exitedAt,
                    dwellMs: dwellMs
                });
            }
        }

        const observer = new IntersectionObserver(function(entries) {
            const now = Date.now();
            entries.forEach(function(entry) {
                const el = entry.target;
                const accId = el.getAttribute('data-acc-id');
                if (!accId) return;

                if (entry.isIntersecting) {
                    if (pending.has(accId)) {
                        clearTimeout(pending.get(accId).timer);
                        pending.delete(accId);
                    }
                    pending.set(accId, { enteredAt: now, timer: null });
                } else {
                    const rec = pending.get(accId);
                    if (rec && !rec.timer) {
                        rec.timer = setTimeout(function() {
                            const exitedAt = Date.now();
                            const dwellMs = exitedAt - rec.enteredAt;
                            report(accId, rec.enteredAt, exitedAt, dwellMs);
                            pending.delete(accId);
                        }, DEBOUNCE_EXIT_MS);
                    }
                }
            });
        }, { threshold: THRESHOLD });

        document.querySelectorAll('span[data-acc-id]').forEach(function(el) {
            observer.observe(el);
        });

        const mutObs = new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                m.addedNodes.forEach(function(node) {
                    if (node.nodeType === 1) {
                        if (node.hasAttribute && node.hasAttribute('data-acc-id')) {
                            observer.observe(node);
                        }
                        node.querySelectorAll && node.querySelectorAll('span[data-acc-id]').forEach(function(el) {
                            observer.observe(el);
                        });
                    }
                });
            });
        });
        mutObs.observe(document.body, { childList: true, subtree: true });
    })();
    """
}

/// Receives `spanObserver` postMessage events from the injected
/// `AccSpanObserverScript` IntersectionObserver and persists each span dwell to
/// the local telemetry queue via `SpanTelemetryRepository`.
///
/// One instance is created per reader session and registered on every Readium
/// spread's `WKUserContentController` (see `EPUBHostViewController`'s
/// `setupUserScripts` delegate). It is created synchronously at reader open,
/// before the loan + accounting manifest have resolved (those require a network
/// round-trip); span events seen in that window are buffered (capped) and
/// flushed once `configure(...)` lands, so the first spans of a session aren't
/// lost to the async fetch.
///
/// Threading: WebKit always delivers `userContentController(_:didReceive:)` on
/// the main thread, and `configure`/`disable` are called from the main-actor
/// host VC, so the mutable state below is only ever touched on the main thread.
/// `WKUserContentController` retains the handler strongly; the bridge holds only
/// value types plus the repository actor, so there is no retain cycle with the
/// web views or the host controller.
final class SpanObserverBridge: NSObject, WKScriptMessageHandler {
    private let repository: SpanTelemetryRepository

    private var loanId: String?
    private var accToSequence: [String: Int] = [:]
    private var disabled = false

    private struct Observation {
        let accId: String
        let enteredAt: Date
        let exitedAt: Date?
        let dwellMs: Int64
    }
    private var buffer: [Observation] = []
    private let bufferCap = 2000

    init(repository: SpanTelemetryRepository) {
        self.repository = repository
        super.init()
    }

    /// Borrowed book: enable recording with the loan id and the
    /// acc_id → sequence_index map from the accounting manifest. Flushes any
    /// observations buffered before the manifest resolved.
    func configure(loanId: String, accToSequence: [String: Int]) {
        guard !disabled else { return }
        self.loanId = loanId
        self.accToSequence = accToSequence
        let pending = buffer
        buffer.removeAll()
        for obs in pending { persist(obs) }
    }

    /// Not a borrowed book (or no manifest available): stop recording and drop
    /// anything buffered. Idempotent.
    func disable() {
        disabled = true
        loanId = nil
        accToSequence.removeAll()
        buffer.removeAll()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "spanObserver", !disabled else { return }
        guard let body = message.body as? [String: Any],
              let accId = body["accId"] as? String else { return }

        let enteredMs = doubleValue(body["enteredAt"])
        let exitedMs: Double? = {
            let d = doubleValue(body["exitedAt"])
            return d > 0 ? d : nil
        }()
        let dwellMs = Int64(doubleValue(body["dwellMs"]))
        guard enteredMs > 0, dwellMs > 0 else { return }

        let observation = Observation(
            accId: accId,
            enteredAt: Date(timeIntervalSince1970: enteredMs / 1000),
            exitedAt: exitedMs.map { Date(timeIntervalSince1970: $0 / 1000) },
            dwellMs: dwellMs
        )

        if loanId != nil {
            persist(observation)
        } else {
            // Manifest/loan not resolved yet — buffer (capped, drop oldest).
            buffer.append(observation)
            if buffer.count > bufferCap {
                buffer.removeFirst(buffer.count - bufferCap)
            }
        }
    }

    private func persist(_ observation: Observation) {
        guard let loanId else { return }
        // Map acc_id → sequence_index from the frozen manifest. An unknown
        // acc_id would be rejected server-side, so skip it (don't enqueue poison).
        guard let sequenceIndex = accToSequence[observation.accId] else { return }
        let repository = self.repository
        Task {
            await repository.recordSpan(
                loanId: loanId,
                accId: observation.accId,
                sequenceIndex: sequenceIndex,
                enteredAt: observation.enteredAt,
                exitedAt: observation.exitedAt,
                dwellMs: observation.dwellMs
            )
        }
    }

    /// JS numbers arrive as `Double` or `NSNumber` depending on the bridge.
    private func doubleValue(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }
}
