import SwiftUI

struct UndoableDeadlineAction {
    enum Kind: Equatable {
        case completed
        case deleted
    }

    let kind: Kind
    let snapshot: Deadline
}

struct DeadlineUndoToast: View {
    let action: UndoableDeadlineAction
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.kind == .completed ? "checkmark.circle.fill" : "trash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(action.kind == .completed ? .green : .orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: onUndo) {
                Text(L("Отменить"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(L("Отменить"))")
        .accessibilityIdentifier("deadlineUndoToast")
    }

    private var message: String {
        switch action.kind {
        case .completed:
            return L("Задача выполнена")
        case .deleted:
            return L("Задача удалена")
        }
    }
}
