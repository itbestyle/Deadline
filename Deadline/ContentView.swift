import SwiftUI
import SwiftData
import UIKit

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
    @State private var sortMode: DeadlineSortMode = .date
    @State private var newPriority = "Авто"
    @State private var isFormExpanded = false
    @State private var newRepeatType = "none"
    @State private var newNotes = ""
    @State private var newReminderTime = "1day"
    @State private var addButtonBreathing = false

    private let deadlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    @State private var editingDeadline: Deadline?
    @State private var detailDeadline: Deadline?
    @State private var pressureDetailDeadline: Deadline?
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
            .sheet(item: $pressureDetailDeadline) { deadline in
                DeadlineDetailSheet(
                    deadline: deadline,
                    viewModel: viewModel,
                    onEdit: {
                        pressureDetailDeadline = nil
                        editingDeadline = deadline
                    },
                    onComplete: { item in
                        await completeDeadlineWithUndo(item)
                    }
                )
            }
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

                FilterControlsView(
                    filterStatus: $filterStatus,
                    filterSubject: $filterSubject,
                    sortMode: $sortMode
                )
                    .padding(.horizontal)
                    .padding(.top, 8)

                if !hasDismissedTasksPressureHint {
                    tasksPressureHintBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                DeadlineListView(
                    viewModel: viewModel,
                    sortMode: $sortMode,
                    searchQuery: $searchQuery,
                    isSearchExpanded: $isSearchExpanded,
                    filterStatus: $filterStatus,
                    filterSubject: $filterSubject,
                    editingDeadline: $editingDeadline,
                    detailDeadline: $detailDeadline,
                    selectedSplitDeadlineID: $selectedSplitDeadlineID,
                    isFormExpanded: $isFormExpanded,
                    isSearchFocused: $isSearchFocused,
                    onComplete: { deadline in
                        await completeDeadlineWithUndo(deadline)
                    },
                    onDelete: { deadline in
                        await deleteDeadlineWithUndo(deadline)
                    }
                )
            }
            .sheet(isPresented: $isFormExpanded) {
                AddDeadlineFormSheet(
                    newTitle: $newTitle,
                    newNotes: $newNotes,
                    newSubject: $newSubject,
                    newDate: $newDate,
                    newReminderTime: $newReminderTime,
                    newRepeatType: $newRepeatType,
                    newPriority: $newPriority,
                    newStatus: $newStatus,
                    selectedTags: $selectedTags,
                    isAddButtonEnabled: isAddButtonEnabled,
                    onCancel: { isFormExpanded = false },
                    onAdd: addNewDeadline
                )
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
                        .tracking(-0.6)
                        .foregroundStyle(Color.indigo)
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
            },
            onOpenDeadline: { deadline in
                pressureDetailDeadline = deadline
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
            MetallicIndigoSweepLabel()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.indigo.opacity(0.28), lineWidth: 1)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .light ? 0.28 : 0.18), lineWidth: 1)
                                .mask(
                                    LinearGradient(
                                        colors: [.white, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
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

    private struct MetallicIndigoSweepLabel: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let label = HStack {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                Text(L("Добавить задачу"))
                    .font(.subheadline.weight(.semibold))
            }

            label
                .foregroundStyle(Color.indigo)
                .overlay {
                    if reduceMotion {
                        EmptyView()
                    } else {
                        KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                            label
                                .foregroundStyle(metalTint)
                                .mask {
                                    GeometryReader { geometry in
                                        let width = geometry.size.width
                                        let band = max(width * (colorScheme == .light ? 0.30 : 0.42), 36)
                                        LinearGradient(
                                            colors: colorScheme == .light
                                                ? [
                                                    .clear,
                                                    .white.opacity(0.18),
                                                    .white.opacity(0.7),
                                                    .white.opacity(0.18),
                                                    .clear
                                                ]
                                                : [
                                                    .clear,
                                                    .white.opacity(0.25),
                                                    .white,
                                                    .white.opacity(0.25),
                                                    .clear
                                                ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: band, height: geometry.size.height)
                                        .offset(x: -band + (width + band) * progress)
                                    }
                                }
                        } keyframes: { _ in
                            LinearKeyframe(1, duration: 2.35)
                            LinearKeyframe(1, duration: 1.7)
                        }
                    }
                }
        }

        private var metalTint: LinearGradient {
            let highlight = colorScheme == .light
                ? Color(red: 0.62, green: 0.58, blue: 0.95)
                : Color(red: 0.84, green: 0.85, blue: 1.0)
            let peak = colorScheme == .light
                ? Color(red: 0.72, green: 0.70, blue: 1.0)
                : Color.white.opacity(0.8)
            return LinearGradient(
                colors: [
                    Color.indigo,
                    highlight,
                    peak,
                    highlight,
                    Color.indigo
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private struct CompactIndigoButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
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
        let wasOverdue = deadline.isOverdue()
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
