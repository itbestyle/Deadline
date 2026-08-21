# Watch app

The companion watchOS app lives in `RedloopWatch Watch App/` and is embedded in `DeadlinesApp`.

iPhone sends the unfiltered deadline list through `WatchConnectivityBridge` (`WCSession.updateApplicationContext`). Completing a task on the watch comes back as `sendMessage` / `transferUserInfo` (`action` + `id`).

## Run

1. Pair an Apple Watch simulator with an iPhone simulator (Xcode → Window → Devices and Simulators), or use a real paired watch.
2. Run the `DeadlinesApp` scheme on the iPhone — the watch app is built and embedded in `PlugIns/`.
3. On a real watch: enable Developer Mode, then look for Redloop on the watch. If it is missing, open the Watch app on iPhone → My Watch → Available Apps → Install Redloop.
4. Or run the `RedloopWatch Watch App` scheme on the paired watch.

## Check

- High (≤24h) and Mid (≤72h) sections appear on the watch.
- Swipe a row to mark it done — the iPhone list updates.
- Empty state when there are no active tasks, or when the iPhone app has not synced yet.
