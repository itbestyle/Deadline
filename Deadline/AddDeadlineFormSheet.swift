import SwiftUI

struct AddDeadlineFormSheet: View {
    @Binding var newTitle: String
    @Binding var newNotes: String
    @Binding var newSubject: String
    @Binding var newDate: Date
    @Binding var newReminderTime: String
    @Binding var newRepeatType: String
    @Binding var newPriority: String
    @Binding var newStatus: DeadlineStatus
    @Binding var selectedTags: Set<String>
    let isAddButtonEnabled: Bool
    let onCancel: () -> Void
    let onAdd: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Название"), text: $newTitle)
                        .focused($focusedField, equals: .title)
                        .accessibilityIdentifier("titleField")
                    TextField(L("Заметки"), text: $newNotes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("notesField")
                } header: {
                    sectionHeader(L("Основное"))
                }
                .listRowBackground(rowBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Section {
                    Picker(L("Предмет"), selection: $newSubject) {
                        ForEach(DeadlineFormOptions.subjects, id: \.value) { option in
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
                    sectionHeader(L("Срок"))
                }
                .listRowBackground(rowBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Section {
                    Picker(L("Напоминание"), selection: $newReminderTime) {
                        ForEach(DeadlineFormOptions.reminders, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .accessibilityIdentifier("reminderPicker")

                    Picker(L("Повторение"), selection: $newRepeatType) {
                        ForEach(DeadlineFormOptions.repeats, id: \.value) { option in
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
                    sectionHeader(L("Планирование"))
                }
                .listRowBackground(rowBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Section {
                    Picker(L("Приоритет"), selection: $newPriority) {
                        ForEach(DeadlineFormOptions.priorities, id: \.self) { option in
                            Text(L(option)).tag(option)
                        }
                    }
                    .accessibilityIdentifier("priorityPicker")
                    .disabled(newRepeatType != "none")
                    .opacity(newRepeatType != "none" ? 0.55 : 1)
                    .animation(.easeInOut(duration: 0.22), value: newPriority)

                    Picker(L("Статус"), selection: $newStatus) {
                        Text(L("в процессе")).tag(DeadlineStatus.inProgress)
                        Text(L("Выполнен")).tag(DeadlineStatus.completed)
                        Text(L("отменён")).tag(DeadlineStatus.cancelled)
                    }
                    .accessibilityIdentifier("statusPicker")
                    .animation(.easeInOut(duration: 0.22), value: newStatus)
                } header: {
                    sectionHeader(L("Состояние"))
                } footer: {
                    if newRepeatType != "none" {
                        Text(L("Для повторяющихся задач приоритет считается автоматически"))
                            .font(.caption)
                    }
                }
                .listRowBackground(rowBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Section {
                    HStack(spacing: 8) {
                        ForEach(DeadlineFormOptions.tags, id: \.self) { tag in
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
                    sectionHeader(L("Теги"))
                }
                .listRowBackground(rowBackground)
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
                        focusedField = nil
                    }
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("Новая задача"))
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Добавить"), action: onAdd)
                        .bold()
                        .accessibilityIdentifier("confirmAddDeadlineButton")
                        .disabled(!isAddButtonEnabled)
                        .opacity(isAddButtonEnabled ? 1 : 0.55)
                        .animation(.easeInOut(duration: 0.25), value: isAddButtonEnabled)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focusedField = .title
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }
}
