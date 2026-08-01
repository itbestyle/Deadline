import SwiftUI
import UIKit

private func A(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @State private var iconErrorMessage: String?
    @State private var selectedIconName: String?
    @State private var isThemeExpanded = false

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    private let cardTitleFont: Font = .subheadline
    private let cardValueFont: Font = .subheadline
    private let iconLabelFont: Font = .caption

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appTheme) ?? .system
    }

    private var iconOptions: [AppIconOption] {
        let alternateNames = availableAlternateIconNames()
        let alternateOptions = alternateNames.map {
            AppIconOption(name: $0, title: displayTitle(for: $0), previewAssetName: previewAssetName(for: $0))
        }
        return [AppIconOption(name: nil, title: A("Основная"), previewAssetName: "IconPreviewPrimary")] + alternateOptions
    }

    var body: some View {
        ScrollView {
            AdaptiveWidthContainer {
                VStack(alignment: .leading, spacing: 24) {
                    settingsCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text(A("Иконка приложения"))
                            .font(cardTitleFont.weight(.semibold))
                            .foregroundStyle(.secondary)

                        iconGridCard
                    }

                    if !UIApplication.shared.supportsAlternateIcons {
                        Text(A("Это устройство не поддерживает альтернативные иконки."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else if availableAlternateIconNames().isEmpty {
                        Text(A("Альтернативные иконки не настроены в проекте. Добавьте их в Info.plist (CFBundleAlternateIcons)."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    if let iconErrorMessage {
                        Text(iconErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(A("Оформление"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(selectedTheme.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: appTheme)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label(A("Назад"), systemImage: "chevron.left")
                }
            }
        }
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isThemeExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(A("Тема"))
                        .font(cardTitleFont)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(selectedTheme.label)
                        .font(cardValueFont)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isThemeExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)

            if isThemeExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.12))

                VStack(spacing: 0) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Button {
                            appTheme = theme.rawValue
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isThemeExpanded = false
                            }
                        } label: {
                            HStack {
                                Text(theme.label)
                                    .font(cardValueFont)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.indigo)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        if theme != AppTheme.allCases.last {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.leading, 16)
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var iconGridCard: some View {
        LazyVGrid(columns: iconColumns, spacing: 18) {
            ForEach(iconOptions) { option in
                Button {
                    setAppIcon(to: option.name)
                } label: {
                    VStack(spacing: 8) {
                        Image(option.previewAssetName)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.tertiarySystemBackground))
                            )
                        .frame(height: 70)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isCurrentIcon(option.name) ? Color.indigo : Color.white.opacity(0.08), lineWidth: isCurrentIcon(option.name) ? 2.4 : 1)
                        )

                        Text(option.title)
                            .font(iconLabelFont)
                            .foregroundStyle(isCurrentIcon(option.name) ? .indigo : .primary)
                            .lineLimit(1)
                            .frame(height: 14)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!UIApplication.shared.supportsAlternateIcons && option.name != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func isCurrentIcon(_ iconName: String?) -> Bool {
        selectedIconName == iconName
    }

    private func setAppIcon(to iconName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard selectedIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            DispatchQueue.main.async {
                if let error {
                    iconErrorMessage = error.localizedDescription
                } else {
                    selectedIconName = iconName
                    iconErrorMessage = nil
                }
            }
        }
    }

    private func availableAlternateIconNames() -> [String] {
        guard
            let bundleIcons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let alternates = bundleIcons["CFBundleAlternateIcons"] as? [String: Any]
        else {
            return []
        }

        return alternates.keys.sorted()
    }

    private func previewAssetName(for iconName: String) -> String {
        switch iconName {
        case "AppIconLight":
            return "IconPreviewLight"
        case "AppIconDark":
            return "IconPreviewDark"
        default:
            return "IconPreviewPrimary"
        }
    }

    private func displayTitle(for iconName: String) -> String {
        switch iconName {
        case "AppIconLight":
            return A("Светлая")
        case "AppIconDark":
            return A("Тёмная")
        default:
            break
        }

        let normalized = iconName
            .replacingOccurrences(of: "AppIcon", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return A("Вариант")
        }

        return normalized.prefix(1).uppercased() + normalized.dropFirst()
    }
}

private struct AppIconOption: Identifiable {
    let name: String?
    let title: String
    let previewAssetName: String

    var id: String {
        name ?? "primary"
    }
}
