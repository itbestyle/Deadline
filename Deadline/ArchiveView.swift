import SwiftUI
import UIKit

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
