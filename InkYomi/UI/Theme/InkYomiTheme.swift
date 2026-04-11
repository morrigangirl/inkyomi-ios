import SwiftUI

extension Color {
    static let inkPrimary = Color(red: 0.173, green: 0.243, blue: 0.478)       // #2C3E7A
    static let inkPrimaryLight = Color(red: 0.361, green: 0.420, blue: 0.753)  // #5C6BC0
    static let inkPrimaryDark = Color(red: 0.102, green: 0.137, blue: 0.494)   // #1A237E

    static let inkSecondary = Color(red: 0.910, green: 0.337, blue: 0.498)     // #E8567F
    static let inkSecondaryLight = Color(red: 1.0, green: 0.561, blue: 0.639)  // #FF8FA3
    static let inkSecondaryDark = Color(red: 0.690, green: 0.188, blue: 0.310) // #B0304F

    static let inkBackground = Color(red: 1.0, green: 0.984, blue: 0.996)      // #FFFBFE
    static let inkSurface = Color(red: 0.980, green: 0.973, blue: 0.961)       // #FAF8F5

    static let inkError = Color(red: 0.702, green: 0.149, blue: 0.118)         // #B3261E
}

extension Font {
    static let inkTitle = Font.system(.title, design: .default, weight: .bold)
    static let inkHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let inkBody = Font.system(.body, design: .default)
    static let inkCaption = Font.system(.caption, design: .default)
}
