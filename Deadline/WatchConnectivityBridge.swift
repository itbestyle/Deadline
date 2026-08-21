import Foundation
import os

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()
    static let isEnabled = true

    private static let log = Logger(subsystem: "com.sergey.timepressure", category: "WatchSync")

    private var pendingDeadlinesData: Data?

    private override init() {
        super.init()
    }

    func activateIfNeeded() {
        guard Self.isEnabled else { return }
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            Self.trace("WCSession is not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    func sync(encodedDeadlinesData: Data) {
        guard Self.isEnabled else { return }
        pendingDeadlinesData = encodedDeadlinesData
        pushPendingContext()
    }

    private func pushPendingContext() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(), let data = pendingDeadlinesData else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            Self.trace("skip push, session state = \(session.activationState.rawValue)")
            return
        }

        Self.trace(
            "push \(data.count) bytes, paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)"
        )

        // Every send is refused until the companion app is on the watch, and
        // queued transfers would just pile up. sessionWatchStateDidChange
        // replays the cached payload once it lands.
        guard session.isWatchAppInstalled else { return }

        let context: [String: Any] = [
            "deadlines": data,
            "updatedAt": Date().timeIntervalSince1970
        ]
        do {
            try session.updateApplicationContext(context)
        } catch {
            Self.trace("updateApplicationContext failed: \(error.localizedDescription), falling back to transferUserInfo")
            session.transferUserInfo(context)
        }
        #endif
    }

    fileprivate static func trace(_ message: String) {
        log.info("\(message, privacy: .public)")
        #if DEBUG
        print("[WatchSync] \(message)")
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Self.trace("activated state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
        pushPendingContext()
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Self.trace("watch state changed, installed=\(session.isWatchAppInstalled)")
        pushPendingContext()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Self.trace("reachability changed, reachable=\(session.isReachable)")
        pushPendingContext()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleWatchAction(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleWatchAction(userInfo)
    }

    private func handleWatchAction(_ payload: [String: Any]) {
        guard
            let actionRaw = payload["action"] as? String,
            let action = WatchActionType(rawValue: actionRaw),
            let id = payload["id"] as? String
        else { return }

        NotificationCenter.default.post(
            name: .watchActionReceived,
            object: nil,
            userInfo: ["action": action.rawValue, "id": id]
        )
    }
}
#endif
