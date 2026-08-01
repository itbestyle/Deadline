import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [(icon: String, titleKey: String, bodyKey: String)] = [
        (
            "list.bullet.rectangle",
            "Задачи по срокам",
            "Вкладка «Задачи» группирует дела по календарю: просрочено, сегодня, неделя. Удобно планировать и искать по названию, категории и тегам."
        ),
        (
            "exclamationmark.triangle.fill",
            "Задачи vs Pressure",
            "Pressure — не второй список, а режим фокуса на ближайшие 24 и 72 часа: нагрузка, просрочки и конкретный следующий шаг."
        ),
        (
            "wand.and.stars",
            "Auto-приоритет",
            "Если приоритет «Авто», Redloop сам ставит срочность по оставшемуся времени: до 24ч — высокий, до 72ч — средний, дальше — низкий."
        ),
        (
            "scope",
            "Следующий шаг",
            "В Pressure вы увидите план на сегодня и кнопку «Отметить выполненным». После действия 3 секунды можно отменить."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    onboardingPage(icon: item.icon, titleKey: item.titleKey, bodyKey: item.bodyKey)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    page += 1
                } else {
                    isPresented = false
                }
            } label: {
                Text(page < pages.count - 1 ? OB("Далее") : OB("Начать"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button(OB("Пропустить")) {
                isPresented = false
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
            .opacity(page < pages.count - 1 ? 1 : 0)
            .allowsHitTesting(page < pages.count - 1)
            .accessibilityHidden(page >= pages.count - 1)
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        .background(Color(.systemBackground))
        .iPadReadableContent(maxWidth: 560)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func onboardingPage(icon: String, titleKey: String, bodyKey: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text(OB(titleKey))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(OB(bodyKey))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }
}

private func OB(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
