import SwiftUI
import SwiftData
import UIKit
import Combine

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum PressureABVariant: String {
    case a
    case b
}

final class PressureABAnalytics {
    static let shared = PressureABAnalytics()

    private let defaults = UserDefaults.standard
    private let variantKey = "pressure_ab_variant"
    private let ctaImpressionAKey = "pressure_cta_impression_a"
    private let ctaImpressionBKey = "pressure_cta_impression_b"
    private let ctaClickAKey = "pressure_cta_click_a"
    private let ctaClickBKey = "pressure_cta_click_b"
    private let paywallShownKey = "pressure_paywall_shown"

    private init() {}

    var variant: PressureABVariant {
        if let raw = defaults.string(forKey: variantKey), let assigned = PressureABVariant(rawValue: raw) {
            return assigned
        }
        let assigned: PressureABVariant = Bool.random() ? .a : .b
        defaults.set(assigned.rawValue, forKey: variantKey)
        return assigned
    }

    var snapshot: (variant: PressureABVariant, ctaImpressions: Int, ctaClicks: Int, paywallShows: Int) {
        let selected = variant
        let impressions = defaults.integer(forKey: selected == .a ? ctaImpressionAKey : ctaImpressionBKey)
        let clicks = defaults.integer(forKey: selected == .a ? ctaClickAKey : ctaClickBKey)
        let paywallShows = defaults.integer(forKey: paywallShownKey)
        return (selected, impressions, clicks, paywallShows)
    }

    func trackCtaImpression() {
        switch variant {
        case .a:
            defaults.set(defaults.integer(forKey: ctaImpressionAKey) + 1, forKey: ctaImpressionAKey)
        case .b:
            defaults.set(defaults.integer(forKey: ctaImpressionBKey) + 1, forKey: ctaImpressionBKey)
        }
    }

    func trackCtaClick() {
        switch variant {
        case .a:
            defaults.set(defaults.integer(forKey: ctaClickAKey) + 1, forKey: ctaClickAKey)
        case .b:
            defaults.set(defaults.integer(forKey: ctaClickBKey) + 1, forKey: ctaClickBKey)
        }
    }

    func trackPaywallShown() {
        defaults.set(defaults.integer(forKey: paywallShownKey) + 1, forKey: paywallShownKey)
    }
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var label: String {
        switch self {
        case .system: return L("Системная")
        case .light: return L("Светлая")
        case .dark: return L("Тёмная")
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

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
            guard let due = parse(item.dueDate) else { return nil }
            return (item, normalizeDueDate(item.dueDate, due: due))
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

struct WeeklyReportView: View {
    let deadlines: [Deadline]
    private let engine = PressureInsightsEngine()

    private var report: WeeklyPressureReport {
        engine.makeReport(from: deadlines)
    }

    private var overloadTint: Color {
        if report.overloadIndex >= 70 { return .red }
        if report.overloadIndex >= 40 { return .orange }
        return .green
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Weekly Pressure Report"))
                        .font(.title2.weight(.bold))

                    HStack(spacing: 10) {
                        metricCard(title: L("Индекс"), value: "\(report.overloadIndex)%", tint: overloadTint, emphasized: true)
                        metricCard(title: L("Активные"), value: "\(report.totalActive)", tint: .indigo)
                    }

                    HStack(spacing: 10) {
                        metricCard(title: L("Изм. к прошлой неделе"), value: "\(report.overloadDeltaPercent > 0 ? "+" : "")\(report.overloadDeltaPercent)%", tint: report.overloadDeltaPercent <= 0 ? .green : .red)
                        metricCard(title: L("Серия без просрочек"), value: report.noOverdueStreakWeeks == 0 ? "—" : "\(report.noOverdueStreakWeeks)", tint: report.noOverdueStreakWeeks >= 3 ? .green : .orange)
                    }

                    Text(overloadDeltaSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(report.overloadDeltaPercent > 0 ? .red : .secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        metricCard(title: L("Критичные 24ч"), value: "\(report.criticalCount)", tint: .red)
                        metricCard(title: L("72ч окно"), value: "\(report.mediumCount)", tint: .orange)
                    }

                    HStack(spacing: 10) {
                        metricCard(title: L("Просрочено"), value: "\(report.overdueCount)", tint: .pink)
                        metricCard(title: L("Сдано / 7д"), value: "\(report.completedLast7Days)", tint: .green)
                    }

                    if let day = report.overloadDayLabel {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(.orange)
                            Text(String(format: L("Пик нагрузки: %@"), day))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: report.weekAssessment == L("Неделя под контролем") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(report.weekAssessment == L("Неделя под контролем") ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.weekAssessment)
                                .font(.subheadline.weight(.semibold))
                            Text(report.weekAssessmentReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text(L("Умные инсайты"))
                        .font(.headline)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.insights.indices, id: \.self) { index in
                            let text = report.insights[index]
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.indigo)
                                Text(text)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
            }
            .navigationTitle(L("Weekly Report"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var overloadDeltaSummary: String {
        if report.previousOverloadIndex > 0, report.overloadIndex >= report.previousOverloadIndex * 2 {
            return L("Давление удвоилось по сравнению с прошлой неделей")
        }
        if report.overloadDeltaPercent > 0 {
            return String(format: L("Давление выросло на %d%% к прошлой неделе"), abs(report.overloadDeltaPercent))
        }
        if report.overloadDeltaPercent < 0 {
            return String(format: L("Давление снизилось на %d%% к прошлой неделе"), abs(report.overloadDeltaPercent))
        }
        return L("Давление без изменений относительно прошлой недели")
    }

    private func metricCard(title: String, value: String, tint: Color, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(emphasized ? tint.opacity(0.65) : Color.clear, lineWidth: emphasized ? 1.5 : 0)
        )
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DeadlineViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @State private var showAppearance = false
    @State private var showSubscription = false
    @State private var showWeeklyReport = false
    @State private var selectedTab: MainTab = .deadlines
    @State private var showPressurePaywall = false
    
    @State private var showArchive = false
    
    // Поля для добавления нового дедлайна
    @State private var newTitle = ""
    @State private var newSubject = "Личное"
    @State private var newDate = Date()
    @State private var newStatus: DeadlineStatus = .inProgress
    @State private var selectedTags: Set<String> = []
    @State private var sortMode: SortMode = .date
    @State private var newPriority = "Авто"
    @State private var isFormExpanded = false
    @State private var newRepeatType = "none"
    @State private var newNotes = ""
    @State private var newReminderTime = "1day"
    @State private var addButtonBreathing = false
    @FocusState private var addFormFocusedField: AddFormFocusedField?
    
    // Для редактирования
    @State private var editingDeadline: Deadline?
    @State private var detailDeadline: Deadline?
    
    private var syncStatusBanner: some View {
        Group {
            if viewModel.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L("Синхронизация…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let message = viewModel.lastSyncError {
                Text(String(format: L("Ошибка синхронизации: %@"), message))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            }
        }
    }
    @State private var isEditing = false
    
    // Фильтры
    @State private var filterStatus = ""
    @State private var filterSubject = ""
    
    private let statusOptions: [(label: String, value: String)] = [
        (L("Все статусы"), ""),
        (L("В процессе"), DeadlineStatus.inProgress.rawValue),
        (L("Выполнен"), DeadlineStatus.completed.rawValue),
        (L("Отменён"), DeadlineStatus.cancelled.rawValue)
    ]
    
    private let subjectOptions: [(label: String, value: String)] = [
        (L("Все предметы"), ""),
        (L("Личное"), "Личное"),
        (L("Работа"), "Работа"),
        (L("Здоровье"), "Здоровье"),
        (L("Финансы"), "Финансы"),
        (L("Покупки"), "Покупки"),
        (L("Другое"), "Другое")
    ]
    
    private let tagOptions: [String] = ["Срочно", "Личное", "Работа"]
    
    private let deadlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    private let legacyDeadlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
    
    private let priorityOptions = ["Авто", "Высокий", "Средний", "Низкий"]
    
    private let repeatOptions: [(label: String, value: String)] = [
        (L("Без повторения"), "none"),
        (L("Ежедневно"), "daily"),
        (L("Еженедельно"), "weekly"),
        (L("Ежемесячно"), "monthly"),
        (L("Ежегодно"), "yearly")
    ]
    
    private let reminderOptions: [(label: String, value: String)] = [
        (L("Без напоминания"), "none"),
        (L("За час"), "1hour"),
        (L("За день"), "1day"),
        (L("За неделю"), "1week")
    ]

    private enum SortMode: String, CaseIterable, Identifiable {
        case date
        case tag
        
        var id: SortMode { self }
        
        var title: String {
            switch self {
            case .date: return L("По сроку")
            case .tag: return L("По тегу")
            }
        }
    }

    private enum AddFormFocusedField: Hashable {
        case title
        case notes
    }

    private enum MainTab: Hashable {
        case deadlines
        case pressure
    }

    private var isAddButtonEnabled: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    var body: some View {
        TabView(selection: $selectedTab) {
            deadlinesTab
            pressureTab
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .pressure else { return }
            guard !subscriptionManager.isPressureProUnlocked else { return }
            selectedTab = .deadlines
            showPressurePaywall = true
            PressureABAnalytics.shared.trackPaywallShown()
        }
        .onChange(of: subscriptionManager.isPressureProUnlocked) { _, _ in
            rescheduleProNotificationsIfNeeded()
        }
        .onReceive(viewModel.$deadlines) { _ in
            rescheduleProNotificationsIfNeeded()
        }
        .sheet(isPresented: $showPressurePaywall) {
            PressurePaywallView(subscriptionManager: subscriptionManager)
        }
        .onChange(of: showPressurePaywall) { _, shown in
            if shown {
                PressureABAnalytics.shared.trackPaywallShown()
            }
        }
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: appTheme)
        .tint(.indigo)
    }

    private var deadlinesTab: some View {
        NavigationView {
            VStack(spacing: 0) {
                addDeadlineButton

                filterControls
                    .padding(.horizontal)
                    .padding(.top, 8)

                syncStatusBanner

                deadlineList
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.deadlines.count)
            }
            .sheet(isPresented: $isFormExpanded) {
                addFormSheet
            }
            .onAppear {
                NotificationManager.shared.requestAuthorization()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.configureIfNeeded(context: modelContext)
                await fetchDeadlinesWithCurrentFilters()
                rescheduleProNotificationsIfNeeded()
            }
            .onChange(of: filterStatus) { oldValue, newValue in
                guard newValue != oldValue else { return }
                Task { await fetchDeadlinesWithCurrentFilters() }
            }
            .onChange(of: filterSubject) { oldValue, newValue in
                guard newValue != oldValue else { return }
                Task { await fetchDeadlinesWithCurrentFilters() }
            }
            .sheet(isPresented: $isEditing, onDismiss: { editingDeadline = nil }) {
                if let edit = editingDeadline {
                    EditDeadlineView(deadline: edit) { updated in
                        Task {
                            await viewModel.updateDeadline(updated)
                            isEditing = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showArchive) {
                ArchiveView(viewModel: viewModel)
            }
            .sheet(isPresented: $showAppearance) {
                NavigationStack {
                    AppearanceView()
                }
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionStatusView(subscriptionManager: subscriptionManager)
                    .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
            }
            .sheet(isPresented: $showWeeklyReport) {
                WeeklyReportView(deadlines: viewModel.deadlines)
                    .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Redloop")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        if let email = AuthService.shared.currentEmail {
                            Text(email)
                        }

                        Divider()
                        Button {
                            showAppearance = true
                        } label: {
                            Label(L("Оформление"), systemImage: "circle.lefthalf.filled")
                        }

                        Button {
                            showSubscription = true
                        } label: {
                            Label(L("Подписка"), systemImage: "creditcard")
                        }

                        Button {
                            if subscriptionManager.isPressureProUnlocked {
                                showWeeklyReport = true
                            } else {
                                showPressurePaywall = true
                            }
                        } label: {
                            Label(L("Report Pro"), systemImage: "chart.bar.doc.horizontal")
                        }

                        Divider()

                        Button {
                            showArchive = true
                        } label: {
                            Label(L("Архив"), systemImage: "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred(intensity: 0.65)
                            AuthService.shared.logout()
                        } label: {
                            Label(L("Выйти"), systemImage: "rectangle.portrait.and.arrow.right")
                        }.tint(.red)
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred(intensity: 0.65)
                        Task { await viewModel.syncNow() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isSyncing)
                    .accessibilityIdentifier("syncButton")
                }
            }
        }
        .tabItem {
            Label(L("Дедлайны"), systemImage: "list.bullet.rectangle")
        }
        .tag(MainTab.deadlines)
    }

    private var pressureTab: some View {
        PressureModeView(deadlines: viewModel.deadlines, deadlineDateFormatter: deadlineDateFormatter)
            .tabItem {
                Label(L("Режим давления"), systemImage: "exclamationmark.triangle.fill")
            }
            .tag(MainTab.pressure)
    }
    
    // MARK: - Add Deadline Button
    private var addDeadlineButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred(intensity: 0.75)
            isFormExpanded = true
        } label: {
            HStack {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                Text(L("Добавить задачу"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.indigo)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.indigo.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: Color.indigo.opacity(addButtonBreathing ? 0.18 : 0.1), radius: 10, x: 0, y: 4)
            .scaleEffect(addButtonBreathing ? 1 : 0.985)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: addButtonBreathing)
        }
        .buttonStyle(CompactIndigoButtonStyle())
        .accessibilityIdentifier("openAddDeadlineButton")
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            addButtonBreathing = true
        }
    }

    private struct CompactIndigoButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }

    private struct PriorityBadge: View {
        let iconName: String
        let title: String
        let tint: Color
        let pulsing: Bool

        @State private var pulse = false

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.15))
            )
            .scaleEffect(pulsing ? (pulse ? 1.04 : 0.98) : 1)
            .opacity(pulsing ? (pulse ? 1 : 0.9) : 1)
            .onAppear {
                if pulsing {
                    pulse = true
                }
            }
            .onChange(of: pulsing) { _, newValue in
                pulse = newValue
            }
            .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: pulse)
        }
    }
    
    // MARK: - Add Form Sheet
    private var addFormSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $newTitle)
                        .focused($addFormFocusedField, equals: .title)
                        .accessibilityIdentifier("titleField")
                    TextField("Заметки", text: $newNotes, axis: .vertical)
                        .focused($addFormFocusedField, equals: .notes)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("notesField")
                } header: {
                    Text(L("Основное"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                
                Section {
                    Picker(L("Предмет"), selection: $newSubject) {
                        ForEach(subjectOptions.filter { !$0.value.isEmpty }, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .accessibilityIdentifier("subjectPicker")
                    
                    HStack(spacing: 12) {
                        Text(L("Дата и время"))
                        Spacer(minLength: 8)
                        DatePicker("", selection: $newDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("datePicker")
                    }
                } header: {
                    Text(L("Срок"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                
                Section {
                    Picker("Напоминание", selection: $newReminderTime) {
                        ForEach(reminderOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .accessibilityIdentifier("reminderPicker")
                    
                    Picker("Повторение", selection: $newRepeatType) {
                        ForEach(repeatOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .accessibilityIdentifier("repeatPicker")
                    .onChange(of: newRepeatType) { _, newValue in
                        if newValue != "none" {
                            newPriority = "Авто"
                        }
                    }
                } header: {
                    Text(L("Планирование"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                
                Section {
                    Picker("Приоритет", selection: $newPriority) {
                        ForEach(priorityOptions, id: \.self) { option in
                            Text(L(option)).tag(option)
                        }
                    }
                    .accessibilityIdentifier("priorityPicker")
                    .disabled(newRepeatType != "none")
                    .opacity(newRepeatType != "none" ? 0.55 : 1)
                    .animation(.easeInOut(duration: 0.22), value: newPriority)
                    
                    Picker("Статус", selection: $newStatus) {
                        Text(L("в процессе")).tag(DeadlineStatus.inProgress)
                        Text(L("Выполнен")).tag(DeadlineStatus.completed)
                        Text(L("отменён")).tag(DeadlineStatus.cancelled)
                    }
                    .accessibilityIdentifier("statusPicker")
                    .animation(.easeInOut(duration: 0.22), value: newStatus)
                } header: {
                    Text(L("Состояние"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } footer: {
                    if newRepeatType != "none" {
                        Text(L("Для повторяющихся задач приоритет считается автоматически"))
                            .font(.caption)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                
                Section {
                    HStack(spacing: 8) {
                        ForEach(tagOptions, id: \.self) { tag in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            } label: {
                                Text(L(tag))
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTags.contains(tag) ? Color.indigo.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .foregroundStyle(selectedTags.contains(tag) ? Color.indigo : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(L("Теги"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .background(Color(.systemGroupedBackground))
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        addFormFocusedField = nil
                    }
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("Новый дедлайн"))
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена")) {
                        isFormExpanded = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Добавить")) {
                        addNewDeadline()
                    }
                    .bold()
                    .accessibilityIdentifier("confirmAddDeadlineButton")
                    .disabled(!isAddButtonEnabled)
                    .opacity(isAddButtonEnabled ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.25), value: isAddButtonEnabled)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    addFormFocusedField = .title
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
    
    private func addNewDeadline() {
        guard isAddButtonEnabled else { return }
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        haptic.impactOccurred(intensity: 0.7)
        
        let priority: String
        if newRepeatType != "none" {
            // Repeating tasks should always recalculate priority for each cycle.
            priority = "Авто"
        } else {
            priority = newPriority == "Авто" ? calculatePriority(for: newDate) : newPriority
        }
        let deadline = Deadline(
            id: "",
            title: trimmedTitle,
            subject: newSubject,
            dueDate: deadlineDateFormatter.string(from: newDate),
            status: newStatus.rawValue,
            priority: priority,
            tags: Array(selectedTags).sorted(),
            repeatType: newRepeatType,
            notes: newNotes,
            reminderTime: newReminderTime
        )
        
        Task {
            if await viewModel.addDeadline(deadline) != nil {
                clearForm()
                isFormExpanded = false
            }
        }
    }
    
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Фильтры"))
                .font(.headline)
            HStack {
                Picker("Статус", selection: $filterStatus) {
                    ForEach(statusOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("filterStatusPicker")
                
                Picker(L("Предмет"), selection: $filterSubject) {
                    ForEach(subjectOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("filterSubjectPicker")
            }
            Picker("Сортировка", selection: $sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sortModePicker")
        }
    }

    // MARK: - Deadline List
    private var deadlineList: some View {
        Group {
            if sections.isEmpty {
                ScrollView {
                    emptyDeadlinesView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 56)
                        .padding(.horizontal, 24)
                }
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(header:
                            Text(section.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                                .padding(.top, 8)
                        ) {
                            ForEach(section.items) { deadline in
                                deadlineRow(deadline)
                                    .transition(.opacity.combined(with: .scale(scale: 0.75)))
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .refreshable {
            await viewModel.syncNow()
        }
        .sheet(item: $detailDeadline) { deadline in
            DeadlineDetailSheet(deadline: deadline)
        }
    }

    private var emptyDeadlinesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.indigo.opacity(0.9))

            Text(L("Пока нет напоминаний"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(L("Добавьте своё первое напоминание"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private func deadlineRow(_ deadline: Deadline) -> some View {
        let priorityValue = priority(for: deadline)

        DeadlineGlassBox(deadline: deadline, color: color(for: deadline)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(deadline.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                    if deadline.repeatType != "none" {
                        Image(systemName: "repeat")
                            .foregroundStyle(.indigo)
                            .font(.caption)
                            .shadow(color: .indigo.opacity(0.3), radius: 2, x: 0, y: 0)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(deadline.subject) — \(formattedDate(deadline)) — \(localizedStatus(deadline.status))")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !priorityValue.isEmpty {
                    PriorityBadge(
                        iconName: priorityIcon(for: deadline),
                        title: localizedPriority(priorityValue),
                        tint: color(for: deadline),
                        pulsing: false
                    )
                    .shadow(color: color(for: deadline).opacity(0.15), radius: 3, x: 0, y: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !deadline.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(deadline.tags, id: \.self) { tag in
                            tagBadge(for: tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            trailingSwipeActions(for: deadline)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            leadingSwipeActions(for: deadline)
        }
        .contextMenu {
            contextMenu(for: deadline)
        }
    }
    
    @ViewBuilder
    private func trailingSwipeActions(for deadline: Deadline) -> some View {
        Button(role: .destructive) {
            mediumHaptic()
            Task {
                var archived = deadline
                archived.statusType = .cancelled
                archived.deletedAt = Date()
                await viewModel.updateDeadline(archived)
            }
        } label: {
            Label(L("Удалить"), systemImage: "trash")
        }
        .tint(.red)
        Button {
            lightHaptic()
            editingDeadline = deadline
            isEditing = true
        } label: {
            Label(L("Редактировать"), systemImage: "pencil")
        }
        .tint(.indigo)
    }
    
    @ViewBuilder
    private func leadingSwipeActions(for deadline: Deadline) -> some View {
        if deadline.statusType != .completed {
            Button {
                lightHaptic()
                Task {
                    var updated = deadline
                    updated.statusType = .completed
                    await viewModel.updateDeadline(updated)
                }
            } label: {
                Label(L("Выполнен"), systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }
    
    @ViewBuilder
    private func contextMenu(for deadline: Deadline) -> some View {
        Button {
            detailDeadline = deadline
        } label: {
            Label(L("Подробнее"), systemImage: "info.circle")
        }
        
        Button {
            lightHaptic()
            editingDeadline = deadline
            isEditing = true
        } label: {
            Label(L("Редактировать"), systemImage: "pencil")
        } 
        
        if deadline.statusType != .completed {
            Button {
                lightHaptic()
                Task {
                    var updated = deadline
                    updated.statusType = .completed
                    await viewModel.updateDeadline(updated)
                }
            } label: {
                Label(L("Отметить выполненным"), systemImage: "checkmark.circle")
            }.tint(.green)
        }
        
        Button(role: .destructive) {
            mediumHaptic()
            Task {
                var archived = deadline
                archived.statusType = .cancelled
                archived.deletedAt = Date()
                await viewModel.updateDeadline(archived)
            }
        } label: {
            Label(L("Удалить"), systemImage: "trash")
        } .tint(.red)
    }
    
    private var sections: [(title: String, items: [Deadline])] {
        switch sortMode {
        case .date:
            return sectionsByDate()
        case .tag:
            return sectionsByTag()
        }
    }

    private var mainScreenDeadlines: [Deadline] {
        viewModel.deadlines.filter { $0.deletedAt == nil }
    }
    
    private func sectionsByDate() -> [(title: String, items: [Deadline])] {
        var groups: [String: [Deadline]] = [:]
        let calendar = Calendar.current
        let today = Date()
        
        for deadline in mainScreenDeadlines {
            guard let date = parsedDeadlineDate(deadline.dueDate) else { continue }

            let key: String
            if isBurningToday(deadline) {
                key = "Горит сегодня"
            } else if calendar.isDateInToday(date) {
                key = "Сегодня"
            } else if calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear) {
                key = "На этой неделе"
            } else {
                key = "Позже"
            }

            groups[key, default: []].append(deadline)
        }
        
        let predefinedOrder = ["Горит сегодня", "Сегодня", "На этой неделе", "Позже"]
        var result: [(title: String, items: [Deadline])] = []
        
        for key in predefinedOrder {
            if let items = groups.removeValue(forKey: key), !items.isEmpty {
                result.append((L(key), sortByStatus(items)))
            }
        }
        
        for key in groups.keys.sorted() {
            if let items = groups[key] {
                result.append((L(key), sortByStatus(items)))
            }
        }
        
        return result
    }
    
    private func sectionsByTag() -> [(title: String, items: [Deadline])] {
        var groups: [String: [Deadline]] = [:]
        for deadline in mainScreenDeadlines {
            let key = deadline.tags.sorted().first ?? "Без тегов"
            groups[key, default: []].append(deadline)
        }
        let sortedKeys = groups.keys.sorted { lhs, rhs in
            switch (lhs == "Без тегов", rhs == "Без тегов") {
            case (true, true): return lhs < rhs
            case (true, false): return false
            case (false, true): return true
            case (false, false):
                return L(lhs).localizedCaseInsensitiveCompare(L(rhs)) == .orderedAscending
            }
        }
        return sortedKeys.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (title: L(key), items: sortByDueDate(items))
        }
    }
    
    private func sortByStatus(_ deadlines: [Deadline]) -> [Deadline] {
        return deadlines.sorted { lhs, rhs in
            let lhsStatus = lhs.statusType.sortOrder
            let rhsStatus = rhs.statusType.sortOrder
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }

            let lhsUrgency = urgencyRank(lhs)
            let rhsUrgency = urgencyRank(rhs)
            if lhsUrgency != rhsUrgency { return lhsUrgency < rhsUrgency }

            if lhs.subject != rhs.subject { return lhs.subject < rhs.subject }
            return compareByDueDate(lhs, rhs)
        }
    }
    
    private func sortByDueDate(_ deadlines: [Deadline]) -> [Deadline] {
        deadlines.sorted { lhs, rhs in
            compareByDueDate(lhs, rhs)
        }
    }
    
    private func compareByDueDate(_ lhs: Deadline, _ rhs: Deadline) -> Bool {
        let lhsDate = parsedDeadlineDate(lhs.dueDate) ?? .distantPast
        let rhsDate = parsedDeadlineDate(rhs.dueDate) ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    private func isBurningToday(_ deadline: Deadline) -> Bool {
            guard deadline.statusType == .inProgress,
              let dueDate = parsedDeadlineDate(deadline.dueDate) else { return false }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let dueStart = calendar.startOfDay(for: dueDate)

        return dueStart <= todayStart
    }

    private func urgencyRank(_ deadline: Deadline) -> Int {
            guard deadline.statusType == .inProgress,
              let dueDate = parsedDeadlineDate(deadline.dueDate) else { return 5 }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let dueStart = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: todayStart, to: dueStart).day ?? 999

        if days <= 0 { return 0 }
        if days == 1 { return 1 }
        if days <= 3 { return 2 }
        if days <= 7 { return 3 }
        return 4
    }
    private func color(for deadline: Deadline) -> Color {
        switch deadline.statusType {
        case .completed:
            return .green
        case .cancelled:
            return .gray
        default:
            switch priority(for: deadline) {
            case "Высокий": return .red
            case "Средний": return .orange
            case "Низкий": return .yellow
            default: return .indigo
            }
        }
    }
    // MARK: - Helpers
    private func clearForm() {
        newTitle = ""
        newSubject = "Личное"
        newDate = Date()
        newStatus = .inProgress
        newPriority = "Авто"
        newRepeatType = "none"
        newNotes = ""
        newReminderTime = "1day"
        selectedTags.removeAll()
        isFormExpanded = false
    }
    
    private func formattedDate(_ deadline: Deadline) -> String {
        guard let date = deadline.normalizedDueDateForRecurrence() else {
            return deadline.dueDate
        }
        if deadline.hasTimeInDueDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func parsedDeadlineDate(_ value: String) -> Date? {
        deadlineDateFormatter.date(from: value) ?? legacyDeadlineDateFormatter.date(from: value)
    }

    // MARK: - Priority Helpers
    private func calculatePriority(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: today, to: due).day else {
            return "Низкий"
        }
        if days <= 2 {
            return "Высокий"
        } else if days <= 7 {
            return "Средний"
        } else {
            return "Низкий"
        }
    }

    private func priority(for deadline: Deadline) -> String {
        if let date = parsedDeadlineDate(deadline.dueDate) {
            let effectiveDate = deadline.normalizedDueDateForRecurrence(referenceDate: Date()) ?? date
            return calculatePriority(for: effectiveDate)
        }
        return deadline.priority
    }

    private func localizedPriority(_ priority: String) -> String {
        switch priority {
        case "Авто": return L("Авто")
        case "Высокий": return L("Высокий")
        case "Средний": return L("Средний")
        case "Низкий": return L("Низкий")
        default: return priority
        }
    }

    private func localizedStatus(_ status: String) -> String {
        switch DeadlineStatus(rawStatus: status) {
        case .inProgress: return L("В процессе")
        case .completed: return L("Выполнен")
        case .cancelled: return L("Отменён")
        }
    }
    
    private func priorityIcon(for deadline: Deadline) -> String {
        switch deadline.statusType {
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        default:
            switch priority(for: deadline) {
            case "Высокий": return "exclamationmark.triangle.fill"
            case "Средний": return "exclamationmark.circle.fill"
            case "Низкий": return "clock.fill"
            default: return "circle.fill"
            }
        }
    }

    @ViewBuilder
    private func tagBadge(for tag: String) -> some View {
        Text(L(tag))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.indigo.opacity(0.15))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
                }
            )
            .foregroundStyle(Color.indigo)
            .shadow(color: Color.indigo.opacity(0.15), radius: 3, x: 0, y: 1)
    }
    
    private func fetchDeadlinesWithCurrentFilters() async {
        viewModel.configureIfNeeded(context: modelContext)
        await viewModel.fetchDeadlines(status: filterStatus, subject: filterSubject)
    }

    private func lightHaptic(intensity: CGFloat = 0.65) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred(intensity: intensity)
    }

    private func mediumHaptic(intensity: CGFloat = 0.8) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred(intensity: intensity)
    }

    private func rescheduleProNotificationsIfNeeded() {
        NotificationManager.shared.rescheduleProPressureAlerts(
            for: viewModel.deadlines,
            enabled: subscriptionManager.isPressureProUnlocked
        )

        guard subscriptionManager.isPressureProUnlocked else {
            NotificationManager.shared.cancelWeeklyPressureDigest()
            return
        }

        let report = PressureInsightsEngine().makeReport(from: viewModel.deadlines)
        let topInsight = report.insights.first ?? L("Weekly Report доступен")
        NotificationManager.shared.scheduleWeeklyPressureDigest(topInsight: topInsight)
    }
}

struct PressureModeView: View {
    let deadlines: [Deadline]
    let deadlineDateFormatter: DateFormatter
    private let legacyDeadlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
    @Environment(\.colorScheme) private var colorScheme
    @State private var criticalGlow = false
    @State private var pressurePulse = false
    @State private var now = Date()
    @State private var lastUrgencyLevel: UrgencyLevel = .green
    @State private var shakeOffset: CGFloat = 0
    @State private var lastShakeAt: Date = .distantPast
    @State private var isShaking = false
    @State private var didTrackCtaImpression = false

    private typealias DeadlineDue = (deadline: Deadline, due: Date)

    private enum UrgencyLevel: String {
        case green = "Спокойно"
        case yellow = "Внимание"
        case red = "Высокое"
        case critical = "Критический"

        var color: Color {
            switch self {
            case .green: return .green
            case .yellow: return .yellow
            case .red: return .red
            case .critical: return .pink
            }
        }

        var badgeTitle: String {
            switch self {
            case .green: return L("Низкое давление")
            case .yellow: return L("Нарастающее давление")
            case .red: return L("Высокое давление")
            case .critical: return L("Критический уровень")
            }
        }
    }

    private var activeDeadlines: [Deadline] {
        deadlines.filter { $0.statusType == .inProgress }
    }

    private var burning72Hours: [Deadline] {
        activeDeadlines
            .compactMap { deadline -> DeadlineDue? in
                guard let due = dueDateEndOfDay(deadline) else { return nil }
                return (deadline: deadline, due: due)
            }
            .filter { (item: DeadlineDue) in
                let remaining = item.due.timeIntervalSince(now)
                return remaining <= 72 * 3600
            }
            .sorted { (lhs: DeadlineDue, rhs: DeadlineDue) in
                lhs.due < rhs.due
            }
            .prefix(3)
            .map { $0.deadline }
    }

    private var nearestDeadline: DeadlineDue? {
        activeDeadlines
            .compactMap { deadline -> DeadlineDue? in
                guard let due = dueDateEndOfDay(deadline) else { return nil }
                return (deadline: deadline, due: due)
            }
            .sorted { (lhs: DeadlineDue, rhs: DeadlineDue) in
                lhs.due < rhs.due
            }
            .first
    }

    private var urgencyLevel: UrgencyLevel {
        guard let nearest = nearestDeadline else { return .green }
        let hours = nearest.due.timeIntervalSince(now) / 3600
        if hours <= 12 { return .critical }
        if hours <= 24 { return .red }
        if hours <= 72 { return .yellow }
        return .green
    }

    private var remainingText: String {
        guard let nearest = nearestDeadline else { return L("Дедлайнов нет") }
        let remaining = nearest.due.timeIntervalSince(now)
        if remaining <= 0 {
            let overdueDuration = localizedDurationString(from: max(-remaining, 60), maximumUnitCount: 2)
            return String(format: L("Просрочен на %@"), overdueDuration)
        }
        let duration = localizedDurationString(from: max(remaining, 60), maximumUnitCount: 3)
        let hasDays = remaining >= 86_400
        if hasDays {
            return String(format: L("%@ до дедлайна"), duration)
        }
        return String(format: L("Осталось %@"), duration)
    }

    private var timeProgress: Double {
        guard let nearest = nearestDeadline else { return 0 }
        let due = nearest.due
        let start = Calendar.current.date(byAdding: .day, value: -7, to: due) ?? due.addingTimeInterval(-7 * 86_400)
        let total = due.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    private var isHighPressureZone: Bool {
        urgencyLevel == .red || urgencyLevel == .critical
    }

    private var isCriticalZone: Bool {
        urgencyLevel == .critical
    }

    private var remainingSeconds: TimeInterval {
        guard let nearest = nearestDeadline else { return 0 }
        return max(nearest.due.timeIntervalSince(now), 0)
    }

    private var overdueSeconds: TimeInterval {
        guard let nearest = nearestDeadline else { return 0 }
        return max(-nearest.due.timeIntervalSince(now), 0)
    }

    private var progressPercent: Int {
        min(max(Int((timeProgress * 100).rounded()), 0), 100)
    }

    private var shouldAccentMaxPressure: Bool {
        remainingSeconds <= 60 && progressPercent >= 99
    }

    private var shouldAccentNearMaxPressure: Bool {
        progressPercent >= 95 && !shouldAccentMaxPressure
    }

    private var isDeepOverdue: Bool {
        overdueSeconds >= 24 * 3600
    }

    private var isVeryDeepOverdue: Bool {
        overdueSeconds >= 72 * 3600
    }

    private var shouldPulseRemainingText: Bool {
        urgencyLevel == .critical || shouldAccentMaxPressure || isVeryDeepOverdue
    }

    private var pressureAccentColor: Color {
        if isDeepOverdue { return .pink }
        if overdueSeconds > 0 { return .red }
        if shouldAccentMaxPressure { return .red }
        if shouldAccentNearMaxPressure { return .orange }
        return .primary
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("Режим давления"))
                            .font(.title2.weight(.semibold))

                        Text(remainingText)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(pressureAccentColor)
                            .offset(x: shakeOffset)
                            .scaleEffect(shouldPulseRemainingText ? (pressurePulse ? 1.03 : 0.98) : 1)
                            .shadow(
                                color: (shouldAccentMaxPressure || shouldAccentNearMaxPressure || overdueSeconds > 0) ? pressureAccentColor.opacity(criticalGlow ? 0.4 : 0.18) : .clear,
                                radius: (shouldAccentMaxPressure || shouldAccentNearMaxPressure || overdueSeconds > 0) ? 10 : 0,
                                x: 0,
                                y: 0
                            )
                            .contentTransition(.numericText())

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L("Прогресс"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(progressPercent)%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(pressureAccentColor)
                                    .scaleEffect(shouldPulseRemainingText ? (pressurePulse ? 1.06 : 0.96) : 1)
                            }

                            pressureBar
                        }

                        HStack(spacing: 8) {
                            Circle()
                                .fill(urgencyLevel.color)
                                .frame(width: 10, height: 10)
                            Text(urgencyLevel.badgeTitle)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(urgencyLevel.color.opacity(0.3), lineWidth: 1)
                            )
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Ближайшие 72 часа"))
                            .font(.headline)

                        if burning72Hours.isEmpty {
                            Text(L("Срочных дедлайнов пока нет"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            ForEach(burning72Hours) { deadline in
                                pressureCard(deadline)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(backgroundGradient)
            .navigationTitle(L("Режим давления"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                now = Date()
                lastUrgencyLevel = urgencyLevel
                restartPressureAnimations()
                if !didTrackCtaImpression {
                    PressureABAnalytics.shared.trackCtaImpression()
                    didTrackCtaImpression = true
                }
            }
            .onChange(of: urgencyLevel) { oldValue, newValue in
                if oldValue != .critical && newValue == .critical {
                    restartPressureAnimations()
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                now = date
                handleUrgencyTransition()
                triggerVeryDeepOverdueShakeIfNeeded(at: date)
            }
        }
    }

    private func handleUrgencyTransition() {
        let current = urgencyLevel
        if lastUrgencyLevel != .critical && current == .critical {
            let warning = UINotificationFeedbackGenerator()
            warning.prepare()
            warning.notificationOccurred(.warning)
        }
        lastUrgencyLevel = current
    }

    private func triggerVeryDeepOverdueShakeIfNeeded(at date: Date) {
        guard isVeryDeepOverdue else { return }
        guard !isShaking else { return }
        guard date.timeIntervalSince(lastShakeAt) >= 6 else { return }
        lastShakeAt = date
        runShakeSequence()
    }

    private func runShakeSequence() {
        isShaking = true
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.06)) { shakeOffset = -6 }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeInOut(duration: 0.06)) { shakeOffset = 6 }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = -4 }
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = 4 }
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.06)) { shakeOffset = 0 }
            isShaking = false
        }
    }

    private func restartPressureAnimations() {
        criticalGlow = false
        pressurePulse = false

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                criticalGlow = true
            }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pressurePulse = true
            }
        }
    }

    private var pressureBar: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width * timeProgress, 10)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [urgencyLevel.color.opacity(0.85), urgencyLevel.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .scaleEffect(y: isHighPressureZone ? (pressurePulse ? 1.05 : 0.95) : 1, anchor: .center)
                    .opacity(isHighPressureZone ? (pressurePulse ? 1 : 0.92) : 1)
                    .shadow(
                        color: timeProgress >= 0.9 ? urgencyLevel.color.opacity(criticalGlow ? 0.55 : 0.25) : .clear,
                        radius: timeProgress >= 0.9 ? 12 : 0,
                        x: 0,
                        y: 0
                    )
            }
        }
        .frame(height: 9)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color(.systemGray6).opacity(0.25)]
                : [Color(.systemGray6), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func pressureCard(_ deadline: Deadline) -> some View {
        let level = urgency(for: deadline)
        let glow = level == .critical
        let isHighPriority = deadline.statusType == .inProgress && deadline.priority == "Высокий"
        let cta = ctaInsight(for: deadline, level: level)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(deadline.title)
                    .font(.headline)
                Spacer()
                Text(remainingLabel(for: deadline))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(level.color)
            }

            Text(deadline.subject)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isHighPriority {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(L("Высокий"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.16))
                )
                .scaleEffect(pressurePulse ? 1.04 : 0.98)
                .opacity(pressurePulse ? 1 : 0.9)
                .animation(.easeInOut(duration: 0.9), value: pressurePulse)
            }

            ProgressView(value: localProgress(for: deadline))
                .tint(level.color)
                .scaleEffect(x: 1, y: 1.2, anchor: .center)

            Button {
                PressureABAnalytics.shared.trackCtaClick()
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred(intensity: 0.6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text(cta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(level.color.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: glow ? level.color.opacity(criticalGlow ? 0.45 : 0.2) : .clear, radius: 16, x: 0, y: 0)
    }

    private func dueDateEndOfDay(_ deadline: Deadline) -> Date? {
        guard let dueDate = parsedDeadlineDate(deadline.dueDate) else { return nil }
        if deadline.dueDate.contains(":") {
            return dueDate
        }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: dueDate)
    }

    private func parsedDeadlineDate(_ value: String) -> Date? {
        deadlineDateFormatter.date(from: value) ?? legacyDeadlineDateFormatter.date(from: value)
    }

    private func urgency(for deadline: Deadline) -> UrgencyLevel {
        guard let due = dueDateEndOfDay(deadline) else { return .green }
        let hours = due.timeIntervalSince(now) / 3600
        if hours <= 12 { return .critical }
        if hours <= 24 { return .red }
        if hours <= 72 { return .yellow }
        return .green
    }

    private func remainingLabel(for deadline: Deadline) -> String {
        guard let due = dueDateEndOfDay(deadline) else { return "—" }
        let interval = due.timeIntervalSince(now)
        if interval <= 0 { return L("просрочен") }
        return localizedDurationString(from: max(interval, 60), maximumUnitCount: 2)
    }

    private func localizedDurationString(from interval: TimeInterval, maximumUnitCount: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = maximumUnitCount
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        return formatter.string(from: interval) ?? "1m"
    }

    private func localProgress(for deadline: Deadline) -> Double {
        guard let due = dueDateEndOfDay(deadline) else { return 0 }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: due) ?? due.addingTimeInterval(-7 * 86_400)
        let total = due.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    private func ctaInsight(for deadline: Deadline, level: UrgencyLevel) -> String {
        let variant = PressureABAnalytics.shared.variant
        switch level {
        case .critical:
            if variant == .a {
                return L("Сделайте финальный рывок: 25 минут без отвлечений")
            }
            return L("Критическая зона: закройте самый важный шаг в ближайшие 20 минут")
        case .red:
            if variant == .a {
                return L("Разбейте задачу на 3 шага и начните с первого")
            }
            return L("Высокое давление: начните с черновика, потом шлифуйте")
        case .yellow:
            if variant == .a {
                return L("Запланируйте первый блок работы сегодня")
            }
            return L("Окно 72ч: выделите 45 минут сегодня, чтобы снять риск")
        case .green:
            if deadline.priority == "Высокий" {
                return variant == .a
                    ? L("Высокий приоритет: выделите 30 минут заранее")
                    : L("Ранний старт даст запас: заложите 30 минут сегодня")
            }
            return variant == .a
                ? L("Нагрузка под контролем: закрепите прогресс короткой сессией")
                : L("Сейчас спокойный этап: сделайте мини-шаг, пока есть запас")
        }
    }
}

// MARK: - Deadline Detail Sheet
struct DeadlineDetailSheet: View {
    let deadline: Deadline
    @Environment(\.dismiss) private var dismiss
    
    private let reminderLabels: [String: String] = [
        "none": L("Без напоминания"),
        "1hour": L("За час"),
        "1day": L("За день"),
        "1week": L("За неделю")
    ]
    
    private let repeatLabels: [String: String] = [
        "none": L("Без повторения"),
        "daily": L("Ежедневно"),
        "weekly": L("Еженедельно"),
        "monthly": L("Ежемесячно"),
        "yearly": L("Ежегодно")
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(deadline.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            Label(deadline.subject, systemImage: "book")
                            Spacer()
                            Text(L(deadline.status))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(statusColor.opacity(0.2))
                                .foregroundStyle(statusColor)
                                .clipShape(Capsule())
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(L("Дата")) {
                    Label(formattedDate, systemImage: "calendar")
                }
                
                if !deadline.tags.isEmpty {
                    Section(L("Теги")) {
                        HStack(spacing: 8) {
                            ForEach(deadline.tags, id: \.self) { tag in
                                Text(L(tag))
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.indigo.opacity(0.15))
                                    .foregroundStyle(Color.indigo)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                Section(L("Настройки")) {
                    Label(repeatLabels[deadline.repeatType] ?? "Без повторения", systemImage: "repeat")
                    Label(reminderLabels[deadline.reminderTime] ?? "За день", systemImage: "bell")
                }
                
                if !deadline.notes.isEmpty {
                    Section(L("Заметки")) {
                        Text(deadline.notes)
                            .font(.body)
                    }
                }
            }
            .navigationTitle(L("Детали"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = deadline.normalizedDueDateForRecurrence() ?? inputFormatter.date(from: deadline.dueDate) ?? legacyFormatter.date(from: deadline.dueDate) else { return deadline.dueDate }
        if deadline.hasTimeInDueDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    
    private var statusColor: Color {
        switch deadline.statusType {
        case .completed: return .green
        case .cancelled: return .gray
        default: return .indigo
        }
    }
}

// MARK: - Archive View
struct ArchiveView: View {
    @ObservedObject var viewModel: DeadlineViewModel
    @Environment(\.dismiss) private var dismiss
    
    var archived: [Deadline] {
        viewModel.deadlines.filter { $0.statusType == .completed || $0.statusType == .cancelled }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.indigo)
                        Text(L("Задачи в архиве удаляются автоматически через 30 дней."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                ForEach(archived) { deadline in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deadline.title)
                            .font(.headline)
                        Text("\(deadline.subject) — \(formattedDate(deadline)) — \(L(deadline.status))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !deadline.notes.isEmpty {
                            Text(deadline.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            mediumHaptic()
                            Task { await viewModel.deleteDeadline(id: deadline.id) }
                        } label: {
                            Label(L("Удалить"), systemImage: "trash")
                        } .tint(.red)
                        Button {
                            lightHaptic()
                            var restored = deadline
                            restored.statusType = .inProgress
                            restored.deletedAt = nil
                            Task { await viewModel.updateDeadline(restored) }
                        } label: {
                            Label(L("Восстановить"), systemImage: "arrow.uturn.left")
                        }
                        .tint(.green)
                    }
                }
            }
            .navigationTitle(L("Архив"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) { dismiss() }
                }
            }
        }
    }
    
    private func formattedDate(_ deadline: Deadline) -> String {
        guard let date = deadline.normalizedDueDateForRecurrence() else { return deadline.dueDate }
        if deadline.hasTimeInDueDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func lightHaptic(intensity: CGFloat = 0.65) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred(intensity: intensity)
    }

    private func mediumHaptic(intensity: CGFloat = 0.8) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred(intensity: intensity)
    }
}

