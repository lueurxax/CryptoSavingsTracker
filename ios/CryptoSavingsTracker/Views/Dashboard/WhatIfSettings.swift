import Foundation
import Combine

final class WhatIfSettings: ObservableObject {
    @Published var enabled: Bool = false
    @Published var monthly: Double = 0
    @Published var oneTime: Double = 0
}

