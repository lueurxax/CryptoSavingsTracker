//
//  Logger.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import Foundation
import os.log

/// Logging system with category-based filtering for better debugging
struct AppLogger {
    
    /// Logging categories for filtering and organization
    enum Category: String, CaseIterable {
        case goalList = "GoalList"
        case goalEdit = "GoalEdit"
        case transactionHistory = "TransactionHistory"
        case exchangeRate = "ExchangeRate"
        case balanceService = "BalanceService"
        case chainService = "ChainService"
        case notification = "Notification"
        case dataCompatibility = "DataCompatibility"
        case swiftData = "SwiftData"
        case ui = "UI"
        case api = "API"
        case cache = "Cache"
        case validation = "Validation"
        case performance = "Performance"
        case monthlyPlanning = "MonthlyPlanning"
        case accessibility = "Accessibility"
        
        var logger: OSLog {
            return OSLog(subsystem: "com.cryptosavingstracker.app", category: self.rawValue)
        }
    }
    
    /// Log levels
    enum Level {
        case debug
        case info
        case warning
        case error
        case fault
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .fault: return .fault
            }
        }
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .fault: return "💥"
            }
        }
    }
    
    /// Main logging function
    static func log(_ level: Level, category: Category, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.emoji) [\(category.rawValue)] \(message) (\(fileName):\(function):\(line))"
        
        #if DEBUG
        os_log("%@", log: category.logger, type: level.osLogType, logMessage)
        #endif
    }
    
    /// Convenience methods for different log levels
    static func debug(_ message: String, category: Category, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, category: category, message, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, category: Category, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, category: category, message, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, category: Category, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, category: category, message, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, category: Category, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, category: category, message, file: file, function: function, line: line)
    }
    
    static func fault(_ message: String, category: Category, file: String = #file, function: String = #function, line: Int = #line) {
        log(.fault, category: category, message, file: file, function: function, line: line)
    }
}

/// Type alias for convenience - using AppLogger to avoid conflicts with Foundation.Logger
typealias AppLog = AppLogger