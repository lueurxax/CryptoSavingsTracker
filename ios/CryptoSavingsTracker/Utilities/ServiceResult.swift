import Foundation

// MARK: - Service Result

/// Standard result type for service operations that may degrade gracefully.
///
/// Unlike `Result<T, Error>`, this type captures intermediate states:
/// - `.fresh(T)` — data fetched successfully from the primary source
/// - `.cached(T, age:)` — stale data from cache (network unavailable)
/// - `.fallback(T, reason:)` — hardcoded/default data when both network and cache fail
/// - `.failure(AppError)` — no data available at all
enum ServiceResult<T> {
    case fresh(T)
    case cached(T, age: TimeInterval)
    case fallback(T, reason: ServiceDegradationReason)
    case failure(AppError)

    /// The value if available, regardless of freshness.
    var value: T? {
        switch self {
        case .fresh(let v), .cached(let v, _), .fallback(let v, _): return v
        case .failure: return nil
        }
    }

    /// Whether the data is from the primary source.
    var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }

    /// Whether the result contains any data (fresh, cached, or fallback).
    var hasValue: Bool {
        return value != nil
    }

    /// The degradation reason if the result is not fresh.
    var degradationReason: ServiceDegradationReason? {
        switch self {
        case .fresh: return nil
        case .cached: return .networkUnavailable
        case .fallback(_, let reason): return reason
        case .failure: return nil
        }
    }

    /// Map the value while preserving freshness metadata.
    func map<U>(_ transform: (T) -> U) -> ServiceResult<U> {
        switch self {
        case .fresh(let v): return .fresh(transform(v))
        case .cached(let v, let age): return .cached(transform(v), age: age)
        case .fallback(let v, let reason): return .fallback(transform(v), reason: reason)
        case .failure(let error): return .failure(error)
        }
    }
}

// MARK: - Degradation Reason

/// Why a service returned degraded (non-fresh) data.
enum ServiceDegradationReason: String, Sendable {
    case networkUnavailable
    case apiRateLimited
    case apiKeyInvalid
    case serviceUnavailable
    case timeout
}

// MARK: - View State

/// Unified state for any async view that loads data.
enum ViewState: Equatable {
    case idle
    case loading
    case loaded
    case error(UserFacingError)
    case degraded(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var errorValue: UserFacingError? {
        if case .error(let e) = self { return e }
        return nil
    }
}

// MARK: - User-Facing Error

/// A user-friendly error description with recovery guidance.
struct UserFacingError: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let recoverySuggestion: String?
    let isRetryable: Bool
    let category: ErrorCategory

    init(
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        isRetryable: Bool = false,
        category: ErrorCategory = .unknown
    ) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.isRetryable = isRetryable
        self.category = category
    }

    enum ErrorCategory: String, Sendable {
        case network
        case apiKey
        case dataCorruption
        case unknown
    }
}

// MARK: - Error Translator

/// Translates `AppError` into user-friendly `UserFacingError`.
struct ErrorTranslator {
    static func translate(_ error: AppError) -> UserFacingError {
        switch error {
        case .networkUnavailable:
            return UserFacingError(
                title: "No Connection",
                message: "Unable to reach the server. Your existing data is still available.",
                recoverySuggestion: "Check your internet connection and try again.",
                isRetryable: true,
                category: .network
            )
        case .requestTimeout:
            return UserFacingError(
                title: "Request Timed Out",
                message: "The server took too long to respond.",
                recoverySuggestion: "Try again in a moment.",
                isRetryable: true,
                category: .network
            )
        case .apiKeyInvalid:
            return UserFacingError(
                title: "API Key Issue",
                message: "The price data service rejected the API key.",
                recoverySuggestion: "Go to Settings to update your API key.",
                isRetryable: false,
                category: .apiKey
            )
        case .apiQuotaExceeded:
            return UserFacingError(
                title: "Rate Limit Reached",
                message: "Too many requests to the price service. Data may be temporarily stale.",
                recoverySuggestion: "Wait a few minutes and try again.",
                isRetryable: true,
                category: .network
            )
        case .rateLimited:
            return UserFacingError(
                title: "Rate Limited",
                message: "Too many requests. Please wait before retrying.",
                recoverySuggestion: "Wait a minute and try again.",
                isRetryable: true,
                category: .network
            )
        case .currencyConversionFailed:
            return UserFacingError(
                title: "Conversion Error",
                message: "Unable to convert between currencies. Values may be approximate.",
                recoverySuggestion: "Check your internet connection for up-to-date rates.",
                isRetryable: true,
                category: .network
            )
        case .saveFailed:
            return UserFacingError(
                title: "Save Failed",
                message: "Unable to save your changes.",
                recoverySuggestion: "Try again. If the problem persists, restart the app.",
                isRetryable: true,
                category: .dataCorruption
            )
        case .calculationFailed:
            return UserFacingError(
                title: "Calculation Error",
                message: "Unable to calculate goal progress.",
                recoverySuggestion: "Pull to refresh or restart the app.",
                isRetryable: true,
                category: .unknown
            )
        case .modelContextUnavailable:
            return UserFacingError(
                title: "Data Unavailable",
                message: "Unable to access your data.",
                recoverySuggestion: "Restart the app.",
                isRetryable: false,
                category: .dataCorruption
            )
        default:
            return UserFacingError(
                title: "Something Went Wrong",
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion,
                isRetryable: error.isRetriable,
                category: .unknown
            )
        }
    }

    /// Translate any Error into a UserFacingError.
    static func translate(_ error: Error) -> UserFacingError {
        if let appError = error as? AppError {
            return translate(appError)
        }
        return UserFacingError(
            title: "Something Went Wrong",
            message: error.localizedDescription,
            recoverySuggestion: "Try again later.",
            isRetryable: true,
            category: .unknown
        )
    }
}
