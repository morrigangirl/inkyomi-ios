import SwiftUI

/// Builds a Color that resolves to different RGB values in light vs dark mode.
/// The brand palette was authored for light mode only; the dark variants keep
/// the same hue but lift the value so the colors stay legible as foreground /
/// tint on a dark background (audit H6).
typealias InkRGB = (red: Double, green: Double, blue: Double)

func inkAdaptive(
    light: InkRGB,
    dark: InkRGB,
    lightHighContrast: InkRGB? = nil,
    darkHighContrast: InkRGB? = nil
) -> Color {
    Color(uiColor: UIColor { traits in
        // Honor Increase Contrast (Settings → Accessibility → Display &
        // Text Size → Increase Contrast) when a higher-contrast variant is
        // supplied, otherwise fall back to the standard light/dark value.
        let highContrast = traits.accessibilityContrast == .high
        let c: InkRGB
        if traits.userInterfaceStyle == .dark {
            c = (highContrast ? darkHighContrast : nil) ?? dark
        } else {
            c = (highContrast ? lightHighContrast : nil) ?? light
        }
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    })
}

extension Color {
    // Primary: light-mode navy (#2C3E7A) is near-black on a dark background,
    // so dark mode uses the lighter indigo (#5C6BC0).
    static let inkPrimary = inkAdaptive(
        light: (0.173, 0.243, 0.478),             // #2C3E7A
        dark:  (0.361, 0.420, 0.753),             // #5C6BC0
        lightHighContrast: (0.102, 0.137, 0.494), // #1A237E — deeper navy on white
        darkHighContrast:  (0.624, 0.659, 1.0)    // #9FA8FF — brighter on dark
    )
    static let inkPrimaryLight = Color(red: 0.361, green: 0.420, blue: 0.753)  // #5C6BC0
    static let inkPrimaryDark = Color(red: 0.102, green: 0.137, blue: 0.494)   // #1A237E

    static let inkSecondary = inkAdaptive(
        light: (0.910, 0.337, 0.498),             // #E8567F
        dark:  (1.0, 0.561, 0.639),               // #FF8FA3
        lightHighContrast: (0.678, 0.078, 0.341), // #AD1457 — deeper on white
        darkHighContrast:  (1.0, 0.698, 0.757)    // #FFB2C1 — brighter on dark
    )
    static let inkSecondaryLight = Color(red: 1.0, green: 0.561, blue: 0.639)  // #FF8FA3
    static let inkSecondaryDark = Color(red: 0.690, green: 0.188, blue: 0.310) // #B0304F

    static let inkBackground = Color(red: 1.0, green: 0.984, blue: 0.996)      // #FFFBFE
    static let inkSurface = Color(red: 0.980, green: 0.973, blue: 0.961)       // #FAF8F5

    // Error: light-mode #B3261E is too dark to read on a dark surface; dark
    // mode uses a brighter coral red (#FF8A80).
    static let inkError = inkAdaptive(
        light: (0.702, 0.149, 0.118),             // #B3261E
        dark:  (1.0, 0.541, 0.502),               // #FF8A80
        lightHighContrast: (0.557, 0.0, 0.0),     // #8E0000 — deeper red on white
        darkHighContrast:  (1.0, 0.706, 0.671)    // #FFB4AB — brighter on dark
    )
}

extension Font {
    static let inkTitle = Font.system(.title, design: .default, weight: .bold)
    static let inkHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let inkBody = Font.system(.body, design: .default)
    static let inkCaption = Font.system(.caption, design: .default)
}

/// Prominent primary button with an explicitly visible disabled state.
/// `.borderedProminent`'s disabled fill is a dim system grey that is nearly
/// invisible on a dark background (the reported "can't see the greyed-out
/// Sign In button" case). This keeps the brand color — just dimmed — so the
/// button stays discoverable in both light and dark mode (audit H6).
struct InkProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .tint(.white) // keep the in-button ProgressView spinner visible on the fill
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color.inkPrimary.opacity(isEnabled ? 1.0 : 0.4),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundStyle(.white.opacity(isEnabled ? 1.0 : 0.75))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

extension View {
    /// Posts a screen-reader announcement whenever `value` changes to a
    /// non-empty message. Surfaces status messages (errors, confirmations,
    /// load results) that are otherwise silent for VoiceOver users (WCAG 4.1.3
    /// Status Messages).
    func announcesChanges<Value: Equatable>(
        of value: Value,
        message: @escaping (Value) -> String?
    ) -> some View {
        onChange(of: value) { _, newValue in
            guard let text = message(newValue), !text.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
