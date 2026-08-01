import AppIntents
import AudioToolbox
import WidgetKit

struct CompleteDeadlineWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить выполненной"
    static var description = IntentDescription("Завершает задачу из виджета.")

    @Parameter(title: "ID")
    var deadlineID: String

    init() {}

    init(deadlineID: String) {
        self.deadlineID = deadlineID
    }

    func perform() async throws -> some IntentResult {
        WidgetHapticSignal.fireCompleteAction()

        if let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) {
            defaults.set(deadlineID, forKey: WidgetSharedKeys.pendingCompleteKey)
        }
        WidgetAppGroupStore.applyOptimisticComplete(deadlineID: deadlineID)

        // Brief pause so the pressed button state is visible before the row reloads.
        try await Task.sleep(for: .milliseconds(120))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private enum WidgetHapticSignal {
    static func fireCompleteAction() {
        AudioServicesPlaySystemSound(1520)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(WidgetSharedKeys.hapticDarwinNotification as CFString),
            nil,
            nil,
            true
        )
    }
}
