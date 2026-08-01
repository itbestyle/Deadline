import SwiftUI

#if os(watchOS)
@main
struct DeadlineWatchApp: App {
    @StateObject private var store = WatchDeadlineStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
        }
    }
}
#endif
