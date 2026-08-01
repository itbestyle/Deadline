import Foundation
import SwiftData

@Model
final class DeadlineModel {
    @Attribute(.unique) var id: String
    var title: String
    var subject: String
    var dueDate: Date
    var status: String
    var priority: String
    var tags: [String]
    var repeatType: String
    var notes: String
    var reminderTime: String
    var deletedAt: Date?

    var remoteID: String?

    var updatedAt: Date
    var isDirty: Bool
    var isDeleted: Bool

    init(id: String,
         title: String,
         subject: String,
         dueDate: Date,
         status: String,
         priority: String,
         tags: [String],
         repeatType: String = "none",
         notes: String = "",
         reminderTime: String = "1day",
         remoteID: String? = nil,
         updatedAt: Date = Date(),
         isDirty: Bool = false,
         isDeleted: Bool = false,
         deletedAt: Date? = nil) {
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
        self.remoteID = remoteID
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}
