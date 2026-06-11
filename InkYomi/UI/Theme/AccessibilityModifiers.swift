import SwiftUI

// MARK: - Reduce Transparency

/// Background that respects the **Reduce Transparency** setting: the
/// translucent `Material` is swapped for an opaque fill when the user enables
/// it, so overlaid chrome (reader bars, toasts, cards) stays legible.
private struct AdaptiveMaterialBackground<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: Material
    let opaque: Color
    let shape: S

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(opaque, in: shape)
        } else {
            content.background(material, in: shape)
        }
    }
}

extension View {
    /// A translucent `material` background that becomes opaque under Reduce
    /// Transparency. Replaces bare `.background(.ultraThinMaterial)`.
    func adaptiveMaterial(
        _ material: Material = .ultraThinMaterial,
        opaque: Color = Color(.systemBackground),
        in shape: some Shape = Rectangle()
    ) -> some View {
        modifier(AdaptiveMaterialBackground(material: material, opaque: opaque, shape: shape))
    }
}

// MARK: - Reduce Motion

extension View {
    /// Applies `animation` to `value` changes only when **Reduce Motion** is
    /// off; otherwise the change is instant.
    func accessibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
