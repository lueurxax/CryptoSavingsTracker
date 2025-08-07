//
//  TatumModels.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation

// MARK: - Balance Models
struct TatumTokenBalance: Codable {
    let balance: String
    let tokenAddress: String?
    let tokenName: String?
    let tokenSymbol: String?
    let tokenDecimals: Int?
    
    var isNativeBalance: Bool {
        return tokenAddress == nil
    }
    
    var humanReadableBalance: Double {
        guard let balanceValue = Double(balance) else { return 0 }
        let decimals = tokenDecimals ?? 18
        return balanceValue / pow(10, Double(decimals))
    }
}

struct TatumNativeBalance: Codable {
    let balance: String
    
    var humanReadableBalance: Double {
        guard let balanceValue = Double(balance) else { return 0 }
        return balanceValue / pow(10, 18) // Most native tokens use 18 decimals
    }
}

// MARK: - UTXO Balance Models
struct TatumUTXOBalance: Codable {
    let incoming: String
    let outgoing: String
    let incomingPending: String
    let outgoingPending: String
    
    var netBalance: Double {
        let incomingValue = Double(incoming) ?? 0
        let outgoingValue = Double(outgoing) ?? 0
        let incomingPendingValue = Double(incomingPending) ?? 0
        let outgoingPendingValue = Double(outgoingPending) ?? 0
        
        // Net balance = (incoming + incoming pending) - (outgoing + outgoing pending)
        return (incomingValue + incomingPendingValue) - (outgoingValue + outgoingPendingValue)
    }
    
    var confirmedBalance: Double {
        let incomingValue = Double(incoming) ?? 0
        let outgoingValue = Double(outgoing) ?? 0
        
        // Confirmed balance = incoming - outgoing (excluding pending)
        return incomingValue - outgoingValue
    }
}

// Tatum v4 API Portfolio Response Models
struct TatumV4PortfolioResponse: Codable {
    let result: [TatumV4BalanceItem]
    let prevPage: String?
    let nextPage: String?
}

struct TatumV4BalanceItem: Codable {
    let chain: String
    let address: String
    let balance: String // Human readable balance
    let denominatedBalance: String // Raw balance with decimals
    let decimals: Int
    let type: String // "native" or "fungible"
    let tokenAddress: String?
    let tokenName: String?
    let tokenSymbol: String?
}

// MARK: - API Response Models
struct TatumBalanceResponse: Codable {
    let balance: String
    let tokenAddress: String?
    let tokenName: String?
    let tokenSymbol: String?
    let tokenDecimals: Int?
}

struct TatumTokenBalancesResponse: Codable {
    let balances: [TatumBalanceResponse]
}

// MARK: - Transaction Models
struct TatumTransaction: Codable, Identifiable {
    let hash: String
    let blockNumber: Int?
    let timestamp: Int?
    let from: String?
    let to: String?
    let value: String?
    let gasUsed: String?
    let gasPrice: String?
    let tokenTransfers: [TatumTokenTransfer]?
    
    // Tatum v4 API specific fields
    let chain: String?
    let address: String?
    let transactionType: String?
    let transactionSubtype: String?
    let amount: String?
    let counterAddress: String?
    
    init(hash: String, blockNumber: Int? = nil, timestamp: Int? = nil, from: String? = nil, to: String? = nil, value: String? = nil, gasUsed: String? = nil, gasPrice: String? = nil, tokenTransfers: [TatumTokenTransfer]? = nil, chain: String? = nil, address: String? = nil, transactionType: String? = nil, transactionSubtype: String? = nil, amount: String? = nil, counterAddress: String? = nil) {
        self.hash = hash
        self.blockNumber = blockNumber
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.value = value
        self.gasUsed = gasUsed
        self.gasPrice = gasPrice
        self.tokenTransfers = tokenTransfers
        self.chain = chain
        self.address = address
        self.transactionType = transactionType
        self.transactionSubtype = transactionSubtype
        self.amount = amount
        self.counterAddress = counterAddress
    }
    
    var id: String { hash }
    
    var date: Date {
        if let timestamp = timestamp {
            // Tatum v4 returns timestamp in milliseconds
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        }
        return Date()
    }
    
    var nativeValue: Double {
        // Try v4 API amount field first, then fall back to value field
        if let amount = amount, let amountDouble = Double(amount) {
            return amountDouble
        } else if let value = value, let valueDouble = Double(value) {
            return valueDouble / pow(10, 18)
        }
        return 0
    }
}

struct TatumTokenTransfer: Codable {
    let from: String?
    let to: String?
    let value: String?
    let tokenAddress: String?
    let tokenSymbol: String?
    let tokenName: String?
    let tokenDecimals: Int?
    
    var humanReadableValue: Double {
        guard let value = value, let valueDouble = Double(value) else { return 0 }
        let decimals = tokenDecimals ?? 18
        return valueDouble / pow(10, Double(decimals))
    }
}

struct TatumTransactionResponse: Codable {
    let transactions: [TatumTransaction]
}

// Tatum v4 API response wrapper
struct TatumV4TransactionResponse: Codable {
    let result: [TatumTransaction]
    let prevPage: String?
    let nextPage: String?
}

// MARK: - UTXO Transaction Models
struct TatumUTXOTransaction: Codable, Identifiable {
    let hash: String
    let time: Int?
    let inputs: [TatumUTXOInput]?
    let outputs: [TatumUTXOOutput]?
    
    var id: String { hash }
    
    var date: Date {
        if let time = time {
            return Date(timeIntervalSince1970: TimeInterval(time))
        }
        return Date()
    }
}

struct TatumUTXOInput: Codable {
    let prevout: TatumUTXOPrevout?
}

struct TatumUTXOOutput: Codable {
    let value: String?
    let scriptPubKey: TatumScriptPubKey?
    
    var humanReadableValue: Double {
        guard let value = value, let valueDouble = Double(value) else { return 0 }
        return valueDouble / 100000000 // Convert satoshis to BTC
    }
}

struct TatumUTXOPrevout: Codable {
    let value: String?
    let scriptPubKey: TatumScriptPubKey?
}

struct TatumScriptPubKey: Codable {
    let addresses: [String]?
}

// MARK: - XRP Transaction Models
struct TatumXRPTransaction: Codable, Identifiable {
    let hash: String
    let date: String
    let amount: String?
    let fee: String?
    let destination: String?
    let source: String?
    
    var id: String { hash }
    
    var parsedDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: date) ?? Date()
    }
    
    var amountValue: Double {
        guard let amount = amount, let value = Double(amount) else { return 0 }
        return value / 1_000_000 // XRP uses 6 decimal places (drops to XRP)
    }
}

// XRP Account Transaction Response Models (v3 API)
struct XRPAccountResponse: Codable {
    let account: String
    let ledgerIndexMax: Int
    let ledgerIndexMin: Int
    let limit: Int
    let transactions: [XRPTransactionDetails]
    let validated: Bool
    
    enum CodingKeys: String, CodingKey {
        case account
        case ledgerIndexMax = "ledger_index_max"
        case ledgerIndexMin = "ledger_index_min"
        case limit, transactions, validated
    }
}

struct XRPTransactionDetails: Codable {
    let meta: XRPTransactionMeta
    let tx: XRPTransaction
    let validated: Bool
}

struct XRPTransactionMeta: Codable {
    let affectedNodes: [XRPAffectedNode]
    let transactionIndex: Int
    let transactionResult: String
    let deliveredAmount: String?
    
    enum CodingKeys: String, CodingKey {
        case affectedNodes = "AffectedNodes"
        case transactionIndex = "TransactionIndex"
        case transactionResult = "TransactionResult"
        case deliveredAmount = "delivered_amount"
    }
}

struct XRPAffectedNode: Codable {
    let modifiedNode: XRPModifiedNode?
    let createdNode: XRPCreatedNode?
    
    enum CodingKeys: String, CodingKey {
        case modifiedNode = "ModifiedNode"
        case createdNode = "CreatedNode"
    }
}

struct XRPModifiedNode: Codable {
    let finalFields: XRPAccountFields
    let ledgerEntryType: String
    let ledgerIndex: String
    let previousFields: XRPAccountFields?
    
    enum CodingKeys: String, CodingKey {
        case finalFields = "FinalFields"
        case ledgerEntryType = "LedgerEntryType"
        case ledgerIndex = "LedgerIndex"
        case previousFields = "PreviousFields"
    }
}

struct XRPCreatedNode: Codable {
    let ledgerEntryType: String
    let ledgerIndex: String
    let newFields: XRPAccountFields
    
    enum CodingKeys: String, CodingKey {
        case ledgerEntryType = "LedgerEntryType"
        case ledgerIndex = "LedgerIndex"
        case newFields = "NewFields"
    }
}

struct XRPAccountFields: Codable {
    let account: String?
    let balance: String
    let flags: Int?
    let ownerCount: Int?
    let sequence: Int?
    
    enum CodingKeys: String, CodingKey {
        case account = "Account"
        case balance = "Balance"
        case flags = "Flags"
        case ownerCount = "OwnerCount"
        case sequence = "Sequence"
    }
}

struct XRPTransaction: Codable {
    let account: String
    let amount: String?
    let deliverMax: String?
    let destination: String?
    let fee: String
    let flags: Int
    let sequence: Int
    let transactionType: String
    let date: Int
    let hash: String
    let ledgerIndex: Int
    
    enum CodingKeys: String, CodingKey {
        case account = "Account"
        case amount = "Amount"
        case deliverMax = "DeliverMax"
        case destination = "Destination"
        case fee = "Fee"
        case flags = "Flags"
        case sequence = "Sequence"
        case transactionType = "TransactionType"
        case date, hash
        case ledgerIndex = "ledger_index"
    }
}

// MARK: - TRX Transaction Models
// TRX Account Response Models (v3 API)
struct TRXAccountResponse: Codable {
    let balance: Int64
    let createTime: Int64
    let trc10: TRC10Response // Can be either empty array or dictionary
    let trc20: TRC20Response // Array of token objects
    
    var balanceTRX: Double {
        return Double(balance) / 1_000_000 // Convert sun to TRX
    }
    
    // Hardcoded contract addresses for popular TRC20 tokens
    static let tokenContracts: [String: String] = [
        "USDT": "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    ]
    
    func getTokenBalance(symbol: String) -> Double {
        // Check if it's a known TRC20 token
        if let contractAddress = Self.tokenContracts[symbol.uppercased()],
           let balanceString = trc20.getBalance(for: contractAddress),
           let balance = Double(balanceString) {
            // USDT on Tron uses 6 decimals
            return balance / 1_000_000
        }
        
        // Check TRC10 tokens by symbol (though rare)
        if let balanceString = trc10.tokens[symbol.uppercased()],
           let balance = Double(balanceString) {
            return balance / 1_000_000 // Most TRC tokens use 6 decimals
        }
        
        return 0.0
    }
}

// Helper type to handle trc10 field that can be either an empty array or a dictionary
struct TRC10Response: Codable {
    let tokens: [String: String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as dictionary first
        if let dict = try? container.decode([String: String].self) {
            self.tokens = dict
        } else {
            // If decoding as dictionary fails (likely an array), treat as empty tokens
            self.tokens = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if tokens.isEmpty {
            try container.encode([String]()) // Encode as empty array if no tokens
        } else {
            try container.encode(tokens)
        }
    }
}

// Helper type to handle trc20 field that is an array of token objects
struct TRC20Response: Codable {
    let tokenBalances: [[String: String]]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Decode as array of dictionaries
        if let array = try? container.decode([[String: String]].self) {
            self.tokenBalances = array
        } else {
            // Default to empty if decoding fails
            self.tokenBalances = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tokenBalances)
    }
    
    // Helper method to get balance for a specific contract address
    func getBalance(for contractAddress: String) -> String? {
        for tokenDict in tokenBalances {
            if let balance = tokenDict[contractAddress] {
                return balance
            }
        }
        return nil
    }
}

// MARK: - Other Chain Transaction Models
// MARK: - ADA (Cardano) Models
struct TatumADABalanceResponse: Codable {
    let value: String
    let currency: TatumADACurrency
    
    var humanReadableBalance: Double {
        guard let balanceValue = Double(value) else { return 0 }
        return balanceValue / pow(10, Double(currency.decimals))
    }
}

struct TatumADACurrency: Codable {
    let symbol: String
    let decimals: Int
}

struct TatumADATransaction: Codable, Identifiable {
    let hash: String
    let block: TatumADABlock?
    let inputs: [TatumADAInput]?
    let outputs: [TatumADAOutput]?
    let fee: String?
    
    var id: String { hash }
    
    var date: Date {
        // ADA transactions don't include timestamp in this endpoint
        // We could potentially derive from block info if available
        return Date()
    }
    
    var feeValue: Double {
        guard let fee = fee, let feeDouble = Double(fee) else { return 0 }
        return feeDouble / 1_000_000 // Convert lovelace to ADA
    }
}

struct TatumADABlock: Codable {
    let hash: String
    let number: Int
}

struct TatumADAInput: Codable {
    let address: String?
    let symbol: String?
    let value: String?
    let txHash: String?
    
    var amountValue: Double {
        guard let value = value, let val = Double(value) else { return 0 }
        return val / 1_000_000 // Convert lovelace to ADA
    }
}

struct TatumADAOutput: Codable {
    let address: String?
    let symbol: String?
    let value: String?
    let index: Int?
    let txHash: String?
    
    var amountValue: Double {
        guard let value = value, let val = Double(value) else { return 0 }
        return val / 1_000_000 // Convert lovelace to ADA
    }
}

struct TatumSOLTransaction: Codable, Identifiable {
    let hash: String
    let blockTime: Int?
    let meta: TatumSOLMeta?
    
    var id: String { hash }
    
    var date: Date {
        if let blockTime = blockTime {
            return Date(timeIntervalSince1970: TimeInterval(blockTime))
        }
        return Date()
    }
}

struct TatumSOLMeta: Codable {
    let fee: Int?
    let preBalances: [Int]?
    let postBalances: [Int]?
}

struct TatumALGOTransaction: Codable, Identifiable {
    let id: String
    let roundTime: Int?
    let paymentTransaction: TatumALGOPayment?
    
    var date: Date {
        if let roundTime = roundTime {
            return Date(timeIntervalSince1970: TimeInterval(roundTime))
        }
        return Date()
    }
}

struct TatumALGOPayment: Codable {
    let amount: Int?
    let receiver: String?
    
    var amountValue: Double {
        guard let amount = amount else { return 0 }
        return Double(amount) / 1_000_000 // ALGO uses 6 decimal places (microAlgos to ALGO)
    }
}

struct TatumXLMTransaction: Codable, Identifiable {
    let hash: String
    let createdAt: String
    let sourceAccount: String?
    let operationCount: Int?
    
    var id: String { hash }
    
    var date: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: createdAt) ?? Date()
    }
}