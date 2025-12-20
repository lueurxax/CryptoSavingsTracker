
//
//  RateLimiter.swift
//  CryptoSavingsTracker
//
//  Created by Gemini on 12/08/2025.
//

import Foundation

final class RateLimiter {
    private var requestTimestamps: [String: Date] = [:]
    private let lock = NSLock()
    private let timeInterval: TimeInterval

    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }

    func isRateLimited(for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let lastRequestTimestamp = requestTimestamps[key] else {
            return false
        }

        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTimestamp)
        return timeSinceLastRequest < timeInterval
    }

    func recordRequest(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        requestTimestamps[key] = Date()
    }
    
    func execute<T>(key: String, operation: () async throws -> T) async throws -> T {
        // Wait if rate limited
        while isRateLimited(for: key) {
            try await Task.sleep(nanoseconds: 100_000_000) // Sleep for 0.1 seconds
        }
        
        // Record the request
        recordRequest(for: key)
        
        // Execute the operation
        return try await operation()
    }
}
