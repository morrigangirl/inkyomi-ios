import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        Group {
            switch appState.authState {
            case .loading:
                ProgressView("Loading...")
                    .task {
                        await container.authRepository.restoreSession()
                    }
            case .unauthenticated:
                AuthNavHost()
            case .authenticated:
                AdaptiveMainShell()
            }
        }
    }
}

struct AuthNavHost: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LoginView(navigateToForgotPassword: {
                path.append(AuthRoute.forgotPassword)
            })
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .forgotPassword:
                    ForgotPasswordView()
                }
            }
        }
    }
}

enum AuthRoute: Hashable {
    case forgotPassword
}

/// Picks `TabView` on compact (iPhone, iPad Split View ≤ 1/3) and
/// `NavigationSplitView` on regular (iPad full / wide split).
struct AdaptiveMainShell: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        Group {
            if hSizeClass == .regular {
                MainSplitView()
            } else {
                MainTabView()
            }
        }
        .task {
            // Register this device with the server so it shows up in
            // Settings → Devices with the correct platform string.
            // Without this, login's auto-create row falls back to the
            // server's default platform ("android") for iOS devices.
            // Best-effort — we'll retry on next launch on failure.
            try? await container.deviceRepository.ensureRegistered()
        }
    }
}

struct MainTabView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var selectedTab: TabRoute = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(TabRoute.allCases) { tab in
                tabRoot(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .tint(Color.inkPrimary)
        .background(tabShortcuts)
        .task {
            // Foreground half of the silent renewal pair (the other being
            // the 24h `LoanRenewalScheduler` BGProcessingTask). Fired once
            // when the app surfaces in an authenticated state. Best-effort,
            // never blocks the UI, never surfaces errors — the on-open
            // auto-renew is the last-resort safety net.
            await container.loanRenewalCoordinator.renewExpiringSoon()
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: TabRoute) -> some View {
        switch tab {
        case .home:     HomeRoot()
        case .library:  LibraryRoot()
        case .settings: SettingsRoot()
        }
    }

    private var tabShortcuts: some View {
        HStack(spacing: 0) {
            Button("Home")     { selectedTab = .home }    .keyboardShortcut("1", modifiers: .command)
            Button("Library")  { selectedTab = .library } .keyboardShortcut("2", modifiers: .command)
            Button("Settings") { selectedTab = .settings }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

struct MainSplitView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var selection: TabRoute? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(TabRoute.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("InkYomi")
        } detail: {
            if let selection {
                tabRoot(for: selection)
            } else {
                ContentUnavailableView("Pick a section", systemImage: "sidebar.left")
            }
        }
        .tint(Color.inkPrimary)
        .background(splitShortcuts)
        .task {
            await container.loanRenewalCoordinator.renewExpiringSoon()
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: TabRoute) -> some View {
        switch tab {
        case .home:     HomeRoot()
        case .library:  LibraryRoot()
        case .settings: SettingsRoot()
        }
    }

    private var splitShortcuts: some View {
        HStack(spacing: 0) {
            Button("Home")     { selection = .home }    .keyboardShortcut("1", modifiers: .command)
            Button("Library")  { selection = .library } .keyboardShortcut("2", modifiers: .command)
            Button("Settings") { selection = .settings }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

// MARK: - Per-tab root NavigationStacks (shared by MainTabView and MainSplitView)

private struct HomeRoot: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: String.self) { bookId in
                    BookDetailView(bookId: bookId)
                }
                .navigationDestination(for: SearchRoute.self) { route in
                    switch route {
                    case .searchOverlay:
                        SearchView(
                            onSubmitQuery: { query in
                                path.append(SearchRoute.results(query: query))
                            },
                            onApplySavedSearch: { savedSearchId in
                                path.append(SearchRoute.results(savedSearchId: savedSearchId))
                            }
                        )
                    case .results(let q, let tagType, let tagSlug, let authorId, let seriesId, let savedSearchId):
                        SearchResultsView(
                            initialQuery: q,
                            prefilledTagType: tagType,
                            prefilledTagSlug: tagSlug,
                            authorId: authorId,
                            seriesId: seriesId,
                            savedSearchId: savedSearchId
                        )
                    case .resultsWithFilters(let filters, let label):
                        SearchResultsView(
                            prefilledTagFilters: filters,
                            titleOverride: label
                        )
                    }
                }
        }
    }
}

private struct LibraryRoot: View {
    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationDestination(for: String.self) { bookId in
                    BookDetailView(bookId: bookId)
                }
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .lendingCatalog:
                        LendingCatalogView()
                    }
                }
        }
    }
}

private struct SettingsRoot: View {
    var body: some View {
        NavigationStack {
            SettingsView()
        }
    }
}
