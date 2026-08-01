import ActivityKit
import Foundation

struct DeadlineActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remainingSeconds: Int
        var title: String
        var subject: String
        var isOverdue: Bool
    }

    var deadlineId: String
    var dueInstant: Date
}
