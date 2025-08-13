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
    private let client: TatumClient
    private let chainService: ChainService
    private let rateLimiter: RateLimiter
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "BalanceService")

    init(client: TatumClient, chainService: ChainService) {
        self.client = client
        self.chainService = chainService
        let rateLimitInterval = Self.getConfigValue(forKey: "RateLimitInterval") as? Double ?? 5.0
        self.rateLimiter = RateLimiter(timeInterval: rateLimitInterval)
    }

    private static func getConfigValue(forKey key: String) -> Any? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            return nil
        }
        let nsDictionary = NSDictionary(contentsOfFile: path)
        return nsDictionary?[key]
    }
    
    // MARK: - Balance Fetching (Unified Interface)
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool = false) async throws -> Double {
        Self.log.debug("fetchBalance called - ChainId: \(chainId), Address: \(address), Symbol: \(symbol), ForceRefresh: \(forceRefresh)")
        
        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: symbol)

        if !forceRefresh, let cachedBalance = BalanceCacheManager.shared.getCachedBalance(for: cacheKey) {
            Self.log.debug("Using cached balance: \(cachedBalance)")
            return cachedBalance
        }

        if rateLimiter.isRateLimited(for: cacheKey) {
            if let cachedBalance = BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) {
                Self.log.info("Rate limited - returning fallback cached balance: \(cachedBalance)")
                return cachedBalance
            }
            throw TatumError.rateLimitExceeded
        }

        rateLimiter.recordRequest(for: cacheKey)

        do {
            let balance = try await fetchAndCacheBalance(chainId: chainId, address: address, symbol: symbol, cacheKey: cacheKey)
            return balance
        } catch {
            if let cachedBalance = BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) {
                Self.log.info("Returning cached balance due to error: \(cachedBalance)")
                return cachedBalance
            }
            throw error
        }
    }

    private func fetchAndCacheBalance(chainId: String, address: String, symbol: String, cacheKey: String) async throws -> Double {
        guard let chain = chainService.getChain(by: chainId) else {
            Self.log.error("Unsupported chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }

        Self.log.debug("Chain found: \(chain.name) (\(chain.chainType.rawValue))")

        let balance = try await fetchBalanceForChain(chain: chain, address: address, symbol: symbol)
        
        BalanceCacheManager.shared.cacheBalance(balance, for: cacheKey)
        Self.log.debug("Cached balance: \(balance)")
        
        return balance
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
        
        Self.log.debug("fetchV4Balance - Native currency: \(chain?.nativeCurrencySymbol ?? "unknown"), Is native token: \(isNativeToken)")
        
        guard let v4Chain = chainService.getV4ChainName(for: chainId) else {
            Self.log.error("Unsupported chain for v4 API: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
        
        Self.log.debug("V4 chain: \(v4Chain)")
        
        if isNativeToken {
            return try await fetchV4NativeBalance(v4Chain: v4Chain, address: address)
        } else {
            return try await fetchV4TokenBalance(v4Chain: v4Chain, address: address, symbol: symbol)
        }
    }
    
    private func fetchV4PortfolioData(v4Chain: String, address: String, tokenTypes: [String]) async throws -> TatumV4PortfolioResponse {
        let queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "tokenTypes", value: tokenTypes.joined(separator: ","))
        ]

        guard let request = client.createV4Request(path: "/data/wallet/portfolio", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }

        Self.log.debug("Fetching v4 portfolio data from: \(request.url?.absoluteString ?? "")")

        let (data, _) = try await client.performRequest(request)

        Self.log.debug("V4 portfolio response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")

        return try JSONDecoder().decode(TatumV4PortfolioResponse.self, from: data)
    }

    private func fetchV4NativeBalance(v4Chain: String, address: String) async throws -> Double {
        let portfolioResponse = try await fetchV4PortfolioData(v4Chain: v4Chain, address: address, tokenTypes: ["native"])

        Self.log.debug("Found \(portfolioResponse.result.count) balance items")

        // Find native balance
        if let nativeBalance = portfolioResponse.result.first(where: { $0.type == "native" }) {
            let balance = Double(nativeBalance.balance) ?? 0.0
            Self.log.debug("Native balance found: \(balance)")
            return balance
        } else {
            Self.log.info("No native balance found")
            return 0.0
        }
    }

    private func fetchV4TokenBalance(v4Chain: String, address: String, symbol: String) async throws -> Double {
        let portfolioResponse = try await fetchV4PortfolioData(v4Chain: v4Chain, address: address, tokenTypes: ["fungible"])

        Self.log.debug("Found \(portfolioResponse.result.count) token balances")

        // Find matching token by symbol
        let matchingToken = portfolioResponse.result.first { balance in
            balance.tokenSymbol?.uppercased() == symbol.uppercased() && balance.type == "fungible"
        }

        if let token = matchingToken {
            let balance = Double(token.balance) ?? 0.0
            Self.log.debug("Found matching token: \(token.tokenSymbol ?? "unknown"), Balance: \(balance)")
            return balance
        } else {
            Self.log.info("No matching token found for symbol: \(symbol)")
            return 0.0
        }
    }
    
    // MARK: - Legacy Balance Fetching
    private func fetchLegacyBalance(chainId: String, address: String, symbol: String) async throws -> Double {
        Self.log.info("Using legacy API for chain: \(chainId)")

        let path = "/v3/\(chainId.lowercased())/address/balance/\(address)"

        guard let request = client.createLegacyRequest(path: path) else {
            throw TatumError.invalidURL
        }

        let (data, _) = try await client.performRequest(request)

        let decoder = JSONDecoder()
        let balanceResponse = try decoder.decode(TatumBalanceResponse.self, from: data)

        return Double(balanceResponse.balance) ?? 0.0
    }
    
    private enum ChainID: String {
        case btc = "BTC"
        case ltc = "LTC"
        case bch = "BCH"
        case doge = "DOGE"
        case xrp = "XRP"
        case trx = "TRX"
        case ada = "ADA"
        case sol = "SOL"
    }

    // MARK: - UTXO Balance Fetching
    private func fetchUTXOBalance(chainId: String, address: String) async throws -> Double {
        let path: String
        
        switch chainId {
        case ChainID.btc.rawValue:
            path = "/bitcoin/address/balance/\(address)"
        case ChainID.ltc.rawValue:
            path = "/litecoin/address/balance/\(address)"
        case ChainID.bch.rawValue:
            path = "/bcash/address/balance/\(address)"
        case ChainID.doge.rawValue:
            path = "/dogecoin/address/balance/\(address)"
        default:
            Self.log.error("Unsupported UTXO chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
        
        guard let request = client.createLegacyRequest(path: path) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching UTXO balance from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("UTXO balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let balanceResponse = try decoder.decode(TatumUTXOBalance.self, from: data)
        
        // Use confirmed balance (incoming - outgoing, excluding pending)
        let balance = balanceResponse.confirmedBalance
        Self.log.debug("UTXO balance decoded - Incoming: \(balanceResponse.incoming), Outgoing: \(balanceResponse.outgoing), Confirmed balance: \(balance)")
        
        return balance
    }
    
    // MARK: - Other Chain Balance Fetching
    private func fetchOtherBalance(chainId: String, address: String, symbol: String) async throws -> Double {
        switch chainId.uppercased() {
        case ChainID.xrp.rawValue:
            return try await fetchXRPBalance(address: address)
        case ChainID.trx.rawValue:
            return try await fetchTRXBalance(address: address, symbol: symbol)
        case ChainID.ada.rawValue:
            return try await fetchADABalance(address: address)
        case ChainID.sol.rawValue:
            return try await fetchSOLBalance(address: address)
        default:
            Self.log.error("Unsupported other chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
        }
    }
    
    // MARK: - XRP Balance Fetching (v3 API)
    private func fetchXRPBalance(address: String) async throws -> Double {
        Self.log.debug("Fetching XRP balance using v3 API for address: \(address)")
        
        guard let request = client.createV3Request(path: "/xrp/account/\(address)/balance") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("XRP balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let xrpBalanceResponse = try decoder.decode(TatumXRPBalanceResponse.self, from: data)
        
        let balance = xrpBalanceResponse.balanceInXRP
        Self.log.debug("XRP balance extracted: \(balance) XRP (from \(xrpBalanceResponse.balance) drops)")
        
        return balance
    }
    
    
    // MARK: - TRX Balance Fetching (v3 API)
    private func fetchTRXBalance(address: String, symbol: String) async throws -> Double {
        Self.log.debug("Fetching TRX balance using v3 API - Address: \(address), Symbol: \(symbol)")
        
        guard let request = client.createV3Request(path: "/tron/account/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("TRX balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let trxResponse = try decoder.decode(TRXAccountResponse.self, from: data)
        
        let balance: Double
        if symbol.uppercased() == "TRX" {
            // Native TRX balance
            balance = trxResponse.balanceTRX
            Self.log.debug("Native TRX balance extracted: \(balance)")
        } else {
            // TRC20 token balance
            balance = trxResponse.getTokenBalance(symbol: symbol)
            Self.log.debug("TRC20 \(symbol) balance extracted: \(balance)")
        }
        
        return balance
    }
    
    // MARK: - ADA Balance Fetching (v3 API)
    private func fetchADABalance(address: String) async throws -> Double {
        Self.log.debug("Fetching ADA balance using v3 API for address: \(address)")
        
        guard let request = client.createV3Request(path: "/ada/account/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("ADA balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let adaBalanceArray = try decoder.decode([TatumADABalanceResponse].self, from: data)
        
        // Find ADA balance (should be first and only item for native ADA)
        if let adaBalance = adaBalanceArray.first(where: { $0.currency.symbol.uppercased() == "ADA" }) {
            let balance = adaBalance.humanReadableBalance
            Self.log.debug("Native ADA balance extracted: \(balance) (Raw balance lovelace: \(adaBalance.value))")
            return balance
        } else {
            Self.log.info("No ADA balance found in response")
            return 0.0
        }
    }
    
    // MARK: - SOL Balance Fetching (v3 API)
    private func fetchSOLBalance(address: String) async throws -> Double {
        Self.log.debug("Fetching SOL balance using v3 API for address: \(address)")
        
        guard let request = client.createV3Request(path: "/solana/account/balance/\(address)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("SOL balance response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let solResponse = try decoder.decode(TatumSOLBalanceResponse.self, from: data)
        
        let balance = solResponse.solBalance
        Self.log.debug("Native SOL balance extracted: \(balance) SOL")
        
        return balance
    }
}