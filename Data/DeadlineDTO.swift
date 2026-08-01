import Foundation

struct DeadlineDTO: Identifiable {
    var id: String
    var remoteID: String?
    var title: String
    var subject: String
    var dueDate: Date
    var status: String
    var priority: String
    var tags: [String]
    var repeatType: String
    var notes: String
    var reminderTime: String
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var isDeleted: Bool
}

extension DeadlineDTO {
    init(model: DeadlineModel) {
        id = model.id
        remoteID = model.remoteID
        title = model.title
        subject = model.subject
        dueDate = model.dueDate
        status = model.status
        priority = model.priority
        tags = model.tags
        repeatType = model.repeatType
        notes = model.notes
        reminderTime = model.reminderTime
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
        isDirty = model.isDirty
        isDeleted = model.isDeleted
    }

    func apply(to model: DeadlineModel) {
        model.title = title
        model.subject = subject
        model.dueDate = dueDate
        model.status = status
        model.priority = priority
        model.tags = tags
        model.repeatType = repeatType
        model.notes = notes
        model.reminderTime = reminderTime
        model.remoteID = remoteID
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
        model.isDirty = isDirty
        model.isDeleted = isDeleted
    }
}
