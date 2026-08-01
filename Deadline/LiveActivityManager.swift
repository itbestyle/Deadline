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

@MainActor
enum LiveActivityManager {
    /// Live Activity starts only inside the final hour before the deadline (overdue tasks included).
    private static let activationWindow: TimeInterval = 3600

    static func sync(with deadlines: [Deadline]) {
        guard #available(iOS 16.2, *) else { return }
        syncActivity(with: deadlines)
    }

    @available(iOS 16.2, *)
    private static func syncActivity(with deadlines: [Deadline]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        guard let snapshot = nearestWithinActivationWindow(from: deadlines) else {
            endAll()
            return
        }

        let state = DeadlineActivityAttributes.ContentState(
            remainingSeconds: max(Int(snapshot.remainingInterval), 0),
            title: snapshot.title,
            subject: snapshot.subject,
            isOverdue: snapshot.remainingInterval <= 0
        )
        let content = ActivityContent(
            state: state,
            staleDate: snapshot.dueInstant,
            relevanceScore: relevanceScore(for: snapshot.remainingInterval)
        )

        if let existing = Activity<DeadlineActivityAttributes>.activities.first(where: { $0.attributes.deadlineId == snapshot.id }) {
            Task {
                await existing.update(content)
            }
            endActivities(except: snapshot.id)
            return
        }

        endAll()

        let attributes = DeadlineActivityAttributes(
            deadlineId: snapshot.id,
            dueInstant: snapshot.dueInstant
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            return
        }
    }

    /// Higher score surfaces the activity in Apple Watch Smart Stack.
    private static func relevanceScore(for remaining: TimeInterval) -> Double {
        if remaining <= 0 { return 100 }
        let progress = 1 - min(max(remaining, 0), activationWindow) / activationWindow
        return 70 + progress * 30
    }

    private static func nearestWithinActivationWindow(from deadlines: [Deadline]) -> WidgetCriticalSnapshot? {
        let active = deadlines.filter { $0.deletedAt == nil && $0.statusType == .inProgress }
        let now = Date()

        let candidates = active.compactMap { deadline -> (WidgetCriticalSnapshot, TimeInterval)? in
            guard let due = deadline.effectiveDueInstant(referenceDate: now) else { return nil }
            let remaining = due.timeIntervalSince(now)
            guard remaining <= activationWindow else { return nil }

            let snapshot = WidgetCriticalSnapshot(
                id: deadline.id,
                title: deadline.title,
                subject: deadline.localizedSubjectName,
                dueInstant: due,
                priority: deadline.resolvedPriority(referenceDate: now),
                updatedAt: now
            )
            return (snapshot, remaining)
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return liveActivityPriorityRank(lhs.0.priority) < liveActivityPriorityRank(rhs.0.priority)
            }
            .first?
            .0
    }

    private static func liveActivityPriorityRank(_ priority: String) -> Int {
        switch priority {
        case "Высокий": return 0
        case "Средний": return 1
        case "Низкий": return 2
        default: return 3
        }
    }

    static func endAll() {
        guard #available(iOS 16.2, *) else { return }
        endAllActivities()
    }

    @available(iOS 16.2, *)
    private static func endAllActivities() {
        endActivities(except: nil)
    }

    @available(iOS 16.2, *)
    private static func endActivities(except keepId: String?) {
        for activity in Activity<DeadlineActivityAttributes>.activities {
            if activity.attributes.deadlineId != keepId {
                Task {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
