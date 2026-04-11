import SwiftUI

enum TabRoute: Int, CaseIterable, Identifiable {
    case home
    case library
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .library: "books.vertical.fill"
        case .settings: "gearshape.fill"
        }
    }
}
