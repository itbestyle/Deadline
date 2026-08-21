import SwiftUI
import StoreKit
import Combine

private func P(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let pressureMonthlyProductID = "com.company.redloop.premium_monthly"
    static let pressureYearlyProductID = "com.company.redloop.premium_yearly"
    private static let pressureProductIDs: Set<String> = [
        pressureMonthlyProductID,
        pressureYearlyProductID
    ]
#if DEBUG
    private static let debugPressureUnlockKey = "debug_pressure_pro_unlocked"
#endif

    @Published private(set) var isPressureProUnlocked = false
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var nextRenewalDate: Date?
    @Published private(set) var activeProductID: String?
    @Published private(set) var isLoading = false
    @Published var purchaseErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private struct EntitlementSnapshot {
        var isActive: Bool
        var renewalDate: Date?
        var productID: String?
    }

    init() {
        updatesTask = observeTransactionUpdates()

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        purchaseErrorMessage = nil
        do {
            let products = try await Product.products(for: [Self.pressureMonthlyProductID, Self.pressureYearlyProductID])
            monthlyProduct = products.first(where: { $0.id == Self.pressureMonthlyProductID })
            yearlyProduct = products.first(where: { $0.id == Self.pressureYearlyProductID })
            if monthlyProduct == nil && yearlyProduct == nil {
                purchaseErrorMessage = P("Подписка пока недоступна. Проверьте App Store Connect и ID продуктов.")
            }
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
        purchaseErrorMessage = nil

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
        purchaseErrorMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = P("Не удалось восстановить покупки")
        }
    }

    func refreshEntitlements() async {
        var snapshot = await entitlementSnapshotFromTransactions()

        if let productSnapshot = await entitlementSnapshotFromSubscriptionStatus() {
            if productSnapshot.isActive {
                snapshot = mergeSnapshots(snapshot, productSnapshot)
            } else {
                // StoreKit product status is authoritative when it reports no active plan.
                snapshot = productSnapshot
            }
        }

#if DEBUG
        if UserDefaults.standard.bool(forKey: Self.debugPressureUnlockKey) {
            snapshot.isActive = true
        }
#endif

        applyEntitlementSnapshot(snapshot)
    }

#if DEBUG
    func setDebugUnlock(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.debugPressureUnlockKey)
        Task { await refreshEntitlements() }
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

    private func applyEntitlementSnapshot(_ snapshot: EntitlementSnapshot) {
        isPressureProUnlocked = snapshot.isActive
        nextRenewalDate = snapshot.isActive ? snapshot.renewalDate : nil
        activeProductID = snapshot.isActive ? snapshot.productID : nil
    }

    private func entitlementSnapshotFromTransactions() async -> EntitlementSnapshot {
        var snapshot = EntitlementSnapshot(isActive: false, renewalDate: nil, productID: nil)
        var activeExpiration: Date?
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.pressureProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard transaction.productType == .autoRenewable else { continue }
            guard let expirationDate = transaction.expirationDate, expirationDate > now else { continue }

            snapshot.isActive = true

            if let existingRenewal = snapshot.renewalDate {
                snapshot.renewalDate = min(existingRenewal, expirationDate)
            } else {
                snapshot.renewalDate = expirationDate
            }

            let currentBest = activeExpiration ?? .distantPast
            if expirationDate > currentBest {
                activeExpiration = expirationDate
                snapshot.productID = transaction.productID
            }
        }

        return snapshot
    }

    private func entitlementSnapshotFromSubscriptionStatus() async -> EntitlementSnapshot? {
        let products = [monthlyProduct, yearlyProduct].compactMap { $0 }
        guard !products.isEmpty else { return nil }

        var snapshot = EntitlementSnapshot(isActive: false, renewalDate: nil, productID: nil)
        var activeExpiration: Date?
        var checkedAnyStatus = false
        let now = Date()

        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            checkedAnyStatus = true

            for status in statuses {
                guard case .verified = status.renewalInfo else { continue }

                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    let expiration: Date?
                    if case .verified(let transaction) = status.transaction {
                        expiration = transaction.expirationDate
                    } else {
                        expiration = nil
                    }
                    guard let expiration, expiration > now else { continue }

                    snapshot.isActive = true

                    if let existingRenewal = snapshot.renewalDate {
                        snapshot.renewalDate = min(existingRenewal, expiration)
                    } else {
                        snapshot.renewalDate = expiration
                    }

                    let currentBest = activeExpiration ?? .distantPast
                    if expiration > currentBest {
                        activeExpiration = expiration
                        snapshot.productID = product.id
                    }
                default:
                    continue
                }
            }
        }

        return checkedAnyStatus ? snapshot : nil
    }

    private func mergeSnapshots(_ lhs: EntitlementSnapshot, _ rhs: EntitlementSnapshot) -> EntitlementSnapshot {
        guard lhs.isActive || rhs.isActive else {
            return EntitlementSnapshot(isActive: false, renewalDate: nil, productID: nil)
        }

        switch (lhs.renewalDate, rhs.renewalDate) {
        case let (left?, right?) where right > left:
            return EntitlementSnapshot(isActive: true, renewalDate: right, productID: rhs.productID ?? lhs.productID)
        case (nil, let right?):
            return EntitlementSnapshot(isActive: true, renewalDate: right, productID: rhs.productID ?? lhs.productID)
        default:
            return EntitlementSnapshot(isActive: true, renewalDate: lhs.renewalDate, productID: lhs.productID ?? rhs.productID)
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

    private let privacyPolicyURL = URL(string: "https://itbestyle.github.io/privacy-policy/")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(P("Режим давления"))
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
                        featureRow(icon: "bolt.fill", text: P("Не позволяйте задачам застать вас врасплох"))
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
                                    priceText: monthlyPriceText,
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
                                    priceText: yearlyPriceText,
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
                            PressureGradientCTA(
                                title: ctaText,
                                showsSpinner: subscriptionManager.isLoading
                            )
                        }
                        .disabled(subscriptionManager.isLoading)
                    } else {
                        Button {
                            Task { await subscriptionManager.loadProducts() }
                        } label: {
                            PressureGradientCTA(title: P("Включить режим давления"))
                        }
                        .disabled(subscriptionManager.isLoading)
                    }

                    Button(P("Восстановить покупки")) {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(subscriptionManager.isLoading)

                    VStack(alignment: .leading, spacing: 6) {
                        Link(destination: privacyPolicyURL) {
                            Label(P("Политика конфиденциальности"), systemImage: "lock.shield")
                                .font(.caption.weight(.semibold))
                        }

                        Link(destination: termsOfUseURL) {
                            Label(P("Условия использования (EULA)"), systemImage: "doc.text")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.indigo)

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
            .iPadReadableContent(maxWidth: 680)
            .navigationTitle(P("Подписка"))
            .toolbar {
                ToolbarItem {
                    Button(P("Закрыть")) { dismiss() }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .task {
                await subscriptionManager.loadProducts()
                await subscriptionManager.refreshEntitlements()
            }
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

            Text(P("До ближайшей задачи: 18ч"))
                .font(.subheadline.weight(.semibold))

            Text(P("Через 18 часов — критическая зона.\nБез режима давления перегруз останется скрытым."))
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

    private var monthlyPriceText: String {
        if let product = subscriptionManager.monthlyProduct {
            return "\(product.displayPrice) / \(P("month"))"
        }
        return P("$2.99 / month")
    }

    private var yearlyPriceText: String {
        if let product = subscriptionManager.yearlyProduct {
            return "\(product.displayPrice) / \(P("year"))"
        }
        return P("$19.99 / year")
    }

    private var ctaText: String {
        switch selectedPlan {
        case .monthly:
            if let product = subscriptionManager.monthlyProduct {
                return String(format: P("Включить режим давления · 7 days free, then %@/month"), product.displayPrice)
            }
            return P("Включить режим давления · 7 days free, then $2.99/month")
        case .yearly:
            if let product = subscriptionManager.yearlyProduct {
                return String(format: P("Включить режим давления · 7 days free, then %@/year"), product.displayPrice)
            }
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

private struct PressureGradientCTA: View {
    let title: String
    var showsSpinner: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack {
            if showsSpinner {
                ProgressView()
                    .tint(.white)
            }
            Image(systemName: "bolt.fill")
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
        .background {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color.red.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    if !reduceMotion {
                        KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                            GeometryReader { geometry in
                                let width = geometry.size.width
                                let band = max(width * 0.32, 72)
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.12),
                                        .white.opacity(0.28),
                                        .white.opacity(0.12),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: band)
                                .offset(x: -band + (width + band) * progress)
                                .blendMode(.plusLighter)
                            }
                        } keyframes: { _ in
                            LinearKeyframe(1, duration: 3.2)
                            LinearKeyframe(1, duration: 2.2)
                        }
                    }
                }
                .clipShape(shape)
        }
        .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

struct SubscriptionStatusView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    var onSubscribe: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var nextBillingText: String? {
        guard let date = subscriptionManager.nextRenewalDate else { return nil }
        let value = date.formatted(.dateTime.day().month(.abbreviated).year())
        return String(format: P("Активна до: %@"), value)
    }

    private var activeProduct: Product? {
        guard let activeID = subscriptionManager.activeProductID else { return nil }
        if subscriptionManager.monthlyProduct?.id == activeID {
            return subscriptionManager.monthlyProduct
        }
        if subscriptionManager.yearlyProduct?.id == activeID {
            return subscriptionManager.yearlyProduct
        }
        return nil
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
                        Text(P("Режим давления"))
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

                if subscriptionManager.isPressureProUnlocked, let product = activeProduct {
                    Text(String(format: P("Текущий тариф: %@"), product.displayPrice))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if subscriptionManager.isPressureProUnlocked, let nextBillingText {
                    Text(nextBillingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(P("Что входит в режим давления"))
                        .font(.headline)

                    benefitRow(icon: "bell.badge.fill", text: P("Умные push-напоминания перед задачей"))
                    benefitRow(icon: "bolt.fill", text: P("Режим давления и приоритизация задач"))
                    benefitRow(icon: "chart.bar.doc.horizontal.fill", text: P("Еженедельные советы по нагрузке"))
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.indigo.opacity(0.16), lineWidth: 1)
                )

                if !subscriptionManager.isPressureProUnlocked {
                    Button {
                        onSubscribe?()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text(P("Включить режим давления"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }

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
            .iPadReadableContent(maxWidth: 680)
            .navigationTitle(P("Подписка"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label(P("Назад"), systemImage: "chevron.left")
                    }
                }
            }
            .task {
                await subscriptionManager.loadProducts()
                await subscriptionManager.refreshEntitlements()
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
