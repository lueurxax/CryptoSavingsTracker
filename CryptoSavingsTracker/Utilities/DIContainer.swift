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
            
            do {
                let service = try createMonthlyPlanningService()
                _monthlyPlanningService = service
                return service
            } catch {
                AppLog.error("Failed to create MonthlyPlanningService: \(error)", category: .validation)
                // Return a fallback service
                return createFallbackMonthlyPlanningService()
            }
        }
    }
    
    // MARK: - Repository Pattern Implementation
    func makeGoalRepository(modelContext: ModelContext) -> GoalRepository {
        return GoalRepository(modelContext: modelContext)
    }
    
    // MARK: - Service Initialization with Error Recovery
    private func initializeServices() async {
        // Initialize services that can run in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                _ = self.coinGeckoService
            }
            
            group.addTask { @MainActor in
                _ = self.tatumService
            }
            
            group.addTask { @MainActor in
                _ = self.exchangeRateService
            }
            
            group.addTask { @MainActor in
                _ = self.monthlyPlanningService
            }
        }
        
        // Validate all services after initialization
        await validateAllServices()
    }
    
    // MARK: - Service Creation Methods
    private func createCoinGeckoService() throws -> CoinGeckoService {
        if isInitializing("CoinGeckoService") {
            throw DependencyError.circularDependency("CoinGeckoService")
        }
        
        setInitializing("CoinGeckoService")
        defer { setInitialized("CoinGeckoService") }
        
        return CoinGeckoService()
    }
    
    private func createTatumService() throws -> TatumService {
        if isInitializing("TatumService") {
            throw DependencyError.circularDependency("TatumService")
        }
        
        setInitializing("TatumService")
        defer { setInitialized("TatumService") }
        
        return TatumService(client: TatumClient.shared, chainService: ChainService.shared)
    }
    
    private func createExchangeRateService() throws -> ExchangeRateService {
        if isInitializing("ExchangeRateService") {
            throw DependencyError.circularDependency("ExchangeRateService")
        }
        
        setInitializing("ExchangeRateService")
        defer { setInitialized("ExchangeRateService") }
        
        return ExchangeRateService.shared
    }
    
    private func createMonthlyPlanningService() throws -> MonthlyPlanningService {
        if isInitializing("MonthlyPlanningService") {
            throw DependencyError.circularDependency("MonthlyPlanningService")
        }
        
        setInitializing("MonthlyPlanningService")
        defer { setInitialized("MonthlyPlanningService") }
        
        return MonthlyPlanningService(exchangeRateService: exchangeRateService)
    }
    
    
    // MARK: - Mock/Fallback Services
    private func createMockCoinGeckoService() -> CoinGeckoService {
        AppLog.warning("Using mock CoinGeckoService", category: .validation)
        return CoinGeckoService()
    }
    
    private func createMockTatumService() -> TatumService {
        AppLog.warning("Using mock TatumService", category: .validation)
        return TatumService(client: TatumClient.shared, chainService: ChainService.shared)
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
    func performHealthCheck() -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        stateLock.lock()
        defer { stateLock.unlock() }
        
        for (dependency, state) in dependencyStates {
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
    
    // MARK: - Error Recovery
    func resetFailedServices() async {
        stateLock.lock()
        let failedServices = dependencyStates.compactMap { (key, value) -> String? in
            if case .failed = value {
                return key
            }
            return nil
        }
        stateLock.unlock()
        
        for serviceName in failedServices {
            AppLog.info("Attempting to reset failed service: \(serviceName)", category: .validation)
            
            // Reset the specific service based on name
            switch serviceName {
            case "CoinGeckoService":
                _coinGeckoService = nil
            case "TatumService":
                _tatumService = nil
            case "ExchangeRateService":
                _exchangeRateService = nil
            case "MonthlyPlanningService":
                _monthlyPlanningService = nil
            default:
                break
            }
            
            resetServiceState(serviceName)
        }
        
        // Reinitialize services
        await initializeServices()
    }

    private func resetServiceState(_ serviceName: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        dependencyStates[serviceName] = .notInitialized
    }
}