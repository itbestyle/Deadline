import BackgroundTasks
import Foundation
import SwiftData

enum ArchiveCleanupService {
    static let taskIdentifier = "com.deadlines.archiveCleanup"
    private static let cleanupInterval: TimeInterval = 12 * 60 * 60
    private static let baseURL = URL(string: "https://deadlines-api-744471608721.europe-west1.run.app")!

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: cleanupInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        guard let container = makeContainer() else { return }
        let context = ModelContext(container)
        let api = DeadlineAPI(baseURL: baseURL)
        let repository = DeadlineRepository(context: context, api: api)

        let now = Date()
        let all = (try? repository.fetchLocal(filter: DeadlineFilter())) ?? []
        var hasChanges = false

        for model in all {
            let status = DeadlineStatus(rawStatus: model.status)
            guard status == .completed || status == .cancelled else { continue }
            let archiveDate = model.deletedAt ?? model.updatedAt
            if model.deletedAt == nil {
                model.deletedAt = archiveDate
                hasChanges = true
            }
            if now.timeIntervalSince(archiveDate) > 60 * 60 * 24 * 30 {
                try? repository.markDeleted(id: model.id)
                hasChanges = true
            }
        }

        if hasChanges {
            try? repository.saveChanges()
            if AuthService.shared.token != nil {
                try? await repository.syncWithServer()
            }
        }
    }

    @MainActor
    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([DeadlineModel.self])
        let storeURL = URL.applicationSupportDirectory.appending(path: "deadlines_v2.store")
        let config = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            await run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
