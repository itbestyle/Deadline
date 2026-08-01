//
//  DeadlineWidget.swift
//  DeadlineWidget
//
//  Created by Сергей Родоманюк on 05.02.2026.
//

import AppIntents
import WidgetKit
import SwiftUI

private let subjectLocalizationMap: [String: String] = [
    "личное": "Личное",
    "personal": "Личное",
    "работа": "Работа",
    "work": "Работа",
    "здоровье": "Здоровье",
    "health": "Здоровье",
    "финансы": "Финансы",
    "finance": "Финансы",
    "finances": "Финансы",
    "покупки": "Покупки",
    "shopping": "Покупки",
    "другое": "Другое",
    "other": "Другое"
]

private func localizedSubjectName(_ raw: String) -> String {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return raw }
    if let key = subjectLocalizationMap[normalized] {
        return WidgetL10n.string(key)
    }
    return raw
}

// MARK: - Data Models
struct WidgetDeadline: Codable, Identifiable {
    let id: String
    let title: String
    let subject: String
    let dueDate: String
    let effectiveDueDate: String?
    let repeatType: String?
    let priority: String?
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case id, title, subject, status, priority
        case dueDate = "due_date"
        case effectiveDueDate = "effective_due_date"
        case repeatType = "repeat_type"
    }
}

// MARK: - Timeline Entry
struct DeadlineEntry: TimelineEntry {
    let date: Date
    let deadlines: [WidgetDeadline]
    let isLoggedIn: Bool
}

// MARK: - Provider
struct Provider: TimelineProvider {
    private let baseURL = "https://deadlines-api-744471608721.europe-west1.run.app"
    private let appGroup = "group.tic-tac-toe.Deadline"

    private let dueDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }
    
    func placeholder(in context: Context) -> DeadlineEntry {
        DeadlineEntry(date: Date(), deadlines: [
            WidgetDeadline(id: "1", title: "Оплатить счет", subject: "Финансы", dueDate: "2026-02-06", effectiveDueDate: nil, repeatType: "none", priority: "Низкий", status: "в процессе")
        ], isLoggedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> ()) {
        let entry = DeadlineEntry(date: Date(), deadlines: [], isLoggedIn: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> ()) {
        Task {
            let deadlines = await fetchDeadlines()
            let isLoggedIn = sharedDefaults?.string(forKey: "auth_token") != nil
            
            let entry = DeadlineEntry(
                date: Date(),
                deadlines: deadlines,
                isLoggedIn: isLoggedIn
            )
            
            // Refresh every 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func fetchDeadlines() async -> [WidgetDeadline] {
        guard let token = sharedDefaults?.string(forKey: "auth_token"),
              let url = URL(string: "\(baseURL)/deadlines") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            var deadlines = try decoder.decode([WidgetDeadline].self, from: data)
            
            // Filter only active deadlines and sort by effective due date.
            let hiddenIDs = WidgetAppGroupStore.locallyCompletedIDs()
            deadlines = deadlines
                .filter { $0.status == "в процессе" && !hiddenIDs.contains($0.id) }
                .sorted { 
                    let d1 = parsedDate(effectiveDateString(for: $0)) ?? .distantFuture
                    let d2 = parsedDate(effectiveDateString(for: $1)) ?? .distantFuture
                    return d1 < d2
                }
            
            return Array(deadlines.prefix(3))
        } catch {
            return []
        }
    }

    private func parsedDate(_ dateString: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]

        for format in formats {
            dueDateParser.dateFormat = format
            if let date = dueDateParser.date(from: dateString) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: dateString)
    }

    private func effectiveDateString(for deadline: WidgetDeadline) -> String {
        if let effective = deadline.effectiveDueDate, !effective.isEmpty {
            return effective
        }

        guard let repeatType = deadline.repeatType,
              repeatType != "none",
              let initialDate = parsedDate(deadline.dueDate) else {
            return deadline.dueDate
        }

        var next = initialDate
        let now = Date()
        let calendar = Calendar.current
        let hasTime = hasExplicitTime(in: deadline.dueDate)

        for _ in 0..<600 {
            if hasTime {
                if next >= now { break }
            } else {
                if calendar.startOfDay(for: next) >= calendar.startOfDay(for: now) { break }
            }

            switch repeatType {
            case "daily":
                next = next.addingTimeInterval(24 * 60 * 60)
            case "weekly":
                next = next.addingTimeInterval(7 * 24 * 60 * 60)
            case "monthly":
                next = calendar.date(byAdding: .month, value: 1, to: next) ?? next
            case "yearly":
                next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
            default:
                return deadline.dueDate
            }
        }

        dueDateParser.dateFormat = hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return dueDateParser.string(from: next)
    }

    private func hasExplicitTime(in dateString: String) -> Bool {
        dateString.contains(":") || dateString.contains("T")
    }
}

// MARK: - Widget View
struct DeadlineWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private let compactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private let compactTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    var body: some View {
        if !entry.isLoggedIn {
            notLoggedInView
        } else if entry.deadlines.isEmpty {
            emptyView
        } else {
            deadlinesView
        }
    }

    private var notLoggedInView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 6) {
                Label(WidgetL10n.string("Войдите в приложение"), systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(WidgetL10n.string("Откройте Redloop, чтобы подключить задачи"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 6) {
                Label(WidgetL10n.string("Нет активных задач"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text(WidgetL10n.string("Отличная работа — можно немного выдохнуть"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var deadlinesView: some View {
        switch family {
        case .systemSmall:
            compactDeadlinesView
        default:
            regularDeadlinesView
        }
    }

    private var regularDeadlinesView: some View {
        let regularItems = Array(entry.deadlines.prefix(3))

        return VStack(alignment: .leading, spacing: 0) {
            regularWidgetHeader
                .padding(.bottom, 2)

            ForEach(Array(regularItems.enumerated()), id: \.element.id) { index, deadline in
                regularDeadlineRow(deadline: deadline)

                if index < regularItems.count - 1 {
                    dividerLine
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var compactDeadlinesView: some View {
        let compactItems = Array(entry.deadlines.prefix(3))

        return VStack(alignment: .leading, spacing: 0) {
            compactWidgetHeader
                .padding(.bottom, 2)

            ForEach(Array(compactItems.enumerated()), id: \.element.id) { index, deadline in
                compactDeadlineRow(deadline: deadline)

                if index < compactItems.count - 1 {
                    dividerLine
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var widgetHeader: some View {
        HStack(spacing: 0) {
            Image("LoginIcon")
                .resizable()
                .scaledToFit()
                .frame(width: family == .systemSmall ? 18 : 20, height: family == .systemSmall ? 18 : 20)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Spacer(minLength: 0)
        }
    }

    private var regularWidgetHeader: some View {
        HStack(spacing: 0) {
            Image("LoginIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private var compactWidgetHeader: some View {
        HStack(spacing: 0) {
            Image("LoginIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.2))
            .frame(height: 0.5)
    }

    @ViewBuilder
    private func compactDeadlineRow(deadline: WidgetDeadline) -> some View {
        let dateString = resolvedDateString(for: deadline)
        let row = VStack(alignment: .leading, spacing: 2) {
            Text(compactDisplayTitle(deadline.title, dueDate: dateString))
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                Text(localizedSubjectName(deadline.subject))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(compactFormattedDate(dateString))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground(for: deadline, resolvedDateString: dateString))
        )
        .padding(.horizontal, 2)

        if #available(iOS 17.0, *) {
            HStack(spacing: 6) {
                row
                Button(intent: CompleteDeadlineWidgetIntent(deadlineID: deadline.id)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(WidgetIntentButtonStyle())
            }
        } else {
            row
        }
    }

    private func regularDeadlineRow(deadline: WidgetDeadline) -> some View {
        let dateString = resolvedDateString(for: deadline)
        return VStack(alignment: .leading, spacing: 2) {
            Text(deadline.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                Text(localizedSubjectName(deadline.subject))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(regularFormattedDate(dateString))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground(for: deadline, resolvedDateString: dateString))
        )
        .padding(.horizontal, 2)
    }

    private func rowBackground(for deadline: WidgetDeadline, resolvedDateString: String) -> LinearGradient {
        let base = Color(.secondarySystemBackground).opacity(baseRowFillOpacity())
        let isDark = colorScheme == .dark

        switch resolvedPriority(for: deadline, resolvedDateString: resolvedDateString) {
        case "Высокий":
            return LinearGradient(
                colors: [base, Color.red.opacity(isDark ? 0.17 : 0.2)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case "Средний":
            return LinearGradient(
                colors: [base, Color.orange.opacity(isDark ? 0.12 : 0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case "Низкий":
            return LinearGradient(
                colors: [base, Color.yellow.opacity(isDark ? 0.08 : 0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [base, Color.indigo.opacity(isDark ? 0.08 : 0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func resolvedPriority(for deadline: WidgetDeadline, resolvedDateString: String) -> String {
        let stored = (deadline.priority ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, stored != "Авто" {
            return stored
        }

        guard let date = parsedDate(resolvedDateString) else {
            return "Низкий"
        }

        let dueInstant: Date
        if hasExplicitTime(in: resolvedDateString) {
            dueInstant = date
        } else {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: date)
            dueInstant = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
        }

        let remaining = dueInstant.timeIntervalSince(Date())
        if remaining <= 24 * 3600 { return "Высокий" }
        if remaining <= 72 * 3600 { return "Средний" }
        return "Низкий"
    }

    private func baseRowFillOpacity() -> Double {
        colorScheme == .dark ? 0.24 : 0.18
    }

    private enum UrgencyLevel {
        case overdue
        case today
        case tomorrow
        case soon
        case thisWeek
        case normal
    }

    private func urgencyLevel(for dateString: String) -> UrgencyLevel {
        guard let date = parsedDate(dateString) else { return .normal }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: date)
        let hasTime = hasExplicitTime(in: dateString)

        if hasTime && date < now {
            return .overdue
        }

        if !hasTime && dueDay < today {
            return .overdue
        }

        guard let days = calendar.dateComponents([.day], from: today, to: dueDay).day else {
            return .normal
        }

        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        if days <= 3 { return .soon }
        if days <= 7 { return .thisWeek }

        return .normal
    }

    private func parsedDate(_ dateString: String) -> Date? {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]

        for format in formats {
            inputFormatter.dateFormat = format
            if let date = inputFormatter.date(from: dateString) {
                return date
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: dateString)
    }

    private func hasExplicitTime(in dateString: String) -> Bool {
        dateString.contains(":") || dateString.contains("T")
    }

    private func resolvedDateString(for deadline: WidgetDeadline) -> String {
        if let effective = deadline.effectiveDueDate, !effective.isEmpty {
            return effective
        }

        guard let repeatType = deadline.repeatType,
              repeatType != "none",
              let initialDate = parsedDate(deadline.dueDate) else {
            return deadline.dueDate
        }

        var next = initialDate
        let now = Date()
        let calendar = Calendar.current

        for _ in 0..<600 {
            if hasExplicitTime(in: deadline.dueDate) {
                if next >= now { break }
            } else {
                if calendar.startOfDay(for: next) >= calendar.startOfDay(for: now) { break }
            }

            switch repeatType {
            case "daily":
                next = next.addingTimeInterval(24 * 60 * 60)
            case "weekly":
                next = next.addingTimeInterval(7 * 24 * 60 * 60)
            case "monthly":
                next = calendar.date(byAdding: .month, value: 1, to: next) ?? next
            case "yearly":
                next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
            default:
                return deadline.dueDate
            }
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        if hasExplicitTime(in: deadline.dueDate) {
            output.dateFormat = "yyyy-MM-dd HH:mm"
        } else {
            output.dateFormat = "yyyy-MM-dd"
        }
        return output.string(from: next)
    }

    private func regularFormattedDate(_ dateString: String) -> String {
        guard let date = parsedDate(dateString) else { return dateString }
        return dayMonthFormatter.string(from: date)
    }

    private func compactFormattedDate(_ dateString: String) -> String {
        guard let date = parsedDate(dateString) else { return dateString }

        if Calendar.current.isDateInToday(date) {
            return compactTimeFormatter.string(from: date)
        }

        return compactDateFormatter.string(from: date)
    }

    private func compactDisplayTitle(_ title: String, dueDate: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = isTodayDeadline(dueDate) ? 13 : 15

        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }

    private func isTodayDeadline(_ dateString: String) -> Bool {
        guard let date = parsedDate(dateString) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

// MARK: - Widget Configuration
struct DeadlineWidget: Widget {
    let kind: String = "DeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                DeadlineWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                DeadlineWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName(WidgetL10n.string("Задачи"))
        .description(WidgetL10n.string("Показывает ближайшие задачи"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry(date: Date(), deadlines: [
        WidgetDeadline(id: "1", title: "Оплатить аренду", subject: "Финансы", dueDate: "2026-02-06", effectiveDueDate: nil, repeatType: "monthly", priority: "Средний", status: "в процессе"),
        WidgetDeadline(id: "2", title: "Записаться к врачу", subject: "Здоровье", dueDate: "2026-02-07", effectiveDueDate: nil, repeatType: "none", priority: "Высокий", status: "в процессе")
    ], isLoggedIn: true)
}
