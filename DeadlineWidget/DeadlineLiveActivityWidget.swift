import ActivityKit
import SwiftUI
import WidgetKit

/// Countdown for Live Activity — anchored to `dueInstant` only (no stale `remainingSeconds`).
private struct LiveActivityCountdownText: View {
    let dueInstant: Date
    var isOverdue: Bool
    var font: Font = .body
    var width: CGFloat = 84
    var alignment: Alignment = .trailing

    private var timerAnchor: Date {
        dueInstant.addingTimeInterval(-7 * 86_400)
    }

    var body: some View {
        Group {
            if isOverdue {
                Text(dueInstant, style: .timer)
                    .foregroundStyle(.red)
            } else {
                Text(timerInterval: timerAnchor...dueInstant, countsDown: true)
                    .foregroundStyle(.orange)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: width > 0 ? width : nil, alignment: alignment)
    }
}

private struct DeadlineLiveActivityContentView: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<DeadlineActivityAttributes>

    private var overdue: Bool {
        context.state.isOverdue || context.attributes.dueInstant <= Date()
    }

    var body: some View {
        switch activityFamily {
        case .small:
            watchSmartStackView
        default:
            lockScreenView
        }
    }

    /// Compact layout for Apple Watch Smart Stack (watchOS 11+).
    private var watchSmartStackView: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: overdue ? "exclamationmark.triangle.fill" : "timer")
                .font(.caption.weight(.bold))
                .foregroundStyle(overdue ? .red : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(context.state.subject)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            LiveActivityCountdownText(
                dueInstant: context.attributes.dueInstant,
                isOverdue: overdue,
                font: .caption2.weight(.bold).monospacedDigit(),
                width: 52,
                alignment: .trailing
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var lockScreenView: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow(alignment: .firstTextBaseline) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(overdue ? WidgetL10n.string("Просрочено") : WidgetL10n.string("До дедлайна"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            GridRow(alignment: .firstTextBaseline) {
                Text(context.state.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LiveActivityCountdownText(
                    dueInstant: context.attributes.dueInstant,
                    isOverdue: overdue,
                    font: .system(size: 24, weight: .bold).monospacedDigit(),
                    width: 72
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct DeadlineLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeadlineActivityAttributes.self) { context in
            DeadlineLiveActivityContentView(context: context)
                .activityBackgroundTint(Color.red.opacity(0.18))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let overdue = context.state.isOverdue || context.attributes.dueInstant <= Date()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: overdue ? "exclamationmark.triangle.fill" : "timer")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.subject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityCountdownText(
                        dueInstant: context.attributes.dueInstant,
                        isOverdue: overdue,
                        font: .caption.weight(.bold).monospacedDigit(),
                        width: 64
                    )
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.red)
            } compactTrailing: {
                LiveActivityCountdownText(
                    dueInstant: context.attributes.dueInstant,
                    isOverdue: overdue,
                    font: .caption2.weight(.semibold).monospacedDigit(),
                    width: 48
                )
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.red)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}
