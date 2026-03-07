import SwiftUI
import StoreKit
import Combine

private func P(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let pressureMonthlyProductID = "com.redloop.pressuremode.monthly"
    static let pressureYearlyProductID = "com.redloop.pressuremode.yearly"
#if DEBUG
    private static let debugPressureUnlockKey = "debug_pressure_pro_unlocked"
#endif

    @Published private(set) var isPressureProUnlocked = false
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var nextRenewalDate: Date?
    @Published private(set) var isLoading = false
    @Published var purchaseErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()

        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.pressureMonthlyProductID, Self.pressureYearlyProductID])
            monthlyProduct = products.first(where: { $0.id == Self.pressureMonthlyProductID })
            yearlyProduct = products.first(where: { $0.id == Self.pressureYearlyProductID })
        } catch {
            purchaseErrorMessage = P("Не удалось загрузить подписку")
        }
    }

    func purchasePressureMode(plan: PressurePlan) async {
        guard let product = product(for: plan) else {
            purchaseErrorMessage = P("Выбранный план пока недоступен")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseErrorMessage = P("Покупка ожидает подтверждения")
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = P("Не удалось оформить подписку")
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = P("Не удалось восстановить покупки")
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        var nearestRenewalDate: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if [Self.pressureMonthlyProductID, Self.pressureYearlyProductID].contains(transaction.productID),
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                unlocked = true
                if let expirationDate = transaction.expirationDate {
                    if let existing = nearestRenewalDate {
                        nearestRenewalDate = min(existing, expirationDate)
                    } else {
                        nearestRenewalDate = expirationDate
                    }
                }
            }
        }

#if DEBUG
        if UserDefaults.standard.bool(forKey: Self.debugPressureUnlockKey) {
            unlocked = true
        }
#endif

        isPressureProUnlocked = unlocked
    nextRenewalDate = unlocked ? nearestRenewalDate : nil
    }

#if DEBUG
    func setDebugUnlock(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.debugPressureUnlockKey)
        isPressureProUnlocked = enabled
    }
#endif

    func product(for plan: PressurePlan) -> Product? {
        switch plan {
        case .monthly:
            return monthlyProduct
        case .yearly:
            return yearlyProduct
        }
    }

    var hasAnyProduct: Bool {
        monthlyProduct != nil || yearlyProduct != nil
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await update in Transaction.updates {
                guard let transaction = try? checkVerified(update) else { continue }
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signed):
            return signed
        case .unverified:
            throw SubscriptionError.failedVerification
        }
    }
}

enum SubscriptionError: Error {
    case failedVerification
}

enum PressurePlan {
    case monthly
    case yearly
}

struct PressurePaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var subscriptionManager: SubscriptionManager
    @State private var selectedPlan: PressurePlan = .yearly
    @State private var firePulse = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(P("Режим давления Pro"))
                            .font(.title2.weight(.bold))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(P("Работайте в режиме максимального фокуса"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(P("Видьте перегруз за 7 дней вперёд\nи действуйте до того, как станет поздно"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    pressurePreviewCard

                    VStack(alignment: .leading, spacing: 10) {
                        featureRow(icon: "flame.fill", text: P("Видите перегруз до того, как он уничтожит ваш график"))
                        featureRow(icon: "exclamationmark.triangle.fill", text: P("Работайте под контролируемым давлением"))
                        featureRow(icon: "chart.bar.doc.horizontal.fill", text: P("Еженедельные отчёты давления"))
                        featureRow(icon: "bolt.fill", text: P("Не позволяйте дедлайнам застать вас врасплох"))
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.red.opacity(0.14), radius: 14, x: 0, y: 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(P("Выберите план"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                selectedPlan = .monthly
                            } label: {
                                planCard(
                                    title: P("Месяц"),
                                    priceText: P("$2.99 / month"),
                                    subtitle: P("7 days free"),
                                    accentColor: .indigo,
                                    isSelected: selectedPlan == .monthly,
                                    isBestChoice: false
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedPlan = .yearly
                            } label: {
                                planCard(
                                    title: P("Год"),
                                    priceText: P("$19.99 / year"),
                                    subtitle: P("7 days free · Экономия 44% — меньше $1.70 в месяц"),
                                    accentColor: .purple,
                                    isSelected: selectedPlan == .yearly,
                                    isBestChoice: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if subscriptionManager.hasAnyProduct {
                        Button {
                            Task { await subscriptionManager.purchasePressureMode(plan: selectedPlan) }
                        } label: {
                            HStack {
                                if subscriptionManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Image(systemName: "bolt.fill")
                                    .font(.subheadline.weight(.bold))
                                Text(ctaText)
                                    .font(.headline.weight(.semibold))
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [Color.indigo, Color.red.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .disabled(subscriptionManager.isLoading)
                    } else {
                        Button {
                            Task { await subscriptionManager.loadProducts() }
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .font(.subheadline.weight(.bold))
                                Text(P("Включить режим давления"))
                                    .font(.headline.weight(.semibold))
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [Color.indigo, Color.red.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .disabled(subscriptionManager.isLoading)
                    }

                    Button(P("Восстановить покупки")) {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(subscriptionManager.isLoading)

                    if let error = subscriptionManager.purchaseErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

#if DEBUG
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DEBUG")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        let stats = PressureABAnalytics.shared.snapshot
                        Text("A/B: \(stats.variant.rawValue.uppercased()) · Показов CTA: \(stats.ctaImpressions) · Кликов CTA: \(stats.ctaClicks) · Показов Paywall: \(stats.paywallShows)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button("Debug unlock") {
                                subscriptionManager.setDebugUnlock(true)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Debug lock") {
                                subscriptionManager.setDebugUnlock(false)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
#endif
                }
            }
            .padding()
            .navigationTitle(P("Подписка"))
            .toolbar {
                ToolbarItem {
                    Button(P("Закрыть")) { dismiss() }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .onChange(of: subscriptionManager.isPressureProUnlocked) { _, unlocked in
            if unlocked {
                dismiss()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                firePulse = true
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.indigo)
                .font(.headline)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pressurePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(P("Pressure Preview"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(P("Критический"))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .foregroundStyle(.red)
            }

            Text(P("До ближайшего дедлайна: 18ч"))
                .font(.subheadline.weight(.semibold))

            Text(P("Через 18 часов — критическая зона.\nБез Pro перегруз останется скрытым."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.82)
                }
            }
            .frame(height: 9)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.red.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    private var ctaText: String {
        switch selectedPlan {
        case .monthly:
            return P("Включить режим давления · 7 days free, then $2.99/month")
        case .yearly:
            return P("Включить режим давления · 7 days free, then $19.99/year")
        }
    }

    private func planCard(
        title: String,
        priceText: String,
        subtitle: String,
        accentColor: Color,
        isSelected: Bool,
        isBestChoice: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBestChoice {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .scaleEffect(firePulse ? 1.08 : 0.94)
                        .opacity(firePulse ? 1 : 0.82)
                    Text(P("Лучший выбор"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.55), lineWidth: 1)
                )
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isBestChoice ? accentColor : .secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(priceText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isBestChoice ? accentColor.opacity(0.12) : Color.secondary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.9) : accentColor.opacity(isBestChoice ? 0.45 : 0.22), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? accentColor.opacity(0.26) : .clear, radius: 10, x: 0, y: 6)
    }
}

struct SubscriptionStatusView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager

    private var nextBillingText: String? {
        guard let date = subscriptionManager.nextRenewalDate else { return nil }
        let value = date.formatted(.dateTime.day().month(.abbreviated).year())
        return String(format: P("Активна до: %@"), value)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: subscriptionManager.isPressureProUnlocked
                                        ? [Color.indigo.opacity(0.2), Color.blue.opacity(0.08)]
                                        : [Color.orange.opacity(0.22), Color.orange.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(
                                color: subscriptionManager.isPressureProUnlocked
                                    ? Color.indigo.opacity(0.35)
                                    : Color.orange.opacity(0.22),
                                radius: 12,
                                x: 0,
                                y: 4
                            )

                        Image(systemName: subscriptionManager.isPressureProUnlocked ? "checkmark.seal.fill" : "lock.fill")
                            .foregroundStyle(subscriptionManager.isPressureProUnlocked ? .indigo : .orange)
                            .font(.title2.weight(.bold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(P("Pressure Pro"))
                            .font(.headline)
                        Text(subscriptionManager.isPressureProUnlocked ? P("Подписка активна") : P("Подписка неактивна"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(.secondarySystemBackground), Color(.systemBackground)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.indigo.opacity(0.1), radius: 10, x: 0, y: 5)

                if let product = subscriptionManager.yearlyProduct ?? subscriptionManager.monthlyProduct {
                    Text(String(format: P("Текущий тариф: %@"), product.displayPrice))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let nextBillingText {
                    Text(nextBillingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(P("Что входит в Pro"))
                        .font(.headline)

                    benefitRow(icon: "bell.badge.fill", text: P("Умные push-напоминания перед дедлайном"))
                    benefitRow(icon: "bolt.fill", text: P("Режим давления и приоритизация задач"))
                    benefitRow(icon: "chart.bar.doc.horizontal.fill", text: P("Еженедельные советы по нагрузке"))
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.indigo.opacity(0.16), lineWidth: 1)
                )

                Button {
                    Task { await subscriptionManager.restorePurchases() }
                } label: {
                    HStack {
                        if subscriptionManager.isLoading {
                            ProgressView()
                        }
                        Image(systemName: "arrow.clockwise")
                        Text(P("Восстановить покупки"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
                .disabled(subscriptionManager.isLoading)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Text(P("Управлять подпиской в App Store"))
                        .font(.subheadline.weight(.semibold))
                }

                if let error = subscriptionManager.purchaseErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

#if DEBUG
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEBUG")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    let stats = PressureABAnalytics.shared.snapshot
                    Text("A/B: \(stats.variant.rawValue.uppercased()) · Показов CTA: \(stats.ctaImpressions) · Кликов CTA: \(stats.ctaClicks) · Показов Paywall: \(stats.paywallShows)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Debug unlock") {
                            subscriptionManager.setDebugUnlock(true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Debug lock") {
                            subscriptionManager.setDebugUnlock(false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
#endif

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .navigationTitle(P("Подписка"))
            .task {
                await subscriptionManager.refreshEntitlements()
                await subscriptionManager.loadProducts()
            }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.subheadline)
        }
    }
}
