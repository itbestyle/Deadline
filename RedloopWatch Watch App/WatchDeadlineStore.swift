import Foundation
import Observation
import WatchConnectivity
import WatchKit
import os

@Observable
final class WatchDeadlineStore: NSObject {
    private(set) var deadlines: [WatchDeadlineModel] = []
    private(set) var lastUpdatedAt: Date?
    private(set) var isReachable = false

    override init() {
        super.init()
        activateSessionIfNeeded()
    }

    var activeDeadlines: [WatchDeadlineModel] {
        deadlines.filter(\.isActive)
    }

    var criticalDeadlines: [WatchDeadlineModel] {
        activeDeadlines.filter { $0.pressureLevel == .critical }
    }

    var mediumDeadlines: [WatchDeadlineModel] {
        activeDeadlines.filter { $0.pressureLevel == .medium }
    }

    var laterDeadlines: [WatchDeadlineModel] {
        activeDeadlines.filter { $0.pressureLevel == .low }
    }

    func complete(_ item: WatchDeadlineModel) {
        WKInterfaceDevice.current().play(.success)
        deadlines.removeAll { $0.id == item.id }
        send(action: "complete", id: item.id)
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func apply(context: [String: Any]) {
        guard let data = context["deadlines"] as? Data else {
            Self.trace("context without deadlines payload, keys=\(context.keys.joined(separator: ","))")
            return
        }

        if let timestamp = context["updatedAt"] as? TimeInterval {
            lastUpdatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastUpdatedAt = Date()
        }

        do {
            let decoded = try JSONDecoder().decode([WatchDeadlineModel].self, from: data)
            deadlines = decoded.sorted {
                ($0.parsedDueDate ?? .distantFuture) < ($1.parsedDueDate ?? .distantFuture)
            }
            Self.trace("applied \(decoded.count) deadlines")
        } catch {
            Self.trace("decode failed: \(error)")
            return
        }
    }

    fileprivate static func trace(_ message: String) {
        Logger(subsystem: "com.sergey.timepressure.watchkitapp", category: "WatchSync")
            .info("\(message, privacy: .public)")
        #if DEBUG
        print("[WatchSync] \(message)")
        #endif
    }

    private func send(action: String, id: String) {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = ["action": action, "id": id]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

}

extension WatchDeadlineStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            Self.trace("activated state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
            self?.isReachable = session.isReachable
            self?.apply(context: session.receivedApplicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            Self.trace("didReceiveApplicationContext")
            self?.apply(context: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor [weak self] in
            Self.trace("didReceiveUserInfo")
            self?.apply(context: userInfo)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
        }
    }
}
