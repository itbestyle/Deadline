import SwiftUI

#if !os(watchOS)
final class WatchDeadlineStore: ObservableObject {
    @Published var activeDeadlines: [WatchDeadlineModel] = []
    @Published var criticalDeadlines: [WatchDeadlineModel] = []
    @Published var mediumDeadlines: [WatchDeadlineModel] = []
}

struct WatchDeadlineModel: Identifiable {
    let id = UUID().uuidString
    let title = ""
    let subject = ""
    let dueDate = ""
    let pressureLevel: WatchPressureLevel = .low
}

enum WatchPressureLevel {
    case critical
    case medium
    case low

    var symbol: String { "checkmark.circle.fill" }
}
#endif

#if os(watchOS)
struct WatchContentView: View {
    @EnvironmentObject private var store: WatchDeadlineStore

    var body: some View {
        List {
            if !store.criticalDeadlines.isEmpty {
                Section("Pressure High") {
                    ForEach(store.criticalDeadlines.prefix(3)) { item in
                        WatchDeadlineRow(item: item)
                    }
                }
            }

            if !store.mediumDeadlines.isEmpty {
                Section("Pressure Mid") {
                    ForEach(store.mediumDeadlines.prefix(3)) { item in
                        WatchDeadlineRow(item: item)
                    }
                }
            }

            if store.activeDeadlines.isEmpty {
                Section {
                    Text("Нет активных задач")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Redloop")
    }
}
#endif

private struct WatchDeadlineRow: View {
    let item: WatchDeadlineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: item.pressureLevel.symbol)
                    .foregroundStyle(color(for: item.pressureLevel))
                    .font(.caption2.weight(.semibold))

                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }

            Text("\(item.subject) · \(formattedDueDate(item.dueDate))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }

    private func color(for level: WatchPressureLevel) -> Color {
        switch level {
        case .critical:
            return .red
        case .medium:
            return .yellow
        case .low:
            return .green
        }
    }

    private func formattedDueDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            parser.dateFormat = format
            if let date = parser.date(from: value) {
                let output = DateFormatter()
                output.locale = Locale(identifier: "ru_RU")
                if Calendar.current.isDateInToday(date) {
                    output.dateFormat = "HH:mm"
                } else {
                    output.dateFormat = "dd.MM"
                }
                return output.string(from: date)
            }
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            let output = DateFormatter()
            output.locale = Locale(identifier: "ru_RU")
            output.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "dd.MM"
            return output.string(from: date)
        }

        return value
    }
}
