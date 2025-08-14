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
    private let rateLimiter = RateLimiter(
        timeInterval: 1.0
    ) // 1 request per 1 seconds
    private let client: TatumClient
    private let chainService: ChainService
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "TransactionService")
    
    init(client: TatumClient, chainService: ChainService) {
        self.client = client
        self.chainService = chainService
    }
    
    // MARK: - Transaction History Fetching
    func fetchTransactionHistory(chainId: String, address: String, currency: String? = nil, limit: Int = 50, forceRefresh: Bool = false) async throws -> [TatumTransaction] {
        Self.log.debug("fetchTransactionHistory called - ChainId: \(chainId), Address: \(address), Limit: \(limit)")
        
        let rateLimitKey = "\(chainId)-\(address)"
        
        let transactions: [TatumTransaction] = try await rateLimiter.execute(key: rateLimitKey) {
            // Check cache first
            let cacheKey = BalanceCacheManager.transactionsCacheKey(chainId: chainId, address: address, currency: currency)
            
            if !forceRefresh {
                if let cachedTransactions = BalanceCacheManager.shared.getCachedTransactions(for: cacheKey) {
                    Self.log.debug("Using cached transactions (count: \(cachedTransactions.count))")
                    return cachedTransactions
                }
            }
            
            guard let chain = self.chainService.getChain(by: chainId) else {
                throw TatumError.unsupportedChain(chainId)
            }
            
            let fetchedTransactions = try await self.fetchTransactionsForChain(chain: chain, address: address, currency: currency, limit: limit)
            
            // Only cache non-empty results, and fall back to cached data if API returns empty
            if !fetchedTransactions.isEmpty {
                BalanceCacheManager.shared.cacheTransactions(fetchedTransactions, for: cacheKey)
                Self.log.debug("Cached \(fetchedTransactions.count) transactions for \(chainId)")
                return fetchedTransactions
            } else {
                // If API returned empty, try to use cached data (even if expired)
                Self.log.info("API returned empty transactions for \(chainId), attempting cache fallback")
                if let cachedTransactions = BalanceCacheManager.shared.getCachedTransactions(for: cacheKey) {
                    Self.log.info("Using fresh cached transactions for \(chainId) (count: \(cachedTransactions.count))")
                    return cachedTransactions
                } else if let anyCachedTransactions = BalanceCacheManager.shared.getAnyTransactions(for: cacheKey) {
                    Self.log.info("Using expired cached transactions for \(chainId) (count: \(anyCachedTransactions.count))")
                    return anyCachedTransactions
                } else {
                    Self.log.info("No cached transactions available for \(chainId)")
                    return []
                }
            }
        }
        return transactions
    }
    
    private func fetchTransactionsForChain(chain: TatumChain, address: String, currency: String?, limit: Int) async throws -> [TatumTransaction] {
        switch chain.chainType {
        case .evm:
            if chainService.supportsV4API(chain.id) {
                return try await fetchV4Transactions(chainId: chain.id, address: address, limit: limit)
            } else {
                return try await fetchEVMTransactions(chainId: chain.id, address: address, limit: limit)
            }
        case .utxo:
            return try await fetchUTXOTransactions(chainId: chain.id, address: address, limit: limit)
        case .other:
            return try await fetchOtherTransactions(chainId: chain.id, address: address, currency: currency, limit: limit)
        }
    }
    
    // MARK: - Tatum v4 Transaction Fetching
    private func fetchV4Transactions(chainId: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        guard let v4Chain = chainService.getV4ChainName(for: chainId) else {
            throw TatumError.unsupportedChain(chainId)
        }
        
        let queryItems = [
            URLQueryItem(name: "chain", value: v4Chain),
            URLQueryItem(name: "addresses", value: address),
            URLQueryItem(name: "sort", value: "DESC"),
            URLQueryItem(name: "pageSize", value: String(limit))
        ]
        
        guard let request = client.createV4Request(path: "/data/transaction/history", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching v4 transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let v4Response = try decoder.decode(TatumV4TransactionResponse.self, from: data)
            Self.log.debug("Fetched \(v4Response.result.count) transactions")
            return v4Response.result
        } catch {
            Self.log.error("Failed to decode v4 transaction response: \(error)")
            throw TatumError.decodingError(error)
        }
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
                return []
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
    
    // Other UTXO chains (LTC, BCH, DOGE) - keep existing logic for now
    private func fetchLegacyUTXOTransactions(chainId: String, path: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createV3Request(path: path, queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching \(chainId) transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("\(chainId) transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        do {
            let utxoTransactions = try decoder.decode([TatumUTXOTransaction].self, from: data)
            // Convert UTXO transactions to standard format with proper data mapping
            return utxoTransactions.map { utxoTx in
                // Calculate net amount for this address
                var netAmount: Double = 0.0
                var fromAddress: String?
                var toAddress: String?
                
                // Sum inputs where this address is spending
                if let inputs = utxoTx.inputs {
                    for input in inputs {
                        if let addresses = input.prevout?.scriptPubKey?.addresses, addresses.contains(address) {
                            if let value = input.prevout?.valueNumber {
                                netAmount -= value / 100_000_000 // Convert satoshis to BTC
                                fromAddress = address
                            }
                        }
                    }
                }
                
                // Sum outputs where this address is receiving
                if let outputs = utxoTx.outputs {
                    for (index, output) in outputs.enumerated() {
                        // Check direct address field first, then scriptPubKey.addresses
                        let outputAddress = output.address ?? output.scriptPubKey?.addresses?.first
                        
                        if let addr = outputAddress, addr == address {
                            let amount = output.humanReadableValue
                            netAmount += amount
                            toAddress = address
                            Self.log.debug("Found receiving output [\(index)]: \(amount) BTC to \(address)")
                        } else if toAddress == nil, let addr = outputAddress {
                            toAddress = addr // Set first output address as destination if not receiving
                        }
                    }
                }
                
                Self.log.debug("Transaction \(utxoTx.hash): netAmount=\(netAmount), from=\(fromAddress ?? "nil"), to=\(toAddress ?? "nil")")
                
                return TatumTransaction(
                    hash: utxoTx.hash,
                    blockNumber: nil,
                    timestamp: utxoTx.time != nil ? utxoTx.time! * 1000 : nil, // Convert seconds to milliseconds
                    from: fromAddress,
                    to: toAddress,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil,
                    chain: chainId,
                    address: address,
                    transactionType: "utxo",
                    transactionSubtype: netAmount >= 0 ? "received" : "sent",
                    amount: String(abs(netAmount)), // UI expects positive amount
                    counterAddress: netAmount >= 0 ? fromAddress : toAddress
                )
            }
        } catch {
            Self.log.error("Failed to decode \(chainId) transactions: \(error)")
            return []
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
        
        let queryItems = [
            URLQueryItem(name: "min", value: "-1"), // Start from newest transactions
            URLQueryItem(name: "pageSize", value: String(limit))
        ]
        
        guard let request = client.createV3Request(path: "/xrp/account/tx/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("XRP transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        do {
            let xrpResponse = try decoder.decode(XRPAccountResponse.self, from: data)
            let xrpTransactions = xrpResponse.transactions
            Self.log.debug("XRP API returned \(xrpTransactions.count) transactions")
            return xrpTransactions.map { xrpTxDetails in
                let xrpTx = xrpTxDetails.tx
                
                // Determine transaction direction and amount sign
                let amountXRP = (Double(xrpTx.amount ?? "0") ?? 0.0) / 1_000_000 // Convert drops to XRP
                let isSending = xrpTx.account == address
                let isReceiving = xrpTx.destination == address
                let signedAmount = isSending ? -amountXRP : amountXRP
                let subtype = isSending ? "sent" : (isReceiving ? "received" : "unknown")
                
                return TatumTransaction(
                    hash: xrpTx.hash,
                    blockNumber: xrpTx.ledgerIndex,
                    timestamp: Int((xrpTx.date + 946684800) * 1000), // Convert XRPL epoch to Unix epoch in milliseconds
                    from: xrpTx.account,
                    to: xrpTx.destination,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: xrpTx.fee, // Fee in drops
                    tokenTransfers: nil,
                    chain: "XRP",
                    address: address,
                    transactionType: xrpTx.transactionType,
                    transactionSubtype: subtype,
                    amount: String(abs(signedAmount)), // UI expects positive amount
                    counterAddress: xrpTx.destination
                )
            }
        } catch {
            Self.log.error("Failed to decode XRP transactions: \(error)")
            return []
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
            // If no currency specified, fetch both (backward compatibility)
            async let nativeTransactions = fetchNativeTRXTransactions(address: address, limit: limit)
            async let trc20Transactions = fetchTRC20Transactions(address: address, currency: nil, limit: limit)
            
            let allTransactions = try await nativeTransactions + trc20Transactions
            
            // Sort by timestamp (newest first), putting transactions without timestamps first
            let sortedTransactions = allTransactions.sorted { tx1, tx2 in
                switch (tx1.timestamp, tx2.timestamp) {
                case (nil, nil):
                    return false // Keep original order if both have no timestamp
                case (nil, _):
                    return true // TRC-20 transactions (no timestamp) come first
                case (_, nil):
                    return false // Native TRX transactions (with timestamp) come after
                case (let time1?, let time2?):
                    return time1 > time2 // Sort by timestamp if both have it
                }
            }
            
            return Array(sortedTransactions.prefix(limit))
        }
    }
    
    private func fetchNativeTRXTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createV3Request(path: "/tron/transaction/account/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching native TRX transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("Native TRX transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        do {
            let trxResponse = try decoder.decode(TRXTransactionResponse.self, from: data)
            return trxResponse.transactions.compactMap { trxTx in
                // Calculate transaction value and determine direction
                var transactionValue: Double = 0.0
                var fromAddress: String?
                var toAddress: String?
                var transactionType = "tron"
                
                // Parse contract data to extract transfer information
                var shouldSkipTransaction = false
                
                if let contracts = trxTx.rawData?.contract {
                    for (index, contract) in contracts.enumerated() {
                        Self.log.debug("TRX contract[\(index)]: type=\(contract.type ?? "nil")")
                        
                        if let contractValue = contract.parameter?.value {
                            Self.log.debug("TRX contract[\(index)] value: owner=\(contractValue.ownerAddressBase58 ?? "nil"), to=\(contractValue.toAddressBase58 ?? "nil"), amount=\(contractValue.amount ?? 0)")
                            
                            switch contract.type {
                            case "TransferContract":
                                // Native TRX transfer - this is what we want
                                transactionValue = contractValue.trxAmount
                                fromAddress = contractValue.ownerAddressBase58
                                toAddress = contractValue.toAddressBase58
                                transactionType = "tron"
                                
                            case "TriggerSmartContract":
                                // Skip ALL TRC20 token transfers - they're handled by the dedicated TRC20 endpoint
                                Self.log.debug("Skipping TriggerSmartContract transaction (TRC-20 token transfer)")
                                shouldSkipTransaction = true
                                break
                                
                            default:
                                Self.log.debug("TRX contract[\(index)]: unknown type \(contract.type ?? "nil")")
                                break
                            }
                        }
                    }
                }
                
                // Skip TRC-20 transactions entirely
                if shouldSkipTransaction {
                    return nil
                }
                
                // Determine transaction direction based on address involvement
                let isReceiving = toAddress == address
                let isSending = fromAddress == address
                
                // For TRX, if we don't have clear direction, check the addresses more carefully
                var finalSubtype = "unknown"
                if isReceiving {
                    finalSubtype = "received"
                } else if isSending {
                    finalSubtype = "sent"
                } else {
                    // The API might return all transactions for an address, so check both directions
                    if let contracts = trxTx.rawData?.contract {
                        for contract in contracts {
                            if let contractValue = contract.parameter?.value {
                                // Check if our target address is the owner (sender)
                                if contractValue.ownerAddressBase58 == address {
                                    finalSubtype = "sent"
                                    break
                                }
                                // Check if our target address is the recipient
                                else if contractValue.toAddressBase58 == address {
                                    finalSubtype = "received"
                                    break
                                }
                            }
                        }
                    }
                }
                
                let subtype = finalSubtype
                
                // Get timestamp from rawData (already in milliseconds)
                let timestamp = trxTx.rawData?.timestamp != nil ? Int(trxTx.rawData!.timestamp!) : nil
                
                Self.log.debug("TRX transaction \(trxTx.hash): value=\(transactionValue), type=\(transactionType), subtype=\(subtype), from=\(fromAddress ?? "nil"), to=\(toAddress ?? "nil"), targetAddress=\(address)")
                
                return TatumTransaction(
                    hash: trxTx.hash,
                    blockNumber: trxTx.blockNumber,
                    timestamp: timestamp,
                    from: fromAddress,
                    to: toAddress,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: trxTx.totalFee > 0 ? String(trxTx.totalFee) : nil,
                    tokenTransfers: nil,
                    chain: "TRX",
                    address: address,
                    transactionType: transactionType,
                    transactionSubtype: subtype,
                    amount: String(transactionValue), // UI expects positive amount
                    counterAddress: isReceiving ? fromAddress : toAddress
                )
            }
        } catch {
            Self.log.error("Failed to decode native TRX transactions: \(error)")
            return []
        }
    }
    
    private func fetchTRC20Transactions(address: String, currency: String? = nil, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createV3Request(path: "/tron/transaction/account/\(address)/trc20", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching TRC-20 transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("TRC-20 transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        do {
            let trc20Response = try decoder.decode(TRC20TransactionResponse.self, from: data)
            let allTransactions = trc20Response.transactions.map { trc20Tx in
                // Determine transaction direction
                let isSending = trc20Tx.from == address
                let isReceiving = trc20Tx.to == address
                let subtype = isSending ? "sent" : (isReceiving ? "received" : "unknown")
                
                // Convert amount based on token decimals from tokenInfo
                let tokenAmount = trc20Tx.tokenAmount
                
                Self.log.debug("TRC-20 transaction \(trc20Tx.txID): token=\(trc20Tx.tokenInfo.symbol), amount=\(tokenAmount), subtype=\(subtype), from=\(trc20Tx.from ?? "nil"), to=\(trc20Tx.to ?? "nil")")
                
                return TatumTransaction(
                    hash: trc20Tx.txID,
                    blockNumber: nil, // TRC-20 endpoint doesn't provide block numbers
                    timestamp: nil, // TRC-20 endpoint doesn't provide timestamps - will use current time for sorting
                    from: trc20Tx.from,
                    to: trc20Tx.to,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil,
                    chain: "TRX",
                    address: address,
                    transactionType: "trc20",
                    transactionSubtype: subtype,
                    amount: String(tokenAmount),
                    counterAddress: isReceiving ? trc20Tx.from : trc20Tx.to
                )
            }
            
            // Filter by currency if specified
            if let currency = currency {
                let filteredTransactions = trc20Response.transactions.compactMap { trc20Tx -> TatumTransaction? in
                    // Check if this transaction is for the specified token symbol
                    guard trc20Tx.tokenInfo.symbol.uppercased() == currency.uppercased() else {
                        return nil
                    }
                    
                    // Determine transaction direction
                    let isSending = trc20Tx.from == address
                    let isReceiving = trc20Tx.to == address
                    let subtype = isSending ? "sent" : (isReceiving ? "received" : "unknown")
                    
                    // Convert amount based on token decimals from tokenInfo
                    let tokenAmount = trc20Tx.tokenAmount
                    
                    Self.log.debug("TRC-20 transaction \(trc20Tx.txID): token=\(trc20Tx.tokenInfo.symbol), amount=\(tokenAmount), subtype=\(subtype), from=\(trc20Tx.from ?? "nil"), to=\(trc20Tx.to ?? "nil")")
                    
                    return TatumTransaction(
                        hash: trc20Tx.txID,
                        blockNumber: nil,
                        timestamp: nil,
                        from: trc20Tx.from,
                        to: trc20Tx.to,
                        value: nil,
                        gasUsed: nil,
                        gasPrice: nil,
                        tokenTransfers: nil,
                        chain: "TRX",
                        address: address,
                        transactionType: "trc20",
                        transactionSubtype: subtype,
                        amount: String(tokenAmount),
                        counterAddress: isReceiving ? trc20Tx.from : trc20Tx.to
                    )
                }
                Self.log.debug("Filtered TRC-20 transactions for \(currency): \(filteredTransactions.count) out of \(trc20Response.transactions.count)")
                return filteredTransactions
            }
            
            return allTransactions
        } catch {
            Self.log.error("Failed to decode TRC-20 transactions: \(error)")
            return []
        }
    }
    
    private func fetchADATransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createV3Request(path: "/ada/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching ADA transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("ADA transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        do {
            let adaTransactions = try decoder.decode([TatumADATransaction].self, from: data)
            return adaTransactions.map { adaTx in
                // Calculate value for this specific address
                var transactionValue: Double = 0
                var fromAddress: String? = nil
                var toAddress: String? = nil
                
                // Check if this address is in inputs (sending)
                if let input = adaTx.inputs?.first(where: { $0.address == address }) {
                    transactionValue = -input.amountValue // Negative for outgoing
                    fromAddress = address
                    toAddress = adaTx.outputs?.first?.address
                    Self.log.debug("ADA transaction \(adaTx.hash): Found in inputs, sending \(abs(transactionValue)) ADA")
                }
                // Check if this address is in outputs (receiving)
                else if let output = adaTx.outputs?.first(where: { $0.address == address }) {
                    transactionValue = output.amountValue // Positive for incoming
                    fromAddress = adaTx.inputs?.first?.address
                    toAddress = address
                    Self.log.debug("ADA transaction \(adaTx.hash): Found in outputs, receiving \(transactionValue) ADA")
                }
                
                Self.log.debug("ADA transaction \(adaTx.hash): finalValue=\(transactionValue), from=\(fromAddress ?? "nil"), to=\(toAddress ?? "nil")")
                
                return TatumTransaction(
                    hash: adaTx.hash,
                    blockNumber: adaTx.block?.number,
                    timestamp: nil, // ADA endpoint doesn't provide timestamp
                    from: fromAddress,
                    to: toAddress,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: adaTx.fee, // Store fee as gasPrice for reference
                    tokenTransfers: nil,
                    chain: "ADA",
                    address: address,
                    transactionType: "cardano",
                    transactionSubtype: transactionValue >= 0 ? "received" : "sent",
                    amount: String(abs(transactionValue)), // UI expects positive amount
                    counterAddress: transactionValue >= 0 ? fromAddress : toAddress
                )
            }
        } catch {
            Self.log.error("Failed to decode ADA transactions: \(error)")
            return []
        }
    }
    
    private func fetchSOLTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        Self.log.debug("Fetching SOL transactions using two-step process: 1) Get signatures, 2) Fetch transactions")
        
        // Step 1: Get signatures from Solana RPC
        let signatures = try await fetchSolanaSignatures(address: address, limit: limit)
        Self.log.debug("Found \(signatures.count) SOL signatures")
        
        // Step 2: Fetch transaction details for each signature
        var transactions: [TatumTransaction] = []
        
        for signature in signatures.prefix(limit) {
            do {
                if let transaction = try await fetchSolanaTransaction(signature: signature.signature, targetAddress: address) {
                    transactions.append(transaction)
                }
            } catch {
                Self.log.error("Failed to fetch SOL transaction \(signature.signature): \(error)")
                // Continue with other transactions
            }
        }
        
        Self.log.debug("Successfully fetched \(transactions.count) SOL transactions")
        return transactions
    }
    
    private func fetchSolanaSignatures(address: String, limit: Int) async throws -> [SolanaSignature] {
        let params: [SolanaRPCParam] = [
            .string(address),
            .object([
                "limit": .int(limit),
                "commitment": .string("confirmed")
            ])
        ]
        
        guard let request = client.createSolanaRPCRequest(method: "getSignaturesForAddress", params: params) else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching Solana signatures for address: \(address)")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("Solana signatures response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let rpcResponse = try decoder.decode(SolanaRPCResponse<[SolanaSignature]>.self, from: data)
        
        if let error = rpcResponse.error {
            Self.log.error("Solana RPC error: \(error.message)")
            throw TatumError.httpError(error.code)
        }
        
        return rpcResponse.result ?? []
    }
    
    private func fetchSolanaTransaction(signature: String, targetAddress: String) async throws -> TatumTransaction? {
        guard let request = client.createV3Request(path: "/solana/transaction/\(signature)") else {
            throw TatumError.invalidURL
        }
        
        Self.log.debug("Fetching Solana transaction: \(signature)")
        
        let (data, _) = try await client.performRequest(request)
        
        Self.log.debug("Solana transaction response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        let decoder = JSONDecoder()
        let solTx = try decoder.decode(TatumSOLTransaction.self, from: data)
        
        // Skip failed transactions
        guard solTx.meta?.isSuccess == true else {
            Self.log.debug("Skipping failed transaction: \(signature)")
            return nil
        }
        
        // Calculate balance change for the target address
        let balanceChange = calculateSOLBalanceChange(transaction: solTx, targetAddress: targetAddress)
        
        Self.log.debug("SOL transaction \(signature): balanceChange=\(balanceChange), direction=\(balanceChange > 0 ? "received" : "sent")")
        
        // Skip transactions with no balance change for this address
        guard balanceChange != 0.0 else {
            Self.log.debug("Skipping transaction with no balance change: \(signature)")
            return nil
        }
        
        // For sent transactions, try to find the recipient address
        var recipientAddress: String? = nil
        if balanceChange < 0, let accountKeys = solTx.transaction?.message?.accountKeys, let postBalances = solTx.meta?.postBalances {
            // Find target address index
            let targetIndex = accountKeys.firstIndex(of: targetAddress) ?? 0
            
            // Look for an account that gained balance (excluding fee accounts)
            for (index, postBal) in postBalances.enumerated() {
                if index != targetIndex && index < accountKeys.count && postBal > 0 {
                    // This account received funds
                    recipientAddress = accountKeys[index]
                    break
                }
            }
        }
        
        Self.log.debug("SOL transaction \(signature): balanceChange=\(balanceChange), subtype=\(balanceChange > 0 ? "received" : "sent"), storedAmount=\(String(abs(balanceChange))), from=\(balanceChange < 0 ? targetAddress : "nil"), to=\(balanceChange > 0 ? targetAddress : recipientAddress ?? "nil")")
        
        return TatumTransaction(
            hash: solTx.hash,
            blockNumber: nil,
            timestamp: solTx.blockTime != nil ? solTx.blockTime! * 1000 : nil, // Convert to milliseconds
            from: balanceChange < 0 ? targetAddress : nil, // If negative, we sent
            to: balanceChange > 0 ? targetAddress : recipientAddress,   // If positive, we received; if negative, try to find recipient
            value: nil,
            gasUsed: nil,
            gasPrice: solTx.meta?.fee != nil ? String(solTx.meta!.fee!) : nil,
            tokenTransfers: nil,
            chain: "SOL",
            address: targetAddress,
            transactionType: "solana",
            transactionSubtype: balanceChange > 0 ? "received" : "sent",
            amount: String(abs(balanceChange)), // UI likely expects positive amount with subtype for direction
            counterAddress: balanceChange > 0 ? nil : recipientAddress // For sent transactions, store recipient
        )
    }
    
    private func calculateSOLBalanceChange(transaction: TatumSOLTransaction, targetAddress: String) -> Double {
        guard let meta = transaction.meta,
              let preBalances = meta.preBalances,
              let postBalances = meta.postBalances,
              let accountKeys = transaction.transaction?.message?.accountKeys else {
            Self.log.debug("Missing required data for balance calculation")
            return 0.0
        }
        
        // Find the index of the target address in account keys
        guard let addressIndex = accountKeys.firstIndex(of: targetAddress) else {
            Self.log.debug("Target address not found in account keys")
            return 0.0
        }
        
        // Ensure we have balance data for this index
        guard addressIndex < preBalances.count && addressIndex < postBalances.count else {
            Self.log.debug("Balance index out of range")
            return 0.0
        }
        
        let preBalance = preBalances[addressIndex]
        let postBalance = postBalances[addressIndex]
        let balanceChange = postBalance - preBalance
        
        // Convert lamports to SOL
        let solChange = Double(balanceChange) / 1_000_000_000.0
        
        Self.log.debug("SOL balance change for \(targetAddress): \(solChange) SOL (\(balanceChange) lamports), preBalance=\(preBalance), postBalance=\(postBalance), addressIndex=\(addressIndex)")
        
        return solChange
    }
    
    private func fetchALGOTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/algorand/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let algoTransactions = try decoder.decode([TatumALGOTransaction].self, from: data)
            return algoTransactions.map { algoTx in
                let amount = algoTx.paymentTransaction?.amountValue ?? 0
                
                return TatumTransaction(
                    hash: algoTx.id,
                    blockNumber: nil,
                    timestamp: Int(algoTx.date.timeIntervalSince1970),
                    from: nil,
                    to: algoTx.paymentTransaction?.receiver,
                    value: String(amount),
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode ALGO transactions: \(error)")
            return []
        }
    }
    
    private func fetchXLMTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/xlm/transaction/account/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let xlmTransactions = try decoder.decode([TatumXLMTransaction].self, from: data)
            return xlmTransactions.map { xlmTx in
                TatumTransaction(
                    hash: xlmTx.hash,
                    blockNumber: nil,
                    timestamp: Int(xlmTx.date.timeIntervalSince1970),
                    from: xlmTx.sourceAccount,
                    to: nil,
                    value: "0", // XLM transactions need operation-level parsing for amounts
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode XLM transactions: \(error)")
            return []
        }
    }
    
}
