import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if os(watchOS)
@MainActor
final class WatchDeadlineStore: NSObject, ObservableObject {
    @Published private(set) var deadlines: [WatchDeadlineModel] = []
    @Published private(set) var lastUpdatedAt: Date?

    override init() {
        super.init()
        activateSessionIfNeeded()
    }

    var activeDeadlines: [WatchDeadlineModel] {
        deadlines.filter { $0.status == "в процессе" }
    }

    var criticalDeadlines: [WatchDeadlineModel] {
        activeDeadlines.filter { $0.pressureLevel == .critical }
    }

    var mediumDeadlines: [WatchDeadlineModel] {
        activeDeadlines.filter { $0.pressureLevel == .medium }
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func apply(context: [String: Any]) {
        guard let data = context["deadlines"] as? Data else { return }

        if let timestamp = context["updatedAt"] as? TimeInterval {
            lastUpdatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastUpdatedAt = Date()
        }

        do {
            let decoded = try JSONDecoder().decode([WatchDeadlineModel].self, from: data)
            deadlines = decoded.sorted {
                parseDate($0.dueDate) < parseDate($1.dueDate)
            }
        } catch {
            return
        }
    }

    private func parseDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        if let isoDate = ISO8601DateFormatter().date(from: value) {
            return isoDate
        }

        return .distantFuture
    }
}

extension WatchDeadlineStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor [weak self] in
            self?.apply(context: applicationContext)
        }
    }
}
#endif
