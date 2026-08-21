import SwiftUI

@main
struct RedloopWatchApp: App {
    @State private var store = WatchDeadlineStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(store)
        }
    }
}
