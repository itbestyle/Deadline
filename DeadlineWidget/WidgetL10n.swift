import Foundation

/// Loads strings from the host app bundle (widget extension shares the app's Localizable.strings).
enum WidgetL10n {
    private static let hostBundle: Bundle = {
        var url = Bundle.main.bundleURL
        url.deleteLastPathComponent() // PlugIns
        url.deleteLastPathComponent() // .app
        if let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.main
    }()

    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: hostBundle, comment: "")
    }

    static func localizedPriority(_ priority: String) -> String {
        switch priority {
        case "Авто": return string("Авто")
        case "Высокий": return string("Высокий")
        case "Средний": return string("Средний")
        case "Низкий": return string("Низкий")
        default: return priority
        }
    }
}
