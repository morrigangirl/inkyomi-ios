import SwiftUI

/// Centralized size tokens that adapt to the current `horizontalSizeClass`.
/// Use these instead of hardcoded widths so the same view scales sensibly
/// from iPhone (compact) to iPad (regular) and Split View on iPad.
enum CoverSize {
    case thumb        // 60×90 compact / 80×120 regular  — search rows, list cells
    case continueRow  // 100×150 compact / 130×195 regular — Continue Reading carousel
    case shelf        // 120×180 compact / 160×240 regular — featured shelves
    case detail       // 140×210 compact / 220×330 regular — book detail header
}

extension CoverSize {
    func width(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let isRegular = sizeClass == .regular
        switch self {
        case .thumb:        return isRegular ? 80  : 60
        case .continueRow:  return isRegular ? 130 : 100
        case .shelf:        return isRegular ? 160 : 120
        case .detail:       return isRegular ? 220 : 140
        }
    }

    func height(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        // 2:3 portrait aspect, matching book cover convention.
        width(for: sizeClass) * 1.5
    }
}

enum HeroHeight {
    static func height(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 320 : 200
    }
}

enum GridColumns {
    /// Min/max width for `LazyVGrid(.adaptive(...))` library/lending grids.
    static func adaptiveRange(for sizeClass: UserInterfaceSizeClass?) -> (min: CGFloat, max: CGFloat) {
        sizeClass == .regular ? (160, 200) : (140, 180)
    }

    /// For thumbnail grids (smaller items).
    static func adaptiveThumbRange(for sizeClass: UserInterfaceSizeClass?) -> (min: CGFloat, max: CGFloat) {
        sizeClass == .regular ? (120, 160) : (100, 140)
    }
}

enum ContentMaxWidth {
    /// Cap content width on iPad so prose / detail views don't stretch the
    /// full screen width and become uncomfortable to read. nil = no cap.
    static func reading(for sizeClass: UserInterfaceSizeClass?) -> CGFloat? {
        sizeClass == .regular ? 720 : nil
    }
}
