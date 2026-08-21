import SwiftUI

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
