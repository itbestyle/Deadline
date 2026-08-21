import Foundation

struct WeeklyPressureReport {
    let totalActive: Int
    let criticalCount: Int
    let mediumCount: Int
    let overdueCount: Int
    let completedLast7Days: Int
    let overloadIndex: Int
    let previousOverloadIndex: Int
    let overloadDeltaPercent: Int
    let overloadDayLabel: String?
    let weekAssessment: String
    let weekAssessmentReason: String
    let noOverdueStreakWeeks: Int
    let insights: [String]
}

struct PressureInsightsEngine {
    private struct WeeklyMetrics {
        let critical: Int
        let medium: Int
        let overdue: Int
        let completedLast7Days: Int
        let overloadIndex: Int
        let peakWeekday: Int?
        let peakCount: Int
    }

    private let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    private let legacyParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    func makeReport(from deadlines: [Deadline], now: Date = Date()) -> WeeklyPressureReport {
        let active = deadlines.filter { $0.statusType == .inProgress }
        let activePairs = active.compactMap { item -> (Deadline, Date)? in
            guard let due = effectiveDueDate(for: item, now: now) else { return nil }
            return (item, due)
        }

        let current = makeMetrics(from: deadlines, activePairs: activePairs, now: now)
        let previousNow = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let previous = makeMetrics(from: deadlines, activePairs: activePairs, now: previousNow)

        let overloadLabel = current.peakWeekday.map { weekdayName($0) }
        let overloadDeltaPercent: Int = {
            guard previous.overloadIndex > 0 else {
                return current.overloadIndex > 0 ? 100 : 0
            }
            return ((current.overloadIndex - previous.overloadIndex) * 100) / previous.overloadIndex
        }()

        let weekAssessment: String = {
            if current.overdue > 0 || current.critical > 0 || current.overloadIndex >= 55 {
                return L("Неделя в зоне риска")
            }
            return L("Неделя под контролем")
        }()

        let weekAssessmentReason: String = {
            if weekAssessment == L("Неделя в зоне риска") {
                var parts: [String] = []
                if current.critical > 0 {
                    parts.append(String(format: L("критичных задач: %d"), current.critical))
                }
                if overloadDeltaPercent > 0 {
                    parts.append(String(format: L("рост давления: +%d%%"), abs(overloadDeltaPercent)))
                }
                if current.overdue > 0 {
                    parts.append(String(format: L("просрочено: %d"), current.overdue))
                }
                return parts.isEmpty ? L("требуется внимание к срокам") : parts.joined(separator: " · ")
            }

            if overloadDeltaPercent < 0 {
                return String(format: L("давление снизилось на %d%%, критичных задач нет"), abs(overloadDeltaPercent))
            }
            return L("критичных задач нет, нагрузка стабильна")
        }()

        let noOverdueStreakWeeks = makeNoOverdueStreakWeeks(from: activePairs, now: now)

        var insights: [String] = []
        if current.critical > 0 {
            insights.append(String(format: L("%d задача станет критической в течение 24 часов"), current.critical))
        }
        if let peakDay = current.peakWeekday, current.peakCount >= 3 {
            insights.append(String(format: L("Риск перегруза в %@: до %d задач в один день"), weekdayName(peakDay), current.peakCount))
        }
        if current.overdue > 0 {
            insights.append(String(format: L("Есть %d просроченных задач — закройте их сегодня"), current.overdue))
        }
        if overloadDeltaPercent > 0 {
            insights.append(String(format: L("Давление выросло на %d%% к прошлой неделе"), abs(overloadDeltaPercent)))
        } else if overloadDeltaPercent < 0 {
            insights.append(String(format: L("Давление снизилось на %d%% к прошлой неделе"), abs(overloadDeltaPercent)))
        }
        if noOverdueStreakWeeks >= 3 {
            insights.append(String(format: L("%d недели без просрочек — сильная дисциплина"), noOverdueStreakWeeks))
        } else if current.completedLast7Days >= 3 {
            insights.append(String(format: L("Сильная динамика: за 7 дней вы закрыли %d задач"), current.completedLast7Days))
        }
        if insights.isEmpty {
            insights.append(L("Нагрузка под контролем, критических рисков на неделю не видно"))
        }

        return WeeklyPressureReport(
            totalActive: active.count,
            criticalCount: current.critical,
            mediumCount: current.medium,
            overdueCount: current.overdue,
            completedLast7Days: current.completedLast7Days,
            overloadIndex: current.overloadIndex,
            previousOverloadIndex: previous.overloadIndex,
            overloadDeltaPercent: overloadDeltaPercent,
            overloadDayLabel: overloadLabel,
            weekAssessment: weekAssessment,
            weekAssessmentReason: weekAssessmentReason,
            noOverdueStreakWeeks: noOverdueStreakWeeks,
            insights: insights
        )
    }

    private func makeMetrics(from deadlines: [Deadline], activePairs: [(Deadline, Date)], now: Date) -> WeeklyMetrics {
        let critical = activePairs.filter { $0.1.timeIntervalSince(now) <= 24 * 3600 }.count
        let medium = activePairs.filter {
            let remaining = $0.1.timeIntervalSince(now)
            return remaining > 24 * 3600 && remaining <= 72 * 3600
        }.count
        let overdue = activePairs.filter { $0.1 < now }.count

        let completedLast7Days = deadlines.filter {
            guard $0.statusType == .completed, let due = parse($0.dueDate) else { return false }
            let from = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            return due >= from && due <= now
        }.count

        let upperBound = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let next7Days = activePairs.filter { $0.1 >= now && $0.1 <= upperBound }

        var dayBuckets: [Int: Int] = [:]
        for (_, due) in next7Days {
            let day = Calendar.current.component(.weekday, from: due)
            dayBuckets[day, default: 0] += 1
        }

        let peak = dayBuckets.max(by: { $0.value < $1.value })
        let overloadIndex = min(((critical * 40) + (medium * 20) + (overdue * 30) + max((peak?.value ?? 0) - 2, 0) * 10), 100)

        return WeeklyMetrics(
            critical: critical,
            medium: medium,
            overdue: overdue,
            completedLast7Days: completedLast7Days,
            overloadIndex: overloadIndex,
            peakWeekday: peak?.key,
            peakCount: peak?.value ?? 0
        )
    }

    private func makeNoOverdueStreakWeeks(from activePairs: [(Deadline, Date)], now: Date) -> Int {
        guard !activePairs.isEmpty else { return 0 }

        let calendar = Calendar.current
        let startOfCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let earliestDue = activePairs.map { $0.1 }.min() ?? now
        let startOfEarliestWeek = calendar.dateInterval(of: .weekOfYear, for: earliestDue)?.start ?? earliestDue

        let elapsedSeconds = max(startOfCurrentWeek.timeIntervalSince(startOfEarliestWeek), 0)
        let historyWeeks = Int(elapsedSeconds / (7 * 24 * 3600)) + 1
        let maxWeeks = min(12, max(1, historyWeeks))

        var streak = 0

        for offset in 0..<maxWeeks {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * offset, to: startOfCurrentWeek),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }

            let weekHasAnyDeadlines = activePairs.contains { _, due in
                due >= weekStart && due < weekEnd
            }

            if !weekHasAnyDeadlines {
                break
            }

            let hasOverdueInWeek = activePairs.contains { _, due in
                due >= weekStart && due < weekEnd && due < now
            }

            if hasOverdueInWeek {
                break
            }
            streak += 1
        }

        return streak
    }

    private func parse(_ value: String) -> Date? {
        parser.date(from: value) ?? legacyParser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func effectiveDueDate(for deadline: Deadline, now: Date) -> Date? {
        let base = deadline.normalizedDueDateForRecurrence(referenceDate: now) ?? parse(deadline.dueDate)
        guard let due = base else { return nil }
        return normalizeDueDate(deadline.dueDate, due: due)
    }

    private func normalizeDueDate(_ raw: String, due: Date) -> Date {
        if raw.contains(":") {
            return due
        }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: due) ?? due
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }
}
