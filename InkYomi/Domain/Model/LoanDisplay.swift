import Foundation
import SwiftUI

/// Display-layer projections derived from `LoanInfo`. Lives in the domain
/// layer so the SwiftUI Borrowed-tab cards, the renewal coordinator, and
/// any future notification scheduler all share the same "is this loan
/// urgent?" rules — keeping them aligned with the Android `LoanDisplay`
/// counterpart.
enum LoanUrgency {
    case normal
    case soon
    case urgent
    case overdue

    /// Material 3-equivalent surface tinting for the badge background.
    var backgroundColor: Color {
        switch self {
        case .overdue, .urgent: inkAdaptive(light: (0.980, 0.890, 0.880), dark: (0.320, 0.120, 0.110))
        case .soon: inkAdaptive(light: (0.990, 0.930, 0.800), dark: (0.300, 0.220, 0.050))
        case .normal: Color(.systemGray5)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .overdue, .urgent: inkAdaptive(light: (0.630, 0.100, 0.080), dark: (1.0, 0.620, 0.580))
        case .soon: inkAdaptive(light: (0.500, 0.300, 0.0), dark: (1.0, 0.800, 0.450))
        case .normal: Color.secondary
        }
    }
}

struct LoanDisplay {
    let daysRemaining: Int
    let urgency: LoanUrgency
    let dueLabel: String
    let renewalLabel: String?
}

extension LoanInfo {
    func toDisplay(now: Date = Date()) -> LoanDisplay {
        let calendar = Calendar(identifier: .gregorian)
        let nowDay = calendar.startOfDay(for: now)
        let daysRemaining: Int
        let urgency: LoanUrgency
        let dueLabel: String

        if let due = dueAt {
            let dueDay = calendar.startOfDay(for: due)
            let components = calendar.dateComponents([.day], from: nowDay, to: dueDay)
            daysRemaining = components.day ?? 0

            urgency = switch daysRemaining {
            case ..<0: .overdue
            case 0: .urgent
            case 1...3: .soon
            default: .normal
            }

            dueLabel = switch daysRemaining {
            case let d where d < -1: "\(-d) days overdue"
            case -1: "1 day overdue"
            case 0: "Due today"
            case 1: "Due tomorrow"
            case 2...3: "Due in \(daysRemaining) days"
            default: "\(daysRemaining) days left"
            }
        } else {
            daysRemaining = .max
            urgency = .normal
            dueLabel = "Borrowed"
        }

        let renewalLabel: String? = {
            guard status == .active, maxRenewals > 0 else { return nil }
            let left = maxRenewals - renewedCount
            return switch left {
            case ...0: "No renewals left"
            case 1: "Final renewal available"
            default: "\(left) renewals left"
            }
        }()

        return LoanDisplay(
            daysRemaining: daysRemaining,
            urgency: urgency,
            dueLabel: dueLabel,
            renewalLabel: renewalLabel
        )
    }
}
