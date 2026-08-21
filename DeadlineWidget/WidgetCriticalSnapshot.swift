import Foundation
import SwiftUI
import WidgetKit

struct WidgetCriticalSnapshot: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let subject: String
    let dueInstant: Date
    let priority: String
    let updatedAt: Date

    var remainingInterval: TimeInterval {
        dueInstant.timeIntervalSinceNow
    }

    var isCritical: Bool {
        priority == "Высокий" || remainingInterval <= 24 * 3600
    }
}

/// A single active deadline published to the App Group so widgets can render
/// without hitting the network. Recurrence and auto-priority are already resolved.
struct WidgetListEntry: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let subject: String
    let dueInstant: Date
    let priority: String
    let hasExplicitTime: Bool
}

enum WidgetSharedKeys: Sendable {
    static let suiteName = "group.tic-tac-toe.Deadline"
    static let criticalSnapshotKey = "widget.critical.snapshot"
    static let pendingCompleteKey = "widget.pending.complete.id"
    static let locallyCompletedIDsKey = "widget.locally.completed.ids"
    static let activeListKey = "widget.active.list"
    static let hapticDarwinNotification = "group.tic-tac-toe.Deadline.widget.haptic"
}

enum WidgetAppGroupStore: Sendable {
    static func loadCritical() -> WidgetCriticalSnapshot? {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName),
              let data = defaults.data(forKey: WidgetSharedKeys.criticalSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetCriticalSnapshot.self, from: data)
    }

    static func loadVisibleCritical() -> WidgetCriticalSnapshot? {
        guard let snapshot = loadCritical() else { return nil }
        if locallyCompletedIDs().contains(snapshot.id) { return nil }
        return snapshot
    }

    static func saveCritical(_ snapshot: WidgetCriticalSnapshot?) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetSharedKeys.criticalSnapshotKey)
        } else {
            defaults.removeObject(forKey: WidgetSharedKeys.criticalSnapshotKey)
        }
    }

    static func markLocallyCompleted(id: String) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        var ids = Set(defaults.stringArray(forKey: WidgetSharedKeys.locallyCompletedIDsKey) ?? [])
        ids.insert(id)
        defaults.set(Array(ids), forKey: WidgetSharedKeys.locallyCompletedIDsKey)
    }

    static func locallyCompletedIDs() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return [] }
        return Set(defaults.stringArray(forKey: WidgetSharedKeys.locallyCompletedIDsKey) ?? [])
    }

    static func clearLocallyCompleted(id: String) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        var ids = Set(defaults.stringArray(forKey: WidgetSharedKeys.locallyCompletedIDsKey) ?? [])
        ids.remove(id)
        if ids.isEmpty {
            defaults.removeObject(forKey: WidgetSharedKeys.locallyCompletedIDsKey)
        } else {
            defaults.set(Array(ids), forKey: WidgetSharedKeys.locallyCompletedIDsKey)
        }
    }

    static func saveActiveList(_ entries: [WidgetListEntry]) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        if entries.isEmpty {
            defaults.removeObject(forKey: WidgetSharedKeys.activeListKey)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: WidgetSharedKeys.activeListKey)
        }
    }

    static func loadActiveList() -> [WidgetListEntry] {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName),
              let data = defaults.data(forKey: WidgetSharedKeys.activeListKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetListEntry].self, from: data)) ?? []
    }

    static func loadVisibleActiveList() -> [WidgetListEntry] {
        let hidden = locallyCompletedIDs()
        return loadActiveList().filter { !hidden.contains($0.id) }
    }

    static func applyOptimisticComplete(deadlineID: String) {
        markLocallyCompleted(id: deadlineID)
        if let snapshot = loadCritical(), snapshot.id == deadlineID {
            saveCritical(nil)
        }
    }
}

enum WidgetCountdownFormatter {
    static func countdownText(until dueInstant: Date, reference: Date = Date()) -> String {
        let remaining = dueInstant.timeIntervalSince(reference)
        if remaining <= 0 {
            let overdue = abs(remaining)
            return "−" + durationText(overdue)
        }
        return durationText(remaining)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours >= 48 {
            let days = hours / 24
            return "\(days)д \(hours % 24)ч"
        }
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func isOverdue(dueInstant: Date, reference: Date = Date()) -> Bool {
        dueInstant <= reference
    }
}

/// Live countdown rendered by the system (updates every second without new timeline entries).
struct WidgetLiveCountdownText: View {
    let dueInstant: Date
    var reference: Date = Date()
    var font: Font = .body
    var upcomingColor: Color = .orange
    var overdueColor: Color = .red
    var alignment: Alignment = .leading

    private var isOverdue: Bool {
        WidgetCountdownFormatter.isOverdue(dueInstant: dueInstant, reference: reference)
    }

    var body: some View {
        Group {
            if isOverdue {
                Text(dueInstant, style: .timer)
                    .foregroundStyle(overdueColor)
            } else {
                Text(timerInterval: reference...dueInstant, countsDown: true)
                    .foregroundStyle(upcomingColor)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}
