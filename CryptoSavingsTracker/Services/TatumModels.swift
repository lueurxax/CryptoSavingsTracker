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

// Tatum v4 API UTXO Response Models
struct TatumV4UTXOResponse: Codable {
    let result: [TatumV4UTXOItem]
    let prevPage: String?
    let nextPage: String?
}

struct TatumV4UTXOItem: Codable {
    let txHash: String
    let index: Int
    let valueString: String  // Value in satoshis as string
    let address: String
    let blockNumber: Int?
    let spent: Bool
    
    var value: Double {
        return Double(valueString) ?? 0.0
    }
    
    enum CodingKeys: String, CodingKey {
        case txHash = "hash"
        case index
        case valueString = "value"
        case address, blockNumber, spent
    }
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
    let valueNumber: Double?
    let address: String?  // Direct address field
    let scriptPubKey: TatumScriptPubKey?
    
    var humanReadableValue: Double {
        guard let value = valueNumber else { return 0 }
        return value / 100_000_000 // Convert satoshis to BTC
    }
    
    enum CodingKeys: String, CodingKey {
        case valueNumber = "value"
        case address
        case scriptPubKey
    }
}

struct TatumUTXOPrevout: Codable {
    let valueNumber: Double?
    let scriptPubKey: TatumScriptPubKey?
    
    enum CodingKeys: String, CodingKey {
        case valueNumber = "value"
        case scriptPubKey
    }
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

// XRP Balance Response Model (v3 API)
struct TatumXRPBalanceResponse: Codable {
    let balance: String  // Balance in drops (1 XRP = 1,000,000 drops)
    let assets: [String]  // Additional assets (usually empty)
    
    var balanceInXRP: Double {
        guard let drops = Double(balance) else { return 0.0 }
        return drops / 1_000_000  // Convert drops to XRP
    }
}

// XRP Account Transaction Response Models (v3 API)
struct XRPAccountResponse: Codable {
    let account: String
    let ledgerIndexMax: Int
    let ledgerIndexMin: Int
    let limit: Int? // Made optional as it might not always be present
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

// MARK: - TRX Transaction Models
struct TRXTransactionResponse: Codable {
    let transactions: [TRXTransaction]
    let internalTransactions: [TRXInternalTransaction]?
}

struct TRXTransaction: Codable, Identifiable {
    let txID: String
    let blockNumber: Int?
    let ret: [TRXTransactionResult]?
    let signature: [String]?
    let netFee: Int64?
    let netUsage: Int64?
    let energyFee: Int64?
    let energyUsage: Int64?
    let energyUsageTotal: Int64?
    let rawData: TRXRawData?
    let internalTransactions: [TRXInternalTransaction]?
    
    var id: String { txID }
    var hash: String { txID }
    
    var date: Date {
        if let timestamp = rawData?.timestamp {
            return Date(timeIntervalSince1970: TimeInterval(timestamp / 1000)) // Convert ms to seconds
        }
        return Date()
    }
    
    var totalFee: Double {
        let net = Double(netFee ?? 0)
        let energy = Double(energyFee ?? 0)
        return (net + energy) / 1_000_000 // Convert sun to TRX
    }
}

struct TRXTransactionResult: Codable {
    let contractRet: String?
    let fee: Int64?
}

struct TRXRawData: Codable {
    let contract: [TRXContract]?
    let timestamp: Int64?
    let expiration: Int64?
    let refBlockBytes: String?
    let refBlockHash: String?
    let feeLimit: Int64?
    
    enum CodingKeys: String, CodingKey {
        case contract, timestamp, expiration, feeLimit
        case refBlockBytes = "ref_block_bytes"
        case refBlockHash = "ref_block_hash"
    }
}

struct TRXContract: Codable {
    let type: String?
    let parameter: TRXContractParameter?
}

struct TRXContractParameter: Codable {
    let value: TRXContractValue?
    let typeUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case value
        case typeUrl = "type_url"
    }
}

struct TRXContractValue: Codable {
    // For TransferContract (native TRX transfers)
    let amount: Int64?
    let ownerAddress: String?
    let toAddress: String?
    let ownerAddressBase58: String?
    let toAddressBase58: String?
    
    // For TriggerSmartContract (TRC20 transfers)
    let contractAddress: String?
    let contractAddressBase58: String?
    let data: String?
    
    enum CodingKeys: String, CodingKey {
        case amount
        case ownerAddress = "owner_address"
        case toAddress = "to_address"
        case ownerAddressBase58
        case toAddressBase58
        case contractAddress = "contract_address"
        case contractAddressBase58
        case data
    }
    
    // Convert sun to TRX for native transfers
    var trxAmount: Double {
        guard let amount = amount else { return 0.0 }
        return Double(amount) / 1_000_000
    }
}

struct TRXInternalTransaction: Codable {
    let hash: String?
    let callerAddress: String?
    let transferToAddress: String?
    let callValueInfo: [TRXCallValueInfo]?
    let note: String?
}

struct TRXCallValueInfo: Codable {
    let callValue: Int64?
    let tokenName: String?
    let tokenId: String?
    
    var trxValue: Double {
        guard let value = callValue else { return 0.0 }
        return Double(value) / 1_000_000 // Convert sun to TRX
    }
}

// MARK: - TRC-20 Transaction Models
struct TRC20TransactionResponse: Codable {
    let transactions: [TRC20Transaction]
}

struct TRC20Transaction: Codable, Identifiable {
    let txID: String
    let tokenInfo: TRC20TokenInfo
    let from: String?
    let to: String?
    let type: String?
    let value: String
    
    var id: String { txID }
    
    // Convert token amount based on decimals from tokenInfo
    var tokenAmount: Double {
        guard let amountValue = Double(value) else { return 0.0 }
        let decimals = tokenInfo.decimals
        return amountValue / pow(10, Double(decimals))
    }
    
    // Check if this is USDT
    var isUSDT: Bool {
        return tokenInfo.address == "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    }
}

struct TRC20TokenInfo: Codable {
    let symbol: String
    let address: String
    let decimals: Int
    let name: String
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

// MARK: - SOL (Solana) Balance Models
struct TatumSOLBalanceResponse: Codable {
    let balance: String  // Balance is already in SOL, not lamports
    
    var solBalance: Double {
        return Double(balance) ?? 0.0
    }
}

// MARK: - Solana RPC Models
struct SolanaRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: [SolanaRPCParam]
}

enum SolanaRPCParam: Codable {
    case string(String)
    case object([String: SolanaRPCValue])
    case int(Int)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: SolanaRPCValue].self) {
            self = .object(objectValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            throw DecodingError.typeMismatch(SolanaRPCParam.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid SolanaRPCParam"))
        }
    }
}

enum SolanaRPCValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else {
            throw DecodingError.typeMismatch(SolanaRPCValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid SolanaRPCValue"))
        }
    }
}

struct SolanaRPCResponse<T: Codable>: Codable {
    let jsonrpc: String
    let id: Int
    let result: T?
    let error: SolanaRPCError?
}

struct SolanaRPCError: Codable {
    let code: Int
    let message: String
    let data: SolanaRPCErrorData?
}

struct SolanaRPCErrorData: Codable {
    let logs: [String]?
}

struct SolanaSignature: Codable {
    let signature: String
    let slot: Int?
    let err: SolanaTransactionError?
    let memo: String?
    let blockTime: Int?
    
    var isSuccess: Bool {
        return err == nil
    }
}

enum SolanaTransactionError: Codable {
    case object([String: SolanaRPCValue])
    case null
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let objectValue = try? container.decode([String: SolanaRPCValue].self) {
            self = .object(objectValue)
        } else {
            self = .null
        }
    }
}

struct TatumSOLTransaction: Codable, Identifiable {
    let blockTime: Int?
    let meta: TatumSOLMeta?
    let transaction: TatumSOLTransactionData?
    
    var id: String { 
        return transaction?.signatures?.first ?? "unknown"
    }
    
    var hash: String {
        return transaction?.signatures?.first ?? "unknown"
    }
    
    var date: Date {
        if let blockTime = blockTime {
            return Date(timeIntervalSince1970: TimeInterval(blockTime))
        }
        return Date()
    }
}

struct TatumSOLTransactionData: Codable {
    let signatures: [String]?
    let message: TatumSOLMessage?
}

struct TatumSOLMessage: Codable {
    let accountKeys: [String]?
    let instructions: [TatumSOLInstruction]?
}

struct TatumSOLInstruction: Codable {
    let programIdIndex: Int?
    let accounts: [Int]?
    let data: String?
}

struct TatumSOLMeta: Codable {
    let fee: Int?
    let preBalances: [Int]?
    let postBalances: [Int]?
    let err: SolanaTransactionError?
    
    var isSuccess: Bool {
        return err == nil
    }
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