import SwiftUI
import ReadiumShared
import ReadiumNavigator

struct ReaderView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let bookId: String
    @State private var viewModel: ReaderViewModel

    init(bookId: String) {
        self.bookId = bookId
        self._viewModel = State(initialValue: ReaderViewModel(bookId: bookId))
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let doc = viewModel.document {
                readerContent(doc)
            }
        }
        .statusBarHidden(!viewModel.showControls)
        .navigationBarHidden(true)
        .ignoresSafeArea()
        .task {
            viewModel.configure(
                bookRepository: container.bookRepository,
                lendingRepository: container.lendingRepository,
                modelContext: modelContext,
                readerPreferences: container.readerPreferences,
                contentProtection: container.inkyomiContentProtection,
                readerSyncCoordinator: container.readerSyncCoordinator
            )
            await viewModel.loadBook()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                viewModel.onBackgrounded()
            case .active:
                viewModel.onForegrounded()
            @unknown default:
                break
            }
        }
        .onDisappear {
            viewModel.closeReader()
        }
        .overlay(alignment: .top) {
            if viewModel.message != nil {
                messageToast
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isTocVisible },
            set: { viewModel.isTocVisible = $0 }
        )) {
            TocSheet(tocItems: viewModel.tocItems) { item in
                viewModel.isTocVisible = false
                navigateToTocItem(item)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isNotesSheetVisible },
            set: { viewModel.isNotesSheetVisible = $0 }
        )) {
            NotesSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isSettingsVisible },
            set: { viewModel.isSettingsVisible = $0 }
        )) {
            ReaderSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingHighlight != nil },
            set: { if !$0 { viewModel.cancelPendingHighlight() } }
        )) {
            if viewModel.pendingHighlight != nil {
                HighlightEditorSheet(viewModel: viewModel)
            }
        }
        .background(keyboardShortcuts)
        .announcesChanges(of: viewModel.message) { $0 }
        .announcesChanges(of: viewModel.error) { $0 }
        .announcesChanges(of: viewModel.isReadAloudPlaying) { $0 ? "Reading aloud" : "Reading paused" }
    }

    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            Button("Previous Page") {
                NotificationCenter.default.post(name: .readerGoBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Page") {
                NotificationCenter.default.post(name: .readerGoForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Toggle Read Aloud") {
                NotificationCenter.default.post(name: .readerReadAloudToggle, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func readerContent(_ doc: ReaderDocument) -> some View {
        ZStack {
            EPUBReaderRepresentable(
                publication: doc.publication,
                initialLocator: doc.initialLocator,
                viewModel: viewModel
            )
            .ignoresSafeArea()

            // Controls overlay
            if viewModel.showControls {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)
        // Center-tap toggles the chrome, which VoiceOver intercepts — give AT users
        // a rotor action to bring the controls back (audit A6).
        .accessibilityAction(named: "Show reader controls") {
            viewModel.showControls = true
        }
        // Reader-level VoiceOver rotor action so a blind reader can start /
        // pause narration from anywhere in the book without finding the
        // on-screen button (which lives in the auto-hiding chrome).
        .accessibilityAction(named: viewModel.isReadAloudPlaying ? "Pause reading aloud" : "Read aloud") {
            viewModel.toggleReadAloud()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .accessibilityLabel("Back")

            Text(viewModel.bookTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button { viewModel.isTocVisible = true } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Table of contents")

            Button { viewModel.isNotesSheetVisible = true } label: {
                Image(systemName: "bookmark")
            }
            .accessibilityLabel("Bookmarks and highlights")

            if viewModel.isReadAloudAvailable {
                Button { viewModel.toggleReadAloud() } label: {
                    Image(systemName: viewModel.isReadAloudPlaying ? "pause.circle.fill" : "play.circle")
                }
                .accessibilityLabel(viewModel.isReadAloudPlaying ? "Pause reading aloud" : "Read aloud")
                .accessibilityHint("Reads the book aloud and turns pages automatically")
            }

            Button { viewModel.isSettingsVisible = true } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityLabel("Reading settings")
        }
        .padding(.horizontal)
        .padding(.top, 50)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .foregroundStyle(.primary)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.progressPercent)
                .tint(Color.inkPrimary)

            Text("\(Int(viewModel.progressPercent * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 30)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int(viewModel.progressPercent * 100)) percent")
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            if viewModel.isDownloading {
                Text("Downloading...")
                    .foregroundStyle(.secondary)
            } else {
                Text("Opening...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Error")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Go Back") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var messageToast: some View {
        Text(viewModel.message ?? "")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    viewModel.consumeMessage()
                }
            }
    }

    // MARK: - Navigation

    private func navigateToTocItem(_ item: TocItem) {
        // Post notification to the navigator representable
        NotificationCenter.default.post(
            name: .readerNavigateToHref,
            object: item.href
        )
    }
}

extension Notification.Name {
    static let readerNavigateToHref = Notification.Name("readerNavigateToHref")
    static let readerAddBookmark = Notification.Name("readerAddBookmark")
    static let readerPreferencesChanged = Notification.Name("readerPreferencesChanged")
    static let readerPageLayoutChanged = Notification.Name("readerPageLayoutChanged")
    static let readerGoBackward = Notification.Name("readerGoBackward")
    static let readerGoForward = Notification.Name("readerGoForward")
    static let readerReadAloudToggle = Notification.Name("readerReadAloudToggle")
    static let readerReadAloudNext = Notification.Name("readerReadAloudNext")
    static let readerReadAloudPrevious = Notification.Name("readerReadAloudPrevious")
    static let focusHomeSearch = Notification.Name("focusHomeSearch")
}
