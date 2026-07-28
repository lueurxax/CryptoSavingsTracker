//
//  TatumModels.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation

private func humanReadableTatumBalance(_ rawBalance: String, decimals: Int) -> Double? {
    guard let rawValue = Double(rawBalance) else { return nil }
    return rawValue / pow(10, Double(decimals))
}

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

    enum CodingKeys: String, CodingKey {
        case incoming
        case outgoing
        case incomingPending
        case outgoingPending
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.incoming = try container.decodeFiniteNonnegativeNumericString(
            forKey: .incoming
        )
        self.outgoing = try container.decodeFiniteNonnegativeNumericString(
            forKey: .outgoing
        )
        self.incomingPending = try container.decodeFiniteNonnegativeNumericString(
            forKey: .incomingPending
        )
        self.outgoingPending = try container.decodeFiniteNonnegativeNumericString(
            forKey: .outgoingPending
        )
    }
    
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

    init(
        chain: String,
        address: String,
        balance: String,
        denominatedBalance: String,
        decimals: Int,
        type: String,
        tokenAddress: String?,
        tokenName: String?,
        tokenSymbol: String?
    ) {
        self.chain = chain
        self.address = address
        self.balance = balance
        self.denominatedBalance = denominatedBalance
        self.decimals = decimals
        self.type = type
        self.tokenAddress = tokenAddress
        self.tokenName = tokenName
        self.tokenSymbol = tokenSymbol
    }

    enum CodingKeys: String, CodingKey {
        case chain
        case address
        case balance
        case denominatedBalance
        case decimals
        case type
        case tokenAddress
        case tokenName
        case tokenSymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chain = try container.decode(String.self, forKey: .chain)
        self.address = try container.decode(String.self, forKey: .address)
        self.balance = try container.decodeFiniteNonnegativeNumericString(
            forKey: .balance
        )
        self.denominatedBalance = try container.decodeFiniteNonnegativeNumericString(
            forKey: .denominatedBalance
        )
        self.decimals = try container.decodeSupportedDecimals(forKey: .decimals)
        self.type = try container.decode(String.self, forKey: .type)
        self.tokenAddress = try container.decodeIfPresent(
            String.self,
            forKey: .tokenAddress
        )
        self.tokenName = try container.decodeIfPresent(
            String.self,
            forKey: .tokenName
        )
        self.tokenSymbol = try container.decodeIfPresent(
            String.self,
            forKey: .tokenSymbol
        )
    }

    var humanReadableBalance: Double {
        humanReadableTatumBalance(denominatedBalance, decimals: decimals)
            ?? Double(balance)
            ?? 0
    }
}

// MARK: - API Response Models
struct TatumBalanceResponse: Codable {
    let balance: String
    let tokenAddress: String?
    let tokenName: String?
    let tokenSymbol: String?
    let tokenDecimals: Int?

    /// Convert raw balance string to human-readable using token decimals (defaults to 18 for native tokens)
    var humanReadableBalance: Double {
        if let decimals = tokenDecimals {
            return humanReadableTatumBalance(balance, decimals: decimals) ?? 0
        }
        return Double(balance) ?? 0
    }
}

struct TatumTokenBalancesResponse: Codable {
    let balances: [TatumBalanceResponse]
}

// MARK: - Transaction Models
enum TatumProviderHashProvenance: String, Codable {
    case explicitTxid
    case fallbackIdentifier
}

enum ProviderIdentifierGrammar {
    static func isCanonical(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("|")
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }
}

struct TatumTransaction: Codable, Identifiable, Equatable {
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
    let transactionIndex: Int?
    let logIndex: Int?
    let transactionType: String?
    let transactionSubtype: String?
    let amount: String?
    let tokenAddress: String?
    let counterAddress: String?
    let providerHashAliases: [String]?
    let providerHashProvenance: TatumProviderHashProvenance?

    init(
        hash: String,
        blockNumber: Int? = nil,
        timestamp: Int? = nil,
        from: String? = nil,
        to: String? = nil,
        value: String? = nil,
        gasUsed: String? = nil,
        gasPrice: String? = nil,
        tokenTransfers: [TatumTokenTransfer]? = nil,
        chain: String? = nil,
        address: String? = nil,
        transactionIndex: Int? = nil,
        logIndex: Int? = nil,
        transactionType: String? = nil,
        transactionSubtype: String? = nil,
        amount: String? = nil,
        tokenAddress: String? = nil,
        counterAddress: String? = nil,
        providerHashAliases: [String]? = nil,
        providerHashProvenance: TatumProviderHashProvenance? = nil
    ) {
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
        self.transactionIndex = transactionIndex
        self.logIndex = logIndex
        self.transactionType = transactionType
        self.transactionSubtype = transactionSubtype
        self.amount = amount
        self.tokenAddress = tokenAddress
        self.counterAddress = counterAddress
        self.providerHashAliases = providerHashAliases
        self.providerHashProvenance = providerHashProvenance
    }
    
    var id: String { movementIdentity }

    /// Provider-level event key used to identify page overlap. Amount and
    /// timestamp are deliberately excluded so a changed duplicate is rejected
    /// instead of being imported as a second movement.
    var providerRecordIdentity: String {
        providerRecordIdentity(
            normalizeOpaqueIdentifier: {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    $0,
                    forChainIdentifier: chain
                )
            },
            normalizeAddress: {
                guard let chain else { return $0 }
                return OnChainIdentifierPolicy.normalizedAddress(
                    $0,
                    forChainIdentifier: chain
                )
            },
            normalizeTokenIdentifier: {
                OnChainIdentifierPolicy.normalizedTokenIdentifier(
                    $0,
                    forChainIdentifier: chain
                )
            }
        )
    }

    func providerRecordIdentity(for route: BalanceRoute) -> String {
        providerRecordIdentity(
            providerHash: hash,
            normalizeOpaqueIdentifier: {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier($0, for: route)
            },
            normalizeAddress: {
                OnChainIdentifierPolicy.normalizedAddress($0, for: route)
            },
            normalizeTokenIdentifier: {
                OnChainIdentifierPolicy.normalizedTokenIdentifier($0, for: route)
            }
        )
    }

    func providerRecordIdentities(for route: BalanceRoute) -> Set<String> {
        Set(providerHashes(for: route).map { providerHash in
            providerRecordIdentity(
                providerHash: providerHash,
                normalizeOpaqueIdentifier: {
                    OnChainIdentifierPolicy.normalizedOpaqueIdentifier($0, for: route)
                },
                normalizeAddress: {
                    OnChainIdentifierPolicy.normalizedAddress($0, for: route)
                },
                normalizeTokenIdentifier: {
                    OnChainIdentifierPolicy.normalizedTokenIdentifier($0, for: route)
                }
            )
        })
    }

    func normalizedProviderHashes(for route: BalanceRoute) -> Set<String> {
        Set(providerHashes(for: route).map {
            OnChainIdentifierPolicy.normalizedOpaqueIdentifier($0, for: route)
        })
    }

    func hasValidProviderIdentifiers(for route: BalanceRoute) -> Bool {
        guard ProviderIdentifierGrammar.isCanonical(hash) else {
            return false
        }
        return (providerHashAliases ?? []).allSatisfy {
            ProviderIdentifierGrammar.isCanonical($0)
        }
    }

    var hasValidProviderEventIndexes: Bool {
        (transactionIndex.map { $0 >= 0 } ?? true)
            && (logIndex.map { $0 >= 0 } ?? true)
    }

    private func providerRecordIdentity(
        providerHash: String? = nil,
        normalizeOpaqueIdentifier: (String) -> String,
        normalizeAddress: (String) -> String,
        normalizeTokenIdentifier: (String) -> String
    ) -> String {
        var components = [
            normalizeOpaqueIdentifier(providerHash ?? hash),
            chain?.lowercased() ?? "",
            address.map(normalizeAddress) ?? "",
            transactionIndex.map(String.init) ?? "",
            transactionType?.lowercased() ?? "",
            tokenAddress.map(normalizeTokenIdentifier) ?? ""
        ]
        if let logIndex {
            components.append(String(logIndex))
        }
        return components.joined(separator: "|")
    }

    var isValidAuthoritativeMovement: Bool {
        guard !hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let timestamp,
              timestamp > 0,
              let chain,
              !chain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let address,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let transactionType,
              !transactionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let transactionSubtype,
              !transactionSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount,
              let parsedAmount = Double(amount),
              parsedAmount.isFinite,
              parsedAmount >= 0,
              hasValidProviderEventIndexes
        else {
            return false
        }
        return true
    }

    func isCanonicalProviderEquivalent(to other: TatumTransaction) -> Bool {
        canonicalProviderContent == other.canonicalProviderContent
    }

    func isCanonicalProviderEquivalentIgnoringEventIndexes(
        to other: TatumTransaction
    ) -> Bool {
        canonicalProviderContent(includeEventIndexes: false)
            == other.canonicalProviderContent(includeEventIndexes: false)
    }

    /// Stable identity for a normalized wallet movement. A single blockchain
    /// transaction can contain more than one movement for the tracked asset,
    /// so the hash alone is not a unique event identifier.
    var movementIdentity: String {
        movementIdentity(
            normalizeOpaqueIdentifier: {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    $0,
                    forChainIdentifier: chain
                )
            },
            normalizeAddress: {
                guard let chain else { return $0 }
                return OnChainIdentifierPolicy.normalizedAddress(
                    $0,
                    forChainIdentifier: chain
                )
            },
            normalizeTokenIdentifier: {
                OnChainIdentifierPolicy.normalizedTokenIdentifier(
                    $0,
                    forChainIdentifier: chain
                )
            }
        )
    }

    func movementIdentity(for route: BalanceRoute) -> String {
        movementIdentity(
            normalizeOpaqueIdentifier: {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier($0, for: route)
            },
            normalizeAddress: {
                OnChainIdentifierPolicy.normalizedAddress($0, for: route)
            },
            normalizeTokenIdentifier: {
                OnChainIdentifierPolicy.normalizedTokenIdentifier($0, for: route)
            }
        )
    }

    var legacyCaseFoldedMovementIdentity: String {
        var components = [
            hash.lowercased(),
            chain?.lowercased() ?? "",
            address?.lowercased() ?? "",
            transactionIndex.map(String.init) ?? "",
            transactionType?.lowercased() ?? "",
            tokenAddress?.lowercased() ?? "",
            transactionSubtype?.lowercased() ?? "",
            counterAddress?.lowercased() ?? "",
            from?.lowercased() ?? "",
            to?.lowercased() ?? "",
            normalizedMovementAmount,
            timestamp.map(String.init) ?? ""
        ]
        if let logIndex {
            components.append(String(logIndex))
        }
        return components.joined(separator: "|")
    }

    var legacyCaseFoldedProviderRecordIdentity: String {
        legacyCaseFoldedProviderRecordIdentity(providerHash: hash)
    }

    func legacyCaseFoldedProviderRecordIdentities(
        for route: BalanceRoute
    ) -> Set<String> {
        Set(providerHashes(for: route).map {
            legacyCaseFoldedProviderRecordIdentity(providerHash: $0)
        })
    }

    private func legacyCaseFoldedProviderRecordIdentity(
        providerHash: String
    ) -> String {
        var components = [
            providerHash.lowercased(),
            chain?.lowercased() ?? "",
            address?.lowercased() ?? "",
            transactionIndex.map(String.init) ?? "",
            transactionType?.lowercased() ?? "",
            tokenAddress?.lowercased() ?? ""
        ]
        if let logIndex {
            components.append(String(logIndex))
        }
        return components.joined(separator: "|")
    }

    private func providerHashes(for route: BalanceRoute) -> [String] {
        guard case .utxo = route else { return [hash] }

        var normalizedHashes = Set<String>()
        return ([hash] + (providerHashAliases ?? [])).filter { providerHash in
            let normalized = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                providerHash,
                for: route
            )
            return normalizedHashes.insert(normalized).inserted
        }
    }

    private func movementIdentity(
        normalizeOpaqueIdentifier: (String) -> String,
        normalizeAddress: (String) -> String,
        normalizeTokenIdentifier: (String) -> String
    ) -> String {
        var components: [String] = []
        components.append(normalizeOpaqueIdentifier(hash))
        components.append(chain?.lowercased() ?? "")
        components.append(address.map(normalizeAddress) ?? "")
        components.append(transactionIndex.map(String.init) ?? "")
        components.append(transactionType?.lowercased() ?? "")
        components.append(tokenAddress.map(normalizeTokenIdentifier) ?? "")
        components.append(transactionSubtype?.lowercased() ?? "")
        components.append(counterAddress.map(normalizeAddress) ?? "")
        components.append(from.map(normalizeAddress) ?? "")
        components.append(to.map(normalizeAddress) ?? "")
        components.append(normalizedMovementAmount)
        components.append(timestamp.map(String.init) ?? "")
        if let logIndex {
            components.append(String(logIndex))
        }
        return components.joined(separator: "|")
    }

    private var normalizedMovementAmount: String {
        guard let rawAmount = amount ?? value else {
            return ""
        }
        guard let parsedAmount = Double(rawAmount), parsedAmount.isFinite else {
            return rawAmount.lowercased()
        }
        return String(abs(parsedAmount).bitPattern, radix: 16)
    }

    private var canonicalProviderContent: [String] {
        canonicalProviderContent(includeEventIndexes: true)
    }

    private func canonicalProviderContent(includeEventIndexes: Bool) -> [String] {
        let normalizeAddress: (String) -> String = {
            guard let chain else { return $0 }
            return OnChainIdentifierPolicy.normalizedAddress(
                $0,
                forChainIdentifier: chain
            )
        }
        let normalizeToken: (String) -> String = {
            OnChainIdentifierPolicy.normalizedTokenIdentifier(
                $0,
                forChainIdentifier: chain
            )
        }
        let normalizedHash = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
            hash,
            forChainIdentifier: chain
        )
        let canonicalTokenTransfers = tokenTransfers?.map {
            $0.canonicalProviderContent(
                normalizeAddress: normalizeAddress,
                normalizeToken: normalizeToken
            )
        }.joined(separator: "\u{1E}") ?? ""
        var components: [String] = []
        components.append(normalizedHash)
        components.append(blockNumber.map(String.init) ?? "")
        components.append(timestamp.map(String.init) ?? "")
        components.append(from.map(normalizeAddress) ?? "")
        components.append(to.map(normalizeAddress) ?? "")
        components.append(Self.canonicalNumericString(value))
        components.append(Self.canonicalNumericString(gasUsed))
        components.append(Self.canonicalNumericString(gasPrice))
        components.append(canonicalTokenTransfers)
        components.append(chain?.lowercased() ?? "")
        components.append(address.map(normalizeAddress) ?? "")
        components.append(
            includeEventIndexes ? transactionIndex.map(String.init) ?? "" : ""
        )
        components.append(transactionType?.lowercased() ?? "")
        components.append(transactionSubtype?.lowercased() ?? "")
        components.append(Self.canonicalNumericString(amount))
        components.append(tokenAddress.map(normalizeToken) ?? "")
        components.append(counterAddress.map(normalizeAddress) ?? "")
        if includeEventIndexes, let logIndex {
            components.append(String(logIndex))
        }
        return components
    }

    private static func canonicalNumericString(_ rawValue: String?) -> String {
        guard let rawValue else { return "" }
        guard let value = Double(rawValue), value.isFinite else {
            return "raw:\(rawValue)"
        }
        return "number:\(String(value.bitPattern, radix: 16))"
    }
    
    var date: Date {
        if let timestamp = timestamp {
            // Tatum v4 returns timestamp in milliseconds
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        }
        return .distantPast
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

struct TatumTokenTransfer: Codable, Equatable {
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

    fileprivate func canonicalProviderContent(
        normalizeAddress: (String) -> String,
        normalizeToken: (String) -> String
    ) -> String {
        [
            from.map(normalizeAddress) ?? "",
            to.map(normalizeAddress) ?? "",
            value ?? "",
            tokenAddress.map(normalizeToken) ?? "",
            tokenSymbol?.uppercased() ?? "",
            tokenName ?? "",
            tokenDecimals.map(String.init) ?? ""
        ].joined(separator: "\u{1F}")
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
struct TatumUTXOTransaction: Decodable, Identifiable, Equatable {
    let hash: String
    let providerHashAliases: [String]
    let hasExplicitTxid: Bool
    let time: Int?
    let inputs: [TatumUTXOInput]?
    let outputs: [TatumUTXOOutput]?
    
    var id: String { hash }
    
    var date: Date {
        if let time = time {
            return Date(timeIntervalSince1970: TimeInterval(time))
        }
        return .distantPast
    }

    func isCanonicalProviderEquivalent(
        to other: TatumUTXOTransaction,
        chainId: String
    ) -> Bool {
        canonicalProviderContent(chainId: chainId, includeHash: true)
            == other.canonicalProviderContent(chainId: chainId, includeHash: true)
    }

    func isCanonicalProviderEquivalentIgnoringHash(
        to other: TatumUTXOTransaction,
        chainId: String
    ) -> Bool {
        canonicalProviderContent(chainId: chainId, includeHash: false)
            == other.canonicalProviderContent(chainId: chainId, includeHash: false)
    }

    func normalizedProviderHashes(chainId: String) -> Set<String> {
        Set(([hash] + providerHashAliases).map {
            OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                $0,
                forChainIdentifier: chainId
            )
        })
    }

    private func canonicalProviderContent(
        chainId: String,
        includeHash: Bool
    ) -> [String] {
        [
            includeHash
                ? OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    hash,
                    forChainIdentifier: chainId
                )
                : "",
            time.map(String.init) ?? "",
            (inputs ?? []).map {
                $0.canonicalProviderContent(chainId: chainId)
            }.joined(separator: "\u{1E}"),
            (outputs ?? []).map {
                $0.canonicalProviderContent(chainId: chainId)
            }.joined(separator: "\u{1E}")
        ]
    }

    init(
        hash: String,
        providerHashAliases: [String],
        hasExplicitTxid: Bool,
        time: Int?,
        inputs: [TatumUTXOInput]?,
        outputs: [TatumUTXOOutput]?
    ) {
        self.hash = hash
        self.providerHashAliases = providerHashAliases
        self.hasExplicitTxid = hasExplicitTxid
        self.time = time
        self.inputs = inputs
        self.outputs = outputs
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case txid
        case wtxid
        case time
        case ts
        case inputs
        case vin
        case outputs
        case vout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let txid = try container.decodeIfPresent(String.self, forKey: .txid)
        let providerHash = try container.decodeIfPresent(String.self, forKey: .hash)
        let witnessHash = try container.decodeIfPresent(String.self, forKey: .wtxid)
        let providedIdentifiers = [txid, providerHash, witnessHash].compactMap { $0 }
        guard providedIdentifiers.allSatisfy({
            ProviderIdentifierGrammar.isCanonical($0)
        }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "UTXO identifiers must use canonical provider grammar"
                )
            )
        }
        guard let hash = txid ?? providerHash ?? witnessHash else {
            throw DecodingError.keyNotFound(
                CodingKeys.hash,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "UTXO transaction requires txid, hash, or wtxid"
                )
            )
        }
        self.hash = hash
        self.hasExplicitTxid = txid != nil
        var seenAliases = Set([hash])
        self.providerHashAliases = [providerHash, witnessHash]
            .compactMap { $0 }
            .filter { seenAliases.insert($0).inserted }
        self.time = try container.decodeFlexibleIntIfPresent(forKeys: [.time, .ts])
        guard let inputs = try container.decodeIfPresent(
            [TatumUTXOInput].self,
            forKey: .inputs
        ) ?? container.decodeIfPresent([TatumUTXOInput].self, forKey: .vin) else {
            throw DecodingError.keyNotFound(
                CodingKeys.vin,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "UTXO transaction requires inputs or vin"
                )
            )
        }
        guard let outputs = try container.decodeIfPresent(
            [TatumUTXOOutput].self,
            forKey: .outputs
        ) ?? container.decodeIfPresent([TatumUTXOOutput].self, forKey: .vout) else {
            throw DecodingError.keyNotFound(
                CodingKeys.vout,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "UTXO transaction requires outputs or vout"
                )
            )
        }
        self.inputs = inputs
        self.outputs = outputs
    }
}

struct TatumBlockchainTransactionResponse: Decodable {
    let result: TatumUTXOTransaction
}

struct TatumUTXOInput: Decodable, Equatable {
    let prevout: TatumUTXOPrevout?
    let transactionHash: String?
    let outputIndex: Int?
    let coinbase: String?

    var isCoinbase: Bool {
        guard let coinbase else { return false }
        return !coinbase.isEmpty
    }

    fileprivate func canonicalProviderContent(chainId: String) -> String {
        [
            prevout?.canonicalProviderContent(chainId: chainId) ?? "",
            transactionHash.map {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    $0,
                    forChainIdentifier: chainId
                )
            } ?? "",
            outputIndex.map(String.init) ?? "",
            coinbase?.lowercased() ?? ""
        ].joined(separator: "\u{1F}")
    }

    enum CodingKeys: String, CodingKey {
        case prevout
        case transactionHash = "txid"
        case hash
        case outputIndex = "vout"
        case outputIndexAlias = "outputIndex"
        case coinbase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prevout = try container.decodeIfPresent(TatumUTXOPrevout.self, forKey: .prevout)
        self.transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
            ?? container.decodeIfPresent(String.self, forKey: .hash)
        self.outputIndex = try container.decodeFlexibleIntIfPresent(
            forKeys: [.outputIndex, .outputIndexAlias]
        )
        self.coinbase = try container.decodeIfPresent(String.self, forKey: .coinbase)
    }
}

struct TatumUTXOOutput: Decodable, Equatable {
    let valueNumber: Double?
    let address: String?  // Direct address field
    let scriptPubKey: TatumScriptPubKey?
    
    var humanReadableValue: Double {
        guard let value = valueNumber else { return 0 }
        return value / 100_000_000 // Convert satoshis to BTC
    }

    fileprivate func canonicalProviderContent(chainId: String) -> String {
        [
            valueNumber.map {
                String($0.bitPattern, radix: 16)
            } ?? "",
            canonicalAddresses(chainId: chainId).joined(separator: ",")
        ].joined(separator: "\u{1F}")
    }

    private func canonicalAddresses(chainId: String) -> [String] {
        var values = scriptPubKey?.allAddresses ?? []
        if let address, !values.contains(address) {
            values.append(address)
        }
        return values.map {
            OnChainIdentifierPolicy.normalizedAddress(
                $0,
                forChainIdentifier: chainId
            )
        }.sorted()
    }
    
    enum CodingKeys: String, CodingKey {
        case valueNumber = "value"
        case address
        case scriptPubKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.valueNumber = try container.decodeFlexibleDoubleIfPresent(forKey: .valueNumber)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.scriptPubKey = try container.decodeIfPresent(
            TatumScriptPubKey.self,
            forKey: .scriptPubKey
        )
    }
}

struct TatumUTXOPrevout: Decodable, Equatable {
    let valueNumber: Double?
    let scriptPubKey: TatumScriptPubKey?

    fileprivate func canonicalProviderContent(chainId: String) -> String {
        [
            valueNumber.map {
                String($0.bitPattern, radix: 16)
            } ?? "",
            (scriptPubKey?.allAddresses ?? []).map {
                OnChainIdentifierPolicy.normalizedAddress(
                    $0,
                    forChainIdentifier: chainId
                )
            }.sorted().joined(separator: ",")
        ].joined(separator: "\u{1F}")
    }
    
    enum CodingKeys: String, CodingKey {
        case valueNumber = "value"
        case scriptPubKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.valueNumber = try container.decodeFlexibleDoubleIfPresent(forKey: .valueNumber)
        self.scriptPubKey = try container.decodeIfPresent(
            TatumScriptPubKey.self,
            forKey: .scriptPubKey
        )
    }
}

struct TatumScriptPubKey: Codable, Equatable {
    let address: String?
    let addresses: [String]?

    var allAddresses: [String] {
        var result = addresses ?? []
        if let address, !result.contains(address) {
            result.append(address)
        }
        return result
    }
}

private extension KeyedDecodingContainer {
    func decodeFiniteNonnegativeNumericString(forKey key: Key) throws -> String {
        guard let rawValue = try decodeFlexibleStringIfPresent(forKey: key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected a balance value"
                )
            )
        }
        guard let value = Double(rawValue), value.isFinite, value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected a finite nonnegative balance"
            )
        }
        return rawValue
    }

    func decodeSupportedDecimals(forKey key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        guard (0...255).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Decimals must be between 0 and 255"
            )
        }
        return value
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(String.self, forKey: key) {
            guard let parsed = Double(value), parsed.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected a numeric string"
                )
            }
            return value
        }
        let value = try decode(Double.self, forKey: key)
        guard value.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected a finite number"
            )
        }
        return String(value)
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Double.self, forKey: key) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected a finite number"
                )
            }
            return value
        }
        let raw = try decode(String.self, forKey: key)
        guard let value = Double(raw), value.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected a numeric string"
            )
        }
        return value
    }

    func decodeFlexibleIntIfPresent(forKeys keys: [Key]) throws -> Int? {
        for key in keys where contains(key) {
            if try decodeNil(forKey: key) { return nil }
            if let value = try? decode(Int.self, forKey: key) {
                return value
            }
            let raw = try decode(String.self, forKey: key)
            guard let value = Int(raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected an integer or integer string"
                )
            }
            return value
        }
        return nil
    }
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
        return formatter.date(from: date) ?? .distantPast
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

    enum CodingKeys: String, CodingKey {
        case balance
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.balance = try container.decodeFiniteNonnegativeNumericString(
            forKey: .balance
        )
        self.assets = try container.decode([String].self, forKey: .assets)
    }
    
    var balanceInXRP: Double {
        guard let drops = Double(balance) else { return 0.0 }
        return drops / 1_000_000  // Convert drops to XRP
    }
}

// XRP Account Transaction Response Models (v3 API)
struct XRPAccountResponse: Decodable, Equatable {
    let account: String
    let ledgerIndexMax: Int
    let ledgerIndexMin: Int
    let limit: Int? // Made optional as it might not always be present
    let transactions: [XRPTransactionDetails]
    let validated: Bool
    let marker: TatumJSONValue?
    
    enum CodingKeys: String, CodingKey {
        case account
        case ledgerIndexMax = "ledger_index_max"
        case ledgerIndexMin = "ledger_index_min"
        case limit, transactions, validated, marker
    }
}

struct XRPTransactionDetails: Decodable, Equatable {
    let meta: XRPTransactionMeta
    let tx: XRPTransaction
    let validated: Bool

    func isCanonicalProviderEquivalent(to other: XRPTransactionDetails) -> Bool {
        validated == other.validated
            && meta == other.meta
            && tx.isCanonicalProviderEquivalent(to: other.tx)
    }
}

struct XRPTransactionMeta: Decodable, Equatable {
    let affectedNodes: [XRPAffectedNode]
    let transactionIndex: Int
    let transactionResult: String
    let deliveredAmount: XRPAmount?
    
    enum CodingKeys: String, CodingKey {
        case affectedNodes = "AffectedNodes"
        case transactionIndex = "TransactionIndex"
        case transactionResult = "TransactionResult"
        case deliveredAmount = "delivered_amount"
    }
}

struct XRPAffectedNode: Codable, Equatable {
    let modifiedNode: XRPModifiedNode?
    let createdNode: XRPCreatedNode?
    
    enum CodingKeys: String, CodingKey {
        case modifiedNode = "ModifiedNode"
        case createdNode = "CreatedNode"
    }
}

struct XRPModifiedNode: Codable, Equatable {
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

struct XRPCreatedNode: Codable, Equatable {
    let ledgerEntryType: String
    let ledgerIndex: String
    let newFields: XRPAccountFields
    
    enum CodingKeys: String, CodingKey {
        case ledgerEntryType = "LedgerEntryType"
        case ledgerIndex = "LedgerIndex"
        case newFields = "NewFields"
    }
}

struct XRPAccountFields: Codable, Equatable {
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

struct XRPTransaction: Decodable, Equatable {
    let account: String
    let amount: XRPAmount?
    let deliverMax: XRPAmount?
    let destination: String?
    let fee: String
    let flags: Int
    let sequence: Int
    let transactionType: String
    let date: Int
    let hash: String
    let ledgerIndex: Int

    func isCanonicalProviderEquivalent(to other: XRPTransaction) -> Bool {
        account == other.account
            && amount == other.amount
            && deliverMax == other.deliverMax
            && destination == other.destination
            && fee == other.fee
            && flags == other.flags
            && sequence == other.sequence
            && transactionType == other.transactionType
            && date == other.date
            && hash.caseInsensitiveCompare(other.hash) == .orderedSame
            && ledgerIndex == other.ledgerIndex
    }
    
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

enum XRPAmount: Decodable, Equatable {
    case nativeDrops(String)
    case issued(currency: String?, issuer: String?, value: String?)

    private enum CodingKeys: String, CodingKey {
        case currency
        case issuer
        case value
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let string = try? singleValue.decode(String.self) {
            self = .nativeDrops(string)
            return
        }
        if let integer = try? singleValue.decode(Int64.self) {
            self = .nativeDrops(String(integer))
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let issuedValue: String?
        switch try container.decodeIfPresent(TatumJSONValue.self, forKey: .value) {
        case .some(.string(let value)):
            issuedValue = value
        case .some(.number(let value)):
            issuedValue = String(value)
        default:
            issuedValue = nil
        }
        self = .issued(
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            issuer: try container.decodeIfPresent(String.self, forKey: .issuer),
            value: issuedValue
        )
    }
}

indirect enum TatumJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: TatumJSONValue])
    case array([TatumJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: TatumJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([TatumJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var queryValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            guard value.isFinite, let exactValue = Int64(exactly: value) else {
                return nil
            }
            return String(exactValue)
        case .object, .array:
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return nil
        }
    }
}

// MARK: - TRX Transaction Models
// TRX Account Response Models (v3 API)
struct TRXAccountResponse: Codable {
    let balance: Int64
    let createTime: Int64
    let trc10: TRC10Response // Can be either empty array or dictionary
    let trc20: TRC20Response // Array of token objects

    enum CodingKeys: String, CodingKey {
        case balance
        case createTime
        case trc10
        case trc20
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let balance = try container.decode(Int64.self, forKey: .balance)
        guard balance >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .balance,
                in: container,
                debugDescription: "Balance must be nonnegative"
            )
        }
        self.balance = balance
        self.createTime = try container.decode(Int64.self, forKey: .createTime)
        self.trc10 = try container.decode(TRC10Response.self, forKey: .trc10)
        self.trc20 = try container.decode(TRC20Response.self, forKey: .trc20)
    }
    
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

// Helper type to handle the documented dictionary/empty-array forms and the
// key-value object array returned by the TRON account API.
struct TRC10Response: Codable {
    let tokens: [String: String]

    private struct TokenEntry: Decodable {
        let key: String
        let value: String

        private enum CodingKeys: String, CodingKey {
            case key
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let key = try container.decode(String.self, forKey: .key)

            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .key,
                    in: container,
                    debugDescription: "TRC10 token keys must not be empty"
                )
            }

            self.key = key
            self.value = try Self.decodeValue(from: container)
        }

        private static func decodeValue(
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws -> String {
            if let value = try? container.decode(String.self, forKey: .value) {
                guard let numericValue = Double(value),
                      numericValue.isFinite,
                      numericValue >= 0 else {
                    throw invalidValueError(in: container)
                }
                return value
            }

            if let value = try? container.decode(Int64.self, forKey: .value) {
                guard value >= 0 else {
                    throw invalidValueError(in: container)
                }
                return String(value)
            }

            if let value = try? container.decode(UInt64.self, forKey: .value) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: .value) {
                guard value.isFinite, value >= 0 else {
                    throw invalidValueError(in: container)
                }
                return String(value)
            }

            throw invalidValueError(in: container)
        }

        private static func invalidValueError(
            in container: KeyedDecodingContainer<CodingKeys>
        ) -> DecodingError {
            DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "TRC10 balances must be finite nonnegative numbers"
            )
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as dictionary first
        if let dict = try? container.decode([String: String].self) {
            try Self.validateKeys(dict.keys, codingPath: decoder.codingPath)
            try Self.validateBalances(dict.values, codingPath: decoder.codingPath)
            self.tokens = dict
        } else if let array = try? container.decode([String].self), array.isEmpty {
            self.tokens = [:]
        } else {
            let entries = try container.decode([TokenEntry].self)
            var tokens: [String: String] = [:]
            tokens.reserveCapacity(entries.count)

            for entry in entries {
                guard tokens.updateValue(entry.value, forKey: entry.key) == nil else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "TRC10 token keys must be unique"
                    )
                }
            }

            self.tokens = tokens
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

    private static func validateKeys(
        _ keys: Dictionary<String, String>.Keys,
        codingPath: [CodingKey]
    ) throws {
        guard keys.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "TRC10 token keys must not be empty"
                )
            )
        }
    }

    private static func validateBalances(
        _ balances: Dictionary<String, String>.Values,
        codingPath: [CodingKey]
    ) throws {
        guard balances.allSatisfy({
            guard let value = Double($0) else { return false }
            return value.isFinite && value >= 0
        }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "TRC10 balances must be finite nonnegative numbers"
                )
            )
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
            let balances = array.flatMap { $0.values }
            guard balances.allSatisfy({
                guard let value = Double($0) else { return false }
                return value.isFinite && value >= 0
            }) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "TRC20 balances must be finite nonnegative numbers"
                )
            }
            self.tokenBalances = array
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "TRC20 balances must be an array of dictionaries"
            )
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
struct TRXTransactionResponse: Decodable {
    let transactions: [TRXTransaction]
    let internalTransactions: [TRXInternalTransaction]?
    let next: String?

    init(
        transactions: [TRXTransaction],
        internalTransactions: [TRXInternalTransaction]?,
        next: String? = nil
    ) {
        self.transactions = transactions
        self.internalTransactions = internalTransactions
        self.next = next
    }
}

struct TRXTransaction: Codable, Identifiable, Equatable {
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
        return .distantPast
    }
    
    var totalFee: Double {
        let net = Double(netFee ?? 0)
        let energy = Double(energyFee ?? 0)
        return (net + energy) / 1_000_000 // Convert sun to TRX
    }
}

struct TRXTransactionResult: Codable, Equatable {
    let contractRet: String?
    let fee: Int64?
}

struct TRXRawData: Codable, Equatable {
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

struct TRXContract: Codable, Equatable {
    let type: String?
    let parameter: TRXContractParameter?
}

struct TRXContractParameter: Codable, Equatable {
    let value: TRXContractValue?
    let typeUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case value
        case typeUrl = "type_url"
    }
}

struct TRXContractValue: Codable, Equatable {
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

struct TRXInternalTransaction: Codable, Equatable {
    let hash: String?
    let callerAddress: String?
    let transferToAddress: String?
    let callValueInfo: [TRXCallValueInfo]?
    let note: String?
}

struct TRXCallValueInfo: Codable, Equatable {
    let callValue: Int64?
    let tokenName: String?
    let tokenId: String?
    
    var trxValue: Double {
        guard let value = callValue else { return 0.0 }
        return Double(value) / 1_000_000 // Convert sun to TRX
    }
}

// MARK: - TRC-20 Transaction Models
struct TRC20TransactionResponse: Decodable {
    let transactions: [TRC20Transaction]
    let next: String?

    init(transactions: [TRC20Transaction], next: String? = nil) {
        self.transactions = transactions
        self.next = next
    }
}

struct TRC20Transaction: Decodable, Identifiable, Equatable {
    let txID: String
    let tokenInfo: TRC20TokenInfo
    let from: String?
    let to: String?
    let type: String?
    let value: String
    let timestamp: Int?
    let contractRet: String?
    let receipt: TRC20Receipt?
    
    var id: String { txID }
    
    // Convert token amount based on decimals from tokenInfo
    var tokenAmount: Double? {
        guard let amountValue = Double(value),
              amountValue.isFinite,
              amountValue >= 0,
              (0...255).contains(tokenInfo.decimals)
        else {
            return nil
        }
        let divisor = pow(10, Double(tokenInfo.decimals))
        let result = amountValue / divisor
        guard divisor.isFinite,
              divisor > 0,
              result.isFinite,
              result >= 0
        else {
            return nil
        }
        return result
    }
    
    // Check if this is USDT
    var isUSDT: Bool {
        return tokenInfo.address == "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    }

    var isSuccessful: Bool {
        if let contractRet {
            return contractRet == "SUCCESS"
        }
        return receipt?.result == "SUCCESS"
    }

    enum CodingKeys: String, CodingKey {
        case txID
        case transactionID = "transaction_id"
        case tokenInfo
        case tokenInfoSnakeCase = "token_info"
        case from
        case to
        case type
        case value
        case timestamp
        case blockTimestamp = "block_timestamp"
        case contractRet
        case contractRetSnakeCase = "contract_ret"
        case receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let txID = try container.decodeIfPresent(String.self, forKey: .txID)
                ?? container.decodeIfPresent(String.self, forKey: .transactionID)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.txID,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "TRC20 transaction requires txID or transaction_id"
                )
            )
        }
        self.txID = txID
        guard let tokenInfo = try container.decodeIfPresent(
            TRC20TokenInfo.self,
            forKey: .tokenInfo
        ) ?? container.decodeIfPresent(
            TRC20TokenInfo.self,
            forKey: .tokenInfoSnakeCase
        ) else {
            throw DecodingError.keyNotFound(
                CodingKeys.tokenInfo,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "TRC20 transaction requires token info"
                )
            )
        }
        self.tokenInfo = tokenInfo
        self.from = try container.decodeIfPresent(String.self, forKey: .from)
        self.to = try container.decodeIfPresent(String.self, forKey: .to)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        if let stringValue = try? container.decode(String.self, forKey: .value) {
            self.value = stringValue
        } else {
            self.value = String(try container.decode(Double.self, forKey: .value))
        }
        self.timestamp = try container.decodeFlexibleIntIfPresent(
            forKeys: [.timestamp, .blockTimestamp]
        )
        self.contractRet = try container.decodeIfPresent(
            String.self,
            forKey: .contractRet
        ) ?? container.decodeIfPresent(String.self, forKey: .contractRetSnakeCase)
        self.receipt = try container.decodeIfPresent(TRC20Receipt.self, forKey: .receipt)
    }
}

struct TRC20TokenInfo: Decodable, Equatable {
    let symbol: String
    let address: String
    let decimals: Int
    let name: String
}

struct TRC20Receipt: Decodable, Equatable {
    let result: String?
}

// MARK: - Other Chain Transaction Models
// MARK: - ADA (Cardano) Models
struct TatumADABalanceResponse: Codable {
    let value: String
    let currency: TatumADACurrency

    enum CodingKeys: String, CodingKey {
        case value
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decodeFiniteNonnegativeNumericString(forKey: .value)
        self.currency = try container.decode(TatumADACurrency.self, forKey: .currency)
    }
    
    var humanReadableBalance: Double {
        guard let balanceValue = Double(value) else { return 0 }
        return balanceValue / pow(10, Double(currency.decimals))
    }
}

struct TatumADACurrency: Codable {
    let symbol: String
    let decimals: Int

    enum CodingKeys: String, CodingKey {
        case symbol
        case decimals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.decimals = try container.decodeSupportedDecimals(forKey: .decimals)
    }
}

struct TatumADATransaction: Decodable, Identifiable, Equatable {
    let hash: String
    let block: TatumADABlock?
    let inputs: [TatumADAInput]?
    let outputs: [TatumADAOutput]?
    let fee: String?
    let timestamp: Int?
    
    var id: String { hash }
    
    var date: Date {
        guard let timestamp = timestamp ?? block?.timestamp else {
            return .distantPast
        }
        let seconds = timestamp >= 1_000_000_000_000
            ? TimeInterval(timestamp) / 1_000
            : TimeInterval(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }
    
    var feeValue: Double {
        guard let fee = fee, let feeDouble = Double(fee) else { return 0 }
        return feeDouble / 1_000_000 // Convert lovelace to ADA
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case block
        case inputs
        case outputs
        case fee
        case timestamp
        case time
        case blockTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hash = try container.decode(String.self, forKey: .hash)
        self.block = try container.decodeIfPresent(TatumADABlock.self, forKey: .block)
        self.inputs = try container.decodeIfPresent([TatumADAInput].self, forKey: .inputs)
        self.outputs = try container.decodeIfPresent([TatumADAOutput].self, forKey: .outputs)
        self.fee = try container.decodeFlexibleStringIfPresent(forKey: .fee)
        self.timestamp = try container.decodeFlexibleIntIfPresent(
            forKeys: [.timestamp, .time, .blockTime]
        )
    }
}

struct TatumADABlock: Decodable, Equatable {
    let hash: String
    let number: Int
    let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case hash
        case number
        case timestamp
        case time
        case blockTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hash = try container.decode(String.self, forKey: .hash)
        self.number = try container.decode(Int.self, forKey: .number)
        self.timestamp = try container.decodeFlexibleIntIfPresent(
            forKeys: [.timestamp, .time, .blockTime]
        )
    }
}

struct TatumADAInput: Decodable, Equatable {
    let address: String?
    let symbol: String?
    let value: String?
    let txHash: String?
    
    var amountValue: Double? {
        guard let value, let parsed = Double(value), parsed.isFinite, parsed >= 0 else {
            return nil
        }
        return parsed / 1_000_000
    }

    enum CodingKeys: String, CodingKey {
        case address
        case symbol
        case value
        case txHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.value = try container.decodeFlexibleStringIfPresent(forKey: .value)
        self.txHash = try container.decodeIfPresent(String.self, forKey: .txHash)
    }
}

struct TatumADAOutput: Decodable, Equatable {
    let address: String?
    let symbol: String?
    let value: String?
    let index: Int?
    let txHash: String?
    
    var amountValue: Double? {
        guard let value, let parsed = Double(value), parsed.isFinite, parsed >= 0 else {
            return nil
        }
        return parsed / 1_000_000
    }

    enum CodingKeys: String, CodingKey {
        case address
        case symbol
        case value
        case index
        case txHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.value = try container.decodeFlexibleStringIfPresent(forKey: .value)
        self.index = try container.decodeFlexibleIntIfPresent(forKeys: [.index])
        self.txHash = try container.decodeIfPresent(String.self, forKey: .txHash)
    }
}

// MARK: - SOL (Solana) Balance Models
struct TatumSOLBalanceResponse: Codable {
    let balance: String  // Balance is already in SOL, not lamports

    enum CodingKeys: String, CodingKey {
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.balance = try container.decodeFiniteNonnegativeNumericString(
            forKey: .balance
        )
    }
    
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

struct SolanaSignature: Codable, Equatable {
    let signature: String
    let slot: Int?
    let err: SolanaTransactionError?
    let memo: String?
    let blockTime: Int?
    
    var isSuccess: Bool {
        switch err {
        case nil, .some(.null):
            return true
        case .some(.failure):
            return false
        }
    }
}

enum SolanaTransactionError: Codable, Equatable {
    case failure(TatumJSONValue)
    case null
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .failure(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .failure(try container.decode(TatumJSONValue.self))
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
        return .distantPast
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
        switch err {
        case nil, .some(.null):
            return true
        case .some(.failure):
            return false
        }
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
        return .distantPast
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
        return formatter.date(from: createdAt) ?? .distantPast
    }
}
