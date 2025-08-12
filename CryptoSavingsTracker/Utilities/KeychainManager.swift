//
//  KeychainManager.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation
import Security

/// Secure storage for sensitive data using iOS/macOS Keychain
final class KeychainManager {
    
    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unexpectedData:
                return "Unexpected data format in keychain"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    private static let serviceName = "com.cryptosavingstracker.api"
    
    // MARK: - Store API Key
    static func storeAPIKey(_ key: String, for service: String) throws {
        let account = "\(serviceName).\(service)"
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: serviceName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Try to add the item
        var status = SecItemAdd(query as CFDictionary, nil)
        
        // If it already exists, update it
        if status == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: serviceName
            ]
            
            status = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        
        AppLog.info("API key stored securely in keychain for service: \(service)", category: .api)
    }
    
    // MARK: - Retrieve API Key
    static func retrieveAPIKey(for service: String) throws -> String {
        let account = "\(serviceName).\(service)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = dataTypeRef as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        
        return key
    }
    
    // MARK: - Delete API Key
    static func deleteAPIKey(for service: String) throws {
        let account = "\(serviceName).\(service)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
        
        AppLog.info("API key deleted from keychain for service: \(service)", category: .api)
    }
    
    // MARK: - Check if API Key Exists
    static func hasAPIKey(for service: String) -> Bool {
        do {
            _ = try retrieveAPIKey(for: service)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Migration Helper
    static func migrateFromPlist() {
        // Migrate existing API keys from Config.plist to Keychain
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            AppLog.warning("Config.plist not found for migration", category: .api)
            return
        }
        
        // Migrate CoinGecko API key
        if let coinGeckoKey = plist["CoinGeckoAPIKey"] as? String,
           !coinGeckoKey.isEmpty,
           coinGeckoKey != "YOUR_COINGECKO_API_KEY" {
            do {
                try storeAPIKey(coinGeckoKey, for: "coingecko")
                AppLog.info("Migrated CoinGecko API key to Keychain", category: .api)
            } catch {
                AppLog.error("Failed to migrate CoinGecko API key: \(error)", category: .api)
            }
        }
        
        // Migrate Tatum API key
        if let tatumKey = plist["TatumAPIKey"] as? String,
           !tatumKey.isEmpty,
           tatumKey != "YOUR_TATUM_API_KEY" {
            do {
                try storeAPIKey(tatumKey, for: "tatum")
                AppLog.info("Migrated Tatum API key to Keychain", category: .api)
            } catch {
                AppLog.error("Failed to migrate Tatum API key: \(error)", category: .api)
            }
        }
    }
}

// MARK: - Convenience Extensions
extension KeychainManager {
    static var coinGeckoAPIKey: String? {
        try? retrieveAPIKey(for: "coingecko")
    }
    
    static var tatumAPIKey: String? {
        try? retrieveAPIKey(for: "tatum")
    }
}