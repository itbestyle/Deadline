import Foundation

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

enum WidgetSharedKeys: Sendable {
    static let suiteName = "group.tic-tac-toe.Deadline"
    static let criticalSnapshotKey = "widget.critical.snapshot"
    static let pendingCompleteKey = "widget.pending.complete.id"
    static let locallyCompletedIDsKey = "widget.locally.completed.ids"
    static let hapticDarwinNotification = "group.tic-tac-toe.Deadline.widget.haptic"
}

enum WidgetAppGroupStore: Sendable {
    static func saveCritical(_ snapshot: WidgetCriticalSnapshot?) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.suiteName) else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetSharedKeys.criticalSnapshotKey)
        } else {
            defaults.removeObject(forKey: WidgetSharedKeys.criticalSnapshotKey)
        }
    }

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

    static func applyOptimisticComplete(deadlineID: String) {
        markLocallyCompleted(id: deadlineID)
        if let snapshot = loadCritical(), snapshot.id == deadlineID {
            saveCritical(nil)
        }
    }
}

@MainActor
enum WidgetCriticalSnapshotBuilder {
    static func nearestCritical(from deadlines: [Deadline]) -> WidgetCriticalSnapshot? {
        let active = deadlines.filter { $0.deletedAt == nil && $0.statusType == .inProgress }
        let now = Date()

        let ranked = active.compactMap { deadline -> (Deadline, Date, String)? in
            guard let due = deadline.effectiveDueInstant(referenceDate: now) else { return nil }
            let priority = deadline.resolvedPriority(referenceDate: now)
            return (deadline, due, priority)
        }
        .sorted { lhs, rhs in
            let lhsRank = priorityRank(lhs.2)
            let rhsRank = priorityRank(rhs.2)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.1 < rhs.1
        }

        guard let best = ranked.first else { return nil }
        let (deadline, due, priority) = best
        return WidgetCriticalSnapshot(
            id: deadline.id,
            title: deadline.title,
            subject: deadline.localizedSubjectName,
            dueInstant: due,
            priority: priority,
            updatedAt: now
        )
    }

    private static func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "Высокий": return 0
        case "Средний": return 1
        case "Низкий": return 2
        default: return 3
        }
    }
}
