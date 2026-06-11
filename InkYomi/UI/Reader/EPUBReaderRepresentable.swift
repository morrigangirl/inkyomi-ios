import SwiftUI
import UIKit
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
    private var ttsController: ReaderTTSController?
    nonisolated(unsafe) private var hrefObserver: Any?
    nonisolated(unsafe) private var bookmarkObserver: Any?
    nonisolated(unsafe) private var preferencesObserver: Any?
    nonisolated(unsafe) private var pageLayoutObserver: Any?
    nonisolated(unsafe) private var goBackwardObserver: Any?
    nonisolated(unsafe) private var goForwardObserver: Any?
    nonisolated(unsafe) private var ttsToggleObserver: Any?
    nonisolated(unsafe) private var ttsNextObserver: Any?
    nonisolated(unsafe) private var ttsPreviousObserver: Any?

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
        setupReadAloud()

        // Re-apply reader styling live when Increase Contrast or Bold Text
        // changes, so the book updates without reopening.
        registerForTraitChanges(
            [UITraitAccessibilityContrast.self, UITraitLegibilityWeight.self]
        ) { (vc: EPUBHostViewController, _) in
            vc.navigator?.submitPreferences(vc.buildPreferences())
        }
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

    /// Create the read-aloud controller and bridge it to the navigator: it
    /// drives `viewModel.isReadAloudPlaying` for the UI, and turns the page to
    /// follow the narration via `navigator.go(to:)`.
    private func setupReadAloud() {
        let controller = ReaderTTSController(publication: publication, title: viewModel.bookTitle)
        controller.onPlayingChanged = { [weak self] playing in
            self?.viewModel.isReadAloudPlaying = playing
        }
        controller.onAdvance = { [weak self] locator in
            Task { @MainActor [weak self] in
                _ = await self?.navigator?.go(to: locator, options: NavigatorGoOptions())
            }
        }
        viewModel.isReadAloudAvailable = controller.isAvailable
        self.ttsController = controller
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

        ttsToggleObserver = NotificationCenter.default.addObserver(
            forName: .readerReadAloudToggle,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ttsController?.toggle(from: self.navigator?.currentLocation)
            }
        }

        ttsNextObserver = NotificationCenter.default.addObserver(
            forName: .readerReadAloudNext,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.ttsController?.skipNext() }
        }

        ttsPreviousObserver = NotificationCenter.default.addObserver(
            forName: .readerReadAloudPrevious,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.ttsController?.skipPrevious() }
        }
    }

    // MARK: - EPUBNavigatorDelegate / NavigatorDelegate / VisualNavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        viewModel.handleLocatorChanged(locator)
        // Re-sync VoiceOver to the newly-rendered page after a turn / TOC jump so
        // focus doesn't strand on the previous page's content (audit A2 / WCAG 2.4.3).
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
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

        // Increase Contrast: push reader text/background to maximum contrast.
        let highContrast = traitCollection.accessibilityContrast == .high

        switch viewModel.theme {
        case .light:
            if highContrast {
                prefs.backgroundColor = ReadiumNavigator.Color(hex: "#FFFFFF")
                prefs.textColor = ReadiumNavigator.Color(hex: "#000000")
            }
        case .sepia:
            prefs.backgroundColor = ReadiumNavigator.Color(hex: "#F5E6C8")
            prefs.textColor = ReadiumNavigator.Color(hex: highContrast ? "#2B1C0E" : "#5B4636")
        case .dark:
            prefs.backgroundColor = ReadiumNavigator.Color(hex: highContrast ? "#000000" : "#1A1A1A")
            prefs.textColor = ReadiumNavigator.Color(hex: highContrast ? "#FFFFFF" : "#CCCCCC")
        }

        // Bold Text: honor the system setting in the book's body text.
        if traitCollection.legibilityWeight == .bold {
            prefs.fontWeight = 1.5
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
        // Stop narration + release the audio session / Now Playing when the
        // reader is dismissed. Not fired for sheets or app backgrounding, so
        // read-aloud correctly keeps playing in the background.
        ttsController?.stop()
    }

    deinit {
        if let obs = hrefObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = bookmarkObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = preferencesObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = pageLayoutObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = goBackwardObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = goForwardObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = ttsToggleObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = ttsNextObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = ttsPreviousObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
