import SwiftUI
import UIKit

struct DeadlineListView: View {
    @ObservedObject var viewModel: DeadlineViewModel
    @Binding var sortMode: DeadlineSortMode
    @Binding var searchQuery: String
    @Binding var isSearchExpanded: Bool
    @Binding var filterStatus: String
    @Binding var filterSubject: String
    @Binding var editingDeadline: Deadline?
    @Binding var detailDeadline: Deadline?
    @Binding var selectedSplitDeadlineID: String?
    @Binding var isFormExpanded: Bool
    var isSearchFocused: FocusState<Bool>.Binding
    var onComplete: (Deadline) async -> Void
    var onDelete: (Deadline) async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

private struct DeadlinePriorityBadge: View {
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

    var body: some View {
        VStack(spacing: 0) {
            if hasActiveSearch && !sections.isEmpty {
                searchResultsBanner
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            listContent
        }
    }

    private var listContent: some View {
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
                    await onComplete(item)
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
                        await onComplete(item)
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

                if isUrgent, shouldShowDeadlinePriorityBadge(priorityValue) {
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

                if shouldShowDeadlinePriorityBadge(priorityValue) {
                    DeadlinePriorityBadge(
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
            Task { await onDelete(deadline) }
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
                Task { await onComplete(deadline) }
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
                Task { await onComplete(deadline) }
            } label: {
                Label(L("Отметить выполненным"), systemImage: "checkmark.circle")
            }.tint(.green)
        }
        
        Button(role: .destructive) {
            Task { await onDelete(deadline) }
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

    private func shouldShowDeadlinePriorityBadge(_ priority: String) -> Bool {
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
        if shouldShowDeadlinePriorityBadge(priority) {
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

    private var hasActiveFilters: Bool {
        !filterStatus.isEmpty || !filterSubject.isEmpty
    }

    private func resetFilters() {
        filterStatus = ""
        filterSubject = ""
    }

    private func clearSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchExpanded = false
            searchQuery = ""
            isSearchFocused.wrappedValue = false
        }
    }

    private func lightHaptic(intensity: CGFloat = 0.65) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred(intensity: intensity)
    }
}
