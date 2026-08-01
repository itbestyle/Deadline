import Foundation

struct WatchDeadlinePayload: Codable {
    let id: String
    let title: String
    let subject: String
    let dueDate: String
    let status: String
    let priority: String
    let pressure: String
}

enum WatchActionType: String {
    case complete
    case restore
    case archive
}

extension Notification.Name {
    static let watchActionReceived = Notification.Name("watchActionReceived")
}
