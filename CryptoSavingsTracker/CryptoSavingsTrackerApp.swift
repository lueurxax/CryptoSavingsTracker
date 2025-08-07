//
//  CryptoSavingsTrackerApp.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftUI
import SwiftData

@main
struct CryptoSavingsTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Goal.self, Asset.self, Transaction.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // ModelContainer creation failed - app cannot continue
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        Task {
            _ = await NotificationManager.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            OnboardingContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
