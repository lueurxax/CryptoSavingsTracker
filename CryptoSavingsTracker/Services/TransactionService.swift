//
//  TransactionService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import os

// MARK: - Transaction Service
final class TransactionService {
    static let shared = TransactionService()
    
    private let client = TatumClient.shared
    private let chainService = ChainService.shared
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "TransactionService")
    
    private init() {}
    
    // MARK: - Transaction History Fetching
    func fetchTransactionHistory(chainId: String, address: String, limit: Int = 50, forceRefresh: Bool = false) async throws -> [TatumTransaction] {
        print("📜 TransactionService.fetchTransactionHistory called:")
        print("   ChainId: \(chainId)")
        print("   Address: \(address)")
        print("   Limit: \(limit)")
        
        // Check cache first
        let cacheKey = BalanceCacheManager.transactionsCacheKey(chainId: chainId, address: address)
        
        if !forceRefresh {
            if let cachedTransactions = BalanceCacheManager.shared.getCachedTransactions(for: cacheKey) {
                print("✅ Using cached transactions (count: \(cachedTransactions.count))")
                return cachedTransactions
            }
        }
        
        guard let chain = chainService.getChain(by: chainId) else {
            throw TatumError.unsupportedChain(chainId)
        }
        
        let transactions = try await fetchTransactionsForChain(chain: chain, address: address, limit: limit)
        
        // Cache the result
        BalanceCacheManager.shared.cacheTransactions(transactions, for: cacheKey)
        print("💾 Cached \(transactions.count) transactions")
        
        return transactions
    }
    
    private func fetchTransactionsForChain(chain: TatumChain, address: String, limit: Int) async throws -> [TatumTransaction] {
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
            return try await fetchOtherTransactions(chainId: chain.id, address: address, limit: limit)
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
        
        print("📜 Fetching v4 transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let v4Response = try decoder.decode(TatumV4TransactionResponse.self, from: data)
            print("✅ Fetched \(v4Response.result.count) transactions")
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
        let path: String
        
        switch chainId {
        case "BTC":
            path = "/bitcoin/transaction/address/\(address)"
        case "LTC":
            path = "/litecoin/transaction/address/\(address)"
        case "BCH":
            path = "/bcash/transaction/address/\(address)"
        case "DOGE":
            path = "/dogecoin/transaction/address/\(address)"
        default:
            throw TatumError.unsupportedChain(chainId)
        }
        
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: path, queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let utxoTransactions = try decoder.decode([TatumUTXOTransaction].self, from: data)
            // Convert UTXO transactions to standard format
            return utxoTransactions.map { utxoTx in
                TatumTransaction(
                    hash: utxoTx.hash,
                    blockNumber: nil,
                    timestamp: utxoTx.time,
                    from: nil,
                    to: nil,
                    value: nil,
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode UTXO transactions: \(error)")
            return []
        }
    }
    
    // MARK: - Other Chain Transaction Fetching
    private func fetchOtherTransactions(chainId: String, address: String, limit: Int) async throws -> [TatumTransaction] {
        switch chainId {
        case "XRP":
            return try await fetchXRPTransactions(address: address, limit: limit)
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
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/xrp/transaction/account/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let xrpTransactions = try decoder.decode([TatumXRPTransaction].self, from: data)
            return xrpTransactions.map { xrpTx in
                TatumTransaction(
                    hash: xrpTx.hash,
                    blockNumber: nil,
                    timestamp: Int(xrpTx.parsedDate.timeIntervalSince1970),
                    from: xrpTx.source,
                    to: xrpTx.destination,
                    value: String(xrpTx.amountValue),
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode XRP transactions: \(error)")
            return []
        }
    }
    
    private func fetchADATransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createV3Request(path: "/ada/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        print("🔷 Fetching ADA transactions from: \(request.url?.absoluteString ?? "")")
        
        let (data, _) = try await client.performRequest(request)
        
        print("📄 ADA transaction response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
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
                }
                // Check if this address is in outputs (receiving)
                else if let output = adaTx.outputs?.first(where: { $0.address == address }) {
                    transactionValue = output.amountValue // Positive for incoming
                    fromAddress = adaTx.inputs?.first?.address
                    toAddress = address
                }
                
                return TatumTransaction(
                    hash: adaTx.hash,
                    blockNumber: adaTx.block?.number,
                    timestamp: nil, // ADA endpoint doesn't provide timestamp
                    from: fromAddress,
                    to: toAddress,
                    value: String(abs(transactionValue)), // Store absolute value
                    gasUsed: nil,
                    gasPrice: adaTx.fee, // Store fee as gasPrice for reference
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode ADA transactions: \(error)")
            print("❌ ADA transaction decode error: \(error)")
            return []
        }
    }
    
    private func fetchSOLTransactions(address: String, limit: Int) async throws -> [TatumTransaction] {
        let queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        
        guard let request = client.createLegacyRequest(path: "/solana/transaction/address/\(address)", queryItems: queryItems) else {
            throw TatumError.invalidURL
        }
        
        let (data, _) = try await client.performRequest(request)
        
        let decoder = JSONDecoder()
        do {
            let solTransactions = try decoder.decode([TatumSOLTransaction].self, from: data)
            return solTransactions.map { solTx in
                // Calculate balance change from pre/post balances
                let balanceChange = calculateSOLBalanceChange(meta: solTx.meta)
                
                return TatumTransaction(
                    hash: solTx.hash,
                    blockNumber: nil,
                    timestamp: solTx.blockTime,
                    from: nil,
                    to: nil,
                    value: String(balanceChange),
                    gasUsed: nil,
                    gasPrice: nil,
                    tokenTransfers: nil
                )
            }
        } catch {
            Self.log.error("Failed to decode SOL transactions: \(error)")
            return []
        }
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
    
    private func calculateSOLBalanceChange(meta: TatumSOLMeta?) -> Double {
        guard let meta = meta,
              let preBalances = meta.preBalances,
              let postBalances = meta.postBalances,
              preBalances.count > 0,
              postBalances.count > 0 else {
            return 0
        }
        
        let balanceChange = postBalances[0] - preBalances[0]
        return Double(balanceChange) / 1_000_000_000 // Convert lamports to SOL
    }
}