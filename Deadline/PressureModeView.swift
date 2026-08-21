import SwiftUI
import UIKit
import Combine

struct TasksPressureHintBanner: View {
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
    var onOpenDeadline: ((Deadline) -> Void)? = nil
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
                onOpenDeadline?(deadline)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text(cta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Открыть задачу"))
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
