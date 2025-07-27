//
//  ContentView.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        GoalsListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
