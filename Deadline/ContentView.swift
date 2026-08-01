import SwiftUI
import SwiftData
import UIKit
import Combine

func L(_ key: String) -> String {
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

struct WeeklyReportView: View {
    let deadlines: [Deadline]
    private let engine = PressureInsightsEngine()
    @Environment(\.dismiss) private var dismiss

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
                .iPadReadableContent(maxWidth: 720)
            }
            .navigationTitle(L("Weekly Report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label(L("Назад"), systemImage: "chevron.left")
                    }
                }
            }
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

private struct AdaptiveTabViewStyleModifier: ViewModifier {
    let useSidebar: Bool

    func body(content: Content) -> some View {
        if useSidebar {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content.tabViewStyle(.automatic)
        }
    }
}

private struct RootTabPresentationModifier: ViewModifier {
    @Binding var showPressurePaywall: Bool
    @Binding var showOnboarding: Bool
    @ObservedObject var subscriptionManager: SubscriptionManager
    let onOnboardingDismissed: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPressurePaywall) {
                PressurePaywallView(subscriptionManager: subscriptionManager)
                    .iPadSheetPresentation()
            }
            .onChange(of: showPressurePaywall) { _, shown in
                if shown {
                    PressureABAnalytics.shared.trackPaywallShown()
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
                    .iPadSheetPresentation()
            }
            .onChange(of: showOnboarding) { _, isShowing in
                if !isShowing { onOnboardingDismissed() }
            }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DeadlineViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @AppStorage("hasDismissedTasksPressureHint") private var hasDismissedTasksPressureHint = false
    @AppStorage("hasCompletedProductOnboarding") private var hasCompletedProductOnboarding = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAppearance = false
    @State private var showSubscription = false
    @State private var showWeeklyReport = false
    @State private var showCalendarSettings = false
    @State private var showAccountSettings = false
    @State private var showProductHelp = false
    @State private var selectedTab: MainTab = .deadlines
    @State private var showPressurePaywall = false
    @State private var showArchive = false
    
    // Поля для добавления новой задачи
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
    @State private var selectedSplitDeadlineID: String?
    @State private var searchQuery = ""
    @State private var isSearchExpanded = false
    @State private var showOnboarding = false
    @State private var pendingUndo: UndoableDeadlineAction?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var pressureEntranceToken = 0
    @FocusState private var isSearchFocused: Bool
    
    private var syncStatusBanner: some View {
        Group {
            if viewModel.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text(L("Нет сети · показаны локальные данные"))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(.vertical, 4)
            } else if let message = viewModel.lastSyncError {
                Text(String(format: L("Ошибка синхронизации: %@"), message))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            }
        }
    }
    
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
        rootTabInterface
    }

    private var undoToastAppearAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 0.82)
    }

    private var undoToastDismissAnimation: Animation {
        .spring(response: 0.30, dampingFraction: 0.92)
    }

    private var undoToastTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 18)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.96, anchor: .bottom)),
            removal: .offset(y: 10)
                .combined(with: .opacity)
        )
    }

    private var undoToastLift: CGFloat {
        horizontalSizeClass == .regular ? 12 : 56
    }

    private var rootTabInterface: some View {
        rootTabCore
            .modifier(RootTabPresentationModifier(
                showPressurePaywall: $showPressurePaywall,
                showOnboarding: $showOnboarding,
                subscriptionManager: subscriptionManager,
                onOnboardingDismissed: { hasCompletedProductOnboarding = true }
            ))
            .onChange(of: selectedTab) { _, newValue in
                handleSelectedTabChange(newValue)
            }
            .onChange(of: subscriptionManager.isPressureProUnlocked) { _, _ in
                rescheduleProNotificationsIfNeeded()
            }
            .onReceive(viewModel.$deadlines) { _ in
                rescheduleProNotificationsIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                rescheduleNotificationsForCurrentLanguage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deadlineExternalAction)) { notification in
                handleDeadlineExternalAction(notification)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await viewModel.processPendingWidgetActions()
                        await subscriptionManager.refreshEntitlements()
                    }
                }
            }
            .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
            .animation(.easeInOut(duration: 0.2), value: appTheme)
            .tint(.indigo)
    }

    private var rootTabCore: some View {
        TabView(selection: $selectedTab) {
            deadlinesTab
            pressureTab
        }
        .modifier(AdaptiveTabViewStyleModifier(useSidebar: horizontalSizeClass == .regular))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            undoToastInset
        }
    }

    private func handleSelectedTabChange(_ newValue: MainTab) {
        guard newValue == .pressure else { return }
        if subscriptionManager.isPressureProUnlocked {
            pressureEntranceToken += 1
            pressureTabHaptic()
        } else {
            selectedTab = .deadlines
            showPressurePaywall = true
            PressureABAnalytics.shared.trackPaywallShown()
        }
    }

    @ViewBuilder
    private var undoToastInset: some View {
        if let pendingUndo {
            DeadlineUndoToast(action: pendingUndo) {
                Task { await undoDeadlineAction() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, undoToastLift)
            .transition(undoToastTransition)
        }
    }

    private var deadlinesTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                taskActionRow

                filterControls
                    .padding(.horizontal)
                    .padding(.top, 8)

                if !hasDismissedTasksPressureHint {
                    tasksPressureHintBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                if hasActiveSearch && !sections.isEmpty {
                    searchResultsBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                deadlineList
            }
            .sheet(isPresented: $isFormExpanded) {
                addFormSheet
                    .iPadFormSheetPresentation()
            }
            .onAppear {
                NotificationManager.shared.requestAuthorization()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.configureIfNeeded(context: modelContext)
                viewModel.applyFilters(status: filterStatus, subject: filterSubject)
                rescheduleProNotificationsIfNeeded()
                await AuthService.shared.refreshBackendTokenIfNeeded()
                await viewModel.processPendingWidgetActions()
                await viewModel.syncNow()
                if !hasCompletedProductOnboarding {
                    showOnboarding = true
                }
            }
            .onChange(of: filterStatus) { oldValue, newValue in
                guard newValue != oldValue else { return }
                viewModel.applyFilters(status: filterStatus, subject: filterSubject)
                Task { await viewModel.syncNow() }
            }
            .onChange(of: filterSubject) { oldValue, newValue in
                guard newValue != oldValue else { return }
                viewModel.applyFilters(status: filterStatus, subject: filterSubject)
                Task { await viewModel.syncNow() }
            }
            .sheet(item: $editingDeadline, onDismiss: { editingDeadline = nil }) { edit in
                EditDeadlineView(deadline: edit) { updated in
                    Task {
                        await viewModel.updateDeadline(updated)
                        editingDeadline = nil
                    }
                }
                .iPadFormSheetPresentation()
            }
            .sheet(isPresented: $showArchive) {
                ArchiveView(viewModel: viewModel)
                    .iPadSheetPresentation()
            }
            .sheet(isPresented: $showAppearance) {
                NavigationStack {
                    AppearanceView()
                }
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .iPadSheetPresentation()
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionStatusView(subscriptionManager: subscriptionManager) {
                    showSubscription = false
                    showPressurePaywall = true
                }
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .iPadSheetPresentation()
            }
            .sheet(isPresented: $showWeeklyReport) {
                WeeklyReportView(deadlines: viewModel.deadlines)
                    .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                    .iPadSheetPresentation()
            }
            .sheet(isPresented: $showCalendarSettings) {
                NavigationStack {
                    CalendarSettingsView()
                }
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .iPadSheetPresentation()
            }
            .sheet(isPresented: $showAccountSettings) {
                NavigationStack {
                    AccountSettingsView()
                }
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .iPadSheetPresentation()
            }
            .sheet(isPresented: $showProductHelp) {
                ProductHelpView()
                    .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                    .iPadSheetPresentation()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Redloop")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        profileMenuContent
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
            Label(L("Задачи"), systemImage: "list.bullet.rectangle")
        }
        .tag(MainTab.deadlines)
    }

    @ViewBuilder
    private var profileMenuContent: some View {
        Section(L("Профиль")) {
            Button {
                showAccountSettings = true
            } label: {
                if let email = AuthService.shared.currentEmail {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Аккаунт"))
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                } else {
                    Label(L("Аккаунт"), systemImage: "person.crop.circle")
                }
            }
            .accessibilityIdentifier("openAccountSettingsButton")
        }

        Section(L("Настройки")) {
            Button {
                showAppearance = true
            } label: {
                Label(L("Оформление"), systemImage: "circle.lefthalf.filled")
            }

            Button {
                showCalendarSettings = true
            } label: {
                Label(L("Календарь iOS"), systemImage: "calendar")
            }

            Button {
                showArchive = true
            } label: {
                Label(L("Архив"), systemImage: "archivebox")
            }

            Button {
                showProductHelp = true
            } label: {
                Label(L("Как устроен Redloop"), systemImage: "questionmark.circle")
            }
        }

        Section(L("Режим давления")) {
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
                Label(L("Weekly Report"), systemImage: "chart.bar.doc.horizontal")
            }
        }

        Section {
            Button(role: .destructive) {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred(intensity: 0.65)
                AuthService.shared.logout()
            } label: {
                Label(L("Выйти"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private var pressureTab: some View {
        PressureModeView(
            deadlines: viewModel.deadlines,
            deadlineDateFormatter: deadlineDateFormatter,
            showsTasksPressureHint: !hasDismissedTasksPressureHint,
            entranceToken: pressureEntranceToken,
            onDismissTasksPressureHint: { hasDismissedTasksPressureHint = true },
            onCompleteDeadline: { deadline in
                Task { await completeDeadlineWithUndo(deadline) }
            }
        )
            .tabItem {
                Label(L("Режим давления"), systemImage: "exclamationmark.triangle.fill")
            }
            .tag(MainTab.pressure)
    }

    private var tasksPressureHintBanner: some View {
        TasksPressureHintBanner {
            hasDismissedTasksPressureHint = true
        }
    }
    
    // MARK: - Task Action Row
    private var taskActionRow: some View {
        HStack(spacing: 10) {
            if isSearchExpanded {
                searchFieldBar
            } else {
                addTaskButton
                searchToggleButton
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: isSearchExpanded)
    }

    private var addTaskButton: some View {
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
        }
        .buttonStyle(CompactIndigoButtonStyle())
        .accessibilityIdentifier("openAddDeadlineButton")
        .onAppear {
            addButtonBreathing = false
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    addButtonBreathing = true
                }
            }
        }
        .onDisappear {
            addButtonBreathing = false
        }
    }

    private var searchToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
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
        }
        .buttonStyle(CompactIndigoButtonStyle())
        .accessibilityLabel(L("Поиск задач"))
    }

    private var searchFieldBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(L("Поиск задач"), text: $searchQuery)
                .font(.subheadline)
                .focused($isSearchFocused)
                .submitLabel(.search)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchExpanded = false
                    searchQuery = ""
                    isSearchFocused = false
                }
            } label: {
                Text(L("Отмена"))
                    .font(.subheadline)
                    .foregroundStyle(Color.indigo)
            }
        }
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
        .frame(maxWidth: .infinity)
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
        let priority: String
        let pulsing: Bool

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            AccessibleCapsuleBadge(
                iconName: iconName,
                title: title,
                style: BadgeContrastStyle.forPriority(priority, scheme: colorScheme),
                pulsing: pulsing,
                accessibilityLabel: title
            )
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
                    Text(L("Новая задача"))
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
            priority = newPriority == "Авто" ? "Авто" : newPriority
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Фильтры"))
                    .font(.headline)

                if activeFilterCount > 0 {
                    activeFilterBadge
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(filterTrayTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(filterTrayStroke, lineWidth: 1)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .light ? 0.06 : 0.03),
                                        Color.clear,
                                        Color.black.opacity(colorScheme == .light ? 0.05 : 0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.normal)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(filterTrayTopHighlight, lineWidth: 1)
                            .mask(
                                LinearGradient(
                                    colors: [.white.opacity(0.95), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .shadow(color: filterTrayShadow, radius: 14, x: 0, y: 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Menu {
                            Picker("Статус", selection: $filterStatus) {
                                ForEach(statusOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(selectedLabel(for: filterStatus, in: statusOptions))
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .foregroundStyle(chipForegroundColor(isActive: !filterStatus.isEmpty, accent: .indigo))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .fill(chipFillColor(isActive: !filterStatus.isEmpty, accent: .indigo))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(chipStrokeColor(isActive: !filterStatus.isEmpty, accent: .indigo), lineWidth: 1)
                                    )
                            )
                            .shadow(color: chipShadowColor(isActive: !filterStatus.isEmpty, accent: .indigo), radius: !filterStatus.isEmpty ? 9 : 0, x: 0, y: !filterStatus.isEmpty ? 5 : 0)
                        }
                        .accessibilityIdentifier("filterStatusPicker")

                        Menu {
                            Picker(L("Предмет"), selection: $filterSubject) {
                                ForEach(subjectOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(selectedLabel(for: filterSubject, in: subjectOptions))
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .foregroundStyle(chipForegroundColor(isActive: !filterSubject.isEmpty, accent: .indigo))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .fill(chipFillColor(isActive: !filterSubject.isEmpty, accent: .indigo))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(chipStrokeColor(isActive: !filterSubject.isEmpty, accent: .indigo), lineWidth: 1)
                                    )
                            )
                            .shadow(color: chipShadowColor(isActive: !filterSubject.isEmpty, accent: .indigo), radius: !filterSubject.isEmpty ? 9 : 0, x: 0, y: !filterSubject.isEmpty ? 5 : 0)
                        }
                        .accessibilityIdentifier("filterSubjectPicker")

                        Spacer()
                            .frame(width: 4.5)

                        Menu {
                            Picker(L("Сортировка"), selection: $sortMode) {
                                ForEach(SortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.arrow.down.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(sortMode.title)
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(0.86)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .foregroundStyle(chipForegroundColor(isActive: true, accent: .indigo, prominent: true))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .fill(chipFillColor(isActive: true, accent: .indigo, prominent: true))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(chipStrokeColor(isActive: true, accent: .indigo, prominent: true), lineWidth: 1.1)
                                    )
                            )
                            .shadow(color: chipShadowColor(isActive: true, accent: .indigo, prominent: true), radius: 11, x: 0, y: 6)
                        }
                        .accessibilityIdentifier("sortModePicker")

                        if !filterStatus.isEmpty || !filterSubject.isEmpty {
                            Button {
                                filterStatus = ""
                                filterSubject = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(Color.red.opacity(colorScheme == .light ? 0.95 : 0.9))
                                .background(
                                    Circle()
                                        .fill(.regularMaterial)
                                        .overlay(
                                            Circle()
                                                .fill(colorScheme == .light ? Color.red.opacity(0.22) : Color.red.opacity(0.3))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.red.opacity(colorScheme == .light ? 0.58 : 0.66), lineWidth: 1.2)
                                        )
                                )
                                    .shadow(color: Color.red.opacity(colorScheme == .light ? 0.22 : 0.32), radius: 9, x: 0, y: 4)
                            }
                            .accessibilityLabel(Text(L("Сбросить")))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                HStack {
                    LinearGradient(
                        colors: [filterTrayEdgeMask, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)
                    .shadow(color: filterTrayEdgeSoftShadow, radius: 5, x: 2, y: 0)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, filterTrayEdgeMask],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)
                    .shadow(color: filterTrayEdgeSoftShadow, radius: 5, x: -2, y: 0)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 58)
        }
    }

    private var activeFilterBadge: some View {
        let style = BadgeContrastStyle.forAccent(scheme: colorScheme)
        return Text("\(activeFilterCount)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(style.foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(style.stroke, lineWidth: 1)
                    )
            )
            .accessibilityLabel(String(format: L("Активных фильтров: %d"), activeFilterCount))
    }

    private func selectedLabel(for value: String, in options: [(label: String, value: String)]) -> String {
        options.first(where: { $0.value == value })?.label ?? options.first?.label ?? ""
    }

    private var filterTrayTint: Color {
        colorScheme == .light ? Color.black.opacity(0.03) : Color.black.opacity(0.2)
    }

    private var filterTrayStroke: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.1)
    }

    private var filterTrayTopHighlight: Color {
        colorScheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.1)
    }

    private var filterTrayShadow: Color {
        colorScheme == .light ? Color.black.opacity(0.1) : Color.black.opacity(0.3)
    }

    private var filterTrayEdgeMask: Color {
        colorScheme == .light ? Color.white.opacity(0.6) : Color.black.opacity(0.55)
    }

    private var filterTrayEdgeSoftShadow: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : .clear
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterStatus.isEmpty { count += 1 }
        if !filterSubject.isEmpty { count += 1 }
        return count
    }

    private var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    private func resetFilters() {
        filterStatus = ""
        filterSubject = ""
    }

    private func chipFillColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            if prominent {
                return colorScheme == .light ? accent.opacity(0.52) : accent.opacity(0.62)
            }
            return colorScheme == .light ? accent.opacity(0.44) : accent.opacity(0.54)
        }
        return colorScheme == .light ? Color.white.opacity(0.18) : Color.white.opacity(0.06)
    }

    private func chipStrokeColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            if prominent {
                return accent.opacity(colorScheme == .light ? 0.82 : 0.88)
            }
            return accent.opacity(colorScheme == .light ? 0.72 : 0.8)
        }
        return Color.primary.opacity(colorScheme == .light ? 0.12 : 0.2)
    }

    private func chipForegroundColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            return colorScheme == .light ? Color.white.opacity(prominent ? 1.0 : 0.98) : Color.white.opacity(prominent ? 0.98 : 0.95)
        }
        return .primary
    }

    private func chipShadowColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        guard isActive else { return .clear }
        if prominent {
            return accent.opacity(colorScheme == .light ? 0.2 : 0.3)
        }
        return accent.opacity(colorScheme == .light ? 0.16 : 0.24)
    }

    // MARK: - Deadline List
    private var deadlineList: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadDeadlineSplitView
            } else if sections.isEmpty {
                ScrollView {
                    emptyStateForCurrentContext
                        .frame(maxWidth: .infinity)
                        .padding(.top, 56)
                        .padding(.horizontal, 24)
                }
            } else {
                List {
                    ForEach(sections) { section in
                        Section(header: deadlineSectionHeader(key: section.key, title: section.title)) {
                            ForEach(section.items) { deadline in
                                deadlineRow(deadline)
                                    .transition(.opacity)
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
            DeadlineDetailSheet(
                deadline: deadline,
                viewModel: viewModel,
                onEdit: {
                    detailDeadline = nil
                    editingDeadline = deadline
                },
                onComplete: { item in
                    await completeDeadlineWithUndo(item)
                }
            )
        }
    }

    private var splitSelectedDeadline: Deadline? {
        guard let selectedSplitDeadlineID else { return nil }
        return sections.flatMap(\.items).first { $0.id == selectedSplitDeadlineID }
    }

    private var iPadDeadlineSplitView: some View {
        NavigationSplitView {
            Group {
                if sections.isEmpty {
                    ScrollView {
                        emptyStateForCurrentContext
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                            .padding(.horizontal, 24)
                    }
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(header: deadlineSectionHeader(key: section.key, title: section.title)) {
                                ForEach(section.items) { deadline in
                                    iPadSplitDeadlineRow(
                                        deadline,
                                        isSelected: selectedSplitDeadlineID == deadline.id
                                    )
                                    .onTapGesture {
                                        guard selectedSplitDeadlineID != deadline.id else { return }
                                        selectedSplitDeadlineID = deadline.id
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .navigationTitle(L("Задачи"))
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 480)
        } detail: {
            if let deadline = splitSelectedDeadline {
                DeadlineDetailSheet(
                    deadline: deadline,
                    viewModel: viewModel,
                    isEmbeddedInSplitView: true,
                    onEdit: {
                        editingDeadline = deadline
                    },
                    onComplete: { item in
                        await completeDeadlineWithUndo(item)
                    }
                )
                .id(deadline.id)
            } else {
                ContentUnavailableView {
                    Label(L("Выберите задачу"), systemImage: "list.bullet.rectangle")
                } description: {
                    Text(L("Нажмите на задачу слева, чтобы увидеть детали и действия"))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSplitDeadlineID) { oldID, newID in
            guard horizontalSizeClass == .regular, oldID != newID, newID != nil else { return }
            lightHaptic()
        }
        .refreshable {
            await viewModel.syncNow()
        }
        .onAppear {
            syncSelectedSplitDeadlineIfNeeded()
        }
        .onChange(of: viewModel.deadlines.count) { _, _ in
            syncSelectedSplitDeadlineIfNeeded()
        }
        .onChange(of: filterStatus) { _, _ in
            syncSelectedSplitDeadlineIfNeeded()
        }
        .onChange(of: filterSubject) { _, _ in
            syncSelectedSplitDeadlineIfNeeded()
        }
        .onChange(of: searchQuery) { _, _ in
            syncSelectedSplitDeadlineIfNeeded()
        }
    }

    private func syncSelectedSplitDeadlineIfNeeded() {
        guard horizontalSizeClass == .regular else { return }

        let visible = sections.flatMap(\.items)
        guard !visible.isEmpty else {
            selectedSplitDeadlineID = nil
            return
        }

        if let selectedSplitDeadlineID,
           visible.contains(where: { $0.id == selectedSplitDeadlineID }) {
            return
        }

        selectedSplitDeadlineID = visible.first?.id
    }

    private func openDeadlineDetail(_ deadline: Deadline) {
        if horizontalSizeClass == .regular {
            selectedSplitDeadlineID = deadline.id
        } else {
            detailDeadline = deadline
        }
    }

    @ViewBuilder
    private var emptyStateForCurrentContext: some View {
        if hasActiveSearch {
            searchEmptyDeadlinesView
        } else if hasActiveFilters {
            filteredEmptyDeadlinesView
        } else {
            emptyDeadlinesView
        }
    }

    private var hasActiveSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResultsBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(String(format: L("Найдено: %d"), mainScreenDeadlines.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(L("Поиск по названию, категории и тегам"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.indigo.opacity(0.08))
        )
    }

    private var emptyDeadlinesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.indigo.opacity(0.9))

            Text(L("Пока нет напоминаний"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(L("Добавьте задачу с дедлайном — Redloop напомнит и покажет срочность"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isFormExpanded = true
            } label: {
                Text(L("Добавить первую задачу"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
        }
        .padding(.vertical, 16)
    }

    private var searchEmptyDeadlinesView: some View {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.indigo.opacity(0.9))

            Text(L("Ничего не найдено"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(String(format: L("Нет результатов для «%@»"), query))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                clearSearch()
            } label: {
                Text(L("Очистить поиск"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
        }
        .padding(.vertical, 16)
        .accessibilityIdentifier("searchEmptyState")
    }

    private func clearSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchExpanded = false
            searchQuery = ""
            isSearchFocused = false
        }
    }

    private var filteredEmptyDeadlinesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.indigo.opacity(0.9))

            Text(L("Нет задач в этой категории."))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("filteredEmptyState")

            Text(L("Смените статус или предмет — или сбросьте фильтры"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                resetFilters()
            } label: {
                Text(L("Сбросить фильтры"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
        }
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private func iPadSplitDeadlineRow(_ deadline: Deadline, isSelected: Bool) -> some View {
        let priorityValue = priority(for: deadline)
        let tintColor = color(for: deadline, resolvedPriority: priorityValue)
        let effectiveDate = effectiveDueDate(for: deadline)
        let isUrgent = deadline.statusType == .inProgress &&
            (isOverdue(deadline, effectiveDate: effectiveDate) || isDueToday(deadline, effectiveDate: effectiveDate))
        let selectedFillOpacity = colorScheme == .light ? 0.10 : 0.16
        let titleColor = Color.primary
        let subtitleColor = Color.secondary

        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tintColor.opacity(isSelected ? 1 : 0.75))
                .frame(width: isSelected ? 4 : 3)
                .frame(maxHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deadline.title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)

                    if deadline.repeatType != "none" {
                        Image(systemName: "repeat")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                }

                Text(compactCardSubtitle(for: deadline))
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)

                if isUrgent, shouldShowPriorityBadge(priorityValue) {
                    Text(priorityBadgeTitle(for: deadline, resolvedPriority: priorityValue))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tintColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? tintColor.opacity(selectedFillOpacity)
                        : Color(.secondarySystemGroupedBackground)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? tintColor.opacity(colorScheme == .light ? 0.45 : 0.55) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(deadlineAccessibilityLabel(for: deadline, priority: priorityValue))
        .accessibilityHint(L("Открыть детали задачи"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
    private func deadlineRow(_ deadline: Deadline) -> some View {
        let priorityValue = priority(for: deadline)
        let tintColor = color(for: deadline, resolvedPriority: priorityValue)
        let effectiveDate = effectiveDueDate(for: deadline)
        let shouldPulse = deadline.statusType == .inProgress &&
            (isOverdue(deadline, effectiveDate: effectiveDate) || isDueToday(deadline, effectiveDate: effectiveDate))
        let displayTags = nonDuplicateTags(for: deadline)

        DeadlineGlassBox(
            deadline: deadline,
            color: tintColor,
            reducedEffects: priorityValue == "Низкий"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(deadline.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
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

                Text(compactCardSubtitle(for: deadline))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if shouldShowPriorityBadge(priorityValue) {
                    PriorityBadge(
                        iconName: priorityIcon(for: deadline, resolvedPriority: priorityValue),
                        title: priorityBadgeTitle(for: deadline, resolvedPriority: priorityValue),
                        priority: priorityValue,
                        pulsing: shouldPulse
                    )
                    .accessibilityIdentifier("priorityBadge")
                    .shadow(color: tintColor.opacity(0.15), radius: 3, x: 0, y: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !displayTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(displayTags, id: \.self) { tag in
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
        .contentShape(Rectangle())
        .onTapGesture {
            openDeadlineDetail(deadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(deadlineAccessibilityLabel(for: deadline, priority: priorityValue))
        .accessibilityHint(L("Открыть детали задачи"))
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
            Task { await deleteDeadlineWithUndo(deadline) }
        } label: {
            Label(L("Удалить"), systemImage: "trash")
        }
        .tint(.red)
        Button {
            lightHaptic()
            editingDeadline = deadline
        } label: {
            Label(L("Редактировать"), systemImage: "pencil")
        }
        .tint(.indigo)
    }
    
    @ViewBuilder
    private func leadingSwipeActions(for deadline: Deadline) -> some View {
        if deadline.statusType != .completed {
            Button(role: .destructive) {
                Task { await completeDeadlineWithUndo(deadline) }
            } label: {
                Label(L("Выполнен"), systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }
    
    @ViewBuilder
    private func contextMenu(for deadline: Deadline) -> some View {
        Button {
            openDeadlineDetail(deadline)
        } label: {
            Label(L("Подробнее"), systemImage: "info.circle")
        }
        
        Button {
            lightHaptic()
            editingDeadline = deadline
        } label: {
            Label(L("Редактировать"), systemImage: "pencil")
        } 
        
        if deadline.statusType != .completed {
            Button {
                Task { await completeDeadlineWithUndo(deadline) }
            } label: {
                Label(L("Отметить выполненным"), systemImage: "checkmark.circle")
            }.tint(.green)
        }
        
        Button(role: .destructive) {
            Task { await deleteDeadlineWithUndo(deadline) }
        } label: {
            Label(L("Удалить"), systemImage: "trash")
        } .tint(.red)
    }
    
    private struct DeadlineListSection: Identifiable {
        let key: String
        let title: String
        let items: [Deadline]
        var id: String { key }
    }

    private var sections: [DeadlineListSection] {
        switch sortMode {
        case .date:
            return sectionsByDate()
        case .tag:
            return sectionsByTag()
        }
    }

    @ViewBuilder
    private func deadlineSectionHeader(key: String, title: String) -> some View {
        HStack(spacing: 6) {
            if key == "Просрочено" {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            } else if key == "Горит сегодня" {
                Image(systemName: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .padding(.top, (key == "Просрочено" || key == "Горит сегодня") ? 4 : 8)
        .padding(.bottom, (key == "Просрочено" || key == "Горит сегодня") ? 0 : 2)
    }

    private var mainScreenDeadlines: [Deadline] {
        let base = viewModel.deadlines.filter { $0.deletedAt == nil }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        let lowered = query.lowercased()
        return base.filter { deadline in
            deadline.title.lowercased().contains(lowered)
                || deadline.subject.lowercased().contains(lowered)
                || deadline.notes.lowercased().contains(lowered)
                || deadline.localizedSubjectName.lowercased().contains(lowered)
                || deadline.tags.contains { $0.lowercased().contains(lowered) }
        }
    }
    
    private func sectionsByDate() -> [DeadlineListSection] {
        var groups: [String: [Deadline]] = [:]
        let calendar = Calendar.current
        let today = Date()
        let dateCache = buildEffectiveDateCache(for: mainScreenDeadlines)
        
        for deadline in mainScreenDeadlines {
            guard let date = dateCache[deadline.id] else { continue }

            let key: String
            if isOverdue(deadline, effectiveDate: date) {
                key = "Просрочено"
            } else if isDueToday(deadline, effectiveDate: date) {
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
        
        let predefinedOrder = ["Просрочено", "Горит сегодня", "Сегодня", "На этой неделе", "Позже"]
        var result: [DeadlineListSection] = []
        
        for key in predefinedOrder {
            if let items = groups.removeValue(forKey: key), !items.isEmpty {
                result.append(DeadlineListSection(key: key, title: L(key), items: sortByStatus(items, dateCache: dateCache)))
            }
        }
        
        for key in groups.keys.sorted() {
            if let items = groups[key] {
                result.append(DeadlineListSection(key: key, title: L(key), items: sortByStatus(items, dateCache: dateCache)))
            }
        }
        
        return result
    }
    
    private func sectionsByTag() -> [DeadlineListSection] {
        var groups: [String: [Deadline]] = [:]
        for deadline in mainScreenDeadlines {
            let key = deadline.tags.sorted().first ?? "Без тегов"
            groups[key, default: []].append(deadline)
        }
        let dateCache = buildEffectiveDateCache(for: mainScreenDeadlines)
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
            return DeadlineListSection(key: key, title: L(key), items: sortByDueDate(items, dateCache: dateCache))
        }
    }
    
    private func sortByStatus(_ deadlines: [Deadline], dateCache: [String: Date]) -> [Deadline] {
        return deadlines.sorted { lhs, rhs in
            let lhsStatus = lhs.statusType.sortOrder
            let rhsStatus = rhs.statusType.sortOrder
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }

            let lhsUrgency = urgencyRank(lhs, effectiveDate: dateCache[lhs.id])
            let rhsUrgency = urgencyRank(rhs, effectiveDate: dateCache[rhs.id])
            if lhsUrgency != rhsUrgency { return lhsUrgency < rhsUrgency }

            if lhs.subject != rhs.subject { return lhs.subject < rhs.subject }
            return compareByDueDate(lhs, rhs, dateCache: dateCache)
        }
    }
    
    private func sortByDueDate(_ deadlines: [Deadline], dateCache: [String: Date]) -> [Deadline] {
        deadlines.sorted { lhs, rhs in
            compareByDueDate(lhs, rhs, dateCache: dateCache)
        }
    }
    
    private func compareByDueDate(_ lhs: Deadline, _ rhs: Deadline, dateCache: [String: Date]? = nil) -> Bool {
        let lhsDate = dateCache?[lhs.id] ?? effectiveDueDate(for: lhs) ?? .distantPast
        let rhsDate = dateCache?[rhs.id] ?? effectiveDueDate(for: rhs) ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    private func isOverdue(_ deadline: Deadline, effectiveDate: Date? = nil) -> Bool {
        if let effectiveDate {
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            let dueStart = calendar.startOfDay(for: effectiveDate)
            guard deadline.statusType == .inProgress else { return false }
            return dueStart < todayStart
        }
        return deadline.isOverdue()
    }

    private func isDueToday(_ deadline: Deadline, effectiveDate: Date? = nil) -> Bool {
        if let effectiveDate {
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            let dueStart = calendar.startOfDay(for: effectiveDate)
            guard deadline.statusType == .inProgress else { return false }
            return dueStart == todayStart
        }
        return deadline.isDueToday()
    }

    private func urgencyRank(_ deadline: Deadline, effectiveDate: Date? = nil) -> Int {
                        guard deadline.statusType == .inProgress,
                            let dueDate = effectiveDate ?? effectiveDueDate(for: deadline) else { return 5 }

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
    private func color(for deadline: Deadline, resolvedPriority: String? = nil) -> Color {
        switch deadline.statusType {
        case .completed:
            return .green
        case .cancelled:
            return .gray
        default:
            let priorityValue = resolvedPriority ?? priority(for: deadline)
            switch priorityValue {
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

    private func effectiveDueDate(for deadline: Deadline, referenceDate: Date = Date()) -> Date? {
        guard let rawDate = parsedDeadlineDate(deadline.dueDate) else { return nil }
        let normalized = deadline.normalizedDueDateForRecurrence(referenceDate: referenceDate) ?? rawDate
        if !deadline.hasTimeInDueDate {
            return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: normalized) ?? normalized
        }
        return normalized
    }

    private func buildEffectiveDateCache(for deadlines: [Deadline]) -> [String: Date] {
        let now = Date()
        var cache: [String: Date] = [:]
        cache.reserveCapacity(deadlines.count)

        for deadline in deadlines {
            if let date = effectiveDueDate(for: deadline, referenceDate: now) {
                cache[deadline.id] = date
            }
        }

        return cache
    }

    // MARK: - Priority Helpers
    private func priority(for deadline: Deadline) -> String {
        deadline.resolvedPriority()
    }

    private func shouldShowPriorityBadge(_ priority: String) -> Bool {
        priority == "Высокий" || priority == "Средний"
    }

    private func priorityBadgeTitle(for deadline: Deadline, resolvedPriority: String) -> String {
        if deadline.usesAutoPriority {
            return "\(localizedPriority(resolvedPriority)) · \(L("от срока"))"
        }
        return localizedPriority(resolvedPriority)
    }

    private func deadlineAccessibilityLabel(for deadline: Deadline, priority: String) -> String {
        var parts = [deadline.title, compactCardSubtitle(for: deadline)]
        if shouldShowPriorityBadge(priority) {
            parts.append(priorityBadgeTitle(for: deadline, resolvedPriority: priority))
        }
        return parts.joined(separator: ", ")
    }

    private func compactCardSubtitle(for deadline: Deadline) -> String {
        "\(deadline.localizedSubjectName) · \(formattedDate(deadline))"
    }

    private func nonDuplicateTags(for deadline: Deadline) -> [String] {
        let subjectRaw = deadline.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectLocalized = deadline.localizedSubjectName
        return deadline.tags.filter { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if trimmed.caseInsensitiveCompare(subjectRaw) == .orderedSame { return false }
            if trimmed == subjectLocalized { return false }
            if trimmed.caseInsensitiveCompare(deadline.subject) == .orderedSame { return false }
            return true
        }
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
    
    private func priorityIcon(for deadline: Deadline, resolvedPriority: String? = nil) -> String {
        switch deadline.statusType {
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        default:
            let priorityValue = resolvedPriority ?? priority(for: deadline)
            switch priorityValue {
            case "Высокий": return "exclamationmark.triangle.fill"
            case "Средний": return "exclamationmark.circle.fill"
            case "Низкий": return "clock.fill"
            default: return "circle.fill"
            }
        }
    }

    @ViewBuilder
    private func tagBadge(for tag: String) -> some View {
        AccessibleTagBadge(title: L(tag))
    }
    
    private func registerUndo(for deadline: Deadline, kind: UndoableDeadlineAction.Kind) {
        undoDismissTask?.cancel()
        withAnimation(undoToastAppearAnimation) {
            pendingUndo = UndoableDeadlineAction(kind: kind, snapshot: deadline)
        }
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(undoToastDismissAnimation) {
                    pendingUndo = nil
                }
            }
        }
    }

    private func undoDeadlineAction() async {
        undoDismissTask?.cancel()
        guard let action = pendingUndo else { return }
        withAnimation(undoToastDismissAnimation) {
            pendingUndo = nil
        }
        lightHaptic(intensity: 0.75)
        await viewModel.updateDeadline(action.snapshot)
    }

    private func completeDeadlineWithUndo(_ deadline: Deadline) async {
        let effectiveDate = effectiveDueDate(for: deadline)
        let wasOverdue = isOverdue(deadline, effectiveDate: effectiveDate)
        registerUndo(for: deadline, kind: UndoableDeadlineAction.Kind.completed)
        if wasOverdue {
            successHaptic()
        } else {
            lightHaptic()
        }
        var updated = deadline
        updated.statusType = .completed
        updated.deletedAt = updated.deletedAt ?? Date()
        await viewModel.updateDeadline(updated)
    }

    private func deleteDeadlineWithUndo(_ deadline: Deadline) async {
        registerUndo(for: deadline, kind: UndoableDeadlineAction.Kind.deleted)
        mediumHaptic()
        var archived = deadline
        archived.statusType = .cancelled
        archived.deletedAt = Date()
        await viewModel.updateDeadline(archived)
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

    private func successHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private func handleDeadlineExternalAction(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        if action == "complete", let id = notification.userInfo?["id"] as? String {
            if let deadline = viewModel.deadlines.first(where: { $0.id == id && $0.deletedAt == nil }) {
                Task { await completeDeadlineWithUndo(deadline) }
            } else {
                Task { await viewModel.completeDeadline(id: id) }
            }
        } else if action == "openPressure" {
            if subscriptionManager.isPressureProUnlocked {
                selectedTab = .pressure
            } else {
                showPressurePaywall = true
            }
        }
    }

    private func pressureTabHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
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

    private func rescheduleNotificationsForCurrentLanguage() {
        NotificationManager.shared.rescheduleAll(for: viewModel.deadlines)
        rescheduleProNotificationsIfNeeded()
    }
}

private struct TasksPressureHintBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.body)
                .foregroundStyle(.indigo)

            Text(L("Задачи показывают сроки по календарю. Режим давления — аналитика критичных 24 и 72 часов."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("Закрыть")))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

struct PressureModeView: View {
    let deadlines: [Deadline]
    let deadlineDateFormatter: DateFormatter
    var showsTasksPressureHint: Bool = false
    var entranceToken: Int = 0
    var onDismissTasksPressureHint: (() -> Void)? = nil
    var onCompleteDeadline: ((Deadline) -> Void)? = nil
    private let actionPlanner = PressureActionPlanner()
    private let legacyDeadlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var criticalGlow = false
    @State private var pressurePulse = false
    @State private var contentVisible = false
    @State private var now = Date()
    @State private var lastUrgencyLevel: UrgencyLevel = .green
    @State private var shakeOffset: CGFloat = 0
    @State private var lastShakeAt: Date = .distantPast
    @State private var isShaking = false
    @State private var didTrackCtaImpression = false

    private var actionPlan: PressureActionPlan {
        actionPlanner.makePlan(from: deadlines, now: now)
    }

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
                return remaining > 0 && remaining <= 72 * 3600
            }
            .sorted { (lhs: DeadlineDue, rhs: DeadlineDue) in
                let lhsPriority = priorityRank(lhs.deadline.resolvedPriority())
                let rhsPriority = priorityRank(rhs.deadline.resolvedPriority())
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.due < rhs.due
            }
            .prefix(3)
            .map { $0.deadline }
    }

    private var overdueDeadlines: [Deadline] {
        activeDeadlines
            .compactMap { deadline -> DeadlineDue? in
                guard let due = dueDateEndOfDay(deadline) else { return nil }
                return (deadline: deadline, due: due)
            }
            .filter { (item: DeadlineDue) in
                item.due < now
            }
            .sorted { (lhs: DeadlineDue, rhs: DeadlineDue) in
                let lhsPriority = priorityRank(lhs.deadline.resolvedPriority())
                let rhsPriority = priorityRank(rhs.deadline.resolvedPriority())
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.due < rhs.due
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
        let upcomingWorkload = upcoming72Workload

        var score = basePressureScore(hours: hours)

        if nearest.deadline.resolvedPriority() == "Высокий" && hours <= 24 {
            score += 1
        }

        if upcomingWorkload >= 4 {
            score += 1
        }

        switch score {
        case 3...: return .critical
        case 2: return .red
        case 1: return .yellow
        default: return .green
        }
    }

    private var upcoming72Workload: Double {
        activeDeadlines
            .compactMap { deadline -> (deadline: Deadline, due: Date)? in
                guard let due = dueDateEndOfDay(deadline) else { return nil }
                return (deadline, due)
            }
            .filter { item in
                let remaining = item.due.timeIntervalSince(now)
                return remaining > 0 && remaining <= 72 * 3600
            }
            .reduce(0) { partial, item in
                partial + workloadWeight(for: item.deadline)
            }
    }

    private func workloadWeight(for deadline: Deadline) -> Double {
        switch deadline.resolvedPriority() {
        case "Высокий": return 2
        case "Средний": return 1
        case "Низкий": return 0.5
        default: return 1
        }
    }

    private func basePressureScore(hours: Double) -> Int {
        if hours <= 12 { return 2 }
        if hours <= 24 { return 1 }
        if hours <= 72 { return 1 }
        return 0
    }

    private var remainingTitle: String {
        guard let nearest = nearestDeadline else { return L("Задач нет") }
        let remaining = nearest.due.timeIntervalSince(now)
        if remaining <= 0 {
            let overdueDuration = localizedDurationString(from: max(-remaining, 60), maximumUnitCount: 2)
            return String(format: L("Просрочен на %@"), overdueDuration)
        }

        if shouldShowDateSummary(remaining: remaining) {
            return String(format: L("Ближайшая задача — %@"), localizedShortDate(nearest.due))
        }

        let duration = localizedFullDurationString(from: max(remaining, 60), maximumUnitCount: 2)
        return String(format: L("%@ до задачи"), duration)
    }

    private var remainingSubtitle: String? {
        guard let nearest = nearestDeadline else { return nil }
        let remaining = nearest.due.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        guard shouldShowDateSummary(remaining: remaining) else { return nil }
        let daysText = localizedDaysString(from: remaining)
        return String(format: L("Осталось %@"), daysText)
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
        let raw = min(max(Int((timeProgress * 100).rounded()), 0), 100)
        if remainingSeconds > 0 {
            return min(raw, 99)
        }
        return raw
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
                    if showsTasksPressureHint {
                        TasksPressureHintBanner {
                            onDismissTasksPressureHint?()
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(remainingTitle)
                                .font(.largeTitle.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(pressureAccentColor)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                                .offset(x: shakeOffset)
                                .scaleEffect(shouldPulseRemainingText ? (pressurePulse ? 1.03 : 0.98) : 1)
                                .shadow(
                                    color: (shouldAccentMaxPressure || shouldAccentNearMaxPressure || overdueSeconds > 0) ? pressureAccentColor.opacity(criticalGlow ? 0.4 : 0.18) : .clear,
                                    radius: (shouldAccentMaxPressure || shouldAccentNearMaxPressure || overdueSeconds > 0) ? 10 : 0,
                                    x: 0,
                                    y: 0
                                )
                                .contentTransition(.numericText())

                            if let subtitle = remainingSubtitle {
                                Text(subtitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if urgencyLevel == .green {
                                    Text(L("Времени достаточно."))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L("Давление по сроку"))
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
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L("Режим давления"))

                    PressureActionPlanSection(plan: actionPlan, onComplete: onCompleteDeadline)

                    VStack(alignment: .leading, spacing: 12) {
                        if !overdueDeadlines.isEmpty {
                            Text(L("Просроченные"))
                                .font(.headline)

                            ForEach(overdueDeadlines) { deadline in
                                pressureCard(deadline)
                            }
                        }

                        Text(L("Ближайшие 72 часа"))
                            .font(.headline)

                        if burning72Hours.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L("Срочных задач нет"))
                                    .font(.subheadline.weight(.semibold))
                                Text(L("Можно расслабиться."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(urgencyLevel.color.opacity(0.35), lineWidth: 1)
                                    )
                            )
                        } else {
                            ForEach(burning72Hours) { deadline in
                                pressureCard(deadline)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                .padding(.vertical, 14)
                .iPadReadableContent(maxWidth: 980)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(backgroundGradient)
            .navigationTitle(L("Режим давления"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                now = Date()
                lastUrgencyLevel = urgencyLevel
                restartPressureAnimations()
                withAnimation(.easeOut(duration: 0.35)) {
                    contentVisible = true
                }
                if !didTrackCtaImpression {
                    PressureABAnalytics.shared.trackCtaImpression()
                    didTrackCtaImpression = true
                }
            }
            .onChange(of: entranceToken) { _, _ in
                contentVisible = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    contentVisible = true
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

            Text(deadline.localizedSubjectName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isHighPriority {
                AccessibleCapsuleBadge(
                    iconName: "exclamationmark.triangle.fill",
                    title: L("Высокий"),
                    style: BadgeContrastStyle.forPriority("Высокий", scheme: colorScheme),
                    pulsing: pressurePulse
                )
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
        guard let dueDate = deadline.normalizedDueDateForRecurrence(referenceDate: now) else { return nil }
        if deadline.hasTimeInDueDate {
            return dueDate
        }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: dueDate)
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

    private func localizedFullDurationString(from interval: TimeInterval, maximumUnitCount: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = maximumUnitCount
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        return formatter.string(from: interval) ?? "1 minute"
    }

    private func localizedDaysString(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        return formatter.string(from: interval) ?? "1 day"
    }

    private func localizedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func shouldShowDateSummary(remaining: TimeInterval) -> Bool {
        remaining >= 30 * 86_400
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
        let remainingHours = (dueDateEndOfDay(deadline)?.timeIntervalSince(now) ?? 0) / 3600
        let isHighPriority = deadline.priority == "Высокий"
        let heavyWorkload = upcoming72Workload >= 4
        let progress = localProgress(for: deadline)

        if level == .critical {
            return rotatedInsight(
                for: deadline,
                bucket: "critical",
                options: [
                    L("Критическое давление. Сфокусируйтесь на главном и закройте минимум задачи."),
                    L("Критическая зона: закройте самый важный шаг в ближайшие 20 минут"),
                    L("Сделайте финальный рывок: 25 минут без отвлечений")
                ]
            )
        }

        if progress >= 0.6 {
            return rotatedInsight(
                for: deadline,
                bucket: "high_progress",
                options: [
                    L("Осталось немного. Выделите 20–30 минут сегодня, чтобы закрыть задачу."),
                    L("Сделайте финальный рывок: 25 минут без отвлечений"),
                    L("Разбейте задачу на 3 шага и начните с первого")
                ]
            )
        }

        if progress <= 0.15, remainingHours <= 48, remainingHours > 0 {
            return rotatedInsight(
                for: deadline,
                bucket: "low_progress",
                options: [
                    L("Начните сегодня. Даже 30 минут снизят давление."),
                    L("Запланируйте первый блок работы сегодня"),
                    L("Ранний старт даст запас: заложите 30 минут сегодня")
                ]
            )
        }
        switch level {
        case .critical:
            if remainingHours <= 3 {
                return L("Сделайте финальный рывок: 25 минут без отвлечений")
            }
            if isHighPriority {
                return L("Критическая зона: закройте самый важный шаг в ближайшие 20 минут")
            }
            return variant == .a
                ? L("Сделайте финальный рывок: 25 минут без отвлечений")
                : L("Критическая зона: закройте самый важный шаг в ближайшие 20 минут")
        case .red:
            if isHighPriority {
                return variant == .a
                    ? L("Высокий приоритет: выделите 30 минут заранее")
                    : L("Ранний старт даст запас: заложите 30 минут сегодня")
            }
            if remainingHours <= 6 {
                return L("Разбейте задачу на 3 шага и начните с первого")
            }
            return L("Высокое давление: начните с черновика, потом шлифуйте")
        case .yellow:
            if heavyWorkload {
                return L("Окно 72ч: выделите 45 минут сегодня, чтобы снять риск")
            }
            return L("Запланируйте первый блок работы сегодня")
        case .green:
            if isHighPriority {
                return variant == .a
                    ? L("Высокий приоритет: выделите 30 минут заранее")
                    : L("Ранний старт даст запас: заложите 30 минут сегодня")
            }
            if heavyWorkload {
                return L("Нагрузка под контролем: закрепите прогресс короткой сессией")
            }
            return L("Сейчас спокойный этап: сделайте мини-шаг, пока есть запас")
        }
    }

    private func rotatedInsight(for deadline: Deadline, bucket: String, options: [String]) -> String {
        guard !options.isEmpty else { return "" }

        let dayOfEra = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        let seedSource = "\(deadline.id)|\(bucket)|\(dayOfEra)"
        let stableSeed = seedSource.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }

        let index = stableSeed % options.count
        return options[index]
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "Высокий": return 0
        case "Средний": return 1
        case "Низкий": return 2
        default: return 3
        }
    }
}

// MARK: - Deadline Detail Sheet
private struct DeadlineDetailPresentationModifier: ViewModifier {
    let isEmbeddedInSplitView: Bool

    func body(content: Content) -> some View {
        if isEmbeddedInSplitView {
            content
        } else {
            content
                .presentationDetents([.medium, .large])
        }
    }
}

struct DeadlineDetailSheet: View {
    let deadline: Deadline
    @ObservedObject var viewModel: DeadlineViewModel
    var isEmbeddedInSplitView: Bool = false
    var onEdit: () -> Void
    var onComplete: (Deadline) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPerformingAction = false

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

    private var resolvedPriority: String {
        deadline.resolvedPriority()
    }

    var body: some View {
        NavigationStack {
            detailContent
        }
        .modifier(DeadlineDetailPresentationModifier(isEmbeddedInSplitView: isEmbeddedInSplitView))
    }

    private var detailContent: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(deadline.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack {
                            Label(deadline.localizedSubjectName, systemImage: "book")
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

                Section(L("Срок и приоритет")) {
                    Label(formattedDate, systemImage: "calendar")
                    Label(priorityLabel, systemImage: "flag.fill")
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
                    Label(repeatLabels[deadline.repeatType] ?? L("Без повторения"), systemImage: "repeat")
                    Label(reminderLabels[deadline.reminderTime] ?? L("За день"), systemImage: "bell")
                }

                Section(L("Заметки")) {
                    if deadline.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L("Заметок нет"))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(deadline.notes)
                            .font(.body)
                    }
                }

                if deadline.statusType == .inProgress {
                    Section {
                        Button {
                            Task { await postponeDeadline() }
                        } label: {
                            Label(L("Перенести на завтра"), systemImage: "calendar.badge.plus")
                        }
                        .disabled(isPerformingAction)

                        Button {
                            Task { await completeDeadline() }
                        } label: {
                            Label(L("Отметить выполненным"), systemImage: "checkmark.circle.fill")
                        }
                        .disabled(isPerformingAction)

                        Button {
                            onEdit()
                        } label: {
                            Label(L("Редактировать"), systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle(L("Детали"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbeddedInSplitView {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Готово")) { dismiss() }
                    }
                }
            }
    }

    private var priorityLabel: String {
        let name = localizedPriority(resolvedPriority)
        if deadline.usesAutoPriority {
            return "\(name) · \(L("от срока"))"
        }
        return name
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

    private var formattedDate: String {
        guard let date = deadline.normalizedDueDateForRecurrence() ?? deadline.parsedDueDate() else {
            return deadline.dueDate
        }
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

    private func postponeDeadline() async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        let updated = deadline.postponed(byDays: 1)
        await viewModel.updateDeadline(updated)
        if !isEmbeddedInSplitView {
            dismiss()
        }
    }

    private func completeDeadline() async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        await onComplete(deadline)
        if !isEmbeddedInSplitView {
            dismiss()
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
        NavigationStack {
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
                if archived.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(L("В архиве пока нет задач"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(L("Здесь появятся выполненные или отменённые задачи"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(archived) { deadline in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deadline.title)
                                .font(.headline)
                            Text("\(deadline.localizedSubjectName) — \(formattedDate(deadline)) — \(L(deadline.status))")
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

// MARK: - Undo Toast

struct UndoableDeadlineAction {
    enum Kind: Equatable {
        case completed
        case deleted
    }

    let kind: Kind
    let snapshot: Deadline
}

struct DeadlineUndoToast: View {
    let action: UndoableDeadlineAction
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.kind == .completed ? "checkmark.circle.fill" : "trash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(action.kind == .completed ? .green : .orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: onUndo) {
                Text(L("Отменить"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(L("Отменить"))")
        .accessibilityIdentifier("deadlineUndoToast")
    }

    private var message: String {
        switch action.kind {
        case .completed:
            return L("Задача выполнена")
        case .deleted:
            return L("Задача удалена")
        }
    }
}

