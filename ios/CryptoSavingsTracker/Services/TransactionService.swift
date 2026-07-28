//
//  TransactionService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import os


// MARK: - Transaction Service
final class TransactionService: TransactionServiceProtocol {
    private static let maximumHistoryPages = 100
    private static let maximumUTXOPrevoutLookups = 250
    private let rateLimiter = RateLimiter(
        timeInterval: 1.0
    ) // 1 request per 1 seconds
    private let client: TatumClient
    private let chainService: ChainService
    private let refreshGenerationGate: ProviderRefreshGenerationGate
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "TransactionService")
    
    init(
        client: TatumClient,
        chainService: ChainService,
        refreshGenerationGate: ProviderRefreshGenerationGate = .shared
    ) {
        self.client = client
        self.chainService = chainService
        self.refreshGenerationGate = refreshGenerationGate
    }
    
    // MARK: - Transaction History Fetching
    func fetchTransactionHistory(chainId: String, address: String, currency: String? = nil, limit: Int = 50, forceRefresh: Bool = false) async throws -> [TatumTransaction] {
        let batch = try await fetchTransactionHistoryBatch(
            chainId: chainId,
            address: address,
            currency: currency,
            limit: limit,
            forceRefresh: forceRefresh
        )
        return batch.transactions
    }

    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String? = nil,
        limit: Int = 50,
        forceRefresh: Bool = false
    ) async throws -> ProviderTransactionHistoryBatch {
        Self.log.debug("fetchTransactionHistory called - ChainId: \(chainId), Address: \(address), Limit: \(limit)")

        guard let chain = chainService.getChain(by: chainId) else {
            throw TatumError.unsupportedChain(chainId)
        }
        let normalizedRateLimitAddress = OnChainIdentifierPolicy.normalizedAddress(
            address,
            forChainIdentifier: chain.id
        )
        let rateLimitKey = [
            chain.id.lowercased(),
            normalizedRateLimitAddress,
            currency?.lowercased() ?? ""
        ].joined(separator: "-")
        
        return try await rateLimiter.execute(key: rateLimitKey) {
            // Check cache first
            let cacheKey = BalanceCacheManager.transactionsCacheKey(chainId: chainId, address: address, currency: currency)
            
            if !forceRefresh {
                if let cachedTransactions = BalanceCacheManager.shared.getCachedTransactions(for: cacheKey) {
                    Self.log.debug("Using cached transactions (count: \(cachedTransactions.count))")
                    return ProviderTransactionHistoryBatch(
                        transactions: cachedTransactions
                    )
                }
            }

            let publicationToken = self.refreshGenerationGate.begin(
                routeKey: cacheKey
            )
            
            let fetchedTransactions = try await self.fetchTransactionsForChain(chain: chain, address: address, currency: currency, limit: limit)

            let authoritative = Self.authoritativeHistory(
                fetched: fetchedTransactions,
                cached: BalanceCacheManager.shared.getAnyTransactions(for: cacheKey)
            )
            return ProviderTransactionHistoryBatch(
                transactions: authoritative,
                publicationToken: publicationToken
            )
        }
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {
        let cacheKey = BalanceCacheManager.transactionsCacheKey(
            chainId: chainId,
            address: address,
            currency: currency
        )
        // Only durable, route-validated history reaches this publication
        // handshake. Rejected provider batches never enter the two-hour cache.
        BalanceCacheManager.shared.cacheTransactions(transactions, for: cacheKey)
        Self.log.debug(
            "Committed imported history (\(transactions.count) transactions) for \(chainId)"
        )
    }

    static func authoritativeHistory(
        fetched: [TatumTransaction],
        cached: [TatumTransaction]?
    ) -> [TatumTransaction] {
        fetched
    }

    static func decodeProviderResponse<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw TatumError.decodingError(error)
        }
    }
    
    private func fetchTransactionsForChain(chain: TatumChain, address: String, currency: String?, limit: Int) async throws -> [TatumTransaction] {
        switch chain.chainType {
        case .evm:
            let requests = try Self.makeV4HistoryRequests(
                chainId: chain.id,
                address: address,
                currency: currency ?? chain.nativeCurrencySymbol,
                limit: limit,
                client: client,
                chainService: chainService
            )
            return try await fetchV4Transactions(requests: requests, limit: limit)
        case .utxo:
            return try await fetchUTXOTransactions(chainId: chain.id, address: address, limit: limit)
        case .other:
            return try await fetchOtherTransactions(chainId: chain.id, address: address, currency: currency, limit: limit)
        }
    }
    
    // MARK: - Tatum v4 Transaction Fetching
    private static func v4HistoryQueryItems(
        v4Chain: String,
        address: String,
        transactionType: String,
        tokenAddress: String?,
        pageSize: Int,
        offset: Int
    ) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "transactionTypes", value: transactionType),
            URLQueryItem(name: "sort", value: "DESC"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let tokenAddress {
            queryItems.append(URLQueryItem(name: "tokenAddress", value: tokenAddress))
        }
        return queryItems
    }

    static func makeV4HistoryRequests(
        chainId: String,
        address: String,
        currency: String,
        limit: Int,
        client: TatumClient,
        chainService: ChainService
    ) throws -> [URLRequest] {
        let route = try BalanceRouteResolver.resolve(
            chainId: chainId,
            symbol: currency,
            chainService: chainService
        )

        let requestParameters: [(v4Chain: String, type: String, tokenAddress: String?)]
        switch route {
        case .v4Native(let v4Chain):
            requestParameters = [(v4Chain, "native", nil)]
        case .v4Token(let v4Chain, let canonicalContracts):
            requestParameters = canonicalContracts.sorted().map { (v4Chain, "fungible", $0) }
        default:
            throw TatumError.unsupportedChain("\(chainId)/\(currency.uppercased())")
        }

        return try requestParameters.map { parameters in
            let pageSize = max(1, min(limit, 50))
            let queryItems = Self.v4HistoryQueryItems(
                v4Chain: parameters.v4Chain,
                address: address,
                transactionType: parameters.type,
                tokenAddress: parameters.tokenAddress,
                pageSize: pageSize,
                offset: 0
            )
            guard let request = client.createV4Request(
                path: "/data/transaction/history",
                queryItems: queryItems
            ) else {
                throw TatumError.invalidURL
            }
            return request
        }
    }

    private func fetchV4Transactions(
        requests: [URLRequest],
        limit: Int
    ) async throws -> [TatumTransaction] {
        var fetched: [TatumTransaction] = []
        let pageSize = max(1, min(limit, 50))

        for baseRequest in requests {
            let routeHistory = try await Self.collectOffsetTransactionPages(
                pageSize: pageSize,
                maxPages: Self.maximumHistoryPages
            ) { offset, requestedPageSize in
                let request = try Self.paginatedRequest(
                    from: baseRequest,
                    offset: offset,
                    pageSize: requestedPageSize
                )
                Self.log.debug("Fetching filtered v4 transactions from: \(request.url?.absoluteString ?? "")")
                let (data, _) = try await self.client.performRequest(request)
                let response = try Self.decodeProviderResponse(
                    TatumV4TransactionResponse.self,
                    from: data
                )
                let hasMore = response.nextPage.map { !$0.isEmpty }
                    ?? (response.result.count >= requestedPageSize)
                return (response.result, hasMore)
            }
            fetched.append(contentsOf: routeHistory)
        }

        return try Self.deduplicatedProviderTransactions(fetched)
            .sorted { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
    }

    private static func paginatedRequest(
        from baseRequest: URLRequest,
        offset: Int,
        pageSize: Int
    ) throws -> URLRequest {
        guard let url = baseRequest.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw TatumError.invalidURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "offset" || $0.name == "pageSize" }
        queryItems.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        components.queryItems = queryItems
        guard let paginatedURL = components.url else {
            throw TatumError.invalidURL
        }
        var request = baseRequest
        request.url = paginatedURL
        return request
    }

    private static func deduplicatedProviderTransactions(
        _ transactions: [TatumTransaction]
    ) throws -> [TatumTransaction] {
        var ordered: [TatumTransaction] = []
        var byProviderRecordID: [String: TatumTransaction] = [:]
        for transaction in transactions {
            guard transaction.isValidAuthoritativeMovement else {
                throw TatumError.invalidResponse
            }
            let key = transaction.providerRecordIdentity
            if let existing = byProviderRecordID[key] {
                guard existing.isCanonicalProviderEquivalent(to: transaction) else {
                    throw TatumError.invalidResponse
                }
                continue
            }
            byProviderRecordID[key] = transaction
            ordered.append(transaction)
        }
        return ordered
    }

    static func collectOffsetTransactionPages(
        pageSize: Int,
        maxPages: Int,
        fetchPage: (_ offset: Int, _ pageSize: Int) async throws -> (
            transactions: [TatumTransaction],
            hasMore: Bool
        )
    ) async throws -> [TatumTransaction] {
        guard pageSize > 0, maxPages > 0 else {
            throw TatumError.invalidResponse
        }

        var ordered: [TatumTransaction] = []
        var byProviderRecordID: [String: TatumTransaction] = [:]
        var offset = 0

        for pageIndex in 0..<maxPages {
            let page = try await fetchPage(offset, pageSize)
            if page.transactions.isEmpty, page.hasMore {
                throw TatumError.invalidResponse
            }

            for transaction in page.transactions {
                guard transaction.isValidAuthoritativeMovement else {
                    throw TatumError.invalidResponse
                }
                let key = transaction.providerRecordIdentity
                if let existing = byProviderRecordID[key] {
                    guard existing.isCanonicalProviderEquivalent(to: transaction) else {
                        throw TatumError.invalidResponse
                    }
                    continue
                }
                byProviderRecordID[key] = transaction
                ordered.append(transaction)
            }

            guard page.hasMore else {
                return ordered
            }
            guard pageIndex + 1 < maxPages else {
                throw TatumError.invalidResponse
            }
            offset += page.transactions.count
        }

        throw TatumError.invalidResponse
    }

    static func collectUTXOTransactionPages(
        chainId: String,
        pageSize: Int,
        maxPages: Int,
        fetchPage: (_ offset: Int, _ pageSize: Int) async throws -> (
            transactions: [TatumUTXOTransaction],
            hasMore: Bool
        )
    ) async throws -> [TatumUTXOTransaction] {
        guard pageSize > 0, maxPages > 0 else {
            throw TatumError.invalidResponse
        }
        var ordered: [TatumUTXOTransaction] = []
        var indexByProviderHash: [String: Int] = [:]
        var offset = 0

        for pageIndex in 0..<maxPages {
            let page = try await fetchPage(offset, pageSize)
            if page.transactions.isEmpty, page.hasMore {
                throw TatumError.invalidResponse
            }
            for transaction in page.transactions {
                let incomingHashes = transaction.normalizedProviderHashes(
                    chainId: chainId
                )
                let matchingIndexes = Set(
                    incomingHashes.compactMap { indexByProviderHash[$0] }
                )
                guard matchingIndexes.count <= 1 else {
                    throw TatumError.invalidResponse
                }

                guard let existingIndex = matchingIndexes.first else {
                    let newIndex = ordered.count
                    ordered.append(transaction)
                    for providerHash in incomingHashes {
                        indexByProviderHash[providerHash] = newIndex
                    }
                    continue
                }

                let existing = ordered[existingIndex]
                guard existing.isCanonicalProviderEquivalentIgnoringHash(
                    to: transaction,
                    chainId: chainId
                ) else {
                    throw TatumError.invalidResponse
                }
                let existingHashes = existing.normalizedProviderHashes(
                    chainId: chainId
                )
                let preferred: TatumUTXOTransaction
                if existing.hasExplicitTxid != transaction.hasExplicitTxid {
                    preferred = transaction.hasExplicitTxid ? transaction : existing
                } else {
                    let normalizedExistingHash =
                        OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                            existing.hash,
                            forChainIdentifier: chainId
                        )
                    let normalizedIncomingHash =
                        OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                            transaction.hash,
                            forChainIdentifier: chainId
                        )
                    guard normalizedExistingHash == normalizedIncomingHash else {
                        throw TatumError.invalidResponse
                    }
                    preferred = incomingHashes.count > existingHashes.count
                        ? transaction
                        : existing
                }

                var seenHashes = Set<String>()
                let aliases = (
                    [existing.hash]
                        + existing.providerHashAliases
                        + [transaction.hash]
                        + transaction.providerHashAliases
                ).filter { providerHash in
                    let normalizedProviderHash =
                        OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                            providerHash,
                            forChainIdentifier: chainId
                        )
                    let normalizedPreferredHash =
                        OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                            preferred.hash,
                            forChainIdentifier: chainId
                        )
                    return normalizedProviderHash != normalizedPreferredHash
                        && seenHashes.insert(normalizedProviderHash).inserted
                }
                let merged = TatumUTXOTransaction(
                    hash: preferred.hash,
                    providerHashAliases: aliases,
                    hasExplicitTxid: preferred.hasExplicitTxid,
                    time: preferred.time,
                    inputs: preferred.inputs,
                    outputs: preferred.outputs
                )
                ordered[existingIndex] = merged

                for providerHash in existingHashes.union(incomingHashes) {
                    if let indexed = indexByProviderHash[providerHash],
                       indexed != existingIndex {
                        throw TatumError.invalidResponse
                    }
                    indexByProviderHash[providerHash] = existingIndex
                }
            }
            guard page.hasMore else { return ordered }
            guard pageIndex + 1 < maxPages else {
                throw TatumError.invalidResponse
            }
            offset += page.transactions.count
        }
        throw TatumError.invalidResponse
    }

    static func normalizeUTXOTransactions(
        chainId: String,
        address: String,
        transactions: [TatumUTXOTransaction],
        maxPrevoutLookups: Int,
        fetchPrevout: (_ transactionHash: String) async throws -> TatumUTXOTransaction
    ) async throws -> [TatumTransaction] {
        guard maxPrevoutLookups >= 0 else {
            throw TatumError.invalidResponse
        }

        var originalHashByNormalizedHash: [String: String] = [:]
        for transaction in transactions {
            for input in transaction.inputs ?? [] where input.prevout == nil && !input.isCoinbase {
                guard let transactionHash = input.transactionHash,
                      input.outputIndex != nil
                else {
                    throw TatumError.invalidResponse
                }
                let normalizedHash = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    transactionHash,
                    forChainIdentifier: chainId
                )
                originalHashByNormalizedHash[normalizedHash] = transactionHash
            }
        }
        guard originalHashByNormalizedHash.count <= maxPrevoutLookups else {
            throw TatumError.invalidResponse
        }

        var parentByNormalizedHash: [String: TatumUTXOTransaction] = [:]
        for normalizedHash in originalHashByNormalizedHash.keys.sorted() {
            guard let originalHash = originalHashByNormalizedHash[normalizedHash] else {
                throw TatumError.invalidResponse
            }
            let parent = try await fetchPrevout(originalHash)
            let returnedHash = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                parent.hash,
                forChainIdentifier: chainId
            )
            guard returnedHash == normalizedHash else {
                throw TatumError.invalidResponse
            }
            parentByNormalizedHash[normalizedHash] = parent
        }

        let unitScale = chainId.caseInsensitiveCompare("BTC") == .orderedSame
            ? 100_000_000.0
            : 1.0
        var movements: [TatumTransaction] = []
        movements.reserveCapacity(transactions.count)

        for transaction in transactions {
            guard let rawTime = transaction.time,
                  let timestamp = normalizedTimestampMilliseconds(rawTime)
            else {
                throw TatumError.invalidResponse
            }

            var netAmount = 0.0
            var firstInputCounterparty: String?
            var firstOutputCounterparty: String?

            for input in transaction.inputs ?? [] {
                if input.isCoinbase { continue }

                let value: Double
                let inputAddresses: [String]
                if let prevout = input.prevout {
                    guard let rawValue = prevout.valueNumber,
                          rawValue.isFinite,
                          rawValue >= 0
                    else {
                        throw TatumError.invalidResponse
                    }
                    value = rawValue / unitScale
                    inputAddresses = prevout.scriptPubKey?.allAddresses ?? []
                } else {
                    guard let transactionHash = input.transactionHash,
                          let outputIndex = input.outputIndex
                    else {
                        throw TatumError.invalidResponse
                    }
                    let normalizedHash = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                        transactionHash,
                        forChainIdentifier: chainId
                    )
                    guard let parent = parentByNormalizedHash[normalizedHash],
                          let parentOutputs = parent.outputs,
                          parentOutputs.indices.contains(outputIndex),
                          let rawValue = parentOutputs[outputIndex].valueNumber,
                          rawValue.isFinite,
                          rawValue >= 0
                    else {
                        throw TatumError.invalidResponse
                    }
                    value = rawValue / unitScale
                    let parentOutput = parentOutputs[outputIndex]
                    inputAddresses = Self.utxoAddresses(for: parentOutput)
                }

                if inputAddresses.contains(where: {
                    OnChainIdentifierPolicy.addressesEqual($0, address, chainId: chainId)
                }) {
                    netAmount -= value
                } else if firstInputCounterparty == nil {
                    firstInputCounterparty = inputAddresses.first
                }
            }

            for output in transaction.outputs ?? [] {
                guard let rawValue = output.valueNumber,
                      rawValue.isFinite,
                      rawValue >= 0
                else {
                    throw TatumError.invalidResponse
                }
                let value = rawValue / unitScale
                let outputAddresses = Self.utxoAddresses(for: output)
                if outputAddresses.contains(where: {
                    OnChainIdentifierPolicy.addressesEqual($0, address, chainId: chainId)
                }) {
                    netAmount += value
                } else if firstOutputCounterparty == nil {
                    firstOutputCounterparty = outputAddresses.first
                }
            }

            guard netAmount.isFinite else {
                throw TatumError.invalidResponse
            }
            if abs(netAmount) <= 0.000_000_000_001 {
                continue
            }
            let isIncoming = netAmount > 0
            movements.append(
                TatumTransaction(
                    hash: transaction.hash,
                    timestamp: timestamp,
                    from: isIncoming ? firstInputCounterparty : address,
                    to: isIncoming ? address : firstOutputCounterparty,
                    chain: chainId.uppercased(),
                    address: address,
                    transactionType: "utxo",
                    transactionSubtype: isIncoming ? "received" : "sent",
                    amount: String(abs(netAmount)),
                    counterAddress: isIncoming ? firstInputCounterparty : firstOutputCounterparty,
                    providerHashAliases: transaction.providerHashAliases.isEmpty
                        ? nil
                        : transaction.providerHashAliases,
                    providerHashProvenance: transaction.hasExplicitTxid
                        ? .explicitTxid
                        : .fallbackIdentifier
                )
            )
        }
        return movements
    }

    private static func utxoAddresses(for output: TatumUTXOOutput) -> [String] {
        var addresses = output.scriptPubKey?.allAddresses ?? []
        if let address = output.address, !addresses.contains(address) {
            addresses.append(address)
        }
        return addresses
    }

    private static func normalizedTimestampMilliseconds(_ rawValue: Int) -> Int? {
        guard rawValue > 0 else { return nil }
        if rawValue >= 1_000_000_000_000 {
            return rawValue
        }
        let (milliseconds, overflow) = rawValue.multipliedReportingOverflow(by: 1_000)
        return overflow ? nil : milliseconds
    }
    
    // MARK: - Legacy EVM Transaction Fetching
    private func fetchEVMTransactions(chainId: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [
            URLQueryItem(name: "chain", value: chainId),
            URLQueryItem(name: "pageSize", value: String(limit))
        ]
        
        guard let request = client.createLegacyRequest(path: "/blockchain/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let transactionResponse = try decoder.decode([TatumTransaction].self, from: data)
            return transactionResponse
        } catch {
            // Try alternative response format
            do {
                let transactionResponse = try decoder.decode(TatumTransactionResponse.self, from: data)
                return transactionResponse.transactions
            } catch {
                Self.log.error("Failed to decode EVM transactions: \(error)")
                throw TatumError.decodingError(error)
            }
        }
    }
    
    // MARK: - UTXO Transaction Fetching
    private func fetchUTXOTransactions(chainId: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        switch chainId {
        case "BTC":
            return try await fetchLegacyUTXOTransactions(chainId: "BTC", path: "/bitcoin/transaction/address/\(address)", address: address, limit: limit)
        case "LTC":
            return try await fetchLegacyUTXOTransactions(chainId: "LTC", path: "/litecoin/transaction/address/\(address)", address: address, limit: limit)
        case "BCH":
            return try await fetchLegacyUTXOTransactions(chainId: "BCH", path: "/bcash/transaction/address/\(address)", address: address, limit: limit)
        case "DOGE":
            return try await fetchLegacyUTXOTransactions(chainId: "DOGE", path: "/dogecoin/transaction/address/\(address)", address: address, limit: limit)
        default:
            throw TatumError.unsupportedChain(chainId)
        }
    }
    
    private func fetchLegacyUTXOTransactions(chainId: String, path: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        let pageSize = max(1, min(limit, 50))
        let rawTransactions = try await Self.collectUTXOTransactionPages(
            chainId: chainId,
            pageSize: pageSize,
            maxPages: Self.maximumHistoryPages
        ) { offset, requestedPageSize in
            let queryItems = [
                URLQueryItem(name: "pageSize", value: String(requestedPageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            guard let request = self.client.createV3Request(
                path: path,
                queryItems: queryItems
            ) else {
                throw TatumError.invalidURL
            }
            let (data, _) = try await self.client.performRequest(request)
            let decoded = try Self.decodeProviderResponse(
                [TatumUTXOTransaction].self,
                from: data
            )
            return (decoded, decoded.count >= requestedPageSize)
        }

        return try await Self.normalizeUTXOTransactions(
            chainId: chainId,
            address: address,
            transactions: rawTransactions,
            maxPrevoutLookups: Self.maximumUTXOPrevoutLookups
        ) { transactionHash in
            try await self.fetchUTXOPrevoutTransaction(
                chainId: chainId,
                hash: transactionHash
            )
        }
    }

    static func makeUTXOPrevoutRequest(
        chainId: String,
        hash: String,
        client: TatumClient
    ) throws -> URLRequest {
        let v4Chain: String
        switch chainId.uppercased() {
        case "BTC": v4Chain = "bitcoin-mainnet"
        case "LTC": v4Chain = "litecoin-mainnet"
        case "BCH": v4Chain = "bch-mainnet"
        case "DOGE": v4Chain = "doge-mainnet"
        default: throw TatumError.unsupportedChain(chainId)
        }
        let queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "hash", value: hash)
        ]
        guard let request = client.createV4Request(
            path: "/data/blockchains/transaction",
            queryItems: queryItems
        ) else {
            throw TatumError.invalidURL
        }
        return request
    }

    private func fetchUTXOPrevoutTransaction(
        chainId: String,
        hash: String
    ) async throws -> TatumUTXOTransaction {
        let request = try Self.makeUTXOPrevoutRequest(
            chainId: chainId,
            hash: hash,
            client: client
        )
        let (data, _) = try await client.performRequest(request)
        do {
            return try JSONDecoder().decode(TatumUTXOTransaction.self, from: data)
        } catch {
            do {
                return try JSONDecoder().decode(
                    TatumBlockchainTransactionResponse.self,
                    from: data
                ).result
            } catch {
                throw TatumError.decodingError(error)
            }
        }
    }
    
    // MARK: - Other Chain Transaction Fetching
    private func fetchOtherTransactions(chainId: String, address: String, currency: String?, limit: Int) async throws -> [TatumTransaction] {
        switch chainId {
        case "XRP":
            return try await fetchXRPTransactions(address: address, limit: limit)
        case "TRX":
            return try await fetchTRXTransactions(address: address, currency: currency, limit: limit)
        case "ADA":
            return try await fetchADATransactions(address: address, limit: limit)
        case "SOL":
            return try await fetchSOLTransactions(address: address, limit: limit)
        case "ALGO":
            return try await fetchALGOTransactions(address: address, limit: limit)
        case "XLM":
            return try await fetchXLMTransactions(address: address, limit: limit)
        default:
            throw TatumError.unsupportedChain(chainId)
        }
    }
    
    private func fetchXRPTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        Self.log.debug("fetchXRPTransactions called for address: \(address), limit: \(limit)")

        let pageSize = max(1, min(limit, 50))
        let details = try await Self.collectXRPTransactionPages(
            pageSize: pageSize,
            maxPages: Self.maximumHistoryPages
        ) { marker, requestedPageSize in
            var queryItems = [
                URLQueryItem(name: "min", value: "-1"),
                URLQueryItem(name: "pageSize", value: String(requestedPageSize))
            ]
            if let marker {
                queryItems.append(URLQueryItem(name: "marker", value: marker))
            }
            guard let request = self.client.createV3Request(
                path: "/xrp/account/tx/\(address)",
                queryItems: queryItems
            ) else {
                throw TatumError.invalidURL
            }
            let (data, _) = try await self.client.performRequest(request)
            return try Self.decodeProviderResponse(XRPAccountResponse.self, from: data)
        }

        let aggregate = XRPAccountResponse(
            account: address,
            ledgerIndexMax: 0,
            ledgerIndexMin: 0,
            limit: pageSize,
            transactions: details,
            validated: true,
            marker: nil
        )
        return try Self.parseXRPTransactions(aggregate, address: address)
    }

    static func collectXRPTransactionPages(
        pageSize: Int,
        maxPages: Int,
        fetchPage: (_ marker: String?, _ pageSize: Int) async throws -> XRPAccountResponse
    ) async throws -> [XRPTransactionDetails] {
        guard pageSize > 0, maxPages > 0 else {
            throw TatumError.invalidResponse
        }
        var marker: String?
        var seenMarkers = Set<String>()
        var ordered: [XRPTransactionDetails] = []
        var byRecordID: [String: XRPTransactionDetails] = [:]

        for pageIndex in 0..<maxPages {
            let response = try await fetchPage(marker, pageSize)
            guard response.validated else {
                throw TatumError.invalidResponse
            }
            for details in response.transactions {
                let key = [
                    details.tx.hash.lowercased(),
                    String(details.meta.transactionIndex)
                ].joined(separator: "|")
                if let existing = byRecordID[key] {
                    guard existing.isCanonicalProviderEquivalent(to: details) else {
                        throw TatumError.invalidResponse
                    }
                    continue
                }
                byRecordID[key] = details
                ordered.append(details)
            }

            guard let providerMarker = response.marker else {
                return ordered
            }
            if case .null = providerMarker {
                return ordered
            }
            guard let nextMarker = providerMarker.queryValue,
                  !nextMarker.isEmpty
            else {
                throw TatumError.invalidResponse
            }
            guard !response.transactions.isEmpty,
                  seenMarkers.insert(nextMarker).inserted,
                  pageIndex + 1 < maxPages
            else {
                throw TatumError.invalidResponse
            }
            marker = nextMarker
        }
        throw TatumError.invalidResponse
    }

    static func parseXRPTransactions(
        _ response: XRPAccountResponse,
        address: String
    ) throws -> [TatumTransaction] {
        guard response.validated else {
            throw TatumError.invalidResponse
        }
        return try response.transactions.compactMap { details in
            let transaction = details.tx
            guard details.validated,
                  details.meta.transactionResult == "tesSUCCESS",
                  transaction.transactionType == "Payment"
            else {
                return nil
            }
            guard case .nativeDrops(let rawDeliveredAmount) = details.meta.deliveredAmount else {
                // Issued-currency payments are valid provider records, but they
                // are not native XRP movements.
                return nil
            }
            guard let drops = Double(rawDeliveredAmount),
                  drops.isFinite,
                  drops >= 0
            else {
                throw TatumError.invalidResponse
            }
            let isSending = transaction.account == address
            let isReceiving = transaction.destination == address
            guard isSending != isReceiving else {
                return nil
            }
            let (unixSeconds, overflow) = transaction.date
                .addingReportingOverflow(946_684_800)
            guard !overflow,
                  let timestamp = normalizedTimestampMilliseconds(unixSeconds)
            else {
                throw TatumError.invalidResponse
            }
            return TatumTransaction(
                hash: transaction.hash,
                blockNumber: transaction.ledgerIndex,
                timestamp: timestamp,
                from: transaction.account,
                to: transaction.destination,
                gasPrice: transaction.fee,
                chain: "XRP",
                address: address,
                transactionIndex: details.meta.transactionIndex,
                transactionType: "Payment",
                transactionSubtype: isSending ? "sent" : "received",
                amount: String(drops / 1_000_000),
                counterAddress: isSending ? transaction.destination : transaction.account
            )
        }
    }
    
    
    private func fetchTRXTransactions(address: String, currency: String?, limit: Int) async throws -> [TatumTransaction] {
        Self.log.debug("fetchTRXTransactions called with currency: \(currency ?? "nil")")
        
        // Filter transactions based on currency
        if let currency = currency {
            switch currency.uppercased() {
            case "TRX":
                // Only fetch native TRX transactions
                Self.log.debug("Fetching native TRX transactions for currency: TRX")
                return try await fetchNativeTRXTransactions(address: address, limit: limit)
            case "USDT":
                // Only fetch USDT TRC-20 transactions
                Self.log.debug("Fetching TRC-20 transactions for currency: USDT")
                return try await fetchTRC20Transactions(address: address, currency: currency, limit: limit)
            default:
                // For other TRC-20 tokens, fetch TRC-20 transactions and filter by symbol
                Self.log.debug("Fetching TRC-20 transactions for currency: \(currency)")
                return try await fetchTRC20Transactions(address: address, currency: currency, limit: limit)
            }
        } else {
            async let nativeTransactions = fetchNativeTRXTransactions(address: address, limit: limit)
            async let trc20Transactions = fetchTRC20Transactions(address: address, currency: nil, limit: limit)
            let allTransactions = try await nativeTransactions + trc20Transactions
            return allTransactions.sorted {
                ($0.timestamp ?? Int.min) > ($1.timestamp ?? Int.min)
            }
        }
    }
    
    private func fetchNativeTRXTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        _ = limit
        let transactions = try await Self.collectTRXTransactionPages(
            maxPages: Self.maximumHistoryPages
        ) { cursor in
            let request = try Self.makeTRONHistoryRequest(
                address: address,
                trc20: false,
                nextCursor: cursor,
                client: self.client
            )
            let (data, _) = try await self.client.performRequest(request)
            return try Self.decodeProviderResponse(
                TRXTransactionResponse.self,
                from: data
            )
        }
        return try Self.parseNativeTRXTransactions(
            TRXTransactionResponse(
                transactions: transactions,
                internalTransactions: nil
            ),
            address: address
        )
    }

    static func makeTRONHistoryRequest(
        address: String,
        trc20: Bool,
        nextCursor: String?,
        client: TatumClient
    ) throws -> URLRequest {
        let queryItems = nextCursor.map {
            [URLQueryItem(name: "next", value: $0)]
        } ?? []
        let suffix = trc20 ? "/trc20" : ""
        guard let request = client.createV3Request(
            path: "/tron/transaction/account/\(address)\(suffix)",
            queryItems: queryItems
        ) else {
            throw TatumError.invalidURL
        }
        return request
    }

    static func collectTRXTransactionPages(
        maxPages: Int,
        fetchPage: (_ cursor: String?) async throws -> TRXTransactionResponse
    ) async throws -> [TRXTransaction] {
        guard maxPages > 0 else { throw TatumError.invalidResponse }
        var cursor: String?
        var followedCursors = Set<String>()
        var ordered: [TRXTransaction] = []
        var byID: [String: TRXTransaction] = [:]

        for pageIndex in 0..<maxPages {
            let response = try await fetchPage(cursor)
            for transaction in response.transactions {
                let key = transaction.txID.lowercased()
                guard !key.isEmpty else { throw TatumError.invalidResponse }
                if let existing = byID[key] {
                    guard trxTransactionsAreEquivalent(existing, transaction) else {
                        throw TatumError.invalidResponse
                    }
                } else {
                    byID[key] = transaction
                    ordered.append(transaction)
                }
            }

            guard let next = normalizedProviderCursor(response.next) else {
                return ordered
            }
            guard !response.transactions.isEmpty,
                  pageIndex + 1 < maxPages,
                  followedCursors.insert(next).inserted
            else {
                throw TatumError.invalidResponse
            }
            cursor = next
        }
        throw TatumError.invalidResponse
    }

    private static func trxTransactionsAreEquivalent(
        _ lhs: TRXTransaction,
        _ rhs: TRXTransaction
    ) -> Bool {
        lhs.txID.caseInsensitiveCompare(rhs.txID) == .orderedSame
            && lhs.blockNumber == rhs.blockNumber
            && lhs.ret == rhs.ret
            && lhs.signature == rhs.signature
            && lhs.netFee == rhs.netFee
            && lhs.netUsage == rhs.netUsage
            && lhs.energyFee == rhs.energyFee
            && lhs.energyUsage == rhs.energyUsage
            && lhs.energyUsageTotal == rhs.energyUsageTotal
            && lhs.rawData == rhs.rawData
            && lhs.internalTransactions == rhs.internalTransactions
    }

    static func parseNativeTRXTransactions(
        _ response: TRXTransactionResponse,
        address: String
    ) throws -> [TatumTransaction] {
        try response.transactions.compactMap { transaction in
            guard let results = transaction.ret,
                  !results.isEmpty,
                  results.allSatisfy({ $0.contractRet == "SUCCESS" })
            else {
                return nil
            }

            var netAmount = 0.0
            var firstSender: String?
            var firstRecipient: String?
            var foundNativeTransfer = false
            for contract in transaction.rawData?.contract ?? []
                where contract.type == "TransferContract" {
                guard let value = contract.parameter?.value,
                      let amount = value.amount,
                      amount >= 0
                else {
                    throw TatumError.invalidResponse
                }
                foundNativeTransfer = true
                let from = value.ownerAddressBase58
                let to = value.toAddressBase58
                if firstSender == nil { firstSender = from }
                if firstRecipient == nil { firstRecipient = to }
                let humanAmount = Double(amount) / 1_000_000
                if from == address { netAmount -= humanAmount }
                if to == address { netAmount += humanAmount }
            }
            guard foundNativeTransfer,
                  abs(netAmount) > 0.000_000_000_001
            else {
                return nil
            }
            guard let rawTimestamp = transaction.rawData?.timestamp,
                  let timestampValue = Int(exactly: rawTimestamp),
                  let timestamp = normalizedTimestampMilliseconds(timestampValue)
            else {
                throw TatumError.invalidResponse
            }
            let incoming = netAmount > 0
            return TatumTransaction(
                hash: transaction.hash,
                blockNumber: transaction.blockNumber,
                timestamp: timestamp,
                from: firstSender,
                to: firstRecipient,
                gasPrice: transaction.totalFee > 0 ? String(transaction.totalFee) : nil,
                chain: "TRX",
                address: address,
                transactionType: "tron",
                transactionSubtype: incoming ? "received" : "sent",
                amount: String(abs(netAmount)),
                counterAddress: incoming ? firstSender : firstRecipient
            )
        }
    }

    private func fetchTRC20Transactions(address: String, currency: String? = nil, limit: Int) async throws -> [TatumTransaction] {
        _ = limit
        let transactions = try await Self.collectTRC20TransactionPages(
            maxPages: Self.maximumHistoryPages
        ) { cursor in
            let request = try Self.makeTRONHistoryRequest(
                address: address,
                trc20: true,
                nextCursor: cursor,
                client: self.client
            )
            let (data, _) = try await self.client.performRequest(request)
            return try Self.decodeProviderResponse(
                TRC20TransactionResponse.self,
                from: data
            )
        }
        return try Self.parseTRC20Transactions(
            TRC20TransactionResponse(transactions: transactions),
            address: address,
            currency: currency
        )
    }

    static func collectTRC20TransactionPages(
        maxPages: Int,
        fetchPage: (_ cursor: String?) async throws -> TRC20TransactionResponse
    ) async throws -> [TRC20Transaction] {
        guard maxPages > 0 else { throw TatumError.invalidResponse }
        var cursor: String?
        var followedCursors = Set<String>()
        var ordered: [TRC20Transaction] = []
        var byID: [String: TRC20Transaction] = [:]

        for pageIndex in 0..<maxPages {
            let response = try await fetchPage(cursor)
            for transaction in response.transactions {
                let key = transaction.txID.lowercased()
                guard !key.isEmpty else { throw TatumError.invalidResponse }
                if let existing = byID[key] {
                    guard trc20TransactionsAreEquivalent(existing, transaction) else {
                        throw TatumError.invalidResponse
                    }
                } else {
                    byID[key] = transaction
                    ordered.append(transaction)
                }
            }

            guard let next = normalizedProviderCursor(response.next) else {
                return ordered
            }
            guard !response.transactions.isEmpty,
                  pageIndex + 1 < maxPages,
                  followedCursors.insert(next).inserted
            else {
                throw TatumError.invalidResponse
            }
            cursor = next
        }
        throw TatumError.invalidResponse
    }

    private static func trc20TransactionsAreEquivalent(
        _ lhs: TRC20Transaction,
        _ rhs: TRC20Transaction
    ) -> Bool {
        lhs.txID.caseInsensitiveCompare(rhs.txID) == .orderedSame
            && lhs.tokenInfo == rhs.tokenInfo
            && lhs.from == rhs.from
            && lhs.to == rhs.to
            && lhs.type == rhs.type
            && lhs.value == rhs.value
            && lhs.timestamp == rhs.timestamp
            && lhs.contractRet == rhs.contractRet
            && lhs.receipt == rhs.receipt
    }

    private static func normalizedProviderCursor(_ cursor: String?) -> String? {
        guard let cursor else { return nil }
        let normalized = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func parseTRC20Transactions(
        _ response: TRC20TransactionResponse,
        address: String,
        currency: String?
    ) throws -> [TatumTransaction] {
        let normalizedCurrency = currency?.uppercased()
        let acceptedContracts: Set<String>
        if let normalizedCurrency {
            guard let contract = TRXAccountResponse.tokenContracts[normalizedCurrency] else {
                throw TatumError.unsupportedChain("TRX/\(normalizedCurrency)")
            }
            acceptedContracts = [contract]
        } else {
            acceptedContracts = Set(TRXAccountResponse.tokenContracts.values)
        }

        return try response.transactions.compactMap { transaction in
            guard transaction.isSuccessful,
                  acceptedContracts.contains(transaction.tokenInfo.address)
            else {
                return nil
            }
            if let normalizedCurrency,
               transaction.tokenInfo.symbol.uppercased() != normalizedCurrency {
                return nil
            }
            let isSending = transaction.from == address
            let isReceiving = transaction.to == address
            guard isSending != isReceiving else {
                return nil
            }
            guard let rawTimestamp = transaction.timestamp,
                  let timestamp = normalizedTimestampMilliseconds(rawTimestamp),
                  let amount = transaction.tokenAmount
            else {
                throw TatumError.invalidResponse
            }
            return TatumTransaction(
                hash: transaction.txID,
                timestamp: timestamp,
                from: transaction.from,
                to: transaction.to,
                chain: "TRX",
                address: address,
                transactionType: "trc20",
                transactionSubtype: isSending ? "sent" : "received",
                amount: String(amount),
                tokenAddress: transaction.tokenInfo.address,
                counterAddress: isSending ? transaction.to : transaction.from
            )
        }
    }
    
    private func fetchADATransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let pageSize = max(1, min(limit, 50))
        let transactions = try await Self.collectADATransactionPages(
            pageSize: pageSize,
            maxPages: Self.maximumHistoryPages
        ) { offset, requestedPageSize in
            let request = try Self.makeADAHistoryRequest(
                address: address,
                offset: offset,
                pageSize: requestedPageSize,
                client: self.client
            )
            let (data, _) = try await self.client.performRequest(request)
            return try Self.decodeProviderResponse(
                [TatumADATransaction].self,
                from: data
            )
        }
        return try Self.parseADATransactions(transactions, address: address)
    }

    static func makeADAHistoryRequest(
        address: String,
        offset: Int,
        pageSize: Int,
        client: TatumClient
    ) throws -> URLRequest {
        guard offset >= 0, (1...50).contains(pageSize) else {
            throw TatumError.invalidResponse
        }
        guard let request = client.createV3Request(
            path: "/ada/transaction/address/\(address)",
            queryItems: [
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        ) else {
            throw TatumError.invalidURL
        }
        return request
    }

    static func collectADATransactionPages(
        pageSize: Int,
        maxPages: Int,
        fetchPage: (_ offset: Int, _ pageSize: Int) async throws -> [TatumADATransaction]
    ) async throws -> [TatumADATransaction] {
        guard (1...50).contains(pageSize), maxPages > 0 else {
            throw TatumError.invalidResponse
        }
        var offset = 0
        var ordered: [TatumADATransaction] = []
        var byHash: [String: TatumADATransaction] = [:]

        for pageIndex in 0..<maxPages {
            let page = try await fetchPage(offset, pageSize)
            guard page.count <= pageSize else { throw TatumError.invalidResponse }
            for transaction in page {
                let key = transaction.hash.lowercased()
                guard !key.isEmpty else { throw TatumError.invalidResponse }
                if let existing = byHash[key] {
                    guard adaTransactionsAreEquivalent(existing, transaction) else {
                        throw TatumError.invalidResponse
                    }
                } else {
                    byHash[key] = transaction
                    ordered.append(transaction)
                }
            }

            guard page.count == pageSize else { return ordered }
            guard pageIndex + 1 < maxPages,
                  offset <= Int.max - page.count
            else {
                throw TatumError.invalidResponse
            }
            offset += page.count
        }
        throw TatumError.invalidResponse
    }

    private static func adaTransactionsAreEquivalent(
        _ lhs: TatumADATransaction,
        _ rhs: TatumADATransaction
    ) -> Bool {
        lhs.hash.caseInsensitiveCompare(rhs.hash) == .orderedSame
            && lhs.block == rhs.block
            && lhs.inputs == rhs.inputs
            && lhs.outputs == rhs.outputs
            && lhs.fee == rhs.fee
            && lhs.timestamp == rhs.timestamp
    }

    static func parseADATransactions(
        _ transactions: [TatumADATransaction],
        address: String
    ) throws -> [TatumTransaction] {
        try transactions.compactMap { transaction in
            var incoming = 0.0
            var outgoing = 0.0
            var firstInputCounterparty: String?
            var firstOutputCounterparty: String?
            var trackedAddressWasPresent = false

            for input in transaction.inputs ?? [] {
                let isNative = input.symbol == nil
                    || input.symbol?.caseInsensitiveCompare("ADA") == .orderedSame
                guard isNative else { continue }
                if input.address == address {
                    trackedAddressWasPresent = true
                    guard let amount = input.amountValue else {
                        throw TatumError.invalidResponse
                    }
                    outgoing += amount
                } else if firstInputCounterparty == nil {
                    firstInputCounterparty = input.address
                }
            }

            for output in transaction.outputs ?? [] {
                let isNative = output.symbol == nil
                    || output.symbol?.caseInsensitiveCompare("ADA") == .orderedSame
                guard isNative else { continue }
                if output.address == address {
                    trackedAddressWasPresent = true
                    guard let amount = output.amountValue else {
                        throw TatumError.invalidResponse
                    }
                    incoming += amount
                } else if firstOutputCounterparty == nil {
                    firstOutputCounterparty = output.address
                }
            }

            guard trackedAddressWasPresent else { return nil }
            let netAmount = incoming - outgoing
            guard netAmount.isFinite else {
                throw TatumError.invalidResponse
            }
            if abs(netAmount) <= 0.000_000_000_001 {
                return nil
            }
            guard let rawTimestamp = transaction.timestamp ?? transaction.block?.timestamp,
                  let timestamp = normalizedTimestampMilliseconds(rawTimestamp)
            else {
                throw TatumError.invalidResponse
            }
            let isIncoming = netAmount > 0
            return TatumTransaction(
                hash: transaction.hash,
                blockNumber: transaction.block?.number,
                timestamp: timestamp,
                from: isIncoming ? firstInputCounterparty : address,
                to: isIncoming ? address : firstOutputCounterparty,
                gasPrice: transaction.fee,
                chain: "ADA",
                address: address,
                transactionType: "cardano",
                transactionSubtype: isIncoming ? "received" : "sent",
                amount: String(abs(netAmount)),
                counterAddress: isIncoming ? firstInputCounterparty : firstOutputCounterparty
            )
        }
    }
    
    private func fetchSOLTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let signatures = try await fetchSolanaSignatures(address: address, limit: limit)
        return try await Self.collectSolanaTransactionDetails(signatures: signatures) {
            signature in
            try await self.fetchSolanaTransaction(
                signature: signature.signature,
                targetAddress: address
            )
        }
    }

    static func collectSolanaTransactionDetails(
        signatures: [SolanaSignature],
        fetchDetail: (_ signature: SolanaSignature) async throws -> TatumTransaction?
    ) async throws -> [TatumTransaction] {
        var transactions: [TatumTransaction] = []
        for signature in signatures where signature.isSuccess {
            if let transaction = try await fetchDetail(signature) {
                transactions.append(transaction)
            }
        }
        return transactions
    }
    
    private func fetchSolanaSignatures(address: String, limit: Int) async throws -> [SolanaSignature] {
        let pageSize = max(1, min(limit, 1_000))
        return try await Self.collectSolanaSignaturePages(
            pageSize: pageSize,
            maxPages: Self.maximumHistoryPages
        ) { before, requestedPageSize in
            let request = try Self.makeSolanaSignatureRequest(
                address: address,
                limit: requestedPageSize,
                before: before,
                client: self.client
            )
            let (data, _) = try await self.client.performRequest(request)
            let rpcResponse = try Self.decodeProviderResponse(
                SolanaRPCResponse<[SolanaSignature]>.self,
                from: data
            )

            if let error = rpcResponse.error {
                Self.log.error("Solana RPC error: \(error.message)")
                throw TatumError.httpError(error.code)
            }
            guard let result = rpcResponse.result else {
                throw TatumError.invalidResponse
            }
            return result
        }
    }

    static func makeSolanaSignatureRequest(
        address: String,
        limit: Int,
        before: String?,
        client: TatumClient
    ) throws -> URLRequest {
        var options: [String: SolanaRPCValue] = [
            "limit": .int(max(1, min(limit, 1_000))),
            "commitment": .string("confirmed")
        ]
        if let before = normalizedProviderCursor(before) {
            options["before"] = .string(before)
        }
        let params: [SolanaRPCParam] = [
            .string(address),
            .object(options)
        ]
        guard let request = client.createSolanaRPCRequest(
            method: "getSignaturesForAddress",
            params: params
        ) else {
            throw TatumError.invalidURL
        }
        return request
    }

    static func collectSolanaSignaturePages(
        pageSize: Int,
        maxPages: Int,
        fetchPage: (_ before: String?, _ pageSize: Int) async throws -> [SolanaSignature]
    ) async throws -> [SolanaSignature] {
        guard (1...1_000).contains(pageSize), maxPages > 0 else {
            throw TatumError.invalidResponse
        }
        var before: String?
        var followedCursors = Set<String>()
        var ordered: [SolanaSignature] = []
        var bySignature: [String: SolanaSignature] = [:]

        for pageIndex in 0..<maxPages {
            let page = try await fetchPage(before, pageSize)
            guard page.count <= pageSize else { throw TatumError.invalidResponse }
            for signature in page {
                guard !signature.signature.isEmpty else {
                    throw TatumError.invalidResponse
                }
                if let existing = bySignature[signature.signature] {
                    guard existing == signature else {
                        throw TatumError.invalidResponse
                    }
                } else {
                    bySignature[signature.signature] = signature
                    ordered.append(signature)
                }
            }

            guard page.count == pageSize else { return ordered }
            guard let next = normalizedProviderCursor(page.last?.signature),
                  pageIndex + 1 < maxPages,
                  followedCursors.insert(next).inserted
            else {
                throw TatumError.invalidResponse
            }
            before = next
        }
        throw TatumError.invalidResponse
    }
    
    private func fetchSolanaTransaction(signature: String, targetAddress: String) async throws -> TatumTransaction? {
        guard let request = client.createV3Request(path: "/solana/transaction/\(signature)") else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        let transaction = try Self.decodeProviderResponse(
            TatumSOLTransaction.self,
            from: data
        )
        return try Self.normalizeSOLTransaction(
            transaction,
            requestedSignature: signature,
            targetAddress: targetAddress
        )
    }

    static func normalizeSOLTransaction(
        _ transaction: TatumSOLTransaction,
        requestedSignature: String,
        targetAddress: String
    ) throws -> TatumTransaction? {
        guard let meta = transaction.meta else {
            throw TatumError.invalidResponse
        }
        guard meta.isSuccess else { return nil }
        guard transaction.transaction?.signatures?.first == requestedSignature else {
            throw TatumError.invalidResponse
        }
        guard let rawBlockTime = transaction.blockTime,
              let timestamp = normalizedTimestampMilliseconds(rawBlockTime),
              let preBalances = meta.preBalances,
              let postBalances = meta.postBalances,
              let accountKeys = transaction.transaction?.message?.accountKeys,
              preBalances.count == postBalances.count,
              postBalances.count == accountKeys.count,
              let targetIndex = accountKeys.firstIndex(of: targetAddress)
        else {
            throw TatumError.invalidResponse
        }

        let (lamportChange, overflow) = postBalances[targetIndex]
            .subtractingReportingOverflow(preBalances[targetIndex])
        guard !overflow else {
            throw TatumError.invalidResponse
        }
        if lamportChange == 0 { return nil }

        var counterAddress: String?
        for index in accountKeys.indices where index != targetIndex {
            let (change, changeOverflow) = postBalances[index]
                .subtractingReportingOverflow(preBalances[index])
            guard !changeOverflow else {
                throw TatumError.invalidResponse
            }
            if (lamportChange < 0 && change > 0)
                || (lamportChange > 0 && change < 0) {
                counterAddress = accountKeys[index]
                break
            }
        }
        let balanceChange = Double(lamportChange) / 1_000_000_000
        let incoming = balanceChange > 0
        return TatumTransaction(
            hash: requestedSignature,
            timestamp: timestamp,
            from: incoming ? counterAddress : targetAddress,
            to: incoming ? targetAddress : counterAddress,
            gasPrice: meta.fee.map(String.init),
            chain: "SOL",
            address: targetAddress,
            transactionType: "solana",
            transactionSubtype: incoming ? "received" : "sent",
            amount: String(abs(balanceChange)),
            counterAddress: counterAddress
        )
    }
    
    private func fetchALGOTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/algorand/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let transactions = try Self.decodeProviderResponse(
            [TatumALGOTransaction].self,
            from: data
        )
        return try transactions.map { transaction in
            guard let roundTime = transaction.roundTime,
                  let timestamp = Self.normalizedTimestampMilliseconds(roundTime)
            else {
                throw TatumError.invalidResponse
            }
            let amount = transaction.paymentTransaction?.amountValue ?? 0
            return TatumTransaction(
                hash: transaction.id,
                timestamp: timestamp,
                to: transaction.paymentTransaction?.receiver,
                value: String(amount),
                chain: "ALGO",
                address: address,
                transactionType: "payment",
                amount: String(amount)
            )
        }
    }
    
    private func fetchXLMTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/xlm/transaction/account/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let transactions = try Self.decodeProviderResponse(
            [TatumXLMTransaction].self,
            from: data
        )
        return try transactions.map { transaction in
            guard let date = ISO8601DateFormatter().date(from: transaction.createdAt),
                  let timestamp = Self.normalizedTimestampMilliseconds(
                    Int(date.timeIntervalSince1970)
                  )
            else {
                throw TatumError.invalidResponse
            }
            return TatumTransaction(
                hash: transaction.hash,
                timestamp: timestamp,
                from: transaction.sourceAccount,
                value: "0",
                chain: "XLM",
                address: address,
                transactionType: "stellar"
            )
        }
    }
    
}
