import Foundation

enum ReminderFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Bi-weekly"
        case .monthly:
            return "Monthly"
        }
    }
    
    var dateComponents: DateComponents {
        switch self {
        case .weekly:
            return DateComponents(day: 7)
        case .biweekly:
            return DateComponents(day: 14)
        case .monthly:
            return DateComponents(month: 1)
        }
    }
}