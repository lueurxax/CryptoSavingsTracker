//
//  DIContainer.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Dependency state for tracking initialization
enum DependencyState {
    case notInitialized
    case initializing
    case initialized
    case failed(Error)
}

/// Protocol for dependencies that can validate themselves
protocol ValidatableDependency {
    func validate() async throws
}

/// Dependency resolution error types
enum DependencyError: LocalizedError {
    case circularDependency(String)
    case initializationFailed(String)
    case validationFailed(String)
    case missingRequiredDependency(String)
    
    var errorDescription: String? {
        switch self {
        case .circularDependency(let dependency):
            return "Circular dependency detected: \(dependency)"
        case .initializationFailed(let dependency):
            return "Failed to initialize: \(dependency)"
        case .validationFailed(let dependency):
            return "Validation failed for: \(dependency)"
        case .missingRequiredDependency(let dependency):
            return "Missing required dependency: \(dependency)"
        }
    }
}

@MainActor
class DIContainer: ObservableObject {
    static let shared = DIContainer()
    
    // MARK: - Dependency States
    private var dependencyStates: [String: DependencyState] = [:]
    private let stateLock = NSLock()
    
    // MARK: - Services with Error Recovery
    private var _coinGeckoService: CoinGeckoService?
    var coinGeckoService: CoinGeckoService {
        get {
            if let service = _coinGeckoService {
                return service
            }
            
            do {
                let service = try createCoinGeckoService()
                _coinGeckoService = service
                return service
            } catch {
                AppLog.error("Failed to create CoinGeckoService: \(error)", category: .validation)
                // Return a mock service as fallback
                return createMockCoinGeckoService()
            }
        }
    }
    
    private var _tatumService: TatumService?
    var tatumService: TatumService {
        get {
            if let service = _tatumService {
                return service
            }
            
            do {
                let service = try createTatumService()
                _tatumService = service
                return service
            } catch {
                AppLog.error("Failed to create TatumService: \(error)", category: .validation)
                // Return a mock service as fallback
                return createMockTatumService()
            }
        }
    }
    
    private var _exchangeRateService: ExchangeRateService?
    var exchangeRateService: ExchangeRateService {
        get {
            if let service = _exchangeRateService {
                return service
            }
            
            do {
                let service = try createExchangeRateService()
                _exchangeRateService = service
                return service
            } catch {
                AppLog.error("Failed to create ExchangeRateService: \(error)", category: .validation)
                // Return a basic service with cached data only
                return createFallbackExchangeRateService()
            }
        }
    }
    
    private var _monthlyPlanningService: MonthlyPlanningService?
    var monthlyPlanningService: MonthlyPlanningService {
        get {
            if let service = _monthlyPlanningService {
                return service
            }
            
            // Check for circular dependency
            guard !isInitializing("monthlyPlanningService") else {
                AppLog.error("Circular dependency detected for MonthlyPlanningService", category: .validation)
                return createFallbackMonthlyPlanningService()
            }
            
            setInitializing("monthlyPlanningService")
            
            let service = MonthlyPlanningService(exchangeRateService: exchangeRateService)
            _monthlyPlanningService = service
            
            setInitialized("monthlyPlanningService")
            return service
        }
    }
    
    // MARK: - Initialization
    private init() {
        Task {
            await initializeServices()
        }
    }
    
    // MARK: - Service Initialization with Recovery
    private func initializeServices() async {
        AppLog.info("Initializing DI container services", category: .validation)
        
        // Initialize services in dependency order
        await initializeService("coinGeckoService") { [weak self] in
            self?._coinGeckoService = try self?.createCoinGeckoService()
        }
        
        await initializeService("tatumService") { [weak self] in
            self?._tatumService = try self?.createTatumService()
        }
        
        await initializeService("exchangeRateService") { [weak self] in
            self?._exchangeRateService = try self?.createExchangeRateService()
        }
        
        // Validate all services
        await validateAllServices()
    }
    
    private func initializeService(_ name: String, initializer: () throws -> Void) async {
        do {
            setInitializing(name)
            try initializer()
            setInitialized(name)
            AppLog.debug("Successfully initialized \(name)", category: .validation)
        } catch {
            setFailed(name, error: error)
            AppLog.error("Failed to initialize \(name): \(error)", category: .validation)
        }
    }
    
    // MARK: - Service Creation with Validation
    private func createCoinGeckoService() throws -> CoinGeckoService {
        let service = CoinGeckoService()
        
        // Validate API key is configured
        if !service.hasValidConfiguration() {
            throw DependencyError.initializationFailed("CoinGecko API key not configured")
        }
        
        return service
    }
    
    private func createTatumService() throws -> TatumService {
        let service = TatumService()
        
        // Validate API key is configured
        if !service.hasValidConfiguration() {
            throw DependencyError.initializationFailed("Tatum API key not configured")
        }
        
        return service
    }
    
    private func createExchangeRateService() throws -> ExchangeRateService {
        return ExchangeRateService()
    }
    
    // MARK: - Fallback Service Creation
    private func createMockCoinGeckoService() -> CoinGeckoService {
        AppLog.warning("Using mock CoinGeckoService due to initialization failure", category: .validation)
        // Return a service that works with cached data only
        let service = CoinGeckoService()
        service.setOfflineMode(true)
        return service
    }
    
    private func createMockTatumService() -> TatumService {
        AppLog.warning("Using mock TatumService due to initialization failure", category: .validation)
        // Return a service that works with cached data only
        let service = TatumService()
        service.setOfflineMode(true)
        return service
    }
    
    private func createFallbackExchangeRateService() -> ExchangeRateService {
        AppLog.warning("Using fallback ExchangeRateService", category: .validation)
        let service = ExchangeRateService()
        service.setOfflineMode(true)
        return service
    }
    
    private func createFallbackMonthlyPlanningService() -> MonthlyPlanningService {
        AppLog.warning("Using fallback MonthlyPlanningService", category: .validation)
        return MonthlyPlanningService(exchangeRateService: createFallbackExchangeRateService())
    }
    
    // MARK: - Flex Adjustment Service Factory
    func makeFlexAdjustmentService(modelContext: ModelContext) -> FlexAdjustmentService {
        return FlexAdjustmentService(exchangeRateService: exchangeRateService, modelContext: modelContext)
    }
    
    // MARK: - ViewModel Factories with Error Recovery
    func makeGoalViewModel(for goal: Goal) -> GoalViewModel {
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: tatumService,
            exchangeRateService: exchangeRateService
        )
        return viewModel
    }
    
    func makeAssetViewModel(for asset: Asset) -> AssetViewModel {
        return AssetViewModel(
            asset: asset,
            tatumService: tatumService
        )
    }
    
    func makeCurrencyViewModel() -> CurrencyViewModel {
        return CurrencyViewModel(coinGeckoService: coinGeckoService)
    }
    
    // MARK: - Dependency State Management
    private func isInitializing(_ dependency: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        if case .initializing = dependencyStates[dependency] {
            return true
        }
        return false
    }
    
    private func setInitializing(_ dependency: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        dependencyStates[dependency] = .initializing
    }
    
    private func setInitialized(_ dependency: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        dependencyStates[dependency] = .initialized
    }
    
    private func setFailed(_ dependency: String, error: Error) {
        stateLock.lock()
        defer { stateLock.unlock() }
        dependencyStates[dependency] = .failed(error)
    }
    
    // MARK: - Service Validation
    private func validateAllServices() async {
        AppLog.info("Validating all services", category: .validation)
        
        // Validate CoinGecko service
        if let service = _coinGeckoService {
            await validateService(service, name: "CoinGeckoService")
        }
        
        // Validate Tatum service
        if let service = _tatumService {
            await validateService(service, name: "TatumService")
        }
        
        // Validate Exchange Rate service
        if let service = _exchangeRateService {
            await validateService(service, name: "ExchangeRateService")
        }
    }
    
    private func validateService(_ service: Any, name: String) async {
        if let validatable = service as? ValidatableDependency {
            do {
                try await validatable.validate()
                AppLog.debug("\(name) validation passed", category: .validation)
            } catch {
                AppLog.error("\(name) validation failed: \(error)", category: .validation)
            }
        }
    }
    
    // MARK: - Health Check
    func performHealthCheck() async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        stateLock.lock()
        let states = dependencyStates
        stateLock.unlock()
        
        for (dependency, state) in states {
            switch state {
            case .initialized:
                results[dependency] = true
            case .failed:
                results[dependency] = false
            default:
                results[dependency] = false
            }
        }
        
        return results
    }
    
    // MARK: - Reset and Recovery
    func resetFailedServices() async {
        AppLog.info("Attempting to reset failed services", category: .validation)
        
        stateLock.lock()
        let failedServices = dependencyStates.compactMap { key, value -> String? in
            if case .failed = value {
                return key
            }
            return nil
        }
        stateLock.unlock()
        
        for serviceName in failedServices {
            AppLog.info("Resetting \(serviceName)", category: .validation)
            
            switch serviceName {
            case "coinGeckoService":
                _coinGeckoService = nil
            case "tatumService":
                _tatumService = nil
            case "exchangeRateService":
                _exchangeRateService = nil
            case "monthlyPlanningService":
                _monthlyPlanningService = nil
            default:
                break
            }
            
            stateLock.lock()
            dependencyStates[serviceName] = .notInitialized
            stateLock.unlock()
        }
        
        // Reinitialize services
        await initializeServices()
    }
}