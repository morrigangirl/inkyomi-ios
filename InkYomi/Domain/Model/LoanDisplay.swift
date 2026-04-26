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
        case .overdue, .urgent: Color.red.opacity(0.18)
        case .soon: Color.orange.opacity(0.20)
        case .normal: Color(.systemGray5).opacity(0.85)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .overdue, .urgent: Color.red
        case .soon: Color.orange
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
