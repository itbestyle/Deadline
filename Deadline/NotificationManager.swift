

import Foundation
import UserNotifications

private func NL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

final class NotificationManager {
    static let shared = NotificationManager()
    private let weeklyPressureIdentifier = "weekly-pressure-report"
    private let proPressureSuffixes = ["pro72h", "pro24h", "pro3h"]
    private let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    private let legacyDueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private init() {}
    
    // 🔹 Запрашиваем разрешение на уведомления
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    // 🔹 Запланировать уведомление на основе reminderTime
    func scheduleNotification(for deadline: Deadline) {
        // Не планируем для уже завершённых или отменённых
        if deadline.statusType == .completed || deadline.statusType == .cancelled {
            return
        }
        
        // Не планируем если напоминание отключено
        if deadline.reminderTime == "none" {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = NL("Напоминание о задаче")
        content.sound = .default
        
        // Парсим дату задачи
        guard let dueDate = dueDateFormatter.date(from: deadline.dueDate) ?? legacyDueDateFormatter.date(from: deadline.dueDate) else { return }
        
        // Вычисляем дату уведомления на основе reminderTime
        var notifyDate: Date?
        
        switch deadline.reminderTime {
        case "1hour":
            content.body = String(format: NL("%@ по предмету %@ через час!"), deadline.title, deadline.localizedSubjectName)
            notifyDate = Calendar.current.date(byAdding: .hour, value: -1, to: dueDate)
        case "1day":
            content.body = String(format: NL("%@ по предмету %@ завтра!"), deadline.title, deadline.localizedSubjectName)
            notifyDate = Calendar.current.date(byAdding: .day, value: -1, to: dueDate)
        case "1week":
            content.body = String(format: NL("%@ по предмету %@ через неделю!"), deadline.title, deadline.localizedSubjectName)
            notifyDate = Calendar.current.date(byAdding: .day, value: -7, to: dueDate)
        default:
            return
        }
        
        guard let finalNotifyDate = notifyDate else { return }
        
        // Если дата уведомления уже прошла — не планируем
        if finalNotifyDate < Date() {
            return
        }
        
        var triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: finalNotifyDate)
        
        // Для 1day и 1week ставим уведомление в 9 утра
        if deadline.reminderTime == "1day" || deadline.reminderTime == "1week" {
            triggerDate.hour = 9
            triggerDate.minute = 0
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: deadline.id,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                let nsError = error as NSError
                print(String(format: NL("Ошибка при создании уведомления (код: %d)"), nsError.code))
            }
        }
    }
    
    // 🔹 Отменить уведомление (по ID задачи)
    func cancelNotification(for deadlineID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [deadlineID])
    }

    func rescheduleAll(for deadlines: [Deadline]) {
        let center = UNUserNotificationCenter.current()

        // Clear previously scheduled notifications to avoid stale duplicates
        // (e.g., notifications created before language change or ID remap).
        center.removeAllPendingNotificationRequests()

        let deadlineIDs = deadlines.flatMap { idsForDeadline($0.id) }
        center.removePendingNotificationRequests(withIdentifiers: deadlineIDs)
        for deadline in deadlines {
            scheduleNotification(for: deadline)
        }
    }

    func rescheduleProPressureAlerts(for deadlines: [Deadline], enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let proIDs = deadlines.flatMap { proAlertIdentifiers(for: $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: proIDs)

        guard enabled else { return }

        for deadline in deadlines where deadline.statusType == .inProgress {
            scheduleProPressureAlerts(for: deadline)
        }
    }

    func scheduleWeeklyPressureDigest(topInsight: String) {
        let content = UNMutableNotificationContent()
        content.title = NL("Weekly Report готов")
        content.body = topInsight
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1
        components.hour = 19
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyPressureIdentifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyPressureIdentifier])
        center.add(request)
    }

    func cancelWeeklyPressureDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyPressureIdentifier])
    }

    private func scheduleProPressureAlerts(for deadline: Deadline) {
        guard let due = normalizedDueDate(for: deadline) else { return }

        scheduleProAlert(
            for: deadline,
            dueDate: due,
            offset: -72 * 3600,
            idSuffix: "pro72h",
            body: String(format: NL("Через 72 часа задача: %@ (%@). Запланируйте старт сегодня."), deadline.title, deadline.localizedSubjectName)
        )

        scheduleProAlert(
            for: deadline,
            dueDate: due,
            offset: -24 * 3600,
            idSuffix: "pro24h",
            body: String(format: NL("Через 24 часа задача: %@ (%@). Пора в фокус-режим."), deadline.title, deadline.localizedSubjectName)
        )

        scheduleProAlert(
            for: deadline,
            dueDate: due,
            offset: -3 * 3600,
            idSuffix: "pro3h",
            body: String(format: NL("Задача %@ уже через 3 часа. Финальный рывок!"), deadline.title)
        )
    }

    private func scheduleProAlert(for deadline: Deadline, dueDate: Date, offset: TimeInterval, idSuffix: String, body: String) {
        let triggerDate = dueDate.addingTimeInterval(offset)
        guard triggerDate > Date() else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        components.second = 0

        let content = UNMutableNotificationContent()
        content.title = NL("Режим давления")
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "\(deadline.id)-\(idSuffix)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    private func normalizedDueDate(for deadline: Deadline) -> Date? {
        guard let dueDate = dueDateFormatter.date(from: deadline.dueDate) ?? legacyDueDateFormatter.date(from: deadline.dueDate) else {
            return nil
        }

        if deadline.dueDate.contains(":") {
            return dueDate
        }

        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: dueDate)
    }

    private func idsForDeadline(_ id: String) -> [String] {
        [id] + proAlertIdentifiers(for: id)
    }

    private func proAlertIdentifiers(for id: String) -> [String] {
        proPressureSuffixes.map { "\(id)-\($0)" }
    }
}
