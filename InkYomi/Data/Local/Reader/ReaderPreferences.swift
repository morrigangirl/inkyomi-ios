import Foundation
import Observation

/// UserDefaults-backed reader settings.
@MainActor @Observable
final class ReaderPreferences {
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "reader.fontSize") }
    }
    var lineHeight: Double {
        didSet { UserDefaults.standard.set(lineHeight, forKey: "reader.lineHeight") }
    }
    var pageMargins: Double {
        didSet { UserDefaults.standard.set(pageMargins, forKey: "reader.pageMargins") }
    }
    var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: "reader.fontFamily") }
    }
    var theme: ReaderTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "reader.theme") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.fontSize = defaults.object(forKey: "reader.fontSize") as? Double ?? 1.0
        self.lineHeight = defaults.object(forKey: "reader.lineHeight") as? Double ?? 1.4
        self.pageMargins = defaults.object(forKey: "reader.pageMargins") as? Double ?? 16.0
        self.fontFamily = defaults.string(forKey: "reader.fontFamily") ?? "System"
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .light
    }
}

enum ReaderTheme: String, CaseIterable, Sendable {
    case light = "light"
    case sepia = "sepia"
    case dark = "dark"
}
