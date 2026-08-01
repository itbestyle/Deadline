import AppIntents
import SwiftUI
import WidgetKit

struct CriticalCountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCriticalSnapshot?
    let isLoggedIn: Bool
}

struct CriticalCountdownProvider: TimelineProvider {
    private let appGroup = WidgetSharedKeys.suiteName

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    func placeholder(in context: Context) -> CriticalCountdownEntry {
        CriticalCountdownEntry(
            date: Date(),
            snapshot: WidgetCriticalSnapshot(
                id: "demo",
                title: "Team sync",
                subject: "Work",
                dueInstant: Date().addingTimeInterval(8100),
                priority: "Высокий",
                updatedAt: Date()
            ),
            isLoggedIn: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CriticalCountdownEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CriticalCountdownEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetAppGroupStore.loadVisibleCritical()
        var entries = [makeEntry(at: now, snapshot: snapshot)]

        // Refresh once when the deadline passes; the on-screen timer ticks every second on its own.
        if let snapshot, snapshot.dueInstant > now {
            entries.append(makeEntry(at: snapshot.dueInstant, snapshot: snapshot))
        }

        let defaultRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        let refresh: Date
        if let snapshot, snapshot.dueInstant > now {
            refresh = min(defaultRefresh, snapshot.dueInstant.addingTimeInterval(1))
        } else {
            refresh = defaultRefresh
        }

        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func makeEntry(at date: Date, snapshot: WidgetCriticalSnapshot? = nil) -> CriticalCountdownEntry {
        let resolved = snapshot ?? WidgetAppGroupStore.loadVisibleCritical()
        let isLoggedIn = sharedDefaults?.string(forKey: "auth_token") != nil
        return CriticalCountdownEntry(date: date, snapshot: resolved, isLoggedIn: isLoggedIn)
    }
}

struct CriticalCountdownWidgetView: View {
    let entry: CriticalCountdownEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.isLoggedIn {
            loggedOutView
        } else if let snapshot = entry.snapshot, isActive(snapshot) {
            countdownView(snapshot)
        } else {
            relaxedView
        }
    }

    private func isActive(_ snapshot: WidgetCriticalSnapshot) -> Bool {
        snapshot.isCritical || snapshot.dueInstant.timeIntervalSince(entry.date) <= 72 * 3600
    }

    private func urgencyColor(for snapshot: WidgetCriticalSnapshot) -> Color {
        let remaining = snapshot.dueInstant.timeIntervalSince(entry.date)
        if remaining <= 0 { return .red }
        if remaining <= 24 * 3600 { return .red }
        return .orange
    }

    private func timerReference(for snapshot: WidgetCriticalSnapshot) -> Date {
        // Anchor to snapshot write time so the interval stays correct between timeline reloads.
        max(entry.date, snapshot.updatedAt)
    }

    @ViewBuilder
    private func countdownView(_ snapshot: WidgetCriticalSnapshot) -> some View {
        let color = urgencyColor(for: snapshot)
        let reference = timerReference(for: snapshot)

        switch family {
        case .accessoryInline:
            if isOverdue(snapshot, reference: reference) {
                (Text("\(snapshot.title) · ")
                    + Text(snapshot.dueInstant, style: .timer))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            } else {
                (Text("\(snapshot.title) · ")
                    + Text(timerInterval: reference...snapshot.dueInstant, countsDown: true))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: isOverdue(snapshot, reference: reference) ? "exclamationmark" : "timer")
                        .font(.caption2)
                    WidgetLiveCountdownText(
                        dueInstant: snapshot.dueInstant,
                        reference: reference,
                        font: .system(size: 10, weight: .bold, design: .default),
                        upcomingColor: color,
                        overdueColor: .red,
                        alignment: .center
                    )
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(1)
                WidgetLiveCountdownText(
                    dueInstant: snapshot.dueInstant,
                    reference: reference,
                    font: .caption.monospacedDigit().weight(.semibold),
                    upcomingColor: color,
                    overdueColor: .red
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image("LoginIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Spacer(minLength: 0)
                    priorityBadge(snapshot.priority)
                }
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(snapshot.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOverdue(snapshot, reference: reference) ? WidgetL10n.string("Просрочено") : WidgetL10n.string("До дедлайна"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WidgetLiveCountdownText(
                        dueInstant: snapshot.dueInstant,
                        reference: reference,
                        font: .system(size: 28, weight: .bold, design: .default),
                        upcomingColor: color,
                        overdueColor: .red
                    )
                }
                if #available(iOS 17.0, *) {
                    Button(intent: CompleteDeadlineWidgetIntent(deadlineID: snapshot.id)) {
                        Label(WidgetL10n.string("Отметить выполненным"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(WidgetIntentButtonStyle())
                    .foregroundStyle(.indigo)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
        }
    }

    private func isOverdue(_ snapshot: WidgetCriticalSnapshot, reference: Date? = nil) -> Bool {
        WidgetCountdownFormatter.isOverdue(
            dueInstant: snapshot.dueInstant,
            reference: reference ?? timerReference(for: snapshot)
        )
    }

    private func timerRange(for snapshot: WidgetCriticalSnapshot, reference: Date? = nil) -> ClosedRange<Date> {
        let anchor = reference ?? timerReference(for: snapshot)
        if isOverdue(snapshot, reference: anchor) {
            return snapshot.dueInstant...anchor
        }
        return anchor...snapshot.dueInstant
    }

    private var loggedOutView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Redloop", systemImage: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
            Text(WidgetL10n.string("Войдите в приложение"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var relaxedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(WidgetL10n.string("Давление низкое"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text(WidgetL10n.string("Критичных дедлайнов на 72ч нет"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = priority == "Высокий" ? .red : (priority == "Средний" ? .orange : .yellow)
        Text(WidgetL10n.localizedPriority(priority))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

struct WidgetIntentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.78 : 1)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct CriticalCountdownWidget: Widget {
    let kind = "CriticalCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CriticalCountdownProvider()) { entry in
            if #available(iOS 17.0, *) {
                CriticalCountdownWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                CriticalCountdownWidgetView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName(WidgetL10n.string("Критичный дедлайн"))
        .description(WidgetL10n.string("Ближайшая срочная задача и обратный отсчёт"))
        .supportedFamilies([
            .systemSmall,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
