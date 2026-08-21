import Foundation

enum DeadlineSortMode: String, CaseIterable, Identifiable {
    case date
    case tag

    var id: DeadlineSortMode { self }

    var title: String {
        switch self {
        case .date: return L("По сроку")
        case .tag: return L("По тегу")
        }
    }
}

enum DeadlineFormOptions {
    static var statusFilters: [(label: String, value: String)] {
        [
            (L("Все статусы"), ""),
            (L("В процессе"), DeadlineStatus.inProgress.rawValue),
            (L("Выполнен"), DeadlineStatus.completed.rawValue),
            (L("Отменён"), DeadlineStatus.cancelled.rawValue)
        ]
    }

    static var subjectFilters: [(label: String, value: String)] {
        [
            (L("Все предметы"), ""),
            (L("Личное"), "Личное"),
            (L("Работа"), "Работа"),
            (L("Здоровье"), "Здоровье"),
            (L("Финансы"), "Финансы"),
            (L("Покупки"), "Покупки"),
            (L("Другое"), "Другое")
        ]
    }

    static var subjects: [(label: String, value: String)] {
        subjectFilters.filter { !$0.value.isEmpty }
    }

    static let tags: [String] = ["Срочно", "Личное", "Работа"]

    static let priorities = ["Авто", "Высокий", "Средний", "Низкий"]

    static var repeats: [(label: String, value: String)] {
        [
            (L("Без повторения"), "none"),
            (L("Ежедневно"), "daily"),
            (L("Еженедельно"), "weekly"),
            (L("Ежемесячно"), "monthly"),
            (L("Ежегодно"), "yearly")
        ]
    }

    static var reminders: [(label: String, value: String)] {
        [
            (L("Без напоминания"), "none"),
            (L("За час"), "1hour"),
            (L("За день"), "1day"),
            (L("За неделю"), "1week")
        ]
    }

    static func selectedLabel(for value: String, in options: [(label: String, value: String)]) -> String {
        options.first(where: { $0.value == value })?.label ?? options.first?.label ?? ""
    }
}
