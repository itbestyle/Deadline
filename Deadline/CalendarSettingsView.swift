import SwiftUI

struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var syncEnabled = CalendarIntegrationManager.shared.isSyncEnabled
    @State private var hasAccess = CalendarIntegrationManager.shared.hasCalendarAccess
    @State private var isRequestingAccess = false

    var body: some View {
        List {
            Section {
                Toggle(L("Дублировать задачи в Календарь"), isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, newValue in
                        CalendarIntegrationManager.shared.isSyncEnabled = newValue
                    }
            } footer: {
                Text(L("События создаются без дублирующих напоминаний — уведомления остаются в Redloop."))
                    .font(.caption)
            }

            Section(L("Доступ")) {
                HStack {
                    Text(L("Статус"))
                    Spacer()
                    Text(hasAccess ? L("Разрешён") : L("Не подключён"))
                        .foregroundStyle(hasAccess ? .green : .secondary)
                }

                Button {
                    Task { await requestAccess() }
                } label: {
                    if isRequestingAccess {
                        ProgressView()
                    } else {
                        Text(L("Запросить доступ к календарю"))
                    }
                }
                .disabled(isRequestingAccess)
            }
        }
        .navigationTitle(L("Календарь iOS"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Готово")) { dismiss() }
            }
        }
        .onAppear {
            syncEnabled = CalendarIntegrationManager.shared.isSyncEnabled
            hasAccess = CalendarIntegrationManager.shared.hasCalendarAccess
        }
    }

    private func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        hasAccess = await CalendarIntegrationManager.shared.requestCalendarAccess()
    }
}

struct ProductHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L("Задачи")) {
                    Text(L("Список группирует задачи по сроку: просрочено, сегодня, неделя и позже. Цвет карточки и бейдж показывают срочность."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(L("Приоритет")) {
                    Text(L("«Авто» считает приоритет от времени до дедлайна: до 24 часов — высокий, до 72 — средний. Ручной приоритет можно задать при создании и в редактировании."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(L("Режим давления")) {
                    Text(L("Аналитика ближайших 24 и 72 часов: нагрузка, просрочки и фокус на критичных задачах. Отличается от календарного списка."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Как устроен Redloop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) { dismiss() }
                }
            }
        }
    }
}
