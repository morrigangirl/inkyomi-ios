import SwiftUI
import UIKit
import WebKit
import ReadiumShared
import ReadiumNavigator

/// Bridges Readium's `EPUBNavigatorViewController` (UIKit) into SwiftUI.
struct EPUBReaderRepresentable: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocator: Locator?
    let viewModel: ReaderViewModel

    func makeUIViewController(context: Context) -> EPUBHostViewController {
        EPUBHostViewController(
            publication: publication,
            initialLocator: initialLocator,
            viewModel: viewModel
        )
    }

    func updateUIViewController(_ uiViewController: EPUBHostViewController, context: Context) {
        // Preferences are applied through the delegate/notification pattern
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {}
}

/// UIKit container that hosts the `EPUBNavigatorViewController`.
@MainActor
final class EPUBHostViewController: UIViewController, EPUBNavigatorDelegate {
    private let publication: Publication
    private let initialLocator: Locator?
    private let viewModel: ReaderViewModel
    private var navigator: EPUBNavigatorViewController?
    nonisolated(unsafe) private var hrefObserver: Any?
    nonisolated(unsafe) private var bookmarkObserver: Any?
    nonisolated(unsafe) private var preferencesObserver: Any?
    nonisolated(unsafe) private var pageLayoutObserver: Any?
    nonisolated(unsafe) private var goBackwardObserver: Any?
    nonisolated(unsafe) private var goForwardObserver: Any?

    init(publication: Publication, initialLocator: Locator?, viewModel: ReaderViewModel) {
        self.publication = publication
        self.initialLocator = initialLocator
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigator(at: initialLocator)
        setupNotificationObservers()
    }

    private func setupNavigator(at locator: Locator?) {
        do {
            let config = EPUBNavigatorViewController.Configuration(
                preferences: buildPreferences(),
                defaults: EPUBDefaults()
            )

            let nav = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: locator,
                config: config
            )

            nav.delegate = self
            self.navigator = nav
            addChild(nav)
            nav.view.frame = view.bounds
            nav.view.autoresizingMask = [
                UIView.AutoresizingMask.flexibleWidth,
                UIView.AutoresizingMask.flexibleHeight
            ]
            view.addSubview(nav.view)
            nav.didMove(toParent: self)

        } catch {
            viewModel.error = "Failed to create navigator: \(error.localizedDescription)"
        }
    }

    private func reloadNavigator() {
        let resumeLocator = navigator?.currentLocation ?? initialLocator
        if let nav = navigator {
            nav.willMove(toParent: nil)
            nav.view.removeFromSuperview()
            nav.removeFromParent()
            self.navigator = nil
        }
        setupNavigator(at: resumeLocator)
    }

    private func setupNotificationObservers() {
        hrefObserver = NotificationCenter.default.addObserver(
            forName: .readerNavigateToHref,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let href = notification.object as? String else { return }
            Task { @MainActor [weak self] in
                guard let self, let nav = self.navigator else { return }
                if let url = AnyURL(string: href) {
                    let locator = Locator(href: url, mediaType: .xhtml)
                    _ = await nav.go(to: locator, options: NavigatorGoOptions())
                }
            }
        }

        bookmarkObserver = NotificationCenter.default.addObserver(
            forName: .readerAddBookmark,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let nav = self.navigator else { return }
                if let locator = nav.currentLocation {
                    self.viewModel.addBookmark(locator: locator)
                }
            }
        }

        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .readerPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let nav = self.navigator else { return }
                nav.submitPreferences(self.buildPreferences())
            }
        }

        pageLayoutObserver = NotificationCenter.default.addObserver(
            forName: .readerPageLayoutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadNavigator()
            }
        }

        goBackwardObserver = NotificationCenter.default.addObserver(
            forName: .readerGoBackward,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let nav = self.navigator else { return }
                _ = await nav.goBackward(options: NavigatorGoOptions())
            }
        }

        goForwardObserver = NotificationCenter.default.addObserver(
            forName: .readerGoForward,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let nav = self.navigator else { return }
                _ = await nav.goForward(options: NavigatorGoOptions())
            }
        }
    }

    // MARK: - EPUBNavigatorDelegate / NavigatorDelegate / VisualNavigatorDelegate

    /// Readium hands us the WKWebView's `WKUserContentController` here
    /// at navigator setup time. We use it to register the
    /// `IntersectionObserver` user script and the `spanObserver`
    /// message channel that `SpanObserverBridge` reads on the native
    /// side. Each reload of the navigator (font/theme change) gets a
    /// fresh content controller; the bridge handles re-registration
    /// idempotently via `removeScriptMessageHandler` before adding.
    func navigator(
        _ navigator: EPUBNavigatorViewController,
        setupUserScripts userContentController: WKUserContentController
    ) {
        viewModel.spanObserverBridge?.installInto(userContentController)
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        viewModel.handleLocatorChanged(locator)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        viewModel.error = error.localizedDescription
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let centerThird = view.bounds.width / 3
        if point.x > centerThird && point.x < centerThird * 2 {
            viewModel.toggleControls()
        }
    }

    /// Build Readium EPUB preferences from the ViewModel state.
    private func buildPreferences() -> EPUBPreferences {
        var prefs = EPUBPreferences()
        prefs.fontSize = viewModel.fontScale
        prefs.publisherStyles = false

        switch viewModel.theme {
        case .light:
            break // defaults
        case .sepia:
            prefs.backgroundColor = ReadiumNavigator.Color(hex: "#F5E6C8")
            prefs.textColor = ReadiumNavigator.Color(hex: "#5B4636")
        case .dark:
            prefs.backgroundColor = ReadiumNavigator.Color(hex: "#1A1A1A")
            prefs.textColor = ReadiumNavigator.Color(hex: "#CCCCCC")
        }

        switch viewModel.pageLayout {
        case .auto:
            prefs.spread = nil           // Readium decides spread by screen size
            prefs.columnCount = nil      // and likewise for column count
        case .single:
            prefs.spread = .never
            prefs.columnCount = .one     // force single column on reflowable EPUBs
        case .double:
            prefs.spread = .always
            prefs.columnCount = .two
        }

        return prefs
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    deinit {
        if let obs = hrefObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = bookmarkObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = preferencesObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = pageLayoutObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = goBackwardObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = goForwardObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
