//
//  ExecutionProgressCache.swift
//  CryptoSavingsTracker
//
//  Lightweight in-memory cache for execution calculations.
//

import Foundation

@MainActor
final class ExecutionProgressCache {
    private struct Entry {
        let totals: [UUID: Double]
        let calculatedAt: Date
    }

    private var cachedTotalsByRecordId: [UUID: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 2.0) {
        self.ttl = ttl
    }

    func totals(
        for recordId: UUID,
        compute: () async throws -> [UUID: Double]
    ) async throws -> [UUID: Double] {
        if let entry = cachedTotalsByRecordId[recordId],
           Date().timeIntervalSince(entry.calculatedAt) < ttl {
            return entry.totals
        }

        let fresh = try await compute()
        cachedTotalsByRecordId[recordId] = Entry(totals: fresh, calculatedAt: Date())
        return fresh
    }

    func invalidate() {
        cachedTotalsByRecordId.removeAll()
    }

    func invalidate(recordId: UUID) {
        cachedTotalsByRecordId.removeValue(forKey: recordId)
    }
}

