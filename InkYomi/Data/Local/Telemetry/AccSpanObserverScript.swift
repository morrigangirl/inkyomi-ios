import Foundation

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
