import Foundation

enum PressureABVariant: String {
    case a
    case b
}

final class PressureABAnalytics {
    static let shared = PressureABAnalytics()

    private let defaults = UserDefaults.standard
    private let variantKey = "pressure_ab_variant"
    private let ctaImpressionAKey = "pressure_cta_impression_a"
    private let ctaImpressionBKey = "pressure_cta_impression_b"
    private let ctaClickAKey = "pressure_cta_click_a"
    private let ctaClickBKey = "pressure_cta_click_b"
    private let paywallShownKey = "pressure_paywall_shown"

    private init() {}

    var variant: PressureABVariant {
        if let raw = defaults.string(forKey: variantKey), let assigned = PressureABVariant(rawValue: raw) {
            return assigned
        }
        let assigned: PressureABVariant = Bool.random() ? .a : .b
        defaults.set(assigned.rawValue, forKey: variantKey)
        return assigned
    }

    var snapshot: (variant: PressureABVariant, ctaImpressions: Int, ctaClicks: Int, paywallShows: Int) {
        let selected = variant
        let impressions = defaults.integer(forKey: selected == .a ? ctaImpressionAKey : ctaImpressionBKey)
        let clicks = defaults.integer(forKey: selected == .a ? ctaClickAKey : ctaClickBKey)
        let paywallShows = defaults.integer(forKey: paywallShownKey)
        return (selected, impressions, clicks, paywallShows)
    }

    func trackCtaImpression() {
        switch variant {
        case .a:
            defaults.set(defaults.integer(forKey: ctaImpressionAKey) + 1, forKey: ctaImpressionAKey)
        case .b:
            defaults.set(defaults.integer(forKey: ctaImpressionBKey) + 1, forKey: ctaImpressionBKey)
        }
    }

    func trackCtaClick() {
        switch variant {
        case .a:
            defaults.set(defaults.integer(forKey: ctaClickAKey) + 1, forKey: ctaClickAKey)
        case .b:
            defaults.set(defaults.integer(forKey: ctaClickBKey) + 1, forKey: ctaClickBKey)
        }
    }

    func trackPaywallShown() {
        defaults.set(defaults.integer(forKey: paywallShownKey) + 1, forKey: paywallShownKey)
    }
}
