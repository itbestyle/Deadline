import Combine
import EventKit
import Foundation
import Network
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
final class DeadlineViewModel: ObservableObject {
    @Published private(set) var deadlines: [Deadline] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isOffline = false

    private let baseURL = URL(string: "https://deadlines-api-744471608721.europe-west1.run.app")!
    private let calendarManager = CalendarIntegrationManager.shared
    private let dateFormatter: DateFormatter
    private let legacyDateFormatter: DateFormatter

    private var repository: DeadlineRepositoryProtocol?
    private var currentFilter = DeadlineFilter()
    private var watchActionObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "deadline.network.monitor")

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        dateFormatter = formatter

        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "yyyy-MM-dd"
        legacy.timeZone = .current
        legacyDateFormatter = legacy

        watchActionObserver = NotificationCenter.default.addObserver(
            forName: .watchActionReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let actionRaw = notification.userInfo?["action"] as? String,
                let action = WatchActionType(rawValue: actionRaw),
                let id = notification.userInfo?["id"] as? String
            else { return }

            Task { [weak self] in
                await self?.applyWatchAction(action, id: id)
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = path.status != .satisfied
                if wasOffline, !self.isOffline {
                    await self.syncNow()
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    deinit {
        pathMonitor.cancel()
        if let watchActionObserver {
            NotificationCenter.default.removeObserver(watchActionObserver)
        }
    }

    private static let legacyPriorityMigrationKey = "didMigrateLegacyMediumPriority"

    func configureIfNeeded(context: ModelContext) {
        guard repository == nil else { return }
        let api = DeadlineAPI(baseURL: baseURL)
        repository = DeadlineRepository(context: context, api: api)
        if !UserDefaults.standard.bool(forKey: Self.legacyPriorityMigrationKey) {
            try? repository?.migrateLegacyPlaceholderPriority()
            UserDefaults.standard.set(true, forKey: Self.legacyPriorityMigrationKey)
        }
        reloadLocal()
    }

    func applyFilters(status: String = "", subject: String = "") {
        currentFilter = DeadlineFilter(status: status, subject: subject)
        reloadLocal()
    }

    func fetchDeadlines(status: String = "", subject: String = "") async {
        applyFilters(status: status, subject: subject)
        await syncNow()
    }

    @discardableResult
    func addDeadline(_ deadline: Deadline) async -> Deadline? {
        guard let repository else { return nil }
        var dto = makeDTO(from: deadline, existing: try? repository.model(for: deadline.id))
        if dto.id.isEmpty {
            dto.id = "local-\(UUID().uuidString)"
        }
        dto.isDirty = true
        dto.isDeleted = false
        dto.updatedAt = Date()

        do {
            try repository.storeLocal(from: dto)
            try repository.saveChanges()
            reloadLocal()
            if let saved = deadlines.first(where: { $0.id == dto.id }) {
                await syncCalendar(for: saved)
            }
            Task { await self.syncNow() }
            return deadlines.first(where: { $0.id == dto.id })
        } catch {
            lastSyncError = userFacingSyncError(error)
            return nil
        }
    }

    func updateDeadline(_ deadline: Deadline, animated: Bool = false) async {
        guard let repository else { return }
        do {
            var normalized = deadline
            if normalized.deletedAt == nil,
               [DeadlineStatus.completed, DeadlineStatus.cancelled].contains(normalized.statusType) {
                normalized.deletedAt = Date()
            }
            let existing = try repository.model(for: normalized.id)
            var dto = makeDTO(from: normalized, existing: existing)
            dto.isDirty = true
            dto.isDeleted = false
            dto.updatedAt = Date()
            try repository.storeLocal(from: dto)
            try repository.saveChanges()
            applyLocalReload(animated: animated)
            if let saved = deadlines.first(where: { $0.id == dto.id }) {
                await syncCalendar(for: saved)
            }
            Task { await self.syncNow() }
        } catch {
            lastSyncError = userFacingSyncError(error)
        }
    }

    func deleteDeadline(id: String) async {
        guard let repository else { return }
        do {
            try await repository.deleteFromServerAndLocal(id: id)
            reloadLocal()
            await calendarManager.removeEvent(forDeadlineID: id)
        } catch {
            lastSyncError = userFacingSyncError(error)
        }
    }

    func completeDeadline(id: String) async {
        guard let current = deadlines.first(where: { $0.id == id }) else { return }
        var updated = current
        updated.statusType = .completed
        updated.deletedAt = updated.deletedAt ?? Date()
        await updateDeadline(updated)
        WidgetAppGroupStore.clearLocallyCompleted(id: id)
    }

    func processPendingWidgetActions() async {
        guard let id = WidgetActionBridge.consumePendingComplete() else { return }
        await completeDeadline(id: id)
    }

    func syncNow() async {
        guard let repository, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await repository.syncWithServer()
            lastSyncError = nil
            // A successful round-trip proves connectivity even when the path
            // monitor never reported a change (e.g. the server itself was down).
            isOffline = false
        } catch {
            if isBenignSyncCancellation(error) {
                return
            }
            if isNetworkRelated(error) {
                isOffline = true
            }
            if let urlError = error as? URLError, urlError.code == .timedOut {
                lastSyncError = NSLocalizedString("Сервер долго отвечает. Проверьте сеть и попробуйте ещё раз.", comment: "Sync timeout message")
            } else {
                lastSyncError = userFacingSyncError(error)
            }
        }
        reloadLocal()
        
        // Обновляем уведомления только после синхронизации
        NotificationManager.shared.rescheduleAll(for: deadlines)
        await syncCalendarForAllDeadlines()
    }

    // MARK: - Helpers

    private static let listChangeAnimation = Animation.easeInOut(duration: 0.28)

    private func applyLocalReload(animated: Bool) {
        if animated {
            withAnimation(Self.listChangeAnimation) {
                reloadLocal()
            }
        } else {
            reloadLocal()
        }
    }

    private func reloadLocal() {
        guard let repository else { return }
        do {
            autoDeleteOldArchived()
            let models = try repository.fetchLocal(filter: currentFilter)
            deadlines = models.map(mapToDeadline)

            // Widget, watch and Live Activity must reflect every deadline,
            // not whatever filter the list screen happens to have applied.
            let unfiltered = (try? repository.fetchLocal(filter: DeadlineFilter()).map(mapToDeadline)) ?? deadlines

            let payloads = unfiltered
                .filter { $0.deletedAt == nil }
                .map {
                    WatchDeadlinePayload(
                        id: $0.id,
                        title: $0.title,
                        subject: $0.localizedSubjectName,
                        dueDate: $0.dueDate,
                        status: $0.status,
                        priority: $0.priority,
                        pressure: Deadline.watchPressureLevel(for: $0)
                    )
                }
            if let data = try? JSONEncoder().encode(payloads) {
                WatchConnectivityBridge.shared.sync(encodedDeadlinesData: data)
            }
            WidgetAppGroupStore.saveCritical(WidgetCriticalSnapshotBuilder.nearestCritical(from: unfiltered))
            WidgetAppGroupStore.saveActiveList(WidgetListBuilder.activeEntries(from: unfiltered))
            LiveActivityManager.sync(with: unfiltered)
            WidgetCenter.shared.reloadAllTimelines()
            Task {
                await DeadlineIntentStore.shared.update(from: unfiltered)
            }
        } catch {
            lastSyncError = userFacingSyncError(error)
        }
    }

    private func applyWatchAction(_ action: WatchActionType, id: String) async {
        guard let current = deadlines.first(where: { $0.id == id }) else { return }

        var updated = current
        switch action {
        case .complete:
            updated.statusType = .completed
            updated.deletedAt = updated.deletedAt ?? Date()
            await updateDeadline(updated)
        case .restore:
            updated.statusType = .inProgress
            updated.deletedAt = nil
            await updateDeadline(updated)
        case .archive:
            updated.statusType = .cancelled
            updated.deletedAt = Date()
            await updateDeadline(updated)
        }
    }

    private func parsedDueDate(from raw: String) -> Date? {
        dateFormatter.date(from: raw)
            ?? legacyDateFormatter.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
    }

    private func shouldBeInCalendar(_ deadline: Deadline) -> Bool {
        deadline.deletedAt == nil && ![.completed, .cancelled].contains(deadline.statusType)
    }

    private func syncCalendar(for deadline: Deadline) async {
        guard calendarManager.isSyncEnabled else {
            if !shouldBeInCalendar(deadline) {
                await calendarManager.removeEvent(forDeadlineID: deadline.id)
            }
            return
        }
        if shouldBeInCalendar(deadline), let dueDate = deadline.effectiveDueInstant() ?? parsedDueDate(from: deadline.dueDate) {
            await calendarManager.upsertEvent(for: deadline, dueDate: dueDate)
        } else {
            await calendarManager.removeEvent(forDeadlineID: deadline.id)
        }
    }

    private func isBenignSyncCancellation(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }

    private func isNetworkRelated(_ error: Error) -> Bool {
        if isOffline { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
            return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut].contains(nsError.code)
        }
        return false
    }

    private func syncCalendarForAllDeadlines() async {
        await calendarManager.reconcileMappings(validDeadlineIDs: Set(deadlines.map { $0.id }))
        for deadline in deadlines {
            await syncCalendar(for: deadline)
        }
    }

    private func userFacingSyncError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return NSLocalizedString("Сервер долго отвечает. Проверьте сеть и попробуйте ещё раз.", comment: "Sync timeout message")
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .callIsActive:
                return NSLocalizedString("Проблема сети. Попробуйте ещё раз", comment: "Sync network issue")
            default:
                return NSLocalizedString("Некорректный ответ сервера", comment: "Generic sync error")
            }
        }
        return NSLocalizedString("Некорректный ответ сервера", comment: "Generic sync error")
    }

    private func autoDeleteOldArchived() {
        guard let repository else { return }
        let now = Date()
        let all = (try? repository.fetchLocal(filter: DeadlineFilter())) ?? []
        var hasChanges = false
        for model in all {
            let status = DeadlineStatus(rawStatus: model.status)
            guard status == .completed || status == .cancelled else { continue }
            let archiveDate = model.deletedAt ?? model.updatedAt
            if model.deletedAt == nil {
                model.deletedAt = archiveDate
                hasChanges = true
            }
            if now.timeIntervalSince(archiveDate) > 60*60*24*30 {
                try? repository.markDeleted(id: model.id)
                hasChanges = true
            }
        }

        if hasChanges {
            try? repository.saveChanges()
            Task { await self.syncNow() }
        }
    }

    private func mapToDeadline(_ model: DeadlineModel) -> Deadline {
        Deadline(
            id: model.id,
            title: model.title,
            subject: model.subject,
            dueDate: dateFormatter.string(from: model.dueDate),
            status: model.status,
            priority: model.priority,
            tags: model.tags,
            repeatType: model.repeatType,
            notes: model.notes,
            reminderTime: model.reminderTime,
            deletedAt: model.deletedAt
        )
    }

    private func makeDTO(from deadline: Deadline, existing: DeadlineModel?) -> DeadlineDTO {
        let dueDate = dateFormatter.date(from: deadline.dueDate)
            ?? legacyDateFormatter.date(from: deadline.dueDate)
            ?? Date()
        return DeadlineDTO(
            id: existing?.id ?? deadline.id,
            remoteID: existing?.remoteID,
            title: deadline.title,
            subject: deadline.subject,
            dueDate: dueDate,
            status: deadline.status,
            priority: deadline.priority,
            tags: deadline.tags,
            repeatType: deadline.repeatType,
            notes: deadline.notes,
            reminderTime: deadline.reminderTime,
            updatedAt: existing?.updatedAt ?? Date(),
            deletedAt: deadline.deletedAt,
            isDirty: existing?.isDirty ?? false,
            isDeleted: existing?.isDeleted ?? false
        )
    }
}

final class CalendarIntegrationManager {
    static let shared = CalendarIntegrationManager()

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private let accessStateKey = "calendar.events.access.granted"
    private let syncEnabledKey = "calendar.sync.enabled"
    private let mappingPrefix = "calendar.event.id."
    private let lock = NSLock()

    private init() {}

    var isSyncEnabled: Bool {
        get {
            if defaults.object(forKey: syncEnabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: syncEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: syncEnabledKey)
        }
    }

    var hasCalendarAccess: Bool {
        defaults.bool(forKey: accessStateKey)
    }

    func reconcileMappings(validDeadlineIDs: Set<String>) async {
        guard isSyncEnabled, await requestAccessIfNeeded() else { return }
        reconcileMappingsWhileLocked(validDeadlineIDs: validDeadlineIDs)
    }

    private func reconcileMappingsWhileLocked(validDeadlineIDs: Set<String>) {
        lock.lock()
        defer { lock.unlock() }

        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(mappingPrefix) }
        for key in keys {
            let deadlineID = String(key.dropFirst(mappingPrefix.count))
            guard let eventID = defaults.string(forKey: key) else {
                defaults.removeObject(forKey: key)
                continue
            }

            if !validDeadlineIDs.contains(deadlineID) {
                removeAllEvents(forDeadlineID: deadlineID, except: nil)
                defaults.removeObject(forKey: key)
                continue
            }

            if store.event(withIdentifier: eventID) == nil {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func upsertEvent(for deadline: Deadline, dueDate: Date) async {
        guard isSyncEnabled, await requestAccessIfNeeded() else { return }
        upsertEventWhileLocked(for: deadline, dueDate: dueDate)
    }

    private func upsertEventWhileLocked(for deadline: Deadline, dueDate: Date) {
        lock.lock()
        defer { lock.unlock() }

        let eventIDKey = eventKey(for: deadline.id)
        let linkedEvents = findEvents(forDeadlineID: deadline.id, near: dueDate)
        let mappedID = defaults.string(forKey: eventIDKey)

        let event: EKEvent
        if let mappedID,
           let mappedEvent = store.event(withIdentifier: mappedID) {
            event = mappedEvent
        } else if let linked = linkedEvents.first {
            event = linked
        } else if let legacy = findLegacyUntaggedEvent(title: deadline.title, dueDate: dueDate) {
            event = legacy
        } else {
            event = EKEvent(eventStore: store)
        }

        event.calendar = event.calendar ?? store.defaultCalendarForNewEvents
        event.title = deadline.title
        event.startDate = dueDate
        event.endDate = dueDate.addingTimeInterval(60 * 60)
        event.url = deadlineEventURL(for: deadline.id)

        var notesParts: [String] = []
        if !deadline.subject.isEmpty {
            notesParts.append(deadline.subject)
        }
        if !deadline.notes.isEmpty {
            notesParts.append(deadline.notes)
        }
        event.notes = notesParts.isEmpty ? nil : notesParts.joined(separator: "\n\n")
        // Keep events visible in Calendar, but suppress Calendar-originated alerts.
        // App reminders are handled exclusively by NotificationManager.
        event.alarms = []

        do {
            try store.save(event, span: .thisEvent)
            // Some calendars can auto-attach defaults on first save; strip once more.
            if let identifier = event.eventIdentifier,
               let saved = store.event(withIdentifier: identifier),
               !(saved.alarms ?? []).isEmpty {
                saved.alarms = []
                try store.save(saved, span: .thisEvent)
            }
            if let identifier = event.eventIdentifier {
                defaults.set(identifier, forKey: eventIDKey)
                removeDuplicateEvents(forDeadlineID: deadline.id, keep: identifier, near: dueDate)
                removeLegacyUntaggedDuplicates(title: deadline.title, dueDate: dueDate, keep: identifier)
            }
        } catch {
            return
        }
    }

    func removeEvent(forDeadlineID deadlineID: String) async {
        guard await requestAccessIfNeeded() else { return }
        removeEventWhileLocked(forDeadlineID: deadlineID)
    }

    private func removeEventWhileLocked(forDeadlineID deadlineID: String) {
        lock.lock()
        defer { lock.unlock() }

        removeAllEvents(forDeadlineID: deadlineID, except: nil)
        defaults.removeObject(forKey: eventKey(for: deadlineID))
    }

    func requestCalendarAccess() async -> Bool {
        await requestAccessIfNeeded(forcePrompt: true)
    }

    private func requestAccessIfNeeded(forcePrompt: Bool = false) async -> Bool {
        if !forcePrompt, !isSyncEnabled {
            return false
        }
        if !forcePrompt, defaults.bool(forKey: accessStateKey) {
            return true
        }

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await withCheckedContinuation { continuation in
                store.requestFullAccessToEvents { allowed, _ in
                    continuation.resume(returning: allowed)
                }
            }
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { allowed, _ in
                    continuation.resume(returning: allowed)
                }
            }
        }

        if granted {
            defaults.set(true, forKey: accessStateKey)
        }

        return granted
    }

    private func eventKey(for deadlineID: String) -> String {
        "\(mappingPrefix)\(deadlineID)"
    }

    private func deadlineEventURL(for deadlineID: String) -> URL {
        URL(string: "redloop://deadline/\(deadlineID)")!
    }

    private func eventMatchesDeadline(_ event: EKEvent, deadlineID: String) -> Bool {
        if event.url?.absoluteString == deadlineEventURL(for: deadlineID).absoluteString {
            return true
        }
        return event.notes?.contains("redloop://deadline/\(deadlineID)") == true
    }

    private func findEvents(forDeadlineID deadlineID: String, near dueDate: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -1, to: dueDate) ?? dueDate.addingTimeInterval(-365 * 86_400)
        let end = calendar.date(byAdding: .year, value: 1, to: dueDate) ?? dueDate.addingTimeInterval(365 * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: store.calendars(for: .event))
        return store.events(matching: predicate).filter { eventMatchesDeadline($0, deadlineID: deadlineID) }
    }

    private func removeDuplicateEvents(forDeadlineID deadlineID: String, keep keepIdentifier: String, near dueDate: Date) {
        let duplicates = findEvents(forDeadlineID: deadlineID, near: dueDate)
        for duplicate in duplicates {
            guard let identifier = duplicate.eventIdentifier, identifier != keepIdentifier else { continue }
            try? store.remove(duplicate, span: .thisEvent)
        }
    }

    private func findLegacyUntaggedEvent(title: String, dueDate: Date) -> EKEvent? {
        let matches = legacyUntaggedMatches(title: title, dueDate: dueDate)
        return matches.count == 1 ? matches.first : nil
    }

    private func removeLegacyUntaggedDuplicates(title: String, dueDate: Date, keep keepIdentifier: String) {
        for duplicate in legacyUntaggedMatches(title: title, dueDate: dueDate) {
            guard let identifier = duplicate.eventIdentifier, identifier != keepIdentifier else { continue }
            try? store.remove(duplicate, span: .thisEvent)
        }
    }

    private func legacyUntaggedMatches(title: String, dueDate: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: dueDate) ?? dueDate.addingTimeInterval(-86_400)
        let end = calendar.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: store.calendars(for: .event))
        return store.events(matching: predicate).filter { event in
            guard event.url == nil else { return false }
            guard event.title == title else { return false }
            return abs(event.startDate.timeIntervalSince(dueDate)) < 120
        }
    }

    private func removeAllEvents(forDeadlineID deadlineID: String, except keepIdentifier: String?) {
        let now = Date()
        let duplicates = findEvents(forDeadlineID: deadlineID, near: now)
        if duplicates.isEmpty, let mappedID = defaults.string(forKey: eventKey(for: deadlineID)),
           let mapped = store.event(withIdentifier: mappedID) {
            if keepIdentifier == nil || mapped.eventIdentifier != keepIdentifier {
                try? store.remove(mapped, span: .thisEvent)
            }
            return
        }

        for duplicate in duplicates {
            guard let identifier = duplicate.eventIdentifier else { continue }
            if let keepIdentifier, identifier == keepIdentifier { continue }
            try? store.remove(duplicate, span: .thisEvent)
        }
    }
}

