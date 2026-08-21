import SwiftUI

struct WatchContentView: View {
    @Environment(WatchDeadlineStore.self) private var store

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Group {
                    if store.activeDeadlines.isEmpty {
                        emptyState
                    } else {
                        taskList(now: timeline.date)
                    }
                }
            }
            .navigationTitle("Redloop")
            .toolbarTitleDisplayMode(.inline)
            .toolbarForegroundStyle(Color.indigo, for: .automatic)
            .navigationDestination(for: WatchDeadlineModel.self) { item in
                WatchDeadlineDetailView(item: item)
            }
            .containerBackground(for: .navigation) {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.14), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func taskList(now: Date) -> some View {
        List {
            if !store.criticalDeadlines.isEmpty {
                section(
                    title: WL("Pressure High"),
                    tint: WatchPressurePalette.color(for: .critical),
                    items: store.criticalDeadlines,
                    now: now
                )
            }
            if !store.mediumDeadlines.isEmpty {
                section(
                    title: WL("Pressure Mid"),
                    tint: WatchPressurePalette.color(for: .medium),
                    items: store.mediumDeadlines,
                    now: now
                )
            }
            if !store.laterDeadlines.isEmpty {
                section(
                    title: WL("Позже"),
                    tint: WatchPressurePalette.color(for: .low),
                    items: store.laterDeadlines,
                    now: now
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationLinkIndicatorVisibility(.hidden)
    }

    private func section(
        title: String,
        tint: Color,
        items: [WatchDeadlineModel],
        now: Date
    ) -> some View {
        Section {
            ForEach(items.prefix(5)) { item in
                NavigationLink(value: item) {
                    WatchDeadlineRow(item: item, now: now)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 5, leading: 2, bottom: 5, trailing: 2))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            store.complete(item)
                        }
                    } label: {
                        Label(WL("Выполнен"), systemImage: "checkmark")
                    }
                    .tint(.green)
                }
            }
        } header: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .textCase(nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.lastUpdatedAt == nil ? "applewatch.radiowaves.left.and.right" : "checkmark")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(store.lastUpdatedAt == nil
                 ? WL("Откройте Redloop, чтобы подключить задачи")
                 : WL("Нет активных задач"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }
}

private struct WatchDeadlineRow: View {
    let item: WatchDeadlineModel
    let now: Date

    private var tint: Color { WatchPressurePalette.color(for: item.pressureLevel) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(item.subject)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(WatchDeadlineFormatting.remainingLabel(for: item, now: now))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                .font(.caption2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            WatchGlassBackground(tint: tint)
        }
        .contentShape(Rectangle())
    }
}

private struct WatchDeadlineDetailView: View {
    let item: WatchDeadlineModel

    @Environment(WatchDeadlineStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { WatchPressurePalette.color(for: item.pressureLevel) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.subject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(WatchDeadlineFormatting.fullDateLabel(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(WatchDeadlineFormatting.remainingLabel(for: item, now: timeline.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }

                    Button {
                        store.complete(item)
                        dismiss()
                    } label: {
                        Label(WL("Выполнен"), systemImage: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background {
                    WatchGlassBackground(tint: tint)
                }
                .padding(.horizontal, 2)
            }
        }
        .containerBackground(for: .navigation) {
            LinearGradient(
                colors: [tint.opacity(0.18), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .onChange(of: store.activeDeadlines) {
            if !store.activeDeadlines.contains(where: { $0.id == item.id }) {
                dismiss()
            }
        }
    }
}

private struct WatchGlassBackground: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.16), tint.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
    }
}

private enum WatchPressurePalette {
    static func color(for level: WatchPressureLevel) -> Color {
        switch level {
        case .critical: return .red
        case .medium: return .orange
        case .low: return Color(red: 0.82, green: 0.74, blue: 0.42)
        }
    }
}

private enum WatchDeadlineFormatting {
    static func remainingLabel(for item: WatchDeadlineModel, now: Date) -> String {
        guard let due = item.parsedDueDate else { return item.dueDate }

        if due < now {
            return WL("просрочен")
        }

        if Calendar.current.isDateInToday(due) {
            let time = due.formatted(date: .omitted, time: .shortened)
            if time == "00:00" || time == "0:00" {
                return WL("сегодня")
            }
            return time
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar

        let duration = formatter.string(from: max(due.timeIntervalSince(now), 60)) ?? item.dueDate
        return String(format: WL("через %@"), duration)
    }

    static func fullDateLabel(for item: WatchDeadlineModel) -> String {
        guard let due = item.parsedDueDate else { return item.dueDate }
        if item.dueDate.contains(":") {
            return due.formatted(date: .abbreviated, time: .shortened)
        }
        return due.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    WatchContentView()
        .environment(WatchDeadlineStore())
}
