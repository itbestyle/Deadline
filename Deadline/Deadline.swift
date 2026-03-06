import Foundation

enum DeadlineStatus: String, Codable, CaseIterable {
    case inProgress = "в процессе"
    case completed = "сдан"
    case cancelled = "отменён"

    init(rawStatus: String) {
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "сдан", "выполнен", "completed":
            self = .completed
        case "отменён", "отменен", "canceled", "cancelled":
            self = .cancelled
        default:
            self = .inProgress
        }
    }

    var sortOrder: Int {
        switch self {
        case .inProgress: return 0
        case .completed: return 1
        case .cancelled: return 2
        }
    }
}

struct Deadline: Identifiable, Codable {
    let id: String
    var title: String
    var subject: String
    var dueDate: String
    var status: String
    var priority: String
    var tags: [String]
    var repeatType: String // none, daily, weekly, monthly, yearly
    var notes: String
    var reminderTime: String // none, 1hour, 1day, 1week
    var deletedAt: Date?
    
    init(id: String, title: String, subject: String, dueDate: String, status: String, priority: String = "Средний", tags: [String] = [], repeatType: String = "none", notes: String = "", reminderTime: String = "1day", deletedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.subject = subject
        self.dueDate = dueDate
        self.status = status
        self.priority = priority
        self.tags = tags
        self.repeatType = repeatType
        self.notes = notes
        self.reminderTime = reminderTime
        self.deletedAt = deletedAt
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, title, subject, dueDate, status, priority, tags, repeatType, notes, reminderTime, deletedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subject = try container.decode(String.self, forKey: .subject)
        dueDate = try container.decode(String.self, forKey: .dueDate)
        status = try container.decode(String.self, forKey: .status)
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? "Средний"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        repeatType = try container.decodeIfPresent(String.self, forKey: .repeatType) ?? "none"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        reminderTime = try container.decodeIfPresent(String.self, forKey: .reminderTime) ?? "1day"
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subject, forKey: .subject)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(tags, forKey: .tags)
        try container.encode(repeatType, forKey: .repeatType)
        try container.encode(notes, forKey: .notes)
        try container.encode(reminderTime, forKey: .reminderTime)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    static let empty = Deadline(id: "", title: "", subject: "", dueDate: "", status: "в процессе", priority: "Средний", tags: [], repeatType: "none", notes: "", reminderTime: "1day", deletedAt: nil)
}

extension Deadline {
    var statusType: DeadlineStatus {
        get { DeadlineStatus(rawStatus: status) }
        set { status = newValue.rawValue }
    }

    var hasTimeInDueDate: Bool {
        dueDate.contains(":")
    }

    func parsedDueDate() -> Date? {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.dateFormat = "yyyy-MM-dd"

        return inputFormatter.date(from: dueDate) ?? legacyFormatter.date(from: dueDate)
    }

    func normalizedDueDateForRecurrence(referenceDate: Date = Date()) -> Date? {
        guard var candidate = parsedDueDate() else { return nil }
        guard repeatType != "none" else { return candidate }

        let calendar = Calendar.current
        let reference = hasTimeInDueDate ? referenceDate : calendar.startOfDay(for: referenceDate)
        if !hasTimeInDueDate {
            candidate = calendar.startOfDay(for: candidate)
        }

        guard candidate < reference else { return candidate }

        // Cap iterations to avoid accidental infinite loops on malformed data.
        for _ in 0..<600 {
            guard candidate < reference else { break }
            switch repeatType {
            case "daily":
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            case "weekly":
                candidate = calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
            case "monthly":
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            case "yearly":
                candidate = calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
            default:
                return parsedDueDate()
            }
        }

        return candidate
    }
}
