
import Foundation
import SwiftUI

struct EditDeadlineView: View {
    @State private var deadline: Deadline
    @State private var deadlineDate: Date
    @FocusState private var focusedField: FocusedField?
    @Environment(\.dismiss) private var dismiss
    var onSave: (Deadline) -> Void

    private enum FocusedField: Hashable {
        case title
        case subject
        case notes
    }
    
    private var repeatOptions: [(label: String, value: String)] {
        [
            (localized("Без повторения"), "none"),
            (localized("Ежедневно"), "daily"),
            (localized("Еженедельно"), "weekly"),
            (localized("Ежемесячно"), "monthly"),
            (localized("Ежегодно"), "yearly")
        ]
    }
    
    private var reminderOptions: [(label: String, value: String)] {
        [
            (localized("Без напоминания"), "none"),
            (localized("За час"), "1hour"),
            (localized("За день"), "1day"),
            (localized("За неделю"), "1week")
        ]
    }

    private let priorityOptions = ["Авто", "Высокий", "Средний", "Низкий"]

    init(deadline: Deadline, onSave: @escaping (Deadline) -> Void) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "yyyy-MM-dd"
        _deadline = State(initialValue: deadline)
        _deadlineDate = State(initialValue: formatter.date(from: deadline.dueDate) ?? legacy.date(from: deadline.dueDate) ?? Date())
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            AdaptiveWidthContainer(maxContentWidth: 720) {
                Form {
                    Section {
                        TextField(localized("Название"), text: $deadline.title)
                            .focused($focusedField, equals: .title)
                        TextField(localized("Предмет"), text: $deadline.subject)
                            .focused($focusedField, equals: .subject)
                        TextField(localized("Заметки"), text: $deadline.notes, axis: .vertical)
                            .focused($focusedField, equals: .notes)
                            .lineLimit(2...4)
                    } header: {
                        Text(localized("Основное"))
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
                        HStack(spacing: 12) {
                            Text(localized("Дата и время"))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            DatePicker("", selection: $deadlineDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }

                        Picker(localized("Статус"), selection: Binding(
                            get: { deadline.statusType },
                            set: { deadline.statusType = $0 }
                        )) {
                            Text(localized("в процессе")).tag(DeadlineStatus.inProgress)
                            Text(localized("Выполнен")).tag(DeadlineStatus.completed)
                            Text(localized("отменён")).tag(DeadlineStatus.cancelled)
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        Picker(localized("Приоритет"), selection: $deadline.priority) {
                            ForEach(priorityOptions, id: \.self) { option in
                                Text(localized(option)).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(deadline.repeatType != "none")
                        .opacity(deadline.repeatType != "none" ? 0.55 : 1)
                    } header: {
                        Text(localized("Состояние"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    } footer: {
                        if deadline.repeatType != "none" {
                            Text(localized("Для повторяющихся задач приоритет считается автоматически"))
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
                        Picker(localized("Повторение"), selection: $deadline.repeatType) {
                            ForEach(repeatOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: deadline.repeatType) { _, newValue in
                            if newValue != "none" {
                                deadline.priority = "Авто"
                            }
                        }

                        Picker(localized("Напоминание"), selection: $deadline.reminderTime) {
                            ForEach(reminderOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text(localized("Планирование"))
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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            focusedField = nil
                        }
                )
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(localized("Редактировать"))
                            .font(.headline.weight(.semibold))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localized("Сохранить")) {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.dateFormat = "yyyy-MM-dd HH:mm"
                            deadline.dueDate = formatter.string(from: deadlineDate)

                            onSave(deadline)
                        }
                        .bold()
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localized("Отмена")) {
                            dismiss()
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
