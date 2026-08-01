import Foundation
import SwiftData

protocol DeadlineRepositoryProtocol {
    func fetchLocal(filter: DeadlineFilter) throws -> [DeadlineModel]
    func storeLocal(from dto: DeadlineDTO) throws
    func markDeleted(id: String) throws
    func saveChanges() throws
    func syncWithServer() async throws
    func model(for id: String) throws -> DeadlineModel?
    func deleteFromServerAndLocal(id: String) async throws
    func migrateLegacyPlaceholderPriority() throws
}

@MainActor
final class DeadlineRepository: DeadlineRepositoryProtocol {
    private let context: ModelContext
    private let api: DeadlineAPI

    init(context: ModelContext, api: DeadlineAPI) {
        self.context = context
        self.api = api
    }

    func fetchLocal(filter: DeadlineFilter) throws -> [DeadlineModel] {
        let allDescriptor = FetchDescriptor<DeadlineModel>()
        let allModels = try context.fetch(allDescriptor)
        
        let activeModels = allModels.filter { !$0.isDeleted }
        let sortedModels = activeModels.sorted { $0.dueDate < $1.dueDate }
        let filtered = sortedModels.filter { filter.matches($0) }
        return filtered
    }

    func storeLocal(from dto: DeadlineDTO) throws {
        if let existing = try findModel(by: dto.id) {
            updateModel(existing, with: dto, preserveIdentifier: true)
        } else {
            let model = DeadlineModel(
                id: dto.id,
                title: dto.title,
                subject: dto.subject,
                dueDate: dto.dueDate,
                status: dto.status,
                priority: dto.priority,
                tags: dto.tags,
                repeatType: dto.repeatType,
                notes: dto.notes,
                reminderTime: dto.reminderTime,
                remoteID: dto.remoteID,
                updatedAt: dto.updatedAt,
                isDirty: dto.isDirty,
                isDeleted: dto.isDeleted,
                deletedAt: dto.deletedAt
            )
            context.insert(model)
        }
    }

    func markDeleted(id: String) throws {
        guard let model = try findModel(by: id) else { return }
        model.isDeleted = true
        model.isDirty = true
        model.updatedAt = Date()
    }

    func deleteFromServerAndLocal(id: String) async throws {
        guard let model = try findModel(by: id) else { return }
        
        if let remoteID = model.remoteID, !remoteID.isEmpty {
            try await api.deleteDeadline(id: remoteID)
        } else if Int(model.id) != nil {
            try await api.deleteDeadline(id: model.id)
        }
        
        context.delete(model)
        try context.save()
    }

    func saveChanges() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    /// Server responses used to overwrite local priority with a placeholder "Средний".
    func migrateLegacyPlaceholderPriority() throws {
        let all = try context.fetch(FetchDescriptor<DeadlineModel>())
        var changed = false
        for model in all where model.priority == "Средний" {
            model.priority = "Авто"
            changed = true
        }
        if changed {
            try saveChanges()
        }
    }

    func syncWithServer() async throws {
        guard AuthService.shared.token != nil else { return }
        try await pushDirtyModels()
        try await pullRemoteChanges()
        try saveChanges()
    }

    // MARK: - Sync helpers

    private func pushDirtyModels() async throws {
        let descriptor = FetchDescriptor<DeadlineModel>(predicate: #Predicate { $0.isDirty == true })
        let dirtyModels = try context.fetch(descriptor)

        for model in dirtyModels {
            if model.isDeleted {
                if let remoteID = remoteIdentifier(for: model) {
                    do {
                        try await api.deleteDeadline(id: remoteID)
                    } catch APIError.httpStatus(let code, _) where code == 404 {
                        // Уже удалено на сервере — считаем синхронизированным
                    }
                }
                context.delete(model)
                continue
            }

            var dto = DeadlineDTO(model: model)
            dto.isDirty = false
            dto.isDeleted = false
            dto.updatedAt = Date()

            let preservedPriority = model.priority

            if let remoteID = remoteIdentifier(for: model) {
                dto.remoteID = remoteID
                do {
                    let localDeletedAt = dto.deletedAt
                    let updated = try await api.updateDeadline(dto)
                    updateModel(model, with: updated, preserveIdentifier: true)
                    model.priority = preservedPriority
                    model.remoteID = remoteID
                    if let localDeletedAt,
                       [DeadlineStatus.completed, .cancelled].contains(DeadlineStatus(rawStatus: model.status)) {
                        model.deletedAt = localDeletedAt
                    }
                } catch APIError.httpStatus(let code, _) where code == 404 {
                    // На сервере запись не найдена — создаём заново как новую
                    dto.remoteID = nil
                    let localDeletedAt = dto.deletedAt
                    let created = try await api.createDeadline(dto)
                    updateModel(model, with: created, preserveIdentifier: true)
                    model.priority = preservedPriority
                    model.remoteID = created.id
                    if let localDeletedAt,
                       [DeadlineStatus.completed, .cancelled].contains(DeadlineStatus(rawStatus: model.status)) {
                        model.deletedAt = localDeletedAt
                    }
                }
            } else {
                dto.remoteID = nil
                let localDeletedAt = dto.deletedAt
                let created = try await api.createDeadline(dto)
                model.remoteID = created.id
                updateModel(model, with: created, preserveIdentifier: true)
                model.priority = preservedPriority
                if let localDeletedAt,
                   [DeadlineStatus.completed, .cancelled].contains(DeadlineStatus(rawStatus: model.status)) {
                    model.deletedAt = localDeletedAt
                }
            }

            model.isDirty = false
            model.isDeleted = false
            model.updatedAt = Date()
        }
    }

    private func pullRemoteChanges() async throws {
        let remoteItems = try await api.fetchDeadlines(filter: DeadlineFilter())
        // An empty API response must not wipe local data — it happens with expired
        // auth, missing token, or transient server issues (e.g. after locale restart).
        guard !remoteItems.isEmpty else { return }

        let allModels = try context.fetch(FetchDescriptor<DeadlineModel>())
        var syncedRemoteIDs = Set<String>()

        for remote in remoteItems {
            let remoteID = remote.remoteID ?? remote.id
            if let match = allModels.first(where: { ($0.remoteID ?? $0.id) == remoteID }) {
                if match.isDirty { continue }
                let preservedDeletedAt = match.deletedAt
                let preservedPriority = match.priority
                var syncedRemote = remote
                syncedRemote.remoteID = remoteID
                syncedRemote.isDirty = false
                syncedRemote.isDeleted = false
                syncedRemote.updatedAt = Date()
                updateModel(match, with: syncedRemote, preserveIdentifier: true)
                match.priority = preservedPriority
                if let preservedDeletedAt,
                   [DeadlineStatus.completed, .cancelled].contains(DeadlineStatus(rawStatus: syncedRemote.status)) {
                    match.deletedAt = preservedDeletedAt
                }
                match.remoteID = remoteID
                syncedRemoteIDs.insert(remoteID)
            } else {
                let model = DeadlineModel(
                    id: remoteID,
                    title: remote.title,
                    subject: remote.subject,
                    dueDate: remote.dueDate,
                    status: remote.status,
                    priority: remote.priority,
                    tags: remote.tags,
                    repeatType: remote.repeatType,
                    notes: remote.notes,
                    reminderTime: remote.reminderTime,
                    remoteID: remoteID,
                    updatedAt: Date(),
                    isDirty: false,
                    isDeleted: false
                )
                context.insert(model)
                syncedRemoteIDs.insert(remoteID)
            }
        }

        try pruneMissingRemoteItems(keeping: syncedRemoteIDs)
    }

    private func pruneMissingRemoteItems(keeping remoteIDs: Set<String>) throws {
        let allModels = try context.fetch(FetchDescriptor<DeadlineModel>())
        for model in allModels where !model.isDirty {
            guard !model.isDeleted else {
                context.delete(model)
                continue
            }
            let identifier = remoteIdentifier(for: model)
            if let identifier, !remoteIDs.contains(identifier) {
                context.delete(model)
            }
        }
    }

    private func findModel(by id: String) throws -> DeadlineModel? {
        let descriptor = FetchDescriptor<DeadlineModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func model(for id: String) throws -> DeadlineModel? {
        try findModel(by: id)
    }

    private func updateModel(_ model: DeadlineModel, with dto: DeadlineDTO, preserveIdentifier: Bool) {
        if !preserveIdentifier {
            model.id = dto.id
        }
        model.title = dto.title
        model.subject = dto.subject
        model.dueDate = dto.dueDate
        model.status = dto.status
        model.priority = dto.priority
        model.tags = dto.tags
        model.repeatType = dto.repeatType
        model.notes = dto.notes
        model.reminderTime = dto.reminderTime
        model.deletedAt = dto.deletedAt
        model.remoteID = dto.remoteID ?? dto.id
        model.updatedAt = dto.updatedAt
        model.isDirty = dto.isDirty
        model.isDeleted = dto.isDeleted
    }

    private func remoteIdentifier(for model: DeadlineModel) -> String? {
        if let remote = model.remoteID, !remote.isEmpty { 
            return remote 
        }
        if Int(model.id) != nil { 
            return model.id 
        }
        return nil
    }
}

