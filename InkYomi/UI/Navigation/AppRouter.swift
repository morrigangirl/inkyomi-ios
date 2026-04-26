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

    var body: some View {
        if hSizeClass == .regular {
            MainSplitView()
        } else {
            MainTabView()
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
}

// MARK: - Per-tab root NavigationStacks (shared by MainTabView and MainSplitView)

private struct HomeRoot: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(for: String.self) { bookId in
                    BookDetailView(bookId: bookId)
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
