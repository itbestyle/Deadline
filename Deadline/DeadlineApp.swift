//
//  DeadlineApp.swift
//  Deadline
//
//  Created by Сергей Родоманюк on 30.09.2025.
//

import BackgroundTasks
import SwiftUI
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

@main
struct DeadlineApp: App {
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif

        WatchConnectivityBridge.shared.activateIfNeeded()
        ArchiveCleanupService.register()
        ArchiveCleanupService.schedule()
        WidgetHapticListener.startIfNeeded()
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([DeadlineModel.self])
        
        // Используем новый файл БД с версией схемы
        let storeURL = URL.applicationSupportDirectory.appending(path: "deadlines_v2.store")
        let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                        .iPadAuthContainer()
                }
            }
            .onOpenURL { url in
                #if canImport(FirebaseAuth)
                if Auth.auth().canHandle(url) {
                    return
                }
                #endif
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                ArchiveCleanupService.schedule()
            }
            if phase == .active {
                Task { @MainActor in
                    await AuthService.shared.refreshBackendTokenIfNeeded()
                }
            }
        }
    }
}
