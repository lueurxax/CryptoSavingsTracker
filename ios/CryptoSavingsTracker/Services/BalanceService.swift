//
//  BalanceService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import os

enum BalanceRoute: Equatable {
    case v4Native(v4Chain: String)
    case v4Token(v4Chain: String, canonicalContracts: Set<String>)
    case utxo(chainId: String)
    case xrp
    case tron(symbol: String)
    case cardano
    case solana
}

enum OnChainIdentifierPolicy {
    static func usesCaseInsensitiveOpaqueIdentifiers(
        for route: BalanceRoute
    ) -> Bool {
        switch route {
        case .v4Native, .v4Token, .utxo, .xrp, .tron, .cardano:
            return true
        case .solana:
            return false
        }
    }

    static func usesCaseInsensitiveOpaqueIdentifiers(
        forChainIdentifier chainIdentifier: String?
    ) -> Bool {
        guard let chainIdentifier else { return false }
        if [
            "BTC", "LTC", "BCH", "DOGE", "XRP", "TRX", "ADA",
            "bitcoin-mainnet", "litecoin-mainnet", "bch-mainnet", "doge-mainnet"
        ].contains(where: {
            $0.caseInsensitiveCompare(chainIdentifier) == .orderedSame
        }) {
            return true
        }
        let chainService = ChainService.shared
        return chainService.supportedChains.contains { chain in
            guard chain.chainType == .evm else { return false }
            if chain.id.caseInsensitiveCompare(chainIdentifier) == .orderedSame {
                return true
            }
            return chainService.getV4ChainName(for: chain.id)?
                .caseInsensitiveCompare(chainIdentifier) == .orderedSame
        }
    }

    static func normalizedOpaqueIdentifier(
        _ value: String,
        for route: BalanceRoute
    ) -> String {
        usesCaseInsensitiveOpaqueIdentifiers(for: route) ? value.lowercased() : value
    }

    static func normalizedOpaqueIdentifier(
        _ value: String,
        forChainIdentifier chainIdentifier: String?
    ) -> String {
        usesCaseInsensitiveOpaqueIdentifiers(forChainIdentifier: chainIdentifier)
            ? value.lowercased()
            : value
    }

    static func normalizedTokenIdentifier(
        _ value: String,
        for route: BalanceRoute
    ) -> String {
        switch route {
        case .v4Native, .v4Token:
            return value.lowercased()
        case .utxo, .xrp, .tron, .cardano, .solana:
            return value
        }
    }

    static func normalizedTokenIdentifier(
        _ value: String,
        forChainIdentifier chainIdentifier: String?
    ) -> String {
        guard let chainIdentifier else { return value }
        let chainService = ChainService.shared
        let isEVM = chainService.supportedChains.contains { chain in
            guard chain.chainType == .evm else { return false }
            if chain.id.caseInsensitiveCompare(chainIdentifier) == .orderedSame {
                return true
            }
            return chainService.getV4ChainName(for: chain.id)?
                .caseInsensitiveCompare(chainIdentifier) == .orderedSame
        }
        return isEVM ? value.lowercased() : value
    }

    static func normalizedAddress(
        _ value: String,
        for route: BalanceRoute
    ) -> String {
        switch route {
        case .v4Native, .v4Token:
            return value.lowercased()
        case .utxo(let chainId):
            return normalizedUTXOAddress(value, chainId: chainId)
        case .xrp, .tron, .cardano, .solana:
            return value
        }
    }

    static func normalizedAddress(
        _ value: String,
        forChainIdentifier chainIdentifier: String
    ) -> String {
        let chainService = ChainService.shared
        let isEVM = chainService.supportedChains.contains { chain in
            guard chain.chainType == .evm else { return false }
            if chain.id.caseInsensitiveCompare(chainIdentifier) == .orderedSame {
                return true
            }
            return chainService.getV4ChainName(for: chain.id)?
                .caseInsensitiveCompare(chainIdentifier) == .orderedSame
        }
        if isEVM {
            return value.lowercased()
        }
        let utxoChainID: String
        switch chainIdentifier.lowercased() {
        case "btc", "bitcoin-mainnet":
            utxoChainID = "BTC"
        case "ltc", "litecoin-mainnet":
            utxoChainID = "LTC"
        case "bch", "bch-mainnet":
            utxoChainID = "BCH"
        case "doge", "doge-mainnet":
            utxoChainID = "DOGE"
        default:
            return value
        }
        return normalizedUTXOAddress(value, chainId: utxoChainID)
    }

    static func addressesEqual(
        _ lhs: String,
        _ rhs: String,
        for route: BalanceRoute
    ) -> Bool {
        normalizedAddress(lhs, for: route) == normalizedAddress(rhs, for: route)
    }

    static func addressesEqual(
        _ lhs: String,
        _ rhs: String,
        chainId: String
    ) -> Bool {
        normalizedAddress(lhs, forChainIdentifier: chainId)
            == normalizedAddress(rhs, forChainIdentifier: chainId)
    }

    static func canonicalNamespace(for route: BalanceRoute) -> String {
        usesCaseInsensitiveOpaqueIdentifiers(for: route) ? "onchain_v3" : "onchain_v4"
    }

    private static func normalizedUTXOAddress(
        _ value: String,
        chainId: String
    ) -> String {
        switch chainId.uppercased() {
        case "BTC":
            return normalizedBech32Address(value, humanReadablePrefix: "bc1")
        case "LTC":
            return normalizedBech32Address(value, humanReadablePrefix: "ltc1")
        case "BCH":
            return normalizedBitcoinCashAddress(value)
        default:
            // Base58 and non-UTXO identifiers are case-sensitive.
            return value
        }
    }

    private static func normalizedBech32Address(
        _ value: String,
        humanReadablePrefix: String
    ) -> String {
        guard hasUniformLetterCase(value),
              value.lowercased().hasPrefix(humanReadablePrefix)
        else {
            return value
        }
        return value.lowercased()
    }

    private static func normalizedBitcoinCashAddress(_ value: String) -> String {
        guard hasUniformLetterCase(value) else { return value }

        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        let payload: Substring
        switch components.count {
        case 1:
            payload = components[0]
        case 2:
            guard components[0].caseInsensitiveCompare("bitcoincash") == .orderedSame else {
                return value
            }
            payload = components[1]
        default:
            return value
        }

        let normalizedPayload = payload.lowercased()
        let cashAddressCharacters = CharacterSet(charactersIn: "qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        guard normalizedPayload.count >= 42,
              normalizedPayload.first == "q" || normalizedPayload.first == "p",
              normalizedPayload.unicodeScalars.allSatisfy(cashAddressCharacters.contains)
        else {
            return value
        }
        return normalizedPayload
    }

    private static func hasUniformLetterCase(_ value: String) -> Bool {
        let containsLowercase = value != value.uppercased()
        let containsUppercase = value != value.lowercased()
        return !(containsLowercase && containsUppercase)
    }
}

enum BalanceTrackingValidationError: LocalizedError {
    case unsupportedPair(symbol: String, chainName: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPair(let symbol, let chainName):
            return "Automatic tracking is not available for \(symbol) on \(chainName). Choose a supported network or leave the address blank for manual tracking."
        }
    }
}

enum BalanceRouteResolver {
    private static let canonicalEVMTokenContracts: [String: [String: Set<String>]] = [
        "ETH": [
            "USDT": ["0xdAC17F958D2ee523a2206206994597C13D831ec7"],
            "USDC": ["0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"],
            "DAI": ["0x6B175474E89094C44Da98b954EedeAC495271d0F"],
            "WETH": ["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"],
            "UNI": ["0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"],
            "LINK": ["0x514910771AF9Ca656af840dff83E8264EcF986CA"],
            "AAVE": ["0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2dDaE9"],
            "SHIB": ["0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE"],
            "APE": ["0x4d224452801ACEd8B2F0aEBE155379bb5D594381"],
            "CRV": ["0xD533a949740bb3306d119CC777fa900bA034cd52"],
            "MKR": ["0x9f8F72aA9304c8B593d555F12ef6589cC3A579A2"],
            "SNX": ["0xC011A72400E58ecD99Ee497CF89E3775d4bd732F"],
            "COMP": ["0xc00e94Cb662C3520282E6f5717214004A7f26888"],
            "YFI": ["0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e"],
            "SUSHI": ["0x6B3595068778DD592e39A122f4f5a5CF09C90fE2"]
        ],
        "BSC": [
            "BUSD": ["0xe9e7CEA3DedcA5984780BAfc599bD69ADd087D56"],
            "CAKE": ["0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82"],
            "BAKE": ["0xE02dF9e3e622DeBdD69fb838bB799E3F168902c5"]
        ],
        "MATIC": [
            "WMATIC": ["0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"],
            "QUICK": ["0xB5C064F955D8e7F38fE0460C556a72987494eE17"]
        ]
    ]

    static func resolve(
        chainId: String,
        symbol: String,
        chainService: ChainService
    ) throws -> BalanceRoute {
        guard let chain = chainService.getChain(by: chainId) else {
            throw TatumError.unsupportedChain(chainId)
        }

        let normalizedChainId = chain.id.uppercased()
        let normalizedSymbol = symbol.uppercased()

        switch chain.chainType {
        case .evm:
            let isLegacyPolygonNative = normalizedChainId == "MATIC" && normalizedSymbol == "MATIC"
            if normalizedSymbol == chain.nativeCurrencySymbol.uppercased() || isLegacyPolygonNative {
                guard let v4Chain = chainService.getV4ChainName(for: chain.id) else {
                    // Do not fall back to a guessed generic v3 URL. Chains
                    // without a documented route must fail closed.
                    throw TatumError.unsupportedChain(chain.id)
                }
                return .v4Native(v4Chain: v4Chain)
            }

            guard
                let v4Chain = chainService.getV4ChainName(for: chain.id),
                let canonicalContracts = canonicalEVMTokenContracts[normalizedChainId]?[normalizedSymbol]
            else {
                throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
            }
            return .v4Token(
                v4Chain: v4Chain,
                canonicalContracts: canonicalContracts
            )

        case .utxo:
            guard normalizedSymbol == chain.nativeCurrencySymbol.uppercased() else {
                throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
            }
            return .utxo(chainId: chain.id)

        case .other:
            switch normalizedChainId {
            case "XRP":
                guard normalizedSymbol == "XRP" else {
                    throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
                }
                return .xrp
            case "TRX":
                guard normalizedSymbol == "TRX"
                        || TRXAccountResponse.tokenContracts[normalizedSymbol] != nil
                else {
                    throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
                }
                return .tron(symbol: normalizedSymbol)
            case "ADA":
                guard normalizedSymbol == "ADA" else {
                    throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
                }
                return .cardano
            case "SOL":
                guard normalizedSymbol == "SOL" else {
                    throw TatumError.unsupportedChain("\(chain.id)/\(normalizedSymbol)")
                }
                return .solana
            default:
                throw TatumError.unsupportedChain(chain.id)
            }
        }
    }

    static func matchingCanonicalToken(
        in balances: [TatumV4BalanceItem],
        canonicalContracts: Set<String>
    ) -> TatumV4BalanceItem? {
        let normalizedContracts = Set(canonicalContracts.map { $0.lowercased() })
        return balances.first { balance in
            guard balance.type.caseInsensitiveCompare("fungible") == .orderedSame,
                  let tokenAddress = balance.tokenAddress
            else {
                return false
            }
            return normalizedContracts.contains(tokenAddress.lowercased())
        }
    }

    static func validateTrackedAsset(
        chainId: String,
        symbol: String,
        chainService: ChainService
    ) throws {
        do {
            _ = try resolve(
                chainId: chainId,
                symbol: symbol,
                chainService: chainService
            )
        } catch {
            let chainName = chainService.getChain(by: chainId)?.name ?? chainId
            throw BalanceTrackingValidationError.unsupportedPair(
                symbol: symbol.uppercased(),
                chainName: chainName
            )
        }
    }
}

// MARK: - Balance Service
final class BalanceService: BalanceServiceProtocol {
    private let client: TatumClient
    private let chainService: ChainService
    private let rateLimiter: RateLimiter
    private let refreshGenerationGate: ProviderRefreshGenerationGate
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "BalanceService")

    init(
        client: TatumClient,
        chainService: ChainService,
        rateLimiter: RateLimiter? = nil,
        refreshGenerationGate: ProviderRefreshGenerationGate = .shared
    ) {
        self.client = client
        self.chainService = chainService
        self.refreshGenerationGate = refreshGenerationGate
        let rateLimitInterval = Self.getConfigValue(forKey: "RateLimitInterval") as? Double ?? 5.0
        self.rateLimiter = rateLimiter ?? RateLimiter(timeInterval: rateLimitInterval)
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

        // Resolve and validate the route before consulting any cache. A value
        // cached under an invalid chain/symbol pair must never bypass routing.
        let route = try BalanceRouteResolver.resolve(
            chainId: chainId,
            symbol: symbol,
            chainService: chainService
        )
        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: symbol)

        if !forceRefresh, let cachedBalance = BalanceCacheManager.shared.getCachedBalance(for: cacheKey) {
            Self.log.debug("Using cached balance: \(cachedBalance)")
            return cachedBalance
        }

        if rateLimiter.isRateLimited(for: cacheKey) {
            throw TatumError.rateLimitExceeded
        }

        rateLimiter.recordRequest(for: cacheKey)
        let publicationToken = refreshGenerationGate.begin(
            routeKey: cacheKey
        )

        return try await fetchAndCacheBalance(
            route: route,
            address: address,
            cacheKey: cacheKey,
            publicationToken: publicationToken
        )
    }

    private func fetchAndCacheBalance(
        route: BalanceRoute,
        address: String,
        cacheKey: String,
        publicationToken: ProviderRefreshGenerationToken
    ) async throws -> Double {
        let balance = try await fetchBalance(for: route, address: address)

        if let publishedBalance = Self.publishFetchedBalance(
            balance,
            cacheKey: cacheKey,
            publicationToken: publicationToken,
            refreshGenerationGate: refreshGenerationGate
        ) {
            return publishedBalance
        }
        throw TatumError.requestCancelled
    }

    static func publishFetchedBalance(
        _ balance: Double,
        cacheKey: String,
        publicationToken: ProviderRefreshGenerationToken,
        refreshGenerationGate: ProviderRefreshGenerationGate
    ) -> Double? {
        switch refreshGenerationGate.performIfCurrent(
            publicationToken,
            {
                BalanceCacheManager.shared.cacheBalance(
                    balance,
                    for: cacheKey
                )
                Self.log.debug("Cached balance: \(balance)")
                return balance
            }
        ) {
        case .committed(let publishedBalance):
            return publishedBalance
        case .superseded:
            switch refreshGenerationGate.performIfLatestGenerationCommitted(
                after: publicationToken,
                {
                    BalanceCacheManager.shared.getCachedBalance(
                        for: cacheKey
                    )
                }
            ) {
            case .committed(let replacementBalance):
                return replacementBalance
            case .superseded:
                // A newer request exists but has not committed yet. Returning
                // any pre-existing cache entry would falsely present it as
                // the newer request's result.
                return nil
            }
        }
    }
    
    private func fetchBalance(for route: BalanceRoute, address: String) async throws -> Double {
        switch route {
        case .v4Native(let v4Chain):
            return try await fetchV4NativeBalance(v4Chain: v4Chain, address: address)
        case .v4Token(let v4Chain, let canonicalContracts):
            return try await fetchV4TokenBalance(
                v4Chain: v4Chain,
                address: address,
                canonicalContracts: canonicalContracts
            )
        case .utxo(let chainId):
            return try await fetchUTXOBalance(chainId: chainId, address: address)
        case .xrp:
            return try await fetchXRPBalance(address: address)
        case .tron(let symbol):
            return try await fetchTRXBalance(address: address, symbol: symbol)
        case .cardano:
            return try await fetchADABalance(address: address)
        case .solana:
            return try await fetchSOLBalance(address: address)
        }
    }

    // MARK: - Tatum v4 Balance Fetching

    static func v4PortfolioQueryItems(
        v4Chain: String,
        address: String,
        tokenTypes: [String],
        pageSize: Int,
        offset: Int
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "tokenTypes", value: tokenTypes.joined(separator: ",")),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
    }

    private func fetchV4PortfolioData(
        v4Chain: String,
        address: String,
        tokenTypes: [String],
        pageSize: Int = 50,
        offset: Int = 0
    ) async throws -> TatumV4PortfolioResponse {
        let queryItems = Self.v4PortfolioQueryItems(
            v4Chain: v4Chain,
            address: address,
            tokenTypes: tokenTypes,
            pageSize: pageSize,
            offset: offset
        )

        guard let request = client.createV4Request(path: "/data/wallet/portfolio", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        let (data, _) = try await client.performRequest(request)
        return try JSONDecoder().decode(TatumV4PortfolioResponse.self, from: data)
    }

    private static func nextPortfolioOffset(_ nextPage: String, after currentOffset: Int) throws -> Int {
        let nextOffset: Int?
        if let numericOffset = Int(nextPage) {
            nextOffset = numericOffset
        } else {
            let continuation = nextPage.hasPrefix("offset=") ? "?" + nextPage : nextPage
            guard let components = URLComponents(string: continuation),
                  (components.scheme == nil && components.host == nil)
                    || (components.scheme?.lowercased() == "https"
                        && components.host?.lowercased() == "api.tatum.io"),
                  components.port == nil || components.port == 443,
                  components.user == nil, components.password == nil, components.fragment == nil,
                  ["", "/data/wallet/portfolio", "/v4/data/wallet/portfolio"].contains(components.path),
                  let offsets = components.queryItems?.filter({ $0.name == "offset" }),
                  offsets.count == 1 else {
                throw TatumError.invalidResponse
            }
            nextOffset = offsets.first?.value.flatMap(Int.init)
        }

        // Rebuild every page request against the fixed endpoint, preserving the wallet
        // filters. A continuation URL must never redirect credentials or repeat a page.
        guard let nextOffset, nextOffset > currentOffset else {
            throw TatumError.invalidResponse
        }
        return nextOffset
    }

    static func canonicalTokenBalance(
        canonicalContracts: Set<String>,
        pageSize: Int = 50,
        maxPages: Int = 20,
        fetchPage: (_ offset: Int, _ pageSize: Int) async throws -> TatumV4PortfolioResponse
    ) async throws -> Double {
        guard pageSize > 0, maxPages > 0 else {
            throw TatumError.invalidResponse
        }

        var offset = 0
        for pageIndex in 0..<maxPages {
            let response = try await fetchPage(offset, pageSize)
            if let token = BalanceRouteResolver.matchingCanonicalToken(
                in: response.result,
                canonicalContracts: canonicalContracts
            ) {
                return token.humanReadableBalance
            }

            guard let nextPage = response.nextPage, !nextPage.isEmpty else {
                return 0
            }
            guard pageIndex + 1 < maxPages, !response.result.isEmpty else {
                throw TatumError.invalidResponse
            }
            offset = try nextPortfolioOffset(nextPage, after: offset)
        }

        throw TatumError.invalidResponse
    }

    private func fetchV4NativeBalance(v4Chain: String, address: String) async throws -> Double {
        var offset = 0
        for pageIndex in 0..<20 {
            let page = try await fetchV4PortfolioData(
                v4Chain: v4Chain,
                address: address,
                tokenTypes: ["native"],
                offset: offset
            )
            if let nativeBalance = page.result.first(where: { $0.type == "native" }) {
                return nativeBalance.humanReadableBalance
            }
            guard let nextPage = page.nextPage, !nextPage.isEmpty else { return 0 }
            guard pageIndex + 1 < 20, !page.result.isEmpty else { throw TatumError.invalidResponse }
            offset = try Self.nextPortfolioOffset(nextPage, after: offset)
        }
        throw TatumError.invalidResponse
    }

    private func fetchV4TokenBalance(
        v4Chain: String,
        address: String,
        canonicalContracts: Set<String>
    ) async throws -> Double {
        let balance = try await Self.canonicalTokenBalance(
            canonicalContracts: canonicalContracts
        ) { offset, pageSize in
            try await self.fetchV4PortfolioData(
                v4Chain: v4Chain,
                address: address,
                tokenTypes: ["fungible"],
                pageSize: pageSize,
                offset: offset
            )
        }
        Self.log.debug("Canonical token balance: \(balance)")
        return balance
    }
    
    /// Interpret denominatedBalance as raw units, using the provider's explicit decimals.
    static func humanReadableBalance(from item: TatumV4BalanceItem) -> Double {
        item.humanReadableBalance
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
    static func makeUTXOBalanceRequest(
        chainId: String,
        address: String,
        client: TatumClient
    ) -> URLRequest? {
        let path: String

        switch chainId.uppercased() {
        case ChainID.btc.rawValue:
            path = "/bitcoin/address/balance/\(address)"
        case ChainID.ltc.rawValue:
            path = "/litecoin/address/balance/\(address)"
        case ChainID.bch.rawValue:
            path = "/bcash/address/balance/\(address)"
        case ChainID.doge.rawValue:
            path = "/dogecoin/address/balance/\(address)"
        default:
            return nil
        }

        return client.createV3Request(path: path)
    }

    private func fetchUTXOBalance(chainId: String, address: String) async throws -> Double {
        guard let request = Self.makeUTXOBalanceRequest(
            chainId: chainId,
            address: address,
            client: client
        ) else {
            Self.log.error("Unsupported UTXO chain: \(chainId)")
            throw TatumError.unsupportedChain(chainId)
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
