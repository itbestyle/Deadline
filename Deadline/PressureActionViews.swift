import SwiftUI

struct PressureActionPlanSection: View {
    let plan: PressureActionPlan
    var onComplete: ((Deadline) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let next = plan.nextStep {
                nextStepCard(next)
            }

            if !plan.todayPlan.isEmpty {
                Text(PA("План на сегодня"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(plan.todayPlan) { item in
                    todayPlanRow(item)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func nextStepCard(_ item: PressureActionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(PA("Следующий шаг"), systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
                .accessibilityAddTraits(.isHeader)

            Text(item.deadline.title)
                .font(.title3.weight(.bold))
                .accessibilityLabel("\(PA("Задача")): \(item.deadline.title)")

            Text(item.deadline.localizedSubjectName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(immediateActionText(item))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onComplete {
                Button {
                    onComplete(item.deadline)
                } label: {
                    Label(PA("Отметить выполненным"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .accessibilityHint(PA("Завершить задачу и убрать из списка давления"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.indigo.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func todayPlanRow(_ item: PressureActionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.deadline.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(immediateActionText(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(String(format: PA("Срок: %@"), item.due.formatted(date: .omitted, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onComplete {
                Button {
                    onComplete(item.deadline)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
                .accessibilityLabel(PA("Отметить выполненным"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private func immediateActionText(_ item: PressureActionItem) -> String {
        String(format: PA("Сейчас: %d минут. %@"), item.focusMinutes, item.actionHint)
    }
}

private func PA(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
