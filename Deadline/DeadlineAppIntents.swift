import AppIntents
import Foundation
import UIKit
import WidgetKit

// MARK: - Entities

struct DeadlineEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task")
    static var defaultQuery = DeadlineEntityQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct DeadlineEntityQuery: EntityQuery {
    func entities(for identifiers: [DeadlineEntity.ID]) async throws -> [DeadlineEntity] {
        let all = await DeadlineIntentStore.shared.snapshot()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DeadlineEntity] {
        await DeadlineIntentStore.shared.snapshot()
    }
}

// MARK: - In-memory snapshot for intents

actor DeadlineIntentStore {
    static let shared = DeadlineIntentStore()
    private var items: [DeadlineEntity] = []

    func update(from deadlines: [Deadline]) {
        items = deadlines
            .filter { $0.deletedAt == nil && DeadlineStatus(rawStatus: $0.status) == .inProgress }
            .prefix(20)
            .map { DeadlineEntity(id: $0.id, title: $0.title) }
    }

    func snapshot() -> [DeadlineEntity] {
        items
    }
}

// MARK: - Intents

struct CompleteDeadlineIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить задачу выполненной"
    static var description = IntentDescription("Завершает выбранную задачу в Redloop.")

    @Parameter(title: "Задача")
    var deadline: DeadlineEntity

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let deadlineID = deadline.id
        await MainActor.run {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
            WidgetActionBridge.enqueueComplete(deadlineID: deadlineID)
            NotificationCenter.default.post(
                name: .deadlineExternalAction,
                object: nil,
                userInfo: ["action": "complete", "id": deadlineID]
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Done")
    }
}

struct ListUrgentDeadlinesIntent: AppIntent {
    static var title: LocalizedStringResource = "Что горит сегодня"
    static var description = IntentDescription("Показывает срочные задачи на ближайшие 72 часа.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let entities = await DeadlineIntentStore.shared.snapshot()
        if entities.isEmpty {
            return .result(dialog: "No urgent tasks")
        }
        let names = entities.prefix(3).map(\.title).joined(separator: ", ")
        return .result(dialog: "\(names)")
    }
}

struct OpenPressureModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть режим давления"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .deadlineExternalAction,
                object: nil,
                userInfo: ["action": "openPressure"]
            )
        }
        return .result()
    }
}

struct RedloopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ListUrgentDeadlinesIntent(),
            phrases: [
                "What's urgent in \(.applicationName)",
                "Show urgent tasks in \(.applicationName)"
            ],
            shortTitle: "Urgent tasks",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: OpenPressureModeIntent(),
            phrases: [
                "Open pressure mode in \(.applicationName)"
            ],
            shortTitle: "Pressure mode",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }
}

extension Notification.Name {
    nonisolated static let deadlineExternalAction = Notification.Name("deadline.external.action")
}
