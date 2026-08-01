import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()
    static let isEnabled = false

    private override init() {
        super.init()
    }

    func activateIfNeeded() {
        guard Self.isEnabled else { return }
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    func sync(encodedDeadlinesData: Data) {
        guard Self.isEnabled else { return }
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }

        let context: [String: Any] = [
            "deadlines": encodedDeadlinesData,
            "updatedAt": Date().timeIntervalSince1970
        ]
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            return
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard
            let actionRaw = message["action"] as? String,
            let action = WatchActionType(rawValue: actionRaw),
            let id = message["id"] as? String
        else { return }

        NotificationCenter.default.post(
            name: .watchActionReceived,
            object: nil,
            userInfo: ["action": action.rawValue, "id": id]
        )
    }
}
#endif
