//
//  AsyncSerialExecutor.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Proper async serialization for SwiftData operations
//  Ensures operations execute sequentially without race conditions
//

import Foundation

/// Proper async serialization executor for SwiftData operations
/// Ensures operations execute sequentially without race conditions
@MainActor
final class AsyncSerialExecutor {
    private var queue: [CheckedContinuation<Void, Never>] = []
    private var isExecuting = false

    /// Enqueue and execute an operation serially
    /// Operations are guaranteed to execute in FIFO order with no overlap
    ///
    /// Usage:
    /// ```swift
    /// let executor = AsyncSerialExecutor()
    /// let result = try await executor.enqueue {
    ///     // Your atomic operation here
    ///     return try await performDatabaseOperation()
    /// }
    /// ```
    func enqueue<T>(_ operation: @MainActor @Sendable () async throws -> T) async throws -> T {
        // Wait for our turn in the queue
        await withCheckedContinuation { continuation in
            queue.append(continuation)
            if !isExecuting {
                // We're first in line, start immediately
                isExecuting = true
                continuation.resume()
            }
        }

        // Execute operation
        defer {
            // Signal next in queue
            Task { @MainActor in
                if !queue.isEmpty {
                    queue.removeFirst()
                }
                if !queue.isEmpty {
                    queue.first?.resume()
                } else {
                    isExecuting = false
                }
            }
        }

        return try await operation()
    }
}
