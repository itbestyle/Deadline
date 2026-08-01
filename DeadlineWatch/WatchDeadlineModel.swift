import Foundation

#if os(watchOS)
struct WatchDeadlineModel: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subject: String
    let dueDate: String
    let status: String
    let priority: String
    let pressure: String

    var pressureLevel: WatchPressureLevel {
        WatchPressureLevel(rawValue: pressure) ?? .low
    }
}
#endif

enum WatchPressureLevel: String, Codable {
    case critical
    case medium
    case low

    var title: String {
        switch self {
        case .critical:
            return "High"
        case .medium:
            return "Mid"
        case .low:
            return "Low"
        }
    }

    var symbol: String {
        switch self {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .medium:
            return "exclamationmark.circle.fill"
        case .low:
            return "checkmark.circle.fill"
        }
    }
}
