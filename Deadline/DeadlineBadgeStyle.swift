import SwiftUI

struct BadgeContrastStyle: Equatable {
    let foreground: Color
    let background: Color
    let stroke: Color

    static func forPriority(_ priority: String, scheme: ColorScheme) -> BadgeContrastStyle {
        switch priority {
        case "Высокий":
            return scheme == .dark
                ? BadgeContrastStyle(
                    foreground: Color(red: 1, green: 0.55, blue: 0.55),
                    background: Color.red.opacity(0.28),
                    stroke: Color.red.opacity(0.55)
                )
                : BadgeContrastStyle(
                    foreground: Color(red: 0.72, green: 0.11, blue: 0.14),
                    background: Color.red.opacity(0.14),
                    stroke: Color.red.opacity(0.38)
                )
        case "Средний":
            return scheme == .dark
                ? BadgeContrastStyle(
                    foreground: Color(red: 1, green: 0.72, blue: 0.38),
                    background: Color.orange.opacity(0.26),
                    stroke: Color.orange.opacity(0.52)
                )
                : BadgeContrastStyle(
                    foreground: Color(red: 0.72, green: 0.32, blue: 0.02),
                    background: Color.orange.opacity(0.16),
                    stroke: Color.orange.opacity(0.4)
                )
        case "Низкий":
            return scheme == .dark
                ? BadgeContrastStyle(
                    foreground: Color(red: 1, green: 0.88, blue: 0.45),
                    background: Color.yellow.opacity(0.22),
                    stroke: Color.yellow.opacity(0.48)
                )
                : BadgeContrastStyle(
                    foreground: Color(red: 0.52, green: 0.38, blue: 0.02),
                    background: Color.yellow.opacity(0.22),
                    stroke: Color(red: 0.62, green: 0.48, blue: 0.08).opacity(0.45)
                )
        default:
            return forAccent(scheme: scheme)
        }
    }

    static func forAccent(scheme: ColorScheme) -> BadgeContrastStyle {
        scheme == .dark
            ? BadgeContrastStyle(
                foreground: Color(red: 0.72, green: 0.68, blue: 1),
                background: Color.indigo.opacity(0.28),
                stroke: Color.indigo.opacity(0.55)
            )
            : BadgeContrastStyle(
                foreground: Color(red: 0.28, green: 0.22, blue: 0.65),
                background: Color.indigo.opacity(0.14),
                stroke: Color.indigo.opacity(0.38)
            )
    }
}

struct AccessibleCapsuleBadge: View {
    var iconName: String? = nil
    let title: String
    let style: BadgeContrastStyle
    var pulsing: Bool = false
    var accessibilityLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 4
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.foreground)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(style.background)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(style.stroke, lineWidth: 1)
                )
        )
        .scaleEffect(pulsing ? (pulse ? 1.04 : 0.98) : 1)
        .opacity(pulsing ? (pulse ? 1 : 0.92) : 1)
        .accessibilityLabel(accessibilityLabel ?? title)
        .onAppear {
            pulse = pulsing
        }
        .onChange(of: pulsing) { _, newValue in
            pulse = newValue
        }
        .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: pulse)
    }
}

struct AccessibleTagBadge: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var horizontalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var verticalPadding: CGFloat = 5

    private var style: BadgeContrastStyle {
        BadgeContrastStyle.forAccent(scheme: colorScheme)
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(style.stroke, lineWidth: 1)
                    )
            )
            .accessibilityLabel(title)
    }
}
