import SwiftUI

struct FilterControlsView: View {
    @Binding var filterStatus: String
    @Binding var filterSubject: String
    @Binding var sortMode: DeadlineSortMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Фильтры"))
                    .font(.headline)

                if activeFilterCount > 0 {
                    activeFilterBadge
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Menu {
                            Picker(L("Статус"), selection: $filterStatus) {
                                ForEach(DeadlineFormOptions.statusFilters, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                        } label: {
                            chipLabel(
                                icon: "checkmark.seal",
                                text: DeadlineFormOptions.selectedLabel(for: filterStatus, in: DeadlineFormOptions.statusFilters),
                                isActive: !filterStatus.isEmpty
                            )
                        }
                        .accessibilityIdentifier("filterStatusPicker")

                        Menu {
                            Picker(L("Предмет"), selection: $filterSubject) {
                                ForEach(DeadlineFormOptions.subjectFilters, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                        } label: {
                            chipLabel(
                                icon: "books.vertical",
                                text: DeadlineFormOptions.selectedLabel(for: filterSubject, in: DeadlineFormOptions.subjectFilters),
                                isActive: !filterSubject.isEmpty
                            )
                        }
                        .accessibilityIdentifier("filterSubjectPicker")

                        Spacer()
                            .frame(width: 4.5)

                        Menu {
                            Picker(L("Сортировка"), selection: $sortMode) {
                                ForEach(DeadlineSortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                        } label: {
                            chipLabel(
                                icon: "arrow.up.arrow.down.circle.fill",
                                text: sortMode.title,
                                isActive: true,
                                prominent: true,
                                iconSize: 14,
                                iconWeight: .bold
                            )
                        }
                        .accessibilityIdentifier("sortModePicker")

                        if !filterStatus.isEmpty || !filterSubject.isEmpty {
                            Button {
                                filterStatus = ""
                                filterSubject = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(Color.red.opacity(colorScheme == .light ? 0.95 : 0.9))
                                    .background(
                                        Circle()
                                            .fill(.regularMaterial)
                                            .overlay(
                                                Circle()
                                                    .fill(colorScheme == .light ? Color.red.opacity(0.22) : Color.red.opacity(0.3))
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.red.opacity(colorScheme == .light ? 0.58 : 0.66), lineWidth: 1.2)
                                            )
                                    )
                                    .shadow(color: Color.red.opacity(colorScheme == .light ? 0.22 : 0.32), radius: 9, x: 0, y: 4)
                            }
                            .accessibilityLabel(Text(L("Сбросить")))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                HStack {
                    LinearGradient(
                        colors: [filterTrayEdgeMask, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, filterTrayEdgeMask],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(filterTrayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(filterTrayStroke, lineWidth: 1)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(filterTrayTopHighlight, lineWidth: 1)
                            .mask(
                                LinearGradient(
                                    colors: [.white.opacity(0.95), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .compositingGroup()
            .shadow(color: filterTrayShadow, radius: 10, x: 0, y: 4)
        }
    }

    private func chipLabel(
        icon: String,
        text: String,
        isActive: Bool,
        prominent: Bool = false,
        iconSize: CGFloat = 13,
        iconWeight: Font.Weight = .semibold
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: iconWeight))
            Text(text)
                .font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .opacity(prominent ? 0.86 : 0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(chipForegroundColor(isActive: isActive, accent: .indigo, prominent: prominent))
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(chipFillColor(isActive: isActive, accent: .indigo, prominent: prominent))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(chipStrokeColor(isActive: isActive, accent: .indigo, prominent: prominent), lineWidth: prominent ? 1.1 : 1)
                )
        )
        .shadow(
            color: chipShadowColor(isActive: isActive, accent: .indigo, prominent: prominent),
            radius: isActive ? (prominent ? 11 : 9) : 0,
            x: 0,
            y: isActive ? (prominent ? 6 : 5) : 0
        )
    }

    private var activeFilterBadge: some View {
        let style = BadgeContrastStyle.forAccent(scheme: colorScheme)
        return Text("\(activeFilterCount)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(style.foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(style.stroke, lineWidth: 1)
                    )
            )
            .accessibilityLabel(String(format: L("Активных фильтров: %d"), activeFilterCount))
    }

    private var filterTrayFill: Color {
        colorScheme == .light
            ? Color(.secondarySystemGroupedBackground)
            : Color.white.opacity(0.08)
    }

    private var filterTrayStroke: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.1)
    }

    private var filterTrayTopHighlight: Color {
        colorScheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.1)
    }

    private var filterTrayShadow: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.3)
    }

    private var filterTrayEdgeMask: Color {
        filterTrayFill
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterStatus.isEmpty { count += 1 }
        if !filterSubject.isEmpty { count += 1 }
        return count
    }

    private func chipFillColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            if prominent {
                return colorScheme == .light ? accent.opacity(0.52) : accent.opacity(0.62)
            }
            return colorScheme == .light ? accent.opacity(0.44) : accent.opacity(0.54)
        }
        return colorScheme == .light ? Color.white.opacity(0.18) : Color.white.opacity(0.06)
    }

    private func chipStrokeColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            if prominent {
                return accent.opacity(colorScheme == .light ? 0.82 : 0.88)
            }
            return accent.opacity(colorScheme == .light ? 0.72 : 0.8)
        }
        return Color.primary.opacity(colorScheme == .light ? 0.12 : 0.2)
    }

    private func chipForegroundColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        if isActive {
            return colorScheme == .light ? Color.white.opacity(prominent ? 1.0 : 0.98) : Color.white.opacity(prominent ? 0.98 : 0.95)
        }
        return .primary
    }

    private func chipShadowColor(isActive: Bool, accent: Color, prominent: Bool = false) -> Color {
        guard isActive else { return .clear }
        if prominent {
            return accent.opacity(colorScheme == .light ? 0.2 : 0.3)
        }
        return accent.opacity(colorScheme == .light ? 0.16 : 0.24)
    }
}
