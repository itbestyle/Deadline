import Foundation
import UIKit

/// Queues widget / Siri actions for the main app to process on next activation.
enum WidgetActionBridge: Sendable {
    static func enqueueComplete(deadlineID: String) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        defaults.set(deadlineID, forKey: WidgetSharedKeys.pendingCompleteKey)
        WidgetAppGroupStore.applyOptimisticComplete(deadlineID: deadlineID)
    }

    static func consumePendingComplete() -> String? {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return nil }
        let id = defaults.string(forKey: WidgetSharedKeys.pendingCompleteKey)
        defaults.removeObject(forKey: WidgetSharedKeys.pendingCompleteKey)
        return id
    }
}

/// Widget extensions cannot drive Taptic Engine reliably; listen for Darwin pings from the widget.
enum WidgetHapticListener {
    private static let token = ListenerToken()

    static func startIfNeeded() {
        guard !token.started else { return }
        token.started = true

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(token).toOpaque(),
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    WidgetHapticListener.playSuccess()
                }
            },
            WidgetSharedKeys.hapticDarwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    static func playSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private final class ListenerToken {
        var started = false
    }
}
