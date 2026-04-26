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
                MainTabView()
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

struct MainTabView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var selectedTab: TabRoute = .home
    @State private var showingReader = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(TabRoute.allCases) { tab in
                tabContent(for: tab)
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
    private func tabContent(for tab: TabRoute) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView()
                    .navigationDestination(for: String.self) { bookId in
                        BookDetailView(bookId: bookId)
                    }
            }
        case .library:
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
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }
}
