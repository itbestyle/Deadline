import Foundation

struct PressureActionItem: Identifiable {
    let id: String
    let deadline: Deadline
    let due: Date
    let focusMinutes: Int
    let actionHint: String
    let isOverdue: Bool

    var deadlineID: String { deadline.id }
}

struct PressureActionPlan {
    let nextStep: PressureActionItem?
    let todayPlan: [PressureActionItem]
}

/// Builds an actionable next step and a focused daily plan from active deadlines.
struct PressureActionPlanner {
    private let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    private let legacyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    func makePlan(from deadlines: [Deadline], now: Date = Date(), maxTodayItems: Int = 3) -> PressureActionPlan {
        let ranked = rankActive(deadlines, now: now)
        let next = ranked.first
        let today = pickTodayPlan(from: ranked, now: now, maxItems: maxTodayItems, excludingNext: next?.deadlineID)
        return PressureActionPlan(nextStep: next, todayPlan: today)
    }

    // MARK: - Ranking

    private func rankActive(_ deadlines: [Deadline], now: Date) -> [PressureActionItem] {
        deadlines
            .filter { $0.statusType == .inProgress }
            .compactMap { item -> (Deadline, Date)? in
                guard let due = effectiveDueDate(for: item, now: now) else { return nil }
                return (item, due)
            }
            .sorted { lhs, rhs in
                let lhsScore = urgencyScore(due: lhs.1, now: now, priority: lhs.0.resolvedPriority(referenceDate: now))
                let rhsScore = urgencyScore(due: rhs.1, now: now, priority: rhs.0.resolvedPriority(referenceDate: now))
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.1 < rhs.1
            }
            .map { pair in
                let overdue = pair.1 < now
                let remaining = pair.1.timeIntervalSince(now)
                return PressureActionItem(
                    id: pair.0.id,
                    deadline: pair.0,
                    due: pair.1,
                    focusMinutes: focusBlockMinutes(remaining: remaining, overdue: overdue, priority: pair.0.resolvedPriority(referenceDate: now)),
                    actionHint: actionHint(remaining: remaining, overdue: overdue, priority: pair.0.resolvedPriority(referenceDate: now)),
                    isOverdue: overdue
                )
            }
    }

    private func pickTodayPlan(from ranked: [PressureActionItem], now: Date, maxItems: Int, excludingNext: String?) -> [PressureActionItem] {
        let endOfToday = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: now)) ?? now

        var plan: [PressureActionItem] = []
        for item in ranked {
            if item.deadlineID == excludingNext { continue }
            if item.isOverdue || item.due <= endOfToday {
                plan.append(item)
            }
            if plan.count >= maxItems { break }
        }

        if plan.count < maxItems {
            for item in ranked where !plan.contains(where: { $0.deadlineID == item.deadlineID }) && item.deadlineID != excludingNext {
                plan.append(item)
                if plan.count >= maxItems { break }
            }
        }

        return plan
    }

    private func urgencyScore(due: Date, now: Date, priority: String) -> Int {
        let remaining = due.timeIntervalSince(now)
        var score = 0
        if remaining <= 0 { score += 100 }
        else if remaining <= 24 * 3600 { score += 60 }
        else if remaining <= 72 * 3600 { score += 30 }
        else { score += 5 }

        switch priority {
        case "Высокий": score += 20
        case "Средний": score += 10
        case "Низкий": score += 2
        default: break
        }
        return score
    }

    private func focusBlockMinutes(remaining: TimeInterval, overdue: Bool, priority: String) -> Int {
        if overdue { return 25 }
        if remaining <= 3 * 3600 { return 25 }
        if remaining <= 24 * 3600 { return 30 }
        if priority == "Высокий" { return 30 }
        return 45
    }

    private func actionHint(remaining: TimeInterval, overdue: Bool, priority: String) -> String {
        if overdue {
            return PA("Начните с минимального шага и закройте просроченный хвост.")
        }
        if remaining <= 3 * 3600 {
            return PA("Финиш рядом: начни без отвлечений.")
        }
        if remaining <= 24 * 3600 {
            return PA("Закройте самый важный шаг до дедлайна.")
        }
        if priority == "Высокий" {
            return PA("Сделайте первый значимый кусок по задаче.")
        }
        if remaining <= 72 * 3600 {
            return PA("Подготовьте черновик, чтобы снять риск 72 часов.")
        }
        return PA("Запустите первый короткий шаг по задаче.")
    }

    private func effectiveDueDate(for deadline: Deadline, now: Date) -> Date? {
        let base = deadline.normalizedDueDateForRecurrence(referenceDate: now) ?? parse(deadline.dueDate)
        guard let due = base else { return nil }
        if deadline.dueDate.contains(":") { return due }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: due) ?? due
    }

    private func parse(_ value: String) -> Date? {
        parser.date(from: value) ?? legacyParser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private func PA(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
