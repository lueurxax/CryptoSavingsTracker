//
//  BalanceService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import os

// MARK: - Balance Service
final class BalanceService {
    static let shared = BalanceService()
    
    private let client = TatumClient.shared
    private let chainService = ChainService.shared
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "BalanceService")
    
    private init() {}
    
    // MARK: - Balance Fetching (Unified Interface)
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool = false) async throws -> Double {
        print("🔍 BalanceService.fetchBalance called:")
        print("   ChainId: \(chainId)")
        print("   Address: \(address)")
        print("   Symbol: \(symbol)")
        print("   Force refresh: \(forceRefresh)")
        
        // Check cache first unless force refresh is requested
        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: symbol)
        
        if !forceRefresh {
            if let cachedBalance = BalanceCacheManager.shared.getCachedBalance(for: cacheKey) {
                print("✅ Using cached balance: \(cachedBalance)")
                return cachedBalance
            }
        } else {
            // Check rate limiting even for force refresh
            if !BalanceCacheManager.shared.canRefreshBalance(for: cacheKey) {
                if let cachedBalance = BalanceCacheManager.shared.getCachedBalance(for: cacheKey) {
                    print("⚠️ Rate limited - returning cached balance: \(cachedBalance)")
                    return cachedBalance
                }
            }
        }
        
        guard let chain = chainService.getChain(by: chainId) else {
            print("❌ Unsupported chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
        
        print("   Chain found: \(chain.name) (\(chain.chainType))")
        
        do {
            let balance = try await fetchBalanceForChain(chain: chain, address: address, symbol: symbol)
            
            // Cache the result
            BalanceCacheManager.shared.cacheBalance(balance, for: cacheKey)
            print("💾 Cached balance: \(balance)")
            
            return balance
        } catch {
            print("❌ Error in fetchBalance: \(error)")
            throw error
        }
    }
    
    private func fetchBalanceForChain(chain: TatumChain, address: String, symbol: String) async throws -> Double {
        switch chain.chainType {
        case .evm:
            if chainService.supportsV4API(chain.id) {
                return try await fetchV4Balance(chainId: chain.id, address: address, symbol: symbol)
            } else {
                return try await fetchLegacyBalance(chainId: chain.id, address: address, symbol: symbol)
            }
        case .utxo:
            return try await fetchUTXOBalance(chainId: chain.id, address: address)
        case .other:
            return try await fetchOtherBalance(chainId: chain.id, address: address, symbol: symbol)
        }
    }
    
    // MARK: - Tatum v4 Balance Fetching
    private func fetchV4Balance(chainId: String, address: String, symbol: String) async throws -> Double {
        let chain = chainService.getChain(by: chainId)
        let isNativeToken = symbol.uppercased() == chain?.nativeCurrencySymbol.uppercased()
        
        print("🔗 fetchV4Balance:")
        print("   Native currency: \(chain?.nativeCurrencySymbol ?? "unknown")")
        print("   Is native token: \(isNativeToken)")
        
        guard let v4Chain = chainService.getV4ChainName(for: chainId) else {
            print("❌ Unsupported chain for v4 API: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
        
        print("   V4 chain: \(v4Chain)")
        
        if isNativeToken {
            return try await fetchV4NativeBalance(v4Chain: v4Chain, address: address)
        } else {
            return try await fetchV4TokenBalance(v4Chain: v4Chain, address: address, symbol: symbol)
        }
    }
    
    private func fetchV4NativeBalance(v4Chain: String, address: String) async throws -> Double {
        let queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "tokenTypes", value: "native")
        ]
        
        guard let request = client.createV4Request(path: "/data/wallet/portfolio", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        print("🌐 Fetching v4 native balance from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 V4 native balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let portfolioResponse = try decoder.decode(TatumV4PortfolioResponse.self, from: data)
        
        print("🔍 Found \(portfolioResponse.result.count) balance items")
        
        // Find native balance
        if let nativeBalance = portfolioResponse.result.first(where: { $0.type == "native" }) {
            let balance = Double(nativeBalance.balance) ?? 0.0
            print("✅ Native balance found: \(balance)")
            return balance
        } else {
            print("⚠️ No native balance found")
            return 0.0
        }
    }
    
    private func fetchV4TokenBalance(v4Chain: String, address: String, symbol: String) async throws -> Double {
        let queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "tokenTypes", value: "fungible")
        ]
        
        guard let request = client.createV4Request(path: "/data/wallet/portfolio", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        print("🪙 Fetching v4 token balance from: \(request.url?.absoluteString ?? "")")
        print("   Looking for symbol: \(symbol)")
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 V4 token balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let portfolioResponse = try decoder.decode(TatumV4PortfolioResponse.self, from: data)
        
        print("🔍 Found \(portfolioResponse.result.count) token balances")
        
        // Find matching token by symbol
        let matchingToken = portfolioResponse.result.first { balance in
            balance.tokenSymbol?.uppercased() == symbol.uppercased() && balance.type == "fungible"
        }
        
        if let token = matchingToken {
            let balance = Double(token.balance) ?? 0.0
            print("✅ Found matching token: \(token.tokenSymbol ?? "unknown"), Balance: \(balance)")
            return balance
        } else {
            print("⚠️ No matching token found for symbol: \(symbol)")
            return 0.0
        }
    }
    
    // MARK: - Legacy Balance Fetching
    private func fetchLegacyBalance(chainId: String, address: String, symbol: String) async throws -> Double {
        // Fallback to legacy API for chains not supported by v4
        print("⚠️ Using legacy API for chain: \(chainId)")
        return 0.0 // Implement if needed
    }
    
    // MARK: - UTXO Balance Fetching
    private func fetchUTXOBalance(chainId: String, address: String) async throws -> Double {
        let path: String
        
        switch chainId {
        case "BTC":
            path = "/bitcoin/address/balance/\(address)"
        case "LTC":
            path = "/litecoin/address/balance/\(address)"
        case "BCH":
            path = "/bcash/address/balance/\(address)"
        case "DOGE":
            path = "/dogecoin/address/balance/\(address)"
        default:
            print("❌ Unsupported UTXO chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
        
        guard let request = client.createLegacyRequest(path: path) else {
            throw TatumError.invalidURL
        }
        
        print("₿ Fetching UTXO balance from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 UTXO balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let balanceResponse = try decoder.decode(TatumUTXOBalance.self, from: data)
        
        // Use confirmed balance (incoming - outgoing, excluding pending)
        let balance = balanceResponse.confirmedBalance
        print("✅ UTXO balance decoded:")
        print("   Incoming: \(balanceResponse.incoming)")
        print("   Outgoing: \(balanceResponse.outgoing)")
        print("   Confirmed balance: \(balance)")
        
        return balance
    }
    
    // MARK: - Other Chain Balance Fetching
    private func fetchOtherBalance(chainId: String, address: String, symbol: String) async throws -> Double {
        switch chainId.uppercased() {
        case "XRP":
            return try await fetchXRPBalance(address: address)
        case "TRX":
            return try await fetchTRXBalance(address: address, symbol: symbol)
        case "ADA":
            return try await fetchADABalance(address: address)
        default:
            print("❌ Unsupported other chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
    }
    
    // MARK: - XRP Balance Fetching (v3 API)
    private func fetchXRPBalance(address: String) async throws -> Double {
        print("💎 Fetching XRP balance using v3 API for address: \(address)")
        
        guard let request = client.createV3Request(path: "/xrp/account/tx/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 XRP balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let xrpResponse = try decoder.decode(XRPAccountResponse.self, from: data)
        
        // Get the most recent balance from the latest transaction
        let balance = extractXRPBalance(from: xrpResponse, targetAddress: address)
        
        print("✅ XRP balance extracted: \(balance)")
        return balance
    }
    
    private func extractXRPBalance(from response: XRPAccountResponse, targetAddress: String) -> Double {
        guard let firstTransaction = response.transactions.first else {
            print("⚠️ No transactions found, returning 0 balance")
            return 0.0
        }
        
        // Look for the target address in the transaction metadata
        for affectedNode in firstTransaction.meta.affectedNodes {
            if let modifiedNode = affectedNode.modifiedNode,
               modifiedNode.finalFields.account == targetAddress {
                let balanceString = modifiedNode.finalFields.balance
                let balanceDrops = Double(balanceString) ?? 0
                let balanceXRP = balanceDrops / 1_000_000 // Convert drops to XRP
                print("💎 Found XRP balance in modified node: \(balanceXRP) XRP")
                return balanceXRP
            }
            
            if let createdNode = affectedNode.createdNode,
               createdNode.newFields.account == targetAddress {
                let balanceString = createdNode.newFields.balance
                let balanceDrops = Double(balanceString) ?? 0
                let balanceXRP = balanceDrops / 1_000_000 // Convert drops to XRP
                print("💎 Found XRP balance in created node: \(balanceXRP) XRP")
                return balanceXRP
            }
        }
        
        print("⚠️ Could not find balance for address \(targetAddress) in transaction metadata")
        return 0.0
    }
    
    // MARK: - TRX Balance Fetching (v3 API)
    private func fetchTRXBalance(address: String, symbol: String) async throws -> Double {
        print("🚀 Fetching TRX balance using v3 API:")
        print("   Address: \(address)")
        print("   Symbol: \(symbol)")
        
        guard let request = client.createV3Request(path: "/tron/account/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 TRX balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let trxResponse = try decoder.decode(TRXAccountResponse.self, from: data)
        
        let balance: Double
        if symbol.uppercased() == "TRX" {
            // Native TRX balance
            balance = trxResponse.balanceTRX
            print("✅ Native TRX balance extracted: \(balance)")
        } else {
            // TRC20 token balance
            balance = trxResponse.getTokenBalance(symbol: symbol)
            print("✅ TRC20 \(symbol) balance extracted: \(balance)")
        }
        
        return balance
    }
    
    // MARK: - ADA Balance Fetching (v3 API)
    private func fetchADABalance(address: String) async throws -> Double {
        print("🔷 Fetching ADA balance using v3 API:")
        print("   Address: \(address)")
        
        guard let request = client.createV3Request(path: "/ada/account/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 ADA balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let adaBalanceArray = try decoder.decode([TatumADABalanceResponse].self, from: data)
        
        // Find ADA balance (should be first and only item for native ADA)
        if let adaBalance = adaBalanceArray.first(where: { $0.currency.symbol.uppercased() == "ADA" }) {
            let balance = adaBalance.humanReadableBalance
            print("✅ Native ADA balance extracted: \(balance)")
            print("   Raw balance (lovelace): \(adaBalance.value)")
            return balance
        } else {
            print("⚠️ No ADA balance found in response")
            return 0.0
        }
    }
}