import Foundation

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

    var isActive: Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "сдан", "выполнен", "completed", "отменён", "отменен", "canceled", "cancelled":
            return false
        default:
            return true
        }
    }

    var parsedDueDate: Date? {
        WatchDeadlineDate.parse(dueDate)
    }

    func isOverdue(now: Date = Date()) -> Bool {
        guard let due = parsedDueDate else { return false }
        return due < now
    }

    func remainingInterval(now: Date = Date()) -> TimeInterval? {
        guard let due = parsedDueDate else { return nil }
        return due.timeIntervalSince(now)
    }

    /// 0...1 fill toward the due date, using the same 72-hour pressure window as iPhone.
    func pressureProgress(now: Date = Date()) -> Double {
        guard let remaining = remainingInterval(now: now) else { return 0 }
        if remaining <= 0 { return 1 }
        let window: TimeInterval = 72 * 3600
        return min(1, max(0.08, 1 - remaining / window))
    }
}

enum WatchPressureLevel: String, Codable {
    case critical
    case medium
    case low

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }
}

enum WatchDeadlineDate {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
