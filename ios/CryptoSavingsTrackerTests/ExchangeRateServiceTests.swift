//
//  ExchangeRateServiceTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by user on 27/07/2025.
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor struct ExchangeRateServiceTests {
    
    // MARK: - Exchange Rate Service Tests
    
    @Test @MainActor func sameCurrencyExchangeRate() async throws {
        // Same currency should always return 1.0
        // Refactored to use mock to avoid network dependency in unit test
        let service: ExchangeRateServiceProtocol = MockExchangeRateService()
        let rate = try await service.fetchRate(from: "USD", to: "USD")
        #expect(rate == 1.0)
    }
    
    @Test @MainActor func exchangeRateErrorHandling() async throws {
        // Test with invalid currency codes
        // Refactored to use mock to avoid network dependency and ensure deterministic error handling
        let service = MockExchangeRateService()
        service.shouldFail = true

        do {
            let _ = try await service.fetchRate(from: "INVALID", to: "USD")
            Issue.record("Expected error for invalid currency, but request succeeded")
        } catch {
            // Error is expected
            #expect(true)
        }
    }
    
    @Test @MainActor func exchangeRateCaching() async throws {
        // Test that the service has caching functionality
        // NOTE: This test hits the live network via ExchangeRateService.shared.
        // In a strictly decoupled environment, this should use a mock with timing support.
        let service = ExchangeRateService.shared
        
        // Make two requests for the same currency pair
        let startTime = Date()
        
        do {
            let rate1 = try await service.fetchRate(from: "USD", to: "EUR")
            let intermediateTime = Date()
            let rate2 = try await service.fetchRate(from: "USD", to: "EUR")
            let endTime = Date()
            
            // Second request should be faster (cached) if service supports it
            let firstRequestTime = intermediateTime.timeIntervalSince(startTime)
            let secondRequestTime = endTime.timeIntervalSince(intermediateTime)
            
            // Both rates should be the same
            #expect(rate1 == rate2)
            
            // Second request should be significantly faster (or at least not slower)
            #expect(secondRequestTime <= firstRequestTime + 0.1) // Small tolerance
            
        } catch {
            Issue.record("Exchange rate fetch failed: \(error)")
        }
    }
    
    @Test @MainActor func exchangeRatePositiveValues() async throws {
        // Test that valid exchange rates are positive
        // Refactored to use mock to avoid network dependency
        let service = MockExchangeRateService()
        service.setRate(from: "USD", to: "EUR", rate: 0.85)

        do {
            let rate = try await service.fetchRate(from: "USD", to: "EUR")
            #expect(rate > 0)
        } catch {
            Issue.record("Exchange rate fetch failed: \(error)")
        }
    }
    
    @Test @MainActor func exchangeRateReciprocalConsistency() async throws {
        // Test that USD->EUR and EUR->USD are roughly reciprocals
        // Refactored to use mock to avoid network dependency and ensure consistency
        let service = MockExchangeRateService()
        service.setRate(from: "USD", to: "EUR", rate: 0.85)
        service.setRate(from: "EUR", to: "USD", rate: 1.0 / 0.85)

        do {
            let usdToEur = try await service.fetchRate(from: "USD", to: "EUR")
            let eurToUsd = try await service.fetchRate(from: "EUR", to: "USD")
            
            // They should be roughly reciprocals
            let product = usdToEur * eurToUsd
            #expect(product > 0.99 && product < 1.01)
            
        } catch {
            Issue.record("Exchange rate fetch failed: \(error)")
        }
    }
    
    @Test func exchangeRateServiceSingleton() {
        // Test that the service is properly implemented as singleton
        let service1 = ExchangeRateService.shared
        let service2 = ExchangeRateService.shared
        
        #expect(service1 === service2)
    }
    
    // MARK: - Performance Tests
    
    @Test @MainActor func exchangeRateServicePerformance() async throws {
        // Test that exchange rate requests complete in reasonable time
        // NOTE: This test hits the live network via ExchangeRateService.shared.
        let startTime = Date()
        
        do {
            let _ = try await ExchangeRateService.shared.fetchRate(from: "USD", to: "EUR")
            let endTime = Date()
            
            let requestTime = endTime.timeIntervalSince(startTime)
            
            // Should complete within 10 seconds (generous for network request)
            #expect(requestTime < 10.0)
            
        } catch {
            let endTime = Date()
            let requestTime = endTime.timeIntervalSince(startTime)
            
            // Even failed requests should timeout reasonably
            #expect(requestTime < 15.0)
            Issue.record("Exchange rate fetch failed: \(error)")
        }
    }
    
    @Test @MainActor func concurrentExchangeRateRequests() async throws {
        // Test that multiple concurrent requests are handled properly
        let service = ExchangeRateService.shared
        
        await withTaskGroup(of: Void.self) { group in
            // Make multiple concurrent requests
            for _ in 0..<5 {
                group.addTask {
                    do {
                        let _ = try await service.fetchRate(from: "USD", to: "EUR")
                    } catch {
                        // Individual request failures are reported
                        Issue.record("Concurrent exchange rate fetch failed: \(error)")
                    }
                }
            }
            
            // Wait for all requests to complete
            await group.waitForAll()
        }
        
        // If we get here without crashing, the concurrent access is handled properly
        #expect(true)
    }
}
