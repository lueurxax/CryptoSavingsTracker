//
//  ChainService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import Combine

// MARK: - Chain Model
struct TatumChain: Codable, Identifiable, Hashable {
    let id: String // Chain slug (ETH, MATIC, BSC, etc.)
    let name: String
    let nativeCurrencySymbol: String
    let chainType: ChainType
    
    enum ChainType: String, Codable {
        case evm = "EVM"
        case utxo = "UTXO"
        case other = "OTHER"
    }
}

// MARK: - Chain Service
final class ChainService {
    static let shared = ChainService()
    
    // Cache for supported chains
    @Published var supportedChains: [TatumChain] = []
    private var cachedChains: [TatumChain]?
    
    init() {
        loadSupportedChains()
    }
    
    // MARK: - Supported Chains (Static List based on Tatum docs)
    private func loadSupportedChains() {
        if let cached = cachedChains {
            supportedChains = cached
            return
        }
        
        // Based on Tatum's supported networks
        let chains = [
            // EVM Chains
            TatumChain(id: "ETH", name: "Ethereum", nativeCurrencySymbol: "ETH", chainType: .evm),
            TatumChain(id: "MATIC", name: "Polygon", nativeCurrencySymbol: "MATIC", chainType: .evm),
            TatumChain(id: "BSC", name: "Binance Smart Chain", nativeCurrencySymbol: "BNB", chainType: .evm),
            TatumChain(id: "AVAX", name: "Avalanche C-Chain", nativeCurrencySymbol: "AVAX", chainType: .evm),
            TatumChain(id: "FTM", name: "Fantom", nativeCurrencySymbol: "FTM", chainType: .evm),
            TatumChain(id: "CELO", name: "Celo", nativeCurrencySymbol: "CELO", chainType: .evm),
            TatumChain(id: "ONE", name: "Harmony", nativeCurrencySymbol: "ONE", chainType: .evm),
            TatumChain(id: "KLAY", name: "Klaytn", nativeCurrencySymbol: "KLAY", chainType: .evm),
            
            // UTXO Chains
            TatumChain(id: "BTC", name: "Bitcoin", nativeCurrencySymbol: "BTC", chainType: .utxo),
            TatumChain(id: "LTC", name: "Litecoin", nativeCurrencySymbol: "LTC", chainType: .utxo),
            TatumChain(id: "BCH", name: "Bitcoin Cash", nativeCurrencySymbol: "BCH", chainType: .utxo),
            TatumChain(id: "DOGE", name: "Dogecoin", nativeCurrencySymbol: "DOGE", chainType: .utxo),
            
            // Other Chains
            TatumChain(id: "XRP", name: "XRP Ledger", nativeCurrencySymbol: "XRP", chainType: .other),
            TatumChain(id: "TRX", name: "Tron", nativeCurrencySymbol: "TRX", chainType: .other),
            TatumChain(id: "ADA", name: "Cardano", nativeCurrencySymbol: "ADA", chainType: .other),
            TatumChain(id: "SOL", name: "Solana", nativeCurrencySymbol: "SOL", chainType: .other),
            TatumChain(id: "ALGO", name: "Algorand", nativeCurrencySymbol: "ALGO", chainType: .other),
            TatumChain(id: "XLM", name: "Stellar", nativeCurrencySymbol: "XLM", chainType: .other)
        ]
        
        supportedChains = chains
        cachedChains = chains
    }
    
    // MARK: - Chain Prediction
    func predictChain(for symbol: String) -> TatumChain? {
        let uppercasedSymbol = symbol.uppercased()
        
        // Direct match for native currencies
        if let chain = supportedChains.first(where: { $0.nativeCurrencySymbol == uppercasedSymbol }) {
            return chain
        }
        
        // Common token mappings
        switch uppercasedSymbol {
        case "USDT", "USDC", "DAI", "WETH", "UNI", "LINK", "AAVE":
            return supportedChains.first { $0.id == "ETH" }
        case "BUSD", "CAKE":
            return supportedChains.first { $0.id == "BSC" }
        case "WMATIC", "QUICK":
            return supportedChains.first { $0.id == "MATIC" }
        default:
            return nil
        }
    }
    
    // MARK: - Chain Lookup
    func getChain(by id: String) -> TatumChain? {
        return supportedChains.first { $0.id == id }
    }
    
    func isChainSupported(_ chainId: String) -> Bool {
        return supportedChains.contains { $0.id == chainId }
    }
    
    // MARK: - V4 API Chain Mapping
    func getV4ChainName(for chainId: String) -> String? {
        switch chainId.uppercased() {
        case "ETH":
            return "ethereum-mainnet"
        case "MATIC":
            return "polygon-mainnet"
        case "BSC":
            return "bsc-mainnet"
        case "AVAX":
            return "avalanche-c-mainnet"
        case "FTM":
            return "fantom-mainnet"
        case "SOL":
            return "solana-mainnet"
        default:
            return nil
        }
    }
    
    func supportsV4API(_ chainId: String) -> Bool {
        return getV4ChainName(for: chainId) != nil
    }
}