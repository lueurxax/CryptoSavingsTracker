//
//  ErrorHandling.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Application Errors

/// Comprehensive error types for the application
enum AppError: LocalizedError, Equatable {
    // Network errors
    case networkUnavailable
    case invalidURL(String)
    case requestTimeout
    case invalidResponse
    case decodingFailed(String)
    case rateLimited
    
    // API-specific errors
    case apiKeyInvalid
    case apiQuotaExceeded
    case coinNotFound(String)
    case chainNotSupported(String)
    case addressInvalid(String)
    
    // Data errors
    case goalNotFound
    case assetNotFound
    case transactionNotFound
    case saveFailed
    case deleteFailed
    case modelContextUnavailable
    
    // Calculation errors
    case invalidAmount
    case invalidDate
    case calculationFailed
    case currencyConversionFailed
    
    // Platform errors
    case featureUnavailable(String)
    case permissionDenied(String)
    case widgetUpdateFailed
    case notificationsFailed
    
    var errorDescription: String? {
        switch self {
        // Network errors
        case .networkUnavailable:
            return "Network connection unavailable. Please check your internet connection."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .invalidResponse:
            return "Received invalid response from server."
        case .decodingFailed(let details):
            return "Failed to process server response: \(details)"
        case .rateLimited:
            return "Too many requests. Please wait a moment before trying again."
            
        // API-specific errors
        case .apiKeyInvalid:
            return "Invalid API key. Please check your configuration."
        case .apiQuotaExceeded:
            return "API quota exceeded. Please try again later."
        case .coinNotFound(let symbol):
            return "Cryptocurrency '\(symbol)' not found."
        case .chainNotSupported(let chain):
            return "Blockchain '\(chain)' is not supported."
        case .addressInvalid(let address):
            return "Invalid wallet address: \(address)"
            
        // Data errors
        case .goalNotFound:
            return "Goal not found."
        case .assetNotFound:
            return "Asset not found."
        case .transactionNotFound:
            return "Transaction not found."
        case .saveFailed:
            return "Failed to save data. Please try again."
        case .deleteFailed:
            return "Failed to delete item. Please try again."
        case .modelContextUnavailable:
            return "Data storage unavailable."
            
        // Calculation errors
        case .invalidAmount:
            return "Invalid amount entered."
        case .invalidDate:
            return "Invalid date selected."
        case .calculationFailed:
            return "Calculation failed. Please try again."
        case .currencyConversionFailed:
            return "Failed to convert currency."
            
        // Platform errors
        case .featureUnavailable(let feature):
            return "Feature '\(feature)' is not available on this platform."
        case .permissionDenied(let permission):
            return "Permission denied for \(permission)."
        case .widgetUpdateFailed:
            return "Failed to update widget."
        case .notificationsFailed:
            return "Failed to schedule notifications."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .requestTimeout:
            return "The server may be busy. Please try again in a few moments."
        case .rateLimited:
            return "Wait a few minutes before making more requests."
        case .apiKeyInvalid:
            return "Please check your API key configuration in settings."
        case .apiQuotaExceeded:
            return "Wait for your API quota to reset or upgrade your plan."
        case .invalidAmount:
            return "Please enter a valid numeric amount."
        case .invalidDate:
            return "Please select a valid date."
        case .saveFailed, .deleteFailed:
            return "Check available storage space and try again."
        default:
            return "If the problem persists, please contact support."
        }
    }
    
    var isRetriable: Bool {
        switch self {
        case .networkUnavailable, .requestTimeout, .rateLimited, .apiQuotaExceeded, .saveFailed, .deleteFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Result Type

/// Result type for operations that can fail
typealias AppResult<Success> = Result<Success, AppError>

// MARK: - Error Handler

/// Centralized error handling and logging
@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var showingError = false
    
    private init() {}
    
    /// Handle an error with optional retry action
    func handle(_ error: AppError, retryAction: (() async -> Void)? = nil) {
        currentError = error
        showingError = true
        
        // Log error for debugging
        logError(error)
        
        // Show user-friendly error message
        showErrorAlert(error, retryAction: retryAction)
    }
    
    /// Handle errors from Result type
    func handle<T>(_ result: AppResult<T>, retryAction: (() async -> Void)? = nil) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            handle(error, retryAction: retryAction)
            return nil
        }
    }
    
    /// Clear current error
    func clearError() {
        currentError = nil
        showingError = false
    }
    
    private func logError(_ error: AppError) {
        AppLog.error("AppError: \(error.localizedDescription)", category: .validation)
        if let recovery = error.recoverySuggestion {
            AppLog.info("Recovery: \(recovery)", category: .validation)
        }
    }
    
    private func showErrorAlert(_ error: AppError, retryAction: (() async -> Void)?) {
        // Error alert is handled by ErrorAlertModifier
    }
}

// MARK: - Service Extensions for Error Handling

extension Result where Failure == Error {
    /// Convert to AppResult, mapping common errors
    func mapToAppError() -> AppResult<Success> {
        return self.mapError { error in
            // Map common system errors to AppError
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return .networkUnavailable
                case .timedOut:
                    return .requestTimeout
                case .badURL:
                    return .invalidURL(urlError.localizedDescription)
                default:
                    return .invalidResponse
                }
            }
            
            if error is DecodingError {
                return .decodingFailed(error.localizedDescription)
            }
            
            // Default mapping
            return .invalidResponse
        }
    }
}

// MARK: - Async Error Handling

/// Utility for handling async operations with proper error mapping
struct AsyncErrorHandler {
    /// Execute async operation with error handling
    @MainActor
    static func execute<T>(
        operation: () async throws -> T,
        errorHandler: ErrorHandler? = nil
    ) async -> T? {
        let handler: ErrorHandler
        if let errorHandler = errorHandler {
            handler = errorHandler
        } else {
            handler = ErrorHandler.shared
        }
        do {
            return try await operation()
        } catch {
            let appError: AppError
            
            // Map system errors to AppError
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    appError = .networkUnavailable
                case .timedOut:
                    appError = .requestTimeout
                default:
                    appError = .invalidResponse
                }
            } else if error is DecodingError {
                appError = .decodingFailed(error.localizedDescription)
            } else {
                appError = .invalidResponse
            }
            
            handler.handle(appError)
            
            return nil
        }
    }
    
    /// Execute with retry logic
    @MainActor
    static func executeWithRetry<T>(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        operation: () async throws -> T,
        errorHandler: ErrorHandler? = nil
    ) async -> T? {
        let handler: ErrorHandler
        if let errorHandler = errorHandler {
            handler = errorHandler
        } else {
            handler = ErrorHandler.shared
        }
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }
        
        // All attempts failed
        if lastError != nil {
            let appError = AppError.requestTimeout // Simplified mapping
            handler.handle(appError)
        }
        
        return nil
    }
}

// MARK: - View Modifiers for Error Handling

/// View modifier for displaying error alerts
struct ErrorAlertModifier: ViewModifier {
    @StateObject private var errorHandler = ErrorHandler.shared
    
    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorHandler.showingError,
                presenting: errorHandler.currentError
            ) { error in
                Button("OK") {
                    errorHandler.clearError()
                }
                
                if error.isRetriable {
                    Button("Retry") {
                        // Retry action would need to be passed in
                        errorHandler.clearError()
                    }
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                    
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
    }
}

extension View {
    /// Add error handling to any view
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier())
    }
}

// MARK: - Service Error Extensions

/// Extension for CoinGecko service errors
extension AppError {
    static func coinGeckoError(from response: HTTPURLResponse?, data: Data?) -> AppError {
        guard let response = response else {
            return .networkUnavailable
        }
        
        switch response.statusCode {
        case 401:
            return .apiKeyInvalid
        case 429:
            return .rateLimited
        case 404:
            return .coinNotFound("Unknown")
        default:
            return .invalidResponse
        }
    }
}

/// Extension for Tatum service errors
extension AppError {
    static func tatumError(from response: HTTPURLResponse?, data: Data?) -> AppError {
        guard let response = response else {
            return .networkUnavailable
        }
        
        switch response.statusCode {
        case 401:
            return .apiKeyInvalid
        case 400:
            return .addressInvalid("Invalid format")
        case 404:
            return .chainNotSupported("Unknown")
        case 429:
            return .rateLimited
        default:
            return .invalidResponse
        }
    }
}
