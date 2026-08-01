import Foundation
import SwiftData

struct DeadlineFilter {
    var status: String?
    var subject: String?

    init(status: String? = nil, subject: String? = nil) {
        self.status = status?.nilIfEmpty
        self.subject = subject?.nilIfEmpty
    }

    func matches(_ model: DeadlineModel) -> Bool {
        if let status, model.status != status { return false }
        if let subject, model.subject != subject { return false }
        return true
    }

    func sortDescriptors() -> [SortDescriptor<DeadlineModel>] {
           [SortDescriptor(\DeadlineModel.dueDate, order: .forward)]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
