//
//  DeadlineTests.swift
//  DeadlineTests
//
//  Created by Сергей Родоманюк on 30.09.2025.
//

import Foundation
import Testing
@testable import DeadlinesApp

@MainActor
struct DeadlineTests {

    @Test func pressureReport_riskScenario_countsAndAssessment() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 12:00")

        let deadlines = [
            makeDeadline(id: "1", due: "2026-02-26 20:00", status: .inProgress),
            makeDeadline(id: "2", due: "2026-02-28 10:00", status: .inProgress),
            makeDeadline(id: "3", due: "2026-02-26 07:00", status: .inProgress),
            makeDeadline(id: "4", due: "2026-02-24 09:00", status: .completed)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.totalActive == 3)
        #expect(report.criticalCount == 2)
        #expect(report.mediumCount == 1)
        #expect(report.overdueCount == 1)
        #expect(report.completedLast7Days == 1)
        #expect(report.overloadIndex == 100)
        #expect(report.weekAssessment == NSLocalizedString("Неделя в зоне риска", comment: ""))
        #expect(report.noOverdueStreakWeeks == 0)
    }

    @Test func pressureReport_stableScenario_underControl() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 12:00")

        let deadlines = [
            makeDeadline(id: "10", due: "2026-03-05 10:00", status: .inProgress),
            makeDeadline(id: "11", due: "2026-03-10 10:00", status: .inProgress),
            makeDeadline(id: "12", due: "2026-02-25 10:00", status: .completed)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.criticalCount == 0)
        #expect(report.mediumCount == 0)
        #expect(report.overdueCount == 0)
        #expect(report.weekAssessment == NSLocalizedString("Неделя под контролем", comment: ""))
        #expect(report.insights.contains(NSLocalizedString("Нагрузка под контролем, критических рисков на неделю не видно", comment: "")))
    }

    @Test func pressureReport_dateOnlyDue_isNotOverdueBeforeEndOfDay() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 10:00")

        let deadlines = [
            makeDeadline(id: "20", due: "2026-02-26", status: .inProgress)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.totalActive == 1)
        #expect(report.overdueCount == 0)
        #expect(report.criticalCount == 1)
    }

    @Test func pressureReport_criticalBoundary_exact24Hours() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 12:00")

        let deadlines = [
            makeDeadline(id: "30", due: "2026-02-27 12:00", status: .inProgress),
            makeDeadline(id: "31", due: "2026-02-27 12:01", status: .inProgress)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.criticalCount == 1)
        #expect(report.mediumCount == 1)
        #expect(report.overdueCount == 0)
    }

    @Test func pressureReport_noOverdueStreak_countsSequentialWeeksOnly() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 12:00")

        let deadlines = [
            makeDeadline(id: "40", due: "2026-02-26 18:00", status: .inProgress),
            makeDeadline(id: "41", due: "2026-02-20 18:00", status: .inProgress),
            makeDeadline(id: "42", due: "2026-02-10 18:00", status: .inProgress)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.noOverdueStreakWeeks == 1)
    }

    @Test func pressureReport_noOverdueStreak_previousWeekDueBeforeNow_breaksStreak() async throws {
        let engine = PressureInsightsEngine()
        let now = makeDate("2026-02-26 12:00")

        let deadlines = [
            makeDeadline(id: "50", due: "2026-02-26 18:00", status: .inProgress),
            makeDeadline(id: "51", due: "2026-02-19 09:00", status: .inProgress)
        ]

        let report = engine.makeReport(from: deadlines, now: now)

        #expect(report.overdueCount == 1)
        #expect(report.noOverdueStreakWeeks == 1)
    }

    // MARK: - Priority & sections

    @Test func resolvedPriority_autoWithinOneHour_isHigh() async throws {
        let now = makeDate("2026-06-01 12:00")
        let deadline = makeDeadline(id: "p1", due: "2026-06-01 13:00", status: .inProgress, priority: "Авто")
        #expect(deadline.resolvedPriority(referenceDate: now) == "Высокий")
    }

    @Test func resolvedPriority_autoWithin48Hours_isMedium() async throws {
        let now = makeDate("2026-06-01 12:00")
        let deadline = makeDeadline(id: "p2", due: "2026-06-03 10:00", status: .inProgress, priority: "Авто")
        #expect(deadline.resolvedPriority(referenceDate: now) == "Средний")
    }

    @Test func resolvedPriority_autoBeyond72Hours_isLow() async throws {
        let now = makeDate("2026-06-01 12:00")
        let deadline = makeDeadline(id: "p3", due: "2026-06-10 10:00", status: .inProgress, priority: "Авто")
        #expect(deadline.resolvedPriority(referenceDate: now) == "Низкий")
    }

    @Test func resolvedPriority_manualLowNearDue_respectsManual() async throws {
        let now = makeDate("2026-06-01 12:00")
        let deadline = makeDeadline(id: "p4", due: "2026-06-01 13:00", status: .inProgress, priority: "Низкий")
        #expect(deadline.resolvedPriority(referenceDate: now) == "Низкий")
    }

    @Test func listSectionKey_overdueTask_isOverdueSection() async throws {
        let now = makeDate("2026-06-02 12:00")
        let deadline = makeDeadline(id: "s1", due: "2026-06-01 18:00", status: .inProgress, priority: "Авто")
        #expect(deadline.isOverdue(referenceDate: now))
        #expect(deadline.listSectionKey(referenceDate: now) == "Просрочено")
    }

    @Test func listSectionKey_dueToday_isBurningTodaySection() async throws {
        let now = makeDate("2026-06-01 10:00")
        let deadline = makeDeadline(id: "s2", due: "2026-06-01 18:00", status: .inProgress, priority: "Авто")
        #expect(deadline.isDueToday(referenceDate: now))
        #expect(deadline.listSectionKey(referenceDate: now) == "Горит сегодня")
    }

    @Test func listSectionKey_laterTask_isLaterSection() async throws {
        let now = makeDate("2026-06-01 12:00")
        let deadline = makeDeadline(id: "s3", due: "2026-07-01 10:00", status: .inProgress, priority: "Авто")
        #expect(deadline.listSectionKey(referenceDate: now) == "Позже")
    }

    @Test func widgetSnapshot_nearestCritical_prefersHighPriority() async throws {
        let now = makeDate("2026-06-01 12:00")
        let high = makeDeadline(id: "w1", due: "2026-06-01 20:00", status: .inProgress, priority: "Авто")
        let low = makeDeadline(id: "w2", due: "2026-06-01 14:00", status: .inProgress, priority: "Низкий")
        let snapshot = WidgetCriticalSnapshotBuilder.nearestCritical(from: [low, high])
        #expect(snapshot?.id == "w1")
        #expect(snapshot?.priority == "Высокий")
        _ = now
    }

    @Test func pressureActionPlan_prioritizesOverdueAsNextStep() async throws {
        let planner = PressureActionPlanner()
        let now = makeDate("2026-06-01 12:00")
        let overdue = makeDeadline(id: "o1", due: "2026-05-31 18:00", status: .inProgress, priority: "Авто")
        let soon = makeDeadline(id: "s1", due: "2026-06-01 20:00", status: .inProgress, priority: "Авто")
        let plan = planner.makePlan(from: [soon, overdue], now: now)
        #expect(plan.nextStep?.deadlineID == "o1")
        #expect(plan.nextStep?.isOverdue == true)
        #expect(plan.nextStep?.focusMinutes == 25)
    }

    @Test func pressureActionPlan_buildsTodayPlanUpToThreeItems() async throws {
        let planner = PressureActionPlanner()
        let now = makeDate("2026-06-01 12:00")
        let deadlines = [
            makeDeadline(id: "t1", due: "2026-06-01 18:00", status: .inProgress),
            makeDeadline(id: "t2", due: "2026-06-01 20:00", status: .inProgress),
            makeDeadline(id: "t3", due: "2026-06-02 10:00", status: .inProgress),
            makeDeadline(id: "t4", due: "2026-06-05 10:00", status: .inProgress)
        ]
        let plan = planner.makePlan(from: deadlines, now: now)
        #expect(plan.nextStep?.deadlineID == "t1")
        #expect(plan.todayPlan.count <= 3)
        #expect(plan.todayPlan.contains(where: { $0.deadlineID == "t2" }))
    }

    private func makeDeadline(
        id: String,
        due: String,
        status: DeadlineStatus,
        priority: String = "Авто"
    ) -> Deadline {
        Deadline(
            id: id,
            title: "Task \(id)",
            subject: "Work",
            dueDate: due,
            status: status.rawValue,
            priority: priority,
            tags: [],
            repeatType: "none",
            notes: "",
            reminderTime: "1day",
            deletedAt: nil
        )
    }

    private func makeDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

}
