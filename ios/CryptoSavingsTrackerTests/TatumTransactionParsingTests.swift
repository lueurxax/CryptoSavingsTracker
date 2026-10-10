//
//  TatumTransactionParsingTests.swift
//  CryptoSavingsTracker
//
//  Created by user on 05/08/2025.
//

import XCTest
import Foundation
import SwiftData
@testable import CryptoSavingsTracker

@MainActor
final class TatumTransactionParsingTests: XCTestCase {
    private enum ForcedSaveError: Error {
        case failed
    }
    
    func testTatumV4TransactionResponseParsing() throws {
        // This is the exact JSON response from your curl example
        let jsonResponse = """
        {
          "result": [
            {
              "chain": "ethereum-mainnet",
              "hash": "0x997d6ed680e3556b01cf474d1e6027dc9fd21e28d3b30ec3ac3c8be949b11bec",
              "address": "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b",
              "blockNumber": 23074598,
              "transactionType": "native",
              "transactionSubtype": "incoming",
              "amount": "0.133276145314559",
              "tokenAddress": null,
              "timestamp": 1754393687000,
              "counterAddress": "0x963737c550e70ffe4d59464542a28604edb2ef9a"
            }
          ],
          "prevPage": "",
          "nextPage": ""
        }
        """.data(using: .utf8)!
        
        // Test that our TatumV4TransactionResponse model can decode this properly
        let decoder = JSONDecoder()
        let response = try decoder.decode(TatumV4TransactionResponse.self, from: jsonResponse)
        
        // Verify the wrapper structure
        XCTAssertEqual(response.result.count, 1)
        XCTAssertEqual(response.prevPage, "")
        XCTAssertEqual(response.nextPage, "")
        
        // Verify the transaction data
        let transaction = response.result[0]
        XCTAssertEqual(transaction.chain, "ethereum-mainnet")
        XCTAssertEqual(transaction.hash, "0x997d6ed680e3556b01cf474d1e6027dc9fd21e28d3b30ec3ac3c8be949b11bec")
        XCTAssertEqual(transaction.address, "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b")
        XCTAssertEqual(transaction.blockNumber, 23074598)
        XCTAssertEqual(transaction.transactionType, "native")
        XCTAssertEqual(transaction.transactionSubtype, "incoming")
        XCTAssertEqual(transaction.amount, "0.133276145314559")
        XCTAssertNil(transaction.tokenAddress)
        XCTAssertEqual(transaction.timestamp, 1754393687000)
        XCTAssertEqual(transaction.counterAddress, "0x963737c550e70ffe4d59464542a28604edb2ef9a")
    }

    func testTatumV4FungibleTransactionDecodesTopLevelTokenAddress() throws {
        let data = """
        {
          "result": [{
            "chain": "ethereum-mainnet",
            "hash": "0xtoken",
            "address": "0x00000000000000000000000000000000000000aa",
            "transactionIndex": 7,
            "transactionType": "fungible",
            "transactionSubtype": "incoming",
            "amount": "2.5",
            "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "timestamp": 1754393687000
          }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TatumV4TransactionResponse.self, from: data)

        XCTAssertEqual(
            response.result.first?.tokenAddress,
            "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
        XCTAssertEqual(response.result.first?.transactionIndex, 7)
    }

    func testTatumV4LogIndexSurvivesDecodingAndDistinguishesMovementIdentity() throws {
        let data = """
        {
          "result": [
            {
              "chain": "ethereum-mainnet",
              "hash": "0xshared-log-transaction",
              "address": "0x00000000000000000000000000000000000000aa",
              "transactionIndex": 7,
              "logIndex": 11,
              "transactionType": "fungible",
              "transactionSubtype": "incoming",
              "amount": "2.5",
              "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
              "timestamp": 1754393687000,
              "counterAddress": "0x00000000000000000000000000000000000000bb"
            },
            {
              "chain": "ethereum-mainnet",
              "hash": "0xshared-log-transaction",
              "address": "0x00000000000000000000000000000000000000aa",
              "transactionIndex": 7,
              "logIndex": 12,
              "transactionType": "fungible",
              "transactionSubtype": "incoming",
              "amount": "2.5",
              "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
              "timestamp": 1754393687000,
              "counterAddress": "0x00000000000000000000000000000000000000bb"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TatumV4TransactionResponse.self, from: data)

        XCTAssertEqual(response.result.count, 2)
        XCTAssertNotEqual(response.result[0].movementIdentity, response.result[1].movementIdentity)
        let encoded = try JSONEncoder().encode(response.result[0])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["logIndex"] as? Int, 11)
    }
    
    func testTatumTransactionNativeValueCalculation() throws {
        // Create a transaction using the v4 API data
        let transaction = TatumTransaction(
            hash: "0x997d6ed680e3556b01cf474d1e6027dc9fd21e28d3b30ec3ac3c8be949b11bec",
            blockNumber: 23074598,
            timestamp: 1754393687000,
            from: nil,
            to: nil,
            value: nil,
            gasUsed: nil,
            gasPrice: nil,
            tokenTransfers: nil,
            chain: "ethereum-mainnet",
            address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "0.133276145314559",
            counterAddress: "0x963737c550e70ffe4d59464542a28604edb2ef9a"
        )
        
        // Test that nativeValue correctly uses the v4 amount field
        XCTAssertEqual(transaction.nativeValue, 0.133276145314559, accuracy: 0.000000000000001)
        
        // Test date conversion (v4 uses milliseconds)
        let expectedDate = Date(timeIntervalSince1970: 1754393687000.0 / 1000.0)
        XCTAssertEqual(transaction.date.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testTatumServiceChainMapping() throws {
        let chainService = ChainService()
        let testCases: [(input: String, expected: String)] = [
            ("ETH", "ethereum-mainnet"),
            ("MATIC", "polygon-mainnet"),
            ("BSC", "bsc-mainnet"),
            ("AVAX", "avax-mainnet"),
            ("CELO", "celo-mainnet")
        ]

        for testCase in testCases {
            XCTAssertEqual(
                chainService.getV4ChainName(for: testCase.input),
                testCase.expected,
                "Chain mapping for \(testCase.input) should be \(testCase.expected)"
            )
        }

        XCTAssertNil(
            chainService.getV4ChainName(for: "FTM"),
            "Fantom is not accepted by Tatum's v4 wallet-portfolio chain enum"
        )
    }
    
    func testTransactionHistoryAPIRequestFormat() throws {
        let address = "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b"
        let client = TatumClient()

        let nativeRequests = try TransactionService.makeV4HistoryRequests(
            chainId: "ETH",
            address: address,
            currency: "ETH",
            limit: 500,
            client: client,
            chainService: ChainService()
        )
        let tokenRequests = try TransactionService.makeV4HistoryRequests(
            chainId: "ETH",
            address: address,
            currency: "USDT",
            limit: 0,
            client: client,
            chainService: ChainService()
        )

        XCTAssertEqual(nativeRequests.count, 1)
        XCTAssertEqual(tokenRequests.count, 1)

        let nativeQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(nativeRequests.first?.url), resolvingAgainstBaseURL: false)
        )
        let tokenQuery = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(tokenRequests.first?.url), resolvingAgainstBaseURL: false)
        )
        let nativeValues = Dictionary(
            uniqueKeysWithValues: (nativeQuery.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        let tokenValues = Dictionary(
            uniqueKeysWithValues: (tokenQuery.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        XCTAssertEqual(nativeValues["chain"], "ethereum-mainnet")
        XCTAssertEqual(nativeValues["addresses"], address)
        XCTAssertEqual(nativeValues["transactionTypes"], "native")
        XCTAssertEqual(nativeValues["sort"], "DESC")
        XCTAssertEqual(nativeValues["pageSize"], "50")
        XCTAssertEqual(nativeValues["offset"], "0")
        XCTAssertNil(nativeValues["tokenAddress"])
        XCTAssertEqual(tokenValues["transactionTypes"], "fungible")
        XCTAssertEqual(tokenValues["pageSize"], "1")
        XCTAssertEqual(tokenValues["offset"], "0")
        XCTAssertEqual(
            tokenValues["tokenAddress"],
            "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
    }
    
    func testTatumTransactionCompatibilityWithExistingCode() throws {
        // Test that the TatumTransaction model works with both v3 and v4 fields
        
        // v3 style transaction (legacy)
        let v3Transaction = TatumTransaction(
            hash: "0xlegacyhash",
            blockNumber: 12345,
            timestamp: 1600000000, // seconds (v3 style)
            from: "0xfrom",
            to: "0xto",
            value: "1000000000000000000", // 1 ETH in wei
            gasUsed: "21000",
            gasPrice: "20000000000",
            tokenTransfers: nil
        )
        
        // Should convert wei to ETH for nativeValue
        XCTAssertEqual(v3Transaction.nativeValue, 1.0, accuracy: 0.000000000000001)
        
        // Should handle seconds timestamp (v3 actually treats as milliseconds in our implementation)
        let expectedV3Date = Date(timeIntervalSince1970: 1600000000.0 / 1000.0)
        XCTAssertEqual(v3Transaction.date.timeIntervalSince1970, expectedV3Date.timeIntervalSince1970, accuracy: 1.0)
        
        // v4 style transaction (new)
        let v4Transaction = TatumTransaction(
            hash: "0xv4hash",
            blockNumber: 23074598,
            timestamp: 1754393687000, // milliseconds (v4 style)
            from: nil,
            to: nil,
            value: nil,
            gasUsed: nil,
            gasPrice: nil,
            tokenTransfers: nil,
            chain: "ethereum-mainnet",
            address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "0.133276145314559", // Already in ETH
            counterAddress: "0x963737c550e70ffe4d59464542a28604edb2ef9a"
        )
        
        // Should use amount field directly for nativeValue
        XCTAssertEqual(v4Transaction.nativeValue, 0.133276145314559, accuracy: 0.000000000000001)
        
        // Should handle milliseconds timestamp
        let expectedV4Date = Date(timeIntervalSince1970: 1754393687000.0 / 1000.0)
        XCTAssertEqual(v4Transaction.date.timeIntervalSince1970, expectedV4Date.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testTransactionDisplayInUI() throws {
        // Test data that would be displayed in AssetRowView
        let transaction = TatumTransaction(
            hash: "0x997d6ed680e3556b01cf474d1e6027dc9fd21e28d3b30ec3ac3c8be949b11bec",
            blockNumber: 23074598,
            timestamp: 1754393687000,
            from: nil,
            to: nil,
            value: nil,
            gasUsed: nil,
            gasPrice: nil,
            tokenTransfers: nil,
            chain: "ethereum-mainnet",
            address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "0.133276145314559",
            counterAddress: "0x963737c550e70ffe4d59464542a28604edb2ef9a"
        )
        
        // Test the formatted values that would appear in UI
        let formattedAmount = String(format: "%.8f", transaction.nativeValue)
        XCTAssertEqual(formattedAmount, "0.13327615")
        
        // Test that the transaction shows as positive (incoming)
        XCTAssertTrue(transaction.nativeValue > 0)
        
        // Test date formatting
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let formattedDate = dateFormatter.string(from: transaction.date)
        
        // The timestamp 1754393687000 (ms) = 1754393687 (s) = roughly year 2025
        // Just verify it's a valid date string
        XCTAssertFalse(formattedDate.isEmpty)
    }

    func testIncomingAndOutgoingSubtypesPersistSignedAmountsBeforeAddressFallback() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(currency: "ETH", address: "0xtracked", chainId: "ETH")
        context.insert(asset)
        try context.save()

        let incoming = TatumTransaction(
            hash: "incoming-hash",
            from: "0xtracked",
            to: "0xother",
            chain: "ethereum-mainnet",
            address: "0xtracked",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1.25"
        )
        let outgoing = TatumTransaction(
            hash: "outgoing-hash",
            from: "0xother",
            to: "0xtracked",
            chain: "ethereum-mainnet",
            address: "0xtracked",
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "0.4"
        )

        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [incoming, outgoing], for: asset), 2)

        let imported = asset.transactions ?? []
        XCTAssertEqual(
            try XCTUnwrap(imported.first { $0.externalId?.contains("|incoming-hash|") == true }).amount,
            1.25,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(imported.first { $0.externalId?.contains("|outgoing-hash|") == true }).amount,
            -0.4,
            accuracy: 0.000_000_001
        )
    }

    func testImportPersistsDistinctLogsFromTheSameEVMTransaction() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()
        let data = """
        [
          {
            "chain": "ethereum-mainnet",
            "hash": "0xshared-import-transaction",
            "address": "\(trackedAddress)",
            "transactionIndex": 7,
            "logIndex": 11,
            "transactionType": "fungible",
            "transactionSubtype": "incoming",
            "amount": "2.5",
            "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "timestamp": 1754393687000,
            "counterAddress": "0x00000000000000000000000000000000000000bb"
          },
          {
            "chain": "ethereum-mainnet",
            "hash": "0xshared-import-transaction",
            "address": "\(trackedAddress)",
            "transactionIndex": 7,
            "logIndex": 12,
            "transactionType": "fungible",
            "transactionSubtype": "incoming",
            "amount": "2.5",
            "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "timestamp": 1754393687000,
            "counterAddress": "0x00000000000000000000000000000000000000bb"
          }
        ]
        """.data(using: .utf8)!
        let movements = try JSONDecoder().decode([TatumTransaction].self, from: data)

        let inserted = try OnChainTransactionImportService(modelContext: context).upsert(
            transactions: movements,
            for: asset
        )

        XCTAssertEqual(inserted, 2)
        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(Set(imported.compactMap(\.externalId)).count, 2)
    }

    func testProviderCorrectionAcrossRefreshUpdatesCanonicalRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let original = TatumTransaction(
            hash: "0xprovider-correction",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1",
            counterAddress: "0x00000000000000000000000000000000000000bb"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(
            try service.upsert(transactions: [original], for: asset),
            1
        )

        let originalRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let originalRowID = originalRow.id
        originalRow.comment = "Preserve user note"
        try context.save()

        let corrected = TatumTransaction(
            hash: "0xprovider-correction",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "2",
            counterAddress: "0x00000000000000000000000000000000000000bb"
        )

        XCTAssertEqual(
            try service.upsert(transactions: [corrected], for: asset),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, originalRowID)
        XCTAssertEqual(rows.first?.amount, -2)
        XCTAssertEqual(rows.first?.date, corrected.date)
        XCTAssertEqual(rows.first?.comment, "Preserve user note")
    }

    func testProviderAmountCorrectionRebalancesDedicatedAllocation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000c01"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let goal = TestDataFactory.createSampleGoal(name: "Corrected deposit goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(asset)
        context.insert(goal)
        context.insert(allocation)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(1, for: cacheKey)

        let original = TatumTransaction(
            hash: "0xprovider-allocation-correction",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 17,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [original], for: asset), 1)
        XCTAssertEqual(allocation.amountValue, 1, accuracy: 0.000_000_001)

        BalanceCacheManager.shared.cacheBalance(2, for: cacheKey)
        let corrected = TatumTransaction(
            hash: original.hash,
            timestamp: 1_750_000_100_000,
            chain: original.chain,
            address: trackedAddress,
            transactionIndex: original.transactionIndex,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertEqual(try service.upsert(transactions: [corrected], for: asset), 1)
        XCTAssertEqual(allocation.amountValue, 2, accuracy: 0.000_000_001)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id && $0.goalId == goal.id }
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(try XCTUnwrap(histories.first?.amount), 2, accuracy: 0.000_000_001)
        XCTAssertEqual(histories.first?.timestamp, corrected.date)
        XCTAssertEqual(histories.first?.sourceTransactionId, asset.transactions?.first?.id)
        XCTAssertFalse(histories.contains { $0.timestamp == original.date })
    }

    func testLegacyUnlinkedProviderAllocationBlocksCorrectionWithStaleBalance() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000c09"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let goal = TestDataFactory.createSampleGoal(name: "Legacy correction goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(asset)
        context.insert(goal)
        context.insert(allocation)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(1, for: cacheKey)
        let original = TatumTransaction(
            hash: "0xlegacy-provider-allocation-correction",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 29,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [original], for: asset), 1)
        let storedTransaction = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let legacyHistory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<AllocationHistory>())
                .first { $0.sourceTransactionId == storedTransaction.id }
        )
        legacyHistory.sourceTransactionId = nil
        legacyHistory.sourcePreviousAmount = nil
        try context.save()

        // Keep the old balance cached. The transaction refresh is allowed to
        // arrive before a later balance refresh, so this cannot prove a safe
        // independent correction.
        BalanceCacheManager.shared.cacheBalance(1, for: cacheKey)
        let corrected = TatumTransaction(
            hash: original.hash,
            timestamp: 1_750_000_100_000,
            chain: original.chain,
            address: trackedAddress,
            transactionIndex: original.transactionIndex,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertThrowsError(
            try service.upsert(transactions: [corrected], for: asset)
        ) { error in
            guard case OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(let transactionID) = error
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(transactionID, storedTransaction.id)
        }

        context.processPendingChanges()
        XCTAssertEqual(storedTransaction.amount, 1, accuracy: 0.000_000_001)
        XCTAssertEqual(storedTransaction.date, original.date)
        XCTAssertEqual(allocation.amountValue, 1, accuracy: 0.000_000_001)
        XCTAssertEqual(legacyHistory.amount, 1, accuracy: 0.000_000_001)
        XCTAssertNil(legacyHistory.sourceTransactionId)
        XCTAssertFalse(context.hasChanges)
    }

    func testBackfilledDepositBeforeLaterManualHistoryStaysUnallocated() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000c0a"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let goal = TestDataFactory.createSampleGoal(name: "Backfill chronology goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 100)
        let laterManualHistory = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 100,
            timestamp: Date(timeIntervalSince1970: 1_750_000_200),
            sourceTransactionId: nil,
            sourcePreviousAmount: nil
        )
        asset.allocations = [allocation]
        asset.allocationHistory = [laterManualHistory]
        goal.allocations = [allocation]
        goal.allocationHistory = [laterManualHistory]
        context.insert(asset)
        context.insert(goal)
        context.insert(allocation)
        context.insert(laterManualHistory)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(110, for: cacheKey)
        let backfilled = TatumTransaction(
            hash: "0xbackfilled-before-manual-history",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 30,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "10"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [backfilled],
                for: asset
            ),
            1
        )

        context.processPendingChanges()
        let imported = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id && $0.goalId == goal.id }
        XCTAssertEqual(allocation.amountValue, 100, accuracy: 0.000_000_001)
        XCTAssertEqual(histories.map(\.id), [laterManualHistory.id])
        XCTAssertFalse(histories.contains { $0.sourceTransactionId == imported.id })
        XCTAssertEqual(
            histories.sorted { $0.timestamp < $1.timestamp }.last?.amount,
            allocation.amountValue
        )
        XCTAssertFalse(context.hasChanges)
    }

    func testProviderDirectionCorrectionRebalancesDedicatedAllocationDownward() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000c02"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let goal = TestDataFactory.createSampleGoal(name: "Corrected direction goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 4)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(asset)
        context.insert(goal)
        context.insert(allocation)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(5, for: cacheKey)

        let original = TatumTransaction(
            hash: "0xprovider-direction-correction",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 18,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [original], for: asset), 1)
        XCTAssertEqual(allocation.amountValue, 5, accuracy: 0.000_000_001)

        BalanceCacheManager.shared.cacheBalance(2, for: cacheKey)
        let corrected = TatumTransaction(
            hash: original.hash,
            timestamp: 1_750_000_100_000,
            chain: original.chain,
            address: trackedAddress,
            transactionIndex: original.transactionIndex,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "2"
        )

        XCTAssertEqual(try service.upsert(transactions: [corrected], for: asset), 1)
        XCTAssertEqual(allocation.amountValue, 2, accuracy: 0.000_000_001)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id && $0.goalId == goal.id }
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(try XCTUnwrap(histories.first?.amount), 2, accuracy: 0.000_000_001)
        XCTAssertEqual(histories.first?.timestamp, corrected.date)
        XCTAssertEqual(histories.first?.sourceTransactionId, asset.transactions?.first?.id)
    }

    func testProviderCorrectionSaveFailureRestoresDedicatedAllocationAndHistory() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000c03"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let goal = TestDataFactory.createSampleGoal(name: "Correction rollback goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(asset)
        context.insert(goal)
        context.insert(allocation)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(1, for: cacheKey)
        let original = TatumTransaction(
            hash: "0xprovider-correction-rollback",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 19,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [original],
                for: asset
            ),
            1
        )
        XCTAssertEqual(allocation.amountValue, 1, accuracy: 0.000_000_001)

        BalanceCacheManager.shared.cacheBalance(2, for: cacheKey)
        let corrected = TatumTransaction(
            hash: original.hash,
            timestamp: 1_750_000_100_000,
            chain: original.chain,
            address: trackedAddress,
            transactionIndex: original.transactionIndex,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let failingService = OnChainTransactionImportService(
            modelContext: context,
            saveChanges: { throw ForcedSaveError.failed }
        )

        XCTAssertThrowsError(
            try failingService.upsert(transactions: [corrected], for: asset)
        )
        context.processPendingChanges()
        XCTAssertEqual(allocation.amountValue, 1, accuracy: 0.000_000_001)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id && $0.goalId == goal.id }
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(try XCTUnwrap(histories.first?.amount), 1, accuracy: 0.000_000_001)
        let durable = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        XCTAssertEqual(durable.amount, 1, accuracy: 0.000_000_001)
        XCTAssertEqual(durable.date, original.date)
    }

    func testUTXOProviderCorrectionUpdatesCanonicalRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qprovidercorrection"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        let original = TatumTransaction(
            hash: "btc-provider-correction",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "incoming",
            amount: "1",
            counterAddress: "bc1qoriginalsender"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [original], for: asset), 1)
        let originalRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let originalRowID = originalRow.id

        let corrected = TatumTransaction(
            hash: "btc-provider-correction",
            timestamp: 1_750_000_100_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "incoming",
            amount: "2",
            counterAddress: "bc1qcorrectedsender"
        )

        XCTAssertEqual(try service.upsert(transactions: [corrected], for: asset), 1)

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, originalRowID)
        XCTAssertEqual(rows.first?.amount, 2)
        XCTAssertEqual(rows.first?.date, corrected.date)
        XCTAssertEqual(rows.first?.counterparty, "bc1qoriginalsender")
    }

    func testProviderIndexEnrichmentUpdatesUniqueCanonicalRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let original = TatumTransaction(
            hash: "0xprovider-index-enrichment",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [original], for: asset), 1)
        let originalRowID = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        ).id

        let enriched = TatumTransaction(
            hash: "0xprovider-index-enrichment",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertEqual(try service.upsert(transactions: [enriched], for: asset), 1)

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, originalRowID)
        XCTAssertEqual(rows.first?.amount, 2)
        XCTAssertTrue(rows.first?.externalId?.hasSuffix("|11") == true)
    }

    func testProviderLogIndexEnrichmentUpdatesTransactionIndexedRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let transactionIndexed = TatumTransaction(
            hash: "0xpartial-index-enrichment",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [transactionIndexed], for: asset), 1)
        let originalRowID = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        ).id

        let logIndexed = TatumTransaction(
            hash: transactionIndexed.hash,
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertEqual(try service.upsert(transactions: [logIndexed], for: asset), 1)

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, originalRowID)
        XCTAssertEqual(rows.first?.amount, 2)
        XCTAssertTrue(rows.first?.externalId?.hasSuffix("|11") == true)
    }

    func testSameBatchWeakAndEnrichedProviderRowsCollapseToEnrichedIdentity() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let weak = TatumTransaction(
            hash: "0xsame-batch-index-enrichment",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let enriched = TatumTransaction(
            hash: weak.hash,
            timestamp: weak.timestamp,
            chain: weak.chain,
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [weak, enriched],
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.first?.externalId?.hasSuffix("|11") == true)
    }

    func testSameBatchWeakProviderRowWithTwoIndexedEventsFailsBeforeWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let weak = TatumTransaction(
            hash: "0xsame-batch-ambiguous-index",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let firstIndexed = TatumTransaction(
            hash: weak.hash,
            timestamp: weak.timestamp,
            chain: weak.chain,
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let secondIndexed = TatumTransaction(
            hash: weak.hash,
            timestamp: weak.timestamp,
            chain: weak.chain,
            address: trackedAddress,
            transactionIndex: 8,
            logIndex: 12,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [weak, firstIndexed, secondIndexed],
                for: asset
            )
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Transaction>())
                .filter { $0.source == .onChain }
                .count,
            0
        )
    }

    func testProviderPartialIndexOmissionFailsClosedBeforeWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let fullyIndexed = TatumTransaction(
            hash: "0xpartial-index-omission",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [fullyIndexed], for: asset), 1)
        let originalRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let originalExternalID = originalRow.externalId

        let missingLogIndex = TatumTransaction(
            hash: fullyIndexed.hash,
            timestamp: 1_750_000_100_000,
            chain: fullyIndexed.chain,
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertThrowsError(
            try service.upsert(transactions: [missingLogIndex], for: asset)
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, originalRow.id)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.externalId, originalExternalID)
    }

    func testProviderIndexEnrichmentFailsClosedWhenWeakRowMapsToMultipleEvents() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let weak = TatumTransaction(
            hash: "0xambiguous-index-enrichment",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(try service.upsert(transactions: [weak], for: asset), 1)
        let weakRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Transaction>())
                .first { $0.source == .onChain }
        )
        let weakRowID = weakRow.id
        let weakExternalID = weakRow.externalId

        let firstEnriched = TatumTransaction(
            hash: weak.hash,
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let secondEnriched = TatumTransaction(
            hash: weak.hash,
            timestamp: 1_750_000_200_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 8,
            logIndex: 12,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "3"
        )

        XCTAssertThrowsError(
            try service.upsert(
                transactions: [firstEnriched, secondEnriched],
                for: asset
            )
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, weakRowID)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.externalId, weakExternalID)
    }

    func testProviderCorrectionMigratesOldV3LogRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
        let oldExternalID = """
        onchain_v3|eth|\(trackedAddress)|eth|\(asset.id.uuidString.lowercased())|0xold-provider-correction|ethereum-mainnet|\(trackedAddress)|7|native||incoming|0x00000000000000000000000000000000000000bb|||3ff0000000000000|1750000000000|11
        """
        let oldRow = Transaction(
            amount: 1,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            source: .onChain,
            externalId: oldExternalID,
            counterparty: "Preserve custom counterparty",
            comment: "Preserve user note"
        )
        context.insert(asset)
        context.insert(oldRow)
        try context.save()
        let oldRowID = oldRow.id

        let corrected = TatumTransaction(
            hash: "0xold-provider-correction",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "2",
            counterAddress: "0x00000000000000000000000000000000000000cc"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [corrected],
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, oldRowID)
        XCTAssertEqual(rows.first?.amount, -2)
        XCTAssertEqual(rows.first?.date, corrected.date)
        XCTAssertEqual(rows.first?.comment, "Preserve user note")
        XCTAssertEqual(rows.first?.counterparty, "Preserve custom counterparty")
        XCTAssertTrue(rows.first?.externalId?.contains("|record_v1|") == true)
        XCTAssertTrue(rows.first?.externalId?.hasSuffix("|11") == true)
    }

    func testProviderCorrectionMigratesExactCaseOldV4SolanaRowWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "SolanaCaseSensitiveWallet"
        let asset = Asset(currency: "SOL", address: trackedAddress, chainId: "SOL")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!
        let oldExternalID = """
        onchain_v4|sol|\(trackedAddress)|sol|\(asset.id.uuidString.lowercased())|CaseSensitiveSignature|SOL|\(trackedAddress)||native||incoming||||3ff0000000000000|1750000000000
        """
        let oldRow = Transaction(
            amount: 1,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            source: .onChain,
            externalId: oldExternalID,
            comment: "Preserve exact-case row"
        )
        context.insert(asset)
        context.insert(oldRow)
        try context.save()
        let oldRowID = oldRow.id

        let corrected = TatumTransaction(
            hash: "CaseSensitiveSignature",
            timestamp: 1_750_000_100_000,
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [corrected],
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, oldRowID)
        XCTAssertEqual(rows.first?.amount, 2)
        XCTAssertEqual(rows.first?.date, corrected.date)
        XCTAssertEqual(rows.first?.comment, "Preserve exact-case row")
        XCTAssertTrue(rows.first?.externalId?.contains("|record_v1|") == true)
        XCTAssertTrue(rows.first?.externalId?.contains("|CaseSensitiveSignature|") == true)
    }

    func testAmbiguousOldProviderRowsFailBeforeCorrectionWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
        let scope = "onchain_v3|eth|\(trackedAddress)|eth|\(asset.id.uuidString.lowercased())"
        let first = Transaction(
            amount: 1,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            source: .onChain,
            externalId: """
            \(scope)|0xambiguous-provider-correction|ethereum-mainnet|\(trackedAddress)|7|native||incoming||||3ff0000000000000|1750000000000|11
            """,
            comment: "First"
        )
        let second = Transaction(
            amount: 2,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_750_000_100),
            source: .onChain,
            externalId: """
            \(scope)|0xambiguous-provider-correction|ethereum-mainnet|\(trackedAddress)|7|native||incoming||||4000000000000000|1750000100000|11
            """,
            comment: "Second"
        )
        context.insert(asset)
        context.insert(first)
        context.insert(second)
        try context.save()

        let corrected = TatumTransaction(
            hash: "0xambiguous-provider-correction",
            timestamp: 1_750_000_200_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "3"
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [corrected],
                for: asset
            )
        )
        XCTAssertEqual(first.amount, 1)
        XCTAssertEqual(second.amount, 2)
        XCTAssertEqual(first.comment, "First")
        XCTAssertEqual(second.comment, "Second")
    }

    func testTokenImportFailsClosedForNativeAndCounterfeitTransactions() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let native = TatumTransaction(
            hash: "native-hash",
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "5"
        )
        let counterfeit = TatumTransaction(
            hash: "counterfeit-hash",
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "500",
            tokenAddress: "0x0000000000000000000000000000000000000bad"
        )
        let canonical = TatumTransaction(
            hash: "canonical-hash",
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "2.5",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )

        let inserted = try OnChainTransactionImportService(modelContext: context).upsert(
            transactions: [native, counterfeit, canonical],
            for: asset
        )

        XCTAssertEqual(inserted, 1)
        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 1)
        XCTAssertTrue(imported.first?.externalId?.contains("|canonical-hash|") == true)
        XCTAssertEqual(try XCTUnwrap(imported.first?.amount), 2.5, accuracy: 0.000_000_001)
    }

    func testFilteredImportRepairsOnlyLegacyRowConfirmedByCanonicalHash() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000bb"
        let goal = TestDataFactory.createSampleGoal(name: "Legacy history owner")
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 7)
        let unrelatedHistory = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 7,
            timestamp: Date(timeIntervalSince1970: 1_500_000_000)
        )
        let confirmedLegacy = Transaction(
            amount: 4,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: "confirmed-hash",
            counterparty: "original-counterparty",
            comment: "Keep this note"
        )
        let unmatchedLegacy = Transaction(
            amount: 9,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_600_000_000),
            source: .onChain,
            externalId: "unmatched-hash",
            comment: "On-chain"
        )
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(unrelatedHistory)
        context.insert(confirmedLegacy)
        context.insert(unmatchedLegacy)
        try context.save()
        let confirmedLegacyID = confirmedLegacy.id

        let canonical = TatumTransaction(
            hash: "confirmed-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "2.5",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
        let inserted = try OnChainTransactionImportService(modelContext: context).upsert(
            transactions: [canonical],
            for: asset
        )

        XCTAssertEqual(inserted, 1)
        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(imported.first { $0.externalId?.contains("|confirmed-hash|") == true }).amount,
            2.5,
            accuracy: 0.000_000_001
        )
        let reconciled = try XCTUnwrap(
            imported.first { $0.externalId?.contains("|confirmed-hash|") == true }
        )
        XCTAssertEqual(reconciled.counterparty, "original-counterparty")
        XCTAssertEqual(reconciled.comment, "Keep this note")
        XCTAssertEqual(reconciled.source, .onChain)
        XCTAssertEqual(reconciled.id, confirmedLegacyID)
        XCTAssertEqual(
            try XCTUnwrap(imported.first { $0.externalId == "unmatched-hash" }).amount,
            9,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(allocation.amountValue, 7, accuracy: 0.000_000_001)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(histories.first?.amount, 7)
    }

    func testAmbiguousLegacyHashAndMissingLogDiscriminatorFailBeforeBatchWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000cc"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        let ambiguousLegacy = Transaction(
            amount: 99,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: "shared-hash",
            comment: "On-chain"
        )
        context.insert(asset)
        context.insert(ambiguousLegacy)
        try context.save()

        let incoming = TatumTransaction(
            hash: "shared-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 42,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "5",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000001"
        )
        let outgoing = TatumTransaction(
            hash: "shared-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 42,
            transactionType: "fungible",
            transactionSubtype: "outgoing",
            amount: "2",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000002"
        )
        let unrelated = TatumTransaction(
            hash: "unrelated-hash",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 43,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "7",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000003"
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [unrelated, incoming, outgoing],
                for: asset
            )
        )

        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first { $0.id == ambiguousLegacy.id }?.externalId, "shared-hash")
        XCTAssertEqual(imported.first { $0.id == ambiguousLegacy.id }?.amount, 99)
    }

    func testLegacyHashOnAnotherAssetStaysQuarantinedWhileCanonicalMovementImports() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000dd"
        let currentAsset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        let otherAsset = Asset(
            currency: "USDC",
            address: "0x00000000000000000000000000000000000000ee",
            chainId: "ETH"
        )
        let crossAssetLegacy = Transaction(
            amount: 12,
            asset: otherAsset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: "cross-asset-hash",
            comment: "On-chain"
        )
        context.insert(currentAsset)
        context.insert(otherAsset)
        context.insert(crossAssetLegacy)
        try context.save()

        let canonical = TatumTransaction(
            hash: "cross-asset-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 51,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "3",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000004"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [canonical],
                for: currentAsset
            ),
            1
        )

        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(
            currentAsset.transactions?.filter {
                $0.externalId?.contains("|cross-asset-hash|") == true
            }.count,
            1
        )
        XCTAssertEqual(otherAsset.transactions?.map(\.id), [crossAssetLegacy.id])
        XCTAssertEqual(crossAssetLegacy.externalId, "cross-asset-hash")
        XCTAssertEqual(crossAssetLegacy.amount, 12)
    }

    func testExistingCanonicalAndLegacyRowsCollapseToLegacyIdentityWithoutDoubleCount() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000ff"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let canonical = TatumTransaction(
            hash: "already-canonical-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 61,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "4",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000005"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [canonical],
                for: asset
            ),
            1
        )
        let existingCanonical = try XCTUnwrap(
            asset.transactions?.first { $0.externalId?.hasPrefix("onchain_v3|") == true }
        )
        let existingCanonicalID = existingCanonical.id

        let legacy = Transaction(
            amount: 99,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: "already-canonical-hash",
            counterparty: "preserved-counterparty",
            comment: "Preserve this note"
        )
        let legacyID = legacy.id
        context.insert(legacy)
        asset.transactions = (asset.transactions ?? []) + [legacy]
        try context.save()

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [canonical],
                for: asset
            ),
            1
        )

        context.processPendingChanges()
        let imported = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(imported.count, 1)
        let reconciled = try XCTUnwrap(imported.first)
        XCTAssertEqual(reconciled.id, legacyID)
        XCTAssertNotEqual(reconciled.id, existingCanonicalID)
        XCTAssertEqual(reconciled.amount, 4, accuracy: 0.000_000_001)
        XCTAssertTrue(reconciled.externalId?.hasPrefix("onchain_v3|") == true)
        XCTAssertEqual(reconciled.counterparty, "preserved-counterparty")
        XCTAssertEqual(reconciled.comment, "Preserve this note")
    }

    func testImportSaveFailureRestoresOnlyOperationOwnedState() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0xrollback0000000000000000000000000000000001"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let existingMovement = TatumTransaction(
            hash: "rollback-existing-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 71,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "4",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000006"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [existingMovement],
                for: asset
            ),
            1
        )
        let existingCanonical = try XCTUnwrap(
            asset.transactions?.first { $0.externalId?.hasPrefix("onchain_v3|") == true }
        )

        let goal = TestDataFactory.createSampleGoal(name: "Rollback Goal")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 10)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = Transaction(
            amount: 99,
            asset: asset,
            date: legacyDate,
            source: .onChain,
            externalId: "rollback-existing-hash",
            counterparty: "rollback-counterparty",
            comment: "Rollback note"
        )
        asset.transactions = (asset.transactions ?? []) + [legacy]
        context.insert(goal)
        context.insert(allocation)
        context.insert(legacy)
        try context.saveWithRelationships()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "USDT"
        )
        BalanceCacheManager.shared.cacheBalance(15, for: cacheKey)
        let originalAllocationModifiedAt = allocation.lastModifiedDate
        let originalTransactionIDs = Set([existingCanonical.id, legacy.id])

        let newMovement = TatumTransaction(
            hash: "rollback-new-hash",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 72,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "5",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            counterAddress: "0x0000000000000000000000000000000000000007"
        )
        let service = OnChainTransactionImportService(
            modelContext: context,
            saveChanges: { throw ForcedSaveError.failed }
        )

        XCTAssertThrowsError(
            try service.upsert(
                transactions: [existingMovement, newMovement],
                for: asset
            )
        )

        context.processPendingChanges()
        let persistedTransactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(Set(persistedTransactions.map(\.id)), originalTransactionIDs)
        XCTAssertEqual(Set(asset.transactions?.map(\.id) ?? []), originalTransactionIDs)
        XCTAssertEqual(existingCanonical.amount, 4, accuracy: 0.000_000_001)
        XCTAssertTrue(existingCanonical.externalId?.hasPrefix("onchain_v3|") == true)
        XCTAssertEqual(legacy.amount, 99, accuracy: 0.000_000_001)
        XCTAssertEqual(legacy.date, legacyDate)
        XCTAssertEqual(legacy.externalId, "rollback-existing-hash")
        XCTAssertEqual(legacy.counterparty, "rollback-counterparty")
        XCTAssertEqual(legacy.comment, "Rollback note")
        XCTAssertEqual(allocation.amountValue, 10, accuracy: 0.000_000_001)
        XCTAssertEqual(allocation.lastModifiedDate, originalAllocationModifiedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        XCTAssertEqual(asset.currentAmount, 15, accuracy: 0.000_000_001)

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [existingMovement, newMovement],
                for: asset
            ),
            2
        )
        context.processPendingChanges()
        let retriedTransactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(retriedTransactions.count, 2)
        XCTAssertEqual(
            retriedTransactions.filter { $0.externalId?.contains("rollback-existing-hash") == true }.count,
            1
        )
        XCTAssertEqual(
            retriedTransactions.filter { $0.externalId?.contains("rollback-new-hash") == true }.count,
            1
        )
        XCTAssertEqual(allocation.amountValue, 15, accuracy: 0.000_000_001)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(try XCTUnwrap(histories.first?.amount), 15, accuracy: 0.000_000_001)

        let freshContext = ModelContext(container)
        let freshOnChain = try freshContext.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(freshOnChain.count, 2)
        XCTAssertEqual(
            freshOnChain.filter { $0.externalId?.contains("rollback-existing-hash") == true }.count,
            1
        )
        let freshExisting = try XCTUnwrap(
            freshOnChain.first { $0.externalId?.contains("rollback-existing-hash") == true }
        )
        XCTAssertEqual(freshExisting.id, legacy.id)
        XCTAssertEqual(freshExisting.counterparty, "rollback-counterparty")
        XCTAssertEqual(freshExisting.comment, "Rollback note")
    }

    func testMovementIdentityFoldsHexTransactionIDsButPreservesSolanaSignaturesAndAddresses() {
        let evmMixedCase = TatumTransaction(
            hash: "0xAbCd",
            from: "0xSender",
            to: "0xReceiver",
            chain: "ethereum-mainnet",
            address: "0xWallet",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let evmLowercase = TatumTransaction(
            hash: "0xabcd",
            from: "0xsender",
            to: "0xreceiver",
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertEqual(evmMixedCase.movementIdentity, evmLowercase.movementIdentity)

        for chainID in ["TRX", "XRP", "BTC", "LTC", "BCH", "DOGE", "ADA"] {
            let mixedCase = TatumTransaction(
                hash: "ABCDEF012345\(chainID)",
                from: "\(chainID)-Sender",
                to: "\(chainID)-Receiver",
                chain: chainID,
                address: "\(chainID)-Wallet",
                transactionType: chainID == "BTC" ? "utxo" : "native",
                transactionSubtype: "incoming",
                amount: "1"
            )
            let caseVariant = TatumTransaction(
                hash: "abcdef012345\(chainID.lowercased())",
                from: "\(chainID)-Sender",
                to: "\(chainID)-Receiver",
                chain: chainID,
                address: "\(chainID)-Wallet",
                transactionType: chainID == "BTC" ? "utxo" : "native",
                transactionSubtype: "incoming",
                amount: "1"
            )

            XCTAssertEqual(
                mixedCase.movementIdentity,
                caseVariant.movementIdentity,
                "\(chainID) transaction IDs are hexadecimal and case-insensitive"
            )
        }

        let solMixedCase = TatumTransaction(
            hash: "CaseSensitiveSignature",
            from: "Solana-Sender",
            to: "Solana-Receiver",
            chain: "SOL",
            address: "Solana-Wallet",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let solCaseVariant = TatumTransaction(
            hash: "casesensitivesignature",
            from: "Solana-Sender",
            to: "Solana-Receiver",
            chain: "SOL",
            address: "Solana-Wallet",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        XCTAssertNotEqual(solMixedCase.movementIdentity, solCaseVariant.movementIdentity)

        let tronContractCaseVariant = TatumTransaction(
            hash: "abcdef",
            from: "TRON-Sender",
            to: "TRON-Receiver",
            chain: "TRX",
            address: "TRON-Wallet",
            transactionType: "trc20",
            transactionSubtype: "incoming",
            amount: "1",
            tokenAddress: "tr7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )
        let canonicalTronContract = TatumTransaction(
            hash: "ABCDEF",
            from: "TRON-Sender",
            to: "TRON-Receiver",
            chain: "TRX",
            address: "TRON-Wallet",
            transactionType: "trc20",
            transactionSubtype: "incoming",
            amount: "1",
            tokenAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )
        XCTAssertNotEqual(
            tronContractCaseVariant.movementIdentity,
            canonicalTronContract.movementIdentity,
            "TRON Base58 contracts remain case-sensitive even though transaction hashes fold"
        )
    }

    func testImportRejectsCaseVariantTrackedAddressesOutsideEVM() throws {
        for (chainID, symbol) in [("SOL", "SOL"), ("TRX", "TRX"), ("XRP", "XRP"), ("BTC", "BTC")] {
            let container = try TestContainer.create()
            let context = ModelContext(container)
            let trackedAddress = "\(chainID)-CaseSensitiveWallet"
            let asset = Asset(currency: symbol, address: trackedAddress, chainId: chainID)
            context.insert(asset)
            try context.save()

            let caseVariant = TatumTransaction(
                hash: "\(chainID)-wrong-address",
                chain: chainID,
                address: trackedAddress.lowercased(),
                transactionType: chainID == "BTC" ? "utxo" : "native",
                transactionSubtype: "incoming",
                amount: "9"
            )
            let exact = TatumTransaction(
                hash: "\(chainID)-exact-address",
                chain: chainID,
                address: trackedAddress,
                transactionType: chainID == "BTC" ? "utxo" : "native",
                transactionSubtype: "incoming",
                amount: "2"
            )

            XCTAssertEqual(
                try OnChainTransactionImportService(modelContext: context).upsert(
                    transactions: [caseVariant, exact],
                    for: asset
                ),
                1,
                "\(chainID) must reject a case-variant tracked address"
            )
            XCTAssertEqual(asset.transactions?.count, 1)
            XCTAssertEqual(asset.transactions?.first?.amount, 2)
        }
    }

    func testImportKeepsCaseVariantSolanaSignaturesDistinct() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "SolanaCaseSensitiveWallet"
        let asset = Asset(currency: "SOL", address: trackedAddress, chainId: "SOL")
        context.insert(asset)
        try context.save()

        let mixedCaseSignature = TatumTransaction(
            hash: "CaseSensitiveSignature",
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let caseVariantSignature = TatumTransaction(
            hash: "casesensitivesignature",
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [mixedCaseSignature, caseVariantSignature],
                for: asset
            ),
            2
        )
        XCTAssertEqual(asset.transactions?.count, 2)
        XCTAssertEqual(
            Set(asset.transactions?.compactMap(\.externalId) ?? []).count,
            2
        )
    }

    func testQuickHistoryRequestsOnlyCurrentContract() throws {
        let requests = try TransactionService.makeV4HistoryRequests(
            chainId: "MATIC",
            address: "0x00000000000000000000000000000000000000aa",
            currency: "QUICK",
            limit: 50,
            client: TatumClient(),
            chainService: ChainService()
        )

        XCTAssertEqual(requests.count, 1)
        let components = try XCTUnwrap(
            URLComponents(
                url: try XCTUnwrap(requests.first?.url),
                resolvingAgainstBaseURL: false
            )
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(
            query["tokenAddress"],
            "0xB5C064F955D8e7F38fE0460C556a72987494eE17"
        )
    }

    func testQuickImportRejectsLegacyContract() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "QUICK", address: trackedAddress, chainId: "MATIC")
        context.insert(asset)
        try context.save()

        let legacy = TatumTransaction(
            hash: "legacy-quick",
            chain: "polygon-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "1000",
            tokenAddress: "0x831753DD7087CaC61aB5644b308642cc1c33Dc13"
        )
        let current = TatumTransaction(
            hash: "current-quick",
            chain: "polygon-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "1",
            tokenAddress: "0xB5C064F955D8e7F38fE0460C556a72987494eE17"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [legacy, current],
                for: asset
            ),
            1
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.amount, 1)
        XCTAssertTrue(asset.transactions?.first?.externalId?.contains("current-quick") == true)
    }

    func testQuickHashOnlyLegacyRowRemainsQuarantinedAfterCurrentContractRefresh() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "QUICK", address: trackedAddress, chainId: "MATIC")
        let hashOnlyLegacy = Transaction(
            amount: 1000,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: "shared-quick-hash",
            comment: "Unknown QUICK generation"
        )
        context.insert(asset)
        context.insert(hashOnlyLegacy)
        try context.save()

        let current = TatumTransaction(
            hash: "shared-quick-hash",
            chain: "polygon-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "1",
            tokenAddress: "0xB5C064F955D8e7F38fE0460C556a72987494eE17"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [current],
                for: asset
            ),
            1
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.id == hashOnlyLegacy.id }?.externalId, "shared-quick-hash")
        XCTAssertEqual(rows.first { $0.id == hashOnlyLegacy.id }?.amount, 1000)
        XCTAssertEqual(
            rows.first { $0.id != hashOnlyLegacy.id }?.amount,
            1
        )
        XCTAssertTrue(
            rows.first { $0.id != hashOnlyLegacy.id }?.externalId?
                .contains("0xb5c064f955d8e7f38fe0460c556a72987494ee17") == true
        )
    }

    func testUTXOImportNormalizesBech32AndCashAddrWithoutFoldingBase58() throws {
        let btcContainer = try TestContainer.create()
        let btcContext = ModelContext(btcContainer)
        let lowerBech32 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let btc = Asset(currency: "BTC", address: lowerBech32, chainId: "BTC")
        btcContext.insert(btc)
        try btcContext.save()

        let uppercaseBech32 = TatumTransaction(
            hash: "btc-bech32",
            chain: "BTC",
            address: lowerBech32.uppercased(),
            transactionType: "utxo",
            transactionSubtype: "incoming",
            amount: "1"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: btcContext).upsert(
                transactions: [uppercaseBech32],
                for: btc
            ),
            1
        )

        let bchContainer = try TestContainer.create()
        let bchContext = ModelContext(bchContainer)
        let cashAddress = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let bch = Asset(currency: "BCH", address: cashAddress, chainId: "BCH")
        bchContext.insert(bch)
        try bchContext.save()

        let prefixedUppercase = TatumTransaction(
            hash: "bch-cashaddr",
            chain: "BCH",
            address: "BITCOINCASH:\(cashAddress.uppercased())",
            transactionType: "utxo",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let invalidMixedCase = TatumTransaction(
            hash: "bch-mixed-case",
            chain: "BCH",
            address: "bitcoincash:Qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            transactionType: "utxo",
            transactionSubtype: "incoming",
            amount: "9"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: bchContext).upsert(
                transactions: [prefixedUppercase, invalidMixedCase],
                for: bch
            ),
            1
        )
        XCTAssertEqual(bch.transactions?.count, 1)
        XCTAssertEqual(bch.transactions?.first?.amount, 2)
    }

    func testUniqueLegacyCaseFoldedCanonicalIdentityUpgradesWithoutDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "SolanaCaseSensitiveWallet"
        let asset = Asset(currency: "SOL", address: trackedAddress, chainId: "SOL")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let oldExternalID = """
        onchain_v3|sol|solanacasesensitivewallet|sol|00000000-0000-0000-0000-000000000001|casesensitivesignature|sol|solanacasesensitivewallet||native||incoming||||3ff0000000000000|1750000000000
        """
        let legacyCanonical = Transaction(
            amount: 9,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: oldExternalID,
            comment: "Preserve canonical metadata"
        )
        context.insert(asset)
        context.insert(legacyCanonical)
        try context.save()
        let legacyID = legacyCanonical.id

        let refreshed = TatumTransaction(
            hash: "CaseSensitiveSignature",
            timestamp: 1_750_000_000_000,
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [refreshed],
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, legacyID)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.comment, "Preserve canonical metadata")
        XCTAssertEqual(
            rows.first?.externalId,
            """
            onchain_v4|sol|SolanaCaseSensitiveWallet|sol|00000000-0000-0000-0000-000000000001|record_v1|CaseSensitiveSignature|sol|SolanaCaseSensitiveWallet||native|
            """
        )
    }

    func testAmbiguousLegacyCaseFoldedCanonicalIdentityFailsBeforeWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "SolanaCaseSensitiveWallet"
        let asset = Asset(currency: "SOL", address: trackedAddress, chainId: "SOL")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let oldExternalID = """
        onchain_v3|sol|solanacasesensitivewallet|sol|00000000-0000-0000-0000-000000000002|casesensitivesignature|sol|solanacasesensitivewallet||native||incoming||||3ff0000000000000|
        """
        let legacyCanonical = Transaction(
            amount: 9,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: .onChain,
            externalId: oldExternalID,
            comment: "Must remain untouched"
        )
        context.insert(asset)
        context.insert(legacyCanonical)
        try context.save()

        let first = TatumTransaction(
            hash: "CaseSensitiveSignature",
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let second = TatumTransaction(
            hash: "casesensitivesignature",
            chain: "SOL",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [first, second],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(legacyCanonical.externalId, oldExternalID)
        XCTAssertEqual(legacyCanonical.amount, 9)
        XCTAssertEqual(legacyCanonical.comment, "Must remain untouched")
    }

    func testOffsetPaginationCollectsBeyondPageSizeAndDeduplicatesExactOverlap() async throws {
        let first = TatumTransaction(
            hash: "0x01",
            timestamp: 3_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionIndex: 1,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let second = TatumTransaction(
            hash: "0x02",
            timestamp: 2_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionIndex: 2,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let third = TatumTransaction(
            hash: "0x03",
            timestamp: 1_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionIndex: 3,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "3"
        )
        let pages: [Int: [TatumTransaction]] = [
            0: [first, second],
            2: [second, third],
            4: []
        ]

        let result = try await TransactionService.collectOffsetTransactionPages(
            pageSize: 2,
            maxPages: 4
        ) { offset, _ in
            let transactions = pages[offset] ?? []
            return (transactions, transactions.count == 2)
        }

        XCTAssertEqual(result.map(\.hash), ["0x01", "0x02", "0x03"])
    }

    func testOffsetPaginationPreservesDistinctLogsFromTheSameEVMTransaction() async throws {
        let data = """
        [
          {
            "chain": "ethereum-mainnet",
            "hash": "0xshared-page-transaction",
            "address": "0x00000000000000000000000000000000000000aa",
            "transactionIndex": 7,
            "logIndex": 11,
            "transactionType": "fungible",
            "transactionSubtype": "incoming",
            "amount": "2.5",
            "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "timestamp": 1754393687000,
            "counterAddress": "0x00000000000000000000000000000000000000bb"
          },
          {
            "chain": "ethereum-mainnet",
            "hash": "0xshared-page-transaction",
            "address": "0x00000000000000000000000000000000000000aa",
            "transactionIndex": 7,
            "logIndex": 12,
            "transactionType": "fungible",
            "transactionSubtype": "incoming",
            "amount": "2.5",
            "tokenAddress": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "timestamp": 1754393687000,
            "counterAddress": "0x00000000000000000000000000000000000000bb"
          }
        ]
        """.data(using: .utf8)!
        let movements = try JSONDecoder().decode([TatumTransaction].self, from: data)

        var page = 0
        let result = try await TransactionService.collectOffsetTransactionPages(
            pageSize: 1,
            maxPages: 3
        ) { _, _ in
            defer { page += 1 }
            return page == 0 ? ([movements[0]], true) : ([movements[1]], false)
        }

        XCTAssertEqual(result.count, 2)
        let first = try XCTUnwrap(result.first)
        let second = try XCTUnwrap(result.dropFirst().first)
        XCTAssertNotEqual(first.movementIdentity, second.movementIdentity)
    }

    func testOffsetPaginationRejectsChangedOverlapAndSafetyCap() async throws {
        let original = TatumTransaction(
            hash: "0xoverlap",
            timestamp: 2_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionIndex: 9,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let changed = TatumTransaction(
            hash: "0xoverlap",
            timestamp: 2_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionIndex: 9,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "999"
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectOffsetTransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { offset, _ in
                offset == 0 ? ([original], true) : ([changed], false)
            }
        }

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectOffsetTransactionPages(
                pageSize: 1,
                maxPages: 2
            ) { offset, _ in
                let transaction = TatumTransaction(
                    hash: "0x\(offset)",
                    timestamp: 1_000 - offset,
                    chain: "ethereum-mainnet",
                    address: "0xwallet",
                    transactionIndex: offset,
                    transactionType: "native",
                    transactionSubtype: "incoming",
                    amount: "1"
                )
                return ([transaction], true)
            }
        }
    }

    func testOffsetPaginationRejectsProviderCorrectionsToMutableMovementFields() async {
        let original = TatumTransaction(
            hash: "0xstable",
            timestamp: 2_000,
            from: "0xTracked",
            to: "0xFirstCounterparty",
            chain: "ethereum-mainnet",
            address: "0xTracked",
            transactionIndex: 9,
            transactionType: "native",
            transactionSubtype: "sent",
            amount: "1",
            counterAddress: "0xFirstCounterparty"
        )
        let correctedAddresses = TatumTransaction(
            hash: "0xstable",
            timestamp: 2_000,
            from: "0xCorrectedSender",
            to: "0xTracked",
            chain: "ethereum-mainnet",
            address: "0xTracked",
            transactionIndex: 9,
            transactionType: "native",
            transactionSubtype: "sent",
            amount: "1",
            counterAddress: "0xCorrectedSender"
        )
        let correctedSubtype = TatumTransaction(
            hash: "0xstable",
            timestamp: 2_000,
            from: "0xTracked",
            to: "0xFirstCounterparty",
            chain: "ethereum-mainnet",
            address: "0xTracked",
            transactionIndex: 9,
            transactionType: "native",
            transactionSubtype: "received",
            amount: "1",
            counterAddress: "0xFirstCounterparty"
        )

        for correction in [correctedAddresses, correctedSubtype] {
            do {
                _ = try await TransactionService.collectOffsetTransactionPages(
                    pageSize: 1,
                    maxPages: 3
                ) { offset, _ in
                    offset == 0
                        ? ([original], true)
                        : ([correction], false)
                }
                XCTFail(
                    "A provider correction to mutable content must conflict with the stable record"
                )
            } catch TatumError.invalidResponse {
                // Expected fail-closed conflict.
            } catch {
                XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testOffsetPaginationAdvancesByReturnedCountAfterAShortPage() async throws {
        func transaction(_ hash: String, index: Int) -> TatumTransaction {
            TatumTransaction(
                hash: hash,
                timestamp: 1_000 - index,
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionIndex: index,
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            )
        }
        var requestedOffsets: [Int] = []

        let result = try await TransactionService.collectOffsetTransactionPages(
            pageSize: 3,
            maxPages: 3
        ) { offset, _ in
            requestedOffsets.append(offset)
            switch offset {
            case 0:
                return ([transaction("0x01", index: 1), transaction("0x02", index: 2)], true)
            case 2:
                return ([transaction("0x03", index: 3)], false)
            default:
                return ([], false)
            }
        }

        XCTAssertEqual(requestedOffsets, [0, 2])
        XCTAssertEqual(result.map(\.hash), ["0x01", "0x02", "0x03"])
    }

    func testV4OverlapCanonicalizesEVMHashAndChecksumAddressesButPreservesSolanaCase() async throws {
        let evmOriginal = TatumTransaction(
            hash: "0xABCDEF",
            timestamp: 2_000,
            from: "0xAaAa",
            to: "0xBbBb",
            chain: "ethereum-mainnet",
            address: "0xAaAa",
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "1",
            counterAddress: "0xBbBb"
        )
        let evmCaseVariant = TatumTransaction(
            hash: "0xabcdef",
            timestamp: 2_000,
            from: "0xaaaa",
            to: "0xbbbb",
            chain: "ethereum-mainnet",
            address: "0xaaaa",
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "outgoing",
            amount: "1",
            counterAddress: "0xbbbb"
        )
        var page = 0
        let deduplicated = try await TransactionService.collectOffsetTransactionPages(
            pageSize: 1,
            maxPages: 3
        ) { _, _ in
            defer { page += 1 }
            return page == 0 ? ([evmOriginal], true) : ([evmCaseVariant], false)
        }
        XCTAssertEqual(deduplicated.map(\.hash), ["0xABCDEF"])

        let solUpper = TatumTransaction(
            hash: "CaseSensitiveSignature",
            timestamp: 2_000,
            chain: "SOL",
            address: "CaseSensitiveWallet",
            transactionType: "solana",
            transactionSubtype: "received",
            amount: "1"
        )
        let solLower = TatumTransaction(
            hash: "casesensitivesignature",
            timestamp: 2_000,
            chain: "SOL",
            address: "CaseSensitiveWallet",
            transactionType: "solana",
            transactionSubtype: "received",
            amount: "1"
        )
        let distinct = try await TransactionService.collectOffsetTransactionPages(
            pageSize: 2,
            maxPages: 1
        ) { _, _ in
            ([solUpper, solLower], false)
        }
        XCTAssertEqual(distinct.count, 2)
    }

    func testV4AuthoritativePagesRejectEveryMovementMissingARequiredField() async {
        let invalidMovements = [
            TatumTransaction(
                hash: "0xmissing-time",
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            ),
            TatumTransaction(
                hash: "0xmissing-amount",
                timestamp: 1_000,
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionType: "native",
                transactionSubtype: "incoming"
            ),
            TatumTransaction(
                hash: "0xinvalid-amount",
                timestamp: 1_000,
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "inf"
            ),
            TatumTransaction(
                hash: "0xmissing-chain",
                timestamp: 1_000,
                address: "0xwallet",
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            ),
            TatumTransaction(
                hash: "0xmissing-address",
                timestamp: 1_000,
                chain: "ethereum-mainnet",
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            ),
            TatumTransaction(
                hash: "0xmissing-type",
                timestamp: 1_000,
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionSubtype: "incoming",
                amount: "1"
            ),
            TatumTransaction(
                hash: "0xmissing-subtype",
                timestamp: 1_000,
                chain: "ethereum-mainnet",
                address: "0xwallet",
                transactionType: "native",
                amount: "1"
            )
        ]

        for movement in invalidMovements {
            await XCTAssertThrowsErrorAsync {
                _ = try await TransactionService.collectOffsetTransactionPages(
                    pageSize: 1,
                    maxPages: 1
                ) { _, _ in
                    ([movement], false)
                }
            }
        }
    }

    func testValidEmptyProviderHistoryDoesNotResurrectStaleCache() {
        let stale = TatumTransaction(
            hash: "0xstale",
            timestamp: 1_000,
            chain: "ethereum-mainnet",
            address: "0xwallet",
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertTrue(
            TransactionService.authoritativeHistory(
                fetched: [],
                cached: [stale]
            ).isEmpty
        )
    }

    func testMalformedProviderPayloadThrowsTypedDecodingErrorWhileValidEmptyRemainsEmpty() throws {
        let validEmpty = """
        {"result":[],"prevPage":"","nextPage":""}
        """.data(using: .utf8)!
        let malformed = """
        {"result":[{"hash":42}]}
        """.data(using: .utf8)!

        let decoded = try TransactionService.decodeProviderResponse(
            TatumV4TransactionResponse.self,
            from: validEmpty
        )
        XCTAssertTrue(decoded.result.isEmpty)

        XCTAssertThrowsError(
            try TransactionService.decodeProviderResponse(
                TatumV4TransactionResponse.self,
                from: malformed
            )
        ) { error in
            guard case TatumError.decodingError = error else {
                return XCTFail("Expected TatumError.decodingError, got \(error)")
            }
        }
    }

    func testRawUTXOFixtureDecodesFlexibleAliasesAndValues() throws {
        let data = """
        [{
          "txid":"ChildABC",
          "ts":"1700000000",
          "vin":[
            {"txid":"ParentABC","vout":"1"},
            {"coinbase":"03abcdef"}
          ],
          "vout":[
            {"value":"1.25000000","address":"qTracked"},
            {"value":2.5,"scriptPubKey":{"addresses":["qOther"]}}
          ]
        }]
        """.data(using: .utf8)!

        let decoded = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )

        XCTAssertEqual(decoded.first?.hash, "ChildABC")
        XCTAssertEqual(decoded.first?.time, 1_700_000_000)
        XCTAssertEqual(decoded.first?.inputs?.first?.transactionHash, "ParentABC")
        XCTAssertEqual(decoded.first?.inputs?.first?.outputIndex, 1)
        XCTAssertTrue(decoded.first?.inputs?.last?.isCoinbase == true)
        XCTAssertEqual(decoded.first?.outputs?.first?.valueNumber, 1.25)
    }

    func testUTXOPrevoutRequestsUseCurrentV4ChainIdentifiers() throws {
        let expectedChains = [
            "BTC": "bitcoin-mainnet",
            "LTC": "litecoin-mainnet",
            "BCH": "bch-mainnet",
            "DOGE": "doge-mainnet"
        ]

        for (chainID, expectedV4Chain) in expectedChains {
            let request = try TransactionService.makeUTXOPrevoutRequest(
                chainId: chainID,
                hash: "parent",
                client: TatumClient()
            )
            let components = try XCTUnwrap(
                request.url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)
                }
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                    item in item.value.map { (item.name, $0) }
                }
            )

            XCTAssertEqual(components.path, "/v4/data/blockchains/transaction")
            XCTAssertEqual(query["chain"], expectedV4Chain)
            XCTAssertEqual(query["hash"], "parent")
            XCTAssertNotEqual(query["chain"], "bcash-mainnet")
            XCTAssertNotEqual(query["chain"], "dogecoin-mainnet")
        }
    }

    func testRawUTXOIdentityPrefersTxidOverHashOrWtxid() throws {
        let data = """
        {
          "txid":"parent-txid",
          "hash":"parent-wtxid",
          "wtxid":"alternate-wtxid",
          "time":1700000000,
          "vin":[{"coinbase":"01"}],
          "vout":[{"value":"1","address":"DTracked"}]
        }
        """.data(using: .utf8)!

        let transaction = try TransactionService.decodeProviderResponse(
            TatumUTXOTransaction.self,
            from: data
        )

        XCTAssertEqual(transaction.hash, "parent-txid")
    }

    func testUTXOTxidUpgradeMigratesPreDiffWitnessHashRowWithoutDuplicate() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qtracked"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        let legacy = Transaction(
            amount: 9,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_600_000_000),
            source: .onChain,
            externalId: "legacy-witness-hash",
            counterparty: "Preserve witness counterparty",
            comment: "Preserve witness metadata"
        )
        context.insert(asset)
        context.insert(legacy)
        try context.save()
        let legacyID = legacy.id

        let data = """
        [{
          "txid":"canonical-txid",
          "hash":"legacy-witness-hash",
          "wtxid":"alternate-witness-hash",
          "time":1700000000,
          "vin":[{"coinbase":"01"}],
          "vout":[{"value":"100000000","address":"bc1qtracked"}]
        }]
        """.data(using: .utf8)!
        let raw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )
        let movements = try await TransactionService.normalizeUTXOTransactions(
            chainId: "BTC",
            address: trackedAddress,
            transactions: raw,
            maxPrevoutLookups: 0
        ) { _ in
            XCTFail("A coinbase transaction must not request a prevout")
            throw TatumError.invalidResponse
        }
        let movement = try XCTUnwrap(movements.first)

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: movements,
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, legacyID)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.date, movement.date)
        XCTAssertEqual(rows.first?.counterparty, "Preserve witness counterparty")
        XCTAssertEqual(rows.first?.comment, "Preserve witness metadata")
        XCTAssertTrue(
            rows.first?.externalId?.contains("|record_v1|canonical-txid|") == true
        )
    }

    func testUTXOTxidUpgradeFailsClosedForAmbiguousWitnessHashRows() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qtracked"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        let firstLegacy = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "legacy-witness-hash",
            comment: "First legacy row"
        )
        let secondLegacy = Transaction(
            amount: 10,
            asset: asset,
            source: .onChain,
            externalId: "legacy-witness-hash",
            comment: "Second legacy row"
        )
        context.insert(asset)
        context.insert(firstLegacy)
        context.insert(secondLegacy)
        try context.save()

        let data = """
        [{
          "txid":"canonical-txid",
          "hash":"legacy-witness-hash",
          "wtxid":"alternate-witness-hash",
          "time":1700000000,
          "vin":[{"coinbase":"01"}],
          "vout":[{"value":"100000000","address":"bc1qtracked"}]
        }]
        """.data(using: .utf8)!
        let raw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )
        let movements = try await TransactionService.normalizeUTXOTransactions(
            chainId: "BTC",
            address: trackedAddress,
            transactions: raw,
            maxPrevoutLookups: 0
        ) { _ in
            XCTFail("A coinbase transaction must not request a prevout")
            throw TatumError.invalidResponse
        }

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: movements,
                for: asset
            )
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(firstLegacy.amount, 9)
        XCTAssertEqual(secondLegacy.amount, 10)
        XCTAssertEqual(firstLegacy.comment, "First legacy row")
        XCTAssertEqual(secondLegacy.comment, "Second legacy row")
    }

    func testUTXOPrevoutLookupRejectsAParentWithTheWrongTxid() async throws {
        let childData = """
        [{
          "txid":"child",
          "time":1700000000,
          "vin":[{"txid":"requested-parent","vout":0}],
          "vout":[{"value":"0.25","address":"DTracked"}]
        }]
        """.data(using: .utf8)!
        let wrongParentData = """
        {
          "txid":"different-parent",
          "hash":"requested-parent",
          "time":1699999999,
          "vin":[{"coinbase":"01"}],
          "vout":[{"value":"1","address":"DTracked"}]
        }
        """.data(using: .utf8)!
        let child = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: childData
        )
        let wrongParent = try TransactionService.decodeProviderResponse(
            TatumUTXOTransaction.self,
            from: wrongParentData
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.normalizeUTXOTransactions(
                chainId: "DOGE",
                address: "DTracked",
                transactions: child,
                maxPrevoutLookups: 10
            ) { requestedHash in
                XCTAssertEqual(requestedHash, "requested-parent")
                return wrongParent
            }
        }
    }

    func testUTXONormalizationReadsSingularScriptPubKeyAddress() async throws {
        let data = """
        [{
          "txid":"child",
          "time":1700000000,
          "vin":[{
            "prevout":{
              "value":"1.5",
              "scriptPubKey":{"address":"DTracked"}
            }
          }],
          "vout":[{
            "value":"0.5",
            "scriptPubKey":{"address":"DOther"}
          }]
        }]
        """.data(using: .utf8)!
        let raw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )

        let movements = try await TransactionService.normalizeUTXOTransactions(
            chainId: "DOGE",
            address: "DTracked",
            transactions: raw,
            maxPrevoutLookups: 0
        ) { _ in
            XCTFail("Inline prevout must not trigger a parent lookup")
            throw TatumError.invalidResponse
        }

        let movement = try XCTUnwrap(movements.first)
        XCTAssertEqual(movement.transactionSubtype, "sent")
        XCTAssertEqual(try XCTUnwrap(Double(movement.amount ?? "")), 1.5, accuracy: 0.000_000_001)
        XCTAssertEqual(movement.counterAddress, "DOther")
    }

    func testRawUTXOTransactionsRequireBothVinAndVout() {
        let missingVin = """
        {
          "txid":"missing-vin",
          "time":1700000000,
          "vout":[{"value":"1","address":"DTracked"}]
        }
        """.data(using: .utf8)!
        let missingVout = """
        {
          "txid":"missing-vout",
          "time":1700000000,
          "vin":[{"coinbase":"01"}]
        }
        """.data(using: .utf8)!

        for payload in [missingVin, missingVout] {
            XCTAssertThrowsError(
                try TransactionService.decodeProviderResponse(
                    TatumUTXOTransaction.self,
                    from: payload
                )
            )
        }
    }

    func testUTXONormalizationUsesBTCAtomicUnitsAndRawBCHHumanUnits() async throws {
        let btcData = """
        [{
          "hash":"btc-child",
          "time":1700000000,
          "inputs":[{
            "prevout":{
              "value":250000000,
              "scriptPubKey":{"addresses":["bc1qtracked"]}
            }
          }],
          "outputs":[{
            "value":"50000000",
            "scriptPubKey":{"addresses":["bc1qtracked"]}
          }]
        }]
        """.data(using: .utf8)!
        let btcRaw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: btcData
        )
        let btc = try await TransactionService.normalizeUTXOTransactions(
            chainId: "BTC",
            address: "bc1qtracked",
            transactions: btcRaw,
            maxPrevoutLookups: 10
        ) { _ in
            XCTFail("Enriched BTC fixture must not need a prevout lookup")
            throw TatumError.invalidResponse
        }
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(btc.first?.amount))),
            2,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(btc.first?.transactionSubtype, "sent")

        let bchData = """
        [{
          "txid":"bch-child",
          "ts":1700000100,
          "vin":[
            {"txid":"bch-parent","vout":0},
            {"txid":"bch-parent","vout":1}
          ],
          "vout":[{"value":"0.25","address":"qtracked"}]
        }]
        """.data(using: .utf8)!
        let parentData = """
        {
          "txid":"bch-parent",
          "ts":1699999999,
          "vin":[{"coinbase":"01"}],
          "vout":[
            {"value":"1.0","address":"qtracked"},
            {"value":0.5,"address":"qtracked"}
          ]
        }
        """.data(using: .utf8)!
        let bchRaw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: bchData
        )
        let parent = try TransactionService.decodeProviderResponse(
            TatumUTXOTransaction.self,
            from: parentData
        )
        var lookupCount = 0
        let bch = try await TransactionService.normalizeUTXOTransactions(
            chainId: "BCH",
            address: "qtracked",
            transactions: bchRaw,
            maxPrevoutLookups: 10
        ) { hash in
            lookupCount += 1
            XCTAssertEqual(hash, "bch-parent")
            return parent
        }
        XCTAssertEqual(lookupCount, 1, "Repeated inputs must share one parent lookup")
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(bch.first?.amount))),
            1.25,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(bch.first?.transactionSubtype, "sent")
    }

    func testUTXOPrevoutCapAndLookupFailureAbortWholeBatchBeforeReturningMovements() async throws {
        let data = """
        [{
          "txid":"child",
          "ts":1700000200,
          "vin":[
            {"txid":"parent-1","vout":0},
            {"txid":"parent-2","vout":0}
          ],
          "vout":[{"value":"1","address":"DTracked"}]
        }]
        """.data(using: .utf8)!
        let raw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )
        var lookupCount = 0

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.normalizeUTXOTransactions(
                chainId: "DOGE",
                address: "DTracked",
                transactions: raw,
                maxPrevoutLookups: 1
            ) { _ in
                lookupCount += 1
                throw TatumError.invalidResponse
            }
        }
        XCTAssertEqual(lookupCount, 0, "The unique-parent cap must be checked before any request")

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.normalizeUTXOTransactions(
                chainId: "DOGE",
                address: "DTracked",
                transactions: raw,
                maxPrevoutLookups: 10
            ) { _ in
                lookupCount += 1
                throw TatumError.httpError(503)
            }
        }
        XCTAssertEqual(lookupCount, 1, "A failed unique lookup aborts without partial movements")
    }

    func testUTXOCoinbaseInputNeedsNoPrevoutLookup() async throws {
        let data = """
        [{
          "txid":"coinbase-child",
          "ts":1700000300,
          "vin":[{"coinbase":"03abcdef"}],
          "vout":[{"value":"12.5","address":"DTracked"}]
        }]
        """.data(using: .utf8)!
        let raw = try TransactionService.decodeProviderResponse(
            [TatumUTXOTransaction].self,
            from: data
        )
        var lookupCount = 0
        let movements = try await TransactionService.normalizeUTXOTransactions(
            chainId: "DOGE",
            address: "DTracked",
            transactions: raw,
            maxPrevoutLookups: 10
        ) { _ in
            lookupCount += 1
            throw TatumError.invalidResponse
        }

        XCTAssertEqual(lookupCount, 0)
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(movements.first?.amount))),
            12.5,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(movements.first?.transactionSubtype, "received")
    }

    func testXRPPaymentUsesValidatedDeliveredNativeAmountAndIgnoresIssuedCurrencyObject() throws {
        let data = """
        {
          "account":"rTracked",
          "ledger_index_max":900,
          "ledger_index_min":1,
          "limit":3,
          "validated":true,
          "marker":"next-marker",
          "transactions":[
            {
              "validated":true,
              "meta":{
                "AffectedNodes":[],
                "TransactionIndex":7,
                "TransactionResult":"tesSUCCESS",
                "delivered_amount":"2500000"
              },
              "tx":{
                "Account":"rSender",
                "Amount":"999999999",
                "Destination":"rTracked",
                "Fee":"12",
                "Flags":0,
                "Sequence":1,
                "TransactionType":"Payment",
                "date":800000000,
                "hash":"ABCDEF",
                "ledger_index":800
              }
            },
            {
              "validated":true,
              "meta":{
                "AffectedNodes":[],
                "TransactionIndex":8,
                "TransactionResult":"tesSUCCESS",
                "delivered_amount":{"currency":"USD","issuer":"rIssuer","value":5.5}
              },
              "tx":{
                "Account":"rSender",
                "Amount":{"currency":"USD","issuer":"rIssuer","value":"10"},
                "Destination":"rTracked",
                "Fee":"12",
                "Flags":0,
                "Sequence":2,
                "TransactionType":"Payment",
                "date":800000001,
                "hash":"ISSUED",
                "ledger_index":801
              }
            },
            {
              "validated":false,
              "meta":{
                "AffectedNodes":[],
                "TransactionIndex":9,
                "TransactionResult":"tecFAILED",
                "delivered_amount":"7000000"
              },
              "tx":{
                "Account":"rSender",
                "Amount":"7000000",
                "Destination":"rTracked",
                "Fee":"12",
                "Flags":0,
                "Sequence":3,
                "TransactionType":"Payment",
                "date":800000002,
                "hash":"FAILED",
                "ledger_index":802
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try TransactionService.decodeProviderResponse(
            XRPAccountResponse.self,
            from: data
        )
        XCTAssertEqual(response.marker?.queryValue, "next-marker")

        let movements = try TransactionService.parseXRPTransactions(
            response,
            address: "rTracked"
        )
        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movements.first?.hash, "ABCDEF")
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(movements.first?.amount))),
            2.5,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(movements.first?.transactionIndex, 7)
    }

    func testXRPMarkerPaginationRunsToExhaustionAndRejectsCyclesAndMalformedMarkers() async throws {
        func response(
            marker: TatumJSONValue?,
            hash: String,
            validated: Bool = true
        ) throws -> XRPAccountResponse {
            let markerJSON: String
            if let marker, let data = try? JSONEncoder().encode(marker) {
                markerJSON = ",\"marker\":\(String(decoding: data, as: UTF8.self))"
            } else {
                markerJSON = ""
            }
            let data = """
            {
              "account":"rTracked",
              "ledger_index_max":900,
              "ledger_index_min":1,
              "validated":\(validated)
              \(markerJSON),
              "transactions":[{
                "validated":true,
                "meta":{
                  "AffectedNodes":[],
                  "TransactionIndex":1,
                  "TransactionResult":"tesSUCCESS",
                  "delivered_amount":"1000000"
                },
                "tx":{
                  "Account":"rSender",
                  "Amount":"1000000",
                  "Destination":"rTracked",
                  "Fee":"12",
                  "Flags":0,
                  "Sequence":1,
                  "TransactionType":"Payment",
                  "date":800000000,
                  "hash":"\(hash)",
                  "ledger_index":800
                }
              }]
            }
            """.data(using: .utf8)!
            return try TransactionService.decodeProviderResponse(
                XRPAccountResponse.self,
                from: data
            )
        }

        var requestedMarkers: [String?] = []
        let pages = try await TransactionService.collectXRPTransactionPages(
            pageSize: 1,
            maxPages: 3
        ) { marker, _ in
            requestedMarkers.append(marker)
            return marker == nil
                ? try response(marker: .string("next"), hash: "ONE")
                : try response(marker: nil, hash: "TWO")
        }
        XCTAssertEqual(requestedMarkers.count, 2)
        XCTAssertNil(requestedMarkers[0])
        XCTAssertEqual(requestedMarkers[1], "next")
        XCTAssertEqual(pages.map(\.tx.hash), ["ONE", "TWO"])

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectXRPTransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                try response(marker: .string("same"), hash: "CYCLE")
            }
        }

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectXRPTransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                try response(marker: nil, hash: "UNVALIDATED", validated: false)
            }
        }

        do {
            _ = try await TransactionService.collectXRPTransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                try response(marker: .number(1e100), hash: "HUGE-MARKER")
            }
            XCTFail("A present, out-of-range numeric marker must fail closed")
        } catch TatumError.invalidResponse {
            // Expected typed failure instead of a numeric conversion trap.
        } catch {
            XCTFail("Expected invalidResponse, got \(error)")
        }

        let nullTerminated = try await TransactionService.collectXRPTransactionPages(
            pageSize: 1,
            maxPages: 1
        ) { _, _ in
            try response(marker: .null, hash: "NULL-TERMINATOR")
        }
        XCTAssertEqual(nullTerminated.map(\.tx.hash), ["NULL-TERMINATOR"])
    }

    func testXRPOverlapCanonicalizesOnlyTheHexHash() async throws {
        func response(
            marker: String?,
            hash: String,
            account: String = "rSender"
        ) throws -> XRPAccountResponse {
            let markerJSON = marker.map { ",\"marker\":\"\($0)\"" } ?? ""
            let data = """
            {
              "account":"rTracked",
              "ledger_index_max":900,
              "ledger_index_min":1,
              "validated":true
              \(markerJSON),
              "transactions":[{
                "validated":true,
                "meta":{
                  "AffectedNodes":[],
                  "TransactionIndex":1,
                  "TransactionResult":"tesSUCCESS",
                  "delivered_amount":"1000000"
                },
                "tx":{
                  "Account":"\(account)",
                  "Amount":"1000000",
                  "Destination":"rTracked",
                  "Fee":"12",
                  "Flags":0,
                  "Sequence":1,
                  "TransactionType":"Payment",
                  "date":800000000,
                  "hash":"\(hash)",
                  "ledger_index":800
                }
              }]
            }
            """.data(using: .utf8)!
            return try TransactionService.decodeProviderResponse(
                XRPAccountResponse.self,
                from: data
            )
        }

        var page = 0
        let deduplicated = try await TransactionService.collectXRPTransactionPages(
            pageSize: 1,
            maxPages: 3
        ) { _, _ in
            defer { page += 1 }
            return page == 0
                ? try response(marker: "next", hash: "ABCDEF")
                : try response(marker: nil, hash: "abcdef")
        }
        XCTAssertEqual(deduplicated.map(\.tx.hash), ["ABCDEF"])

        await XCTAssertThrowsErrorAsync {
            var conflictPage = 0
            _ = try await TransactionService.collectXRPTransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                defer { conflictPage += 1 }
                return conflictPage == 0
                    ? try response(marker: "next", hash: "ABCDEF")
                    : try response(marker: nil, hash: "abcdef", account: "RSender")
            }
        }
    }

    func testTRONHistoryRequiresSuccessAndKeepsNativeAndCanonicalTRC20Separate() throws {
        let nativeData = """
        {
          "transactions":[
            {
              "txID":"NATIVE-SUCCESS",
              "ret":[{"contractRet":"SUCCESS"}],
              "rawData":{
                "timestamp":1700000000000,
                "contract":[{
                  "type":"TransferContract",
                  "parameter":{"value":{
                    "amount":2000000,
                    "ownerAddressBase58":"TTracked",
                    "toAddressBase58":"TOther"
                  }}
                }]
              }
            },
            {
              "txID":"NATIVE-FAILED",
              "ret":[{"contractRet":"REVERT"}],
              "rawData":{
                "timestamp":1700000001000,
                "contract":[{
                  "type":"TransferContract",
                  "parameter":{"value":{
                    "amount":9000000,
                    "ownerAddressBase58":"TTracked",
                    "toAddressBase58":"TOther"
                  }}
                }]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let nativeResponse = try TransactionService.decodeProviderResponse(
            TRXTransactionResponse.self,
            from: nativeData
        )
        let native = try TransactionService.parseNativeTRXTransactions(
            nativeResponse,
            address: "TTracked"
        )
        XCTAssertEqual(native.count, 1)
        XCTAssertEqual(native.first?.hash, "NATIVE-SUCCESS")
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(native.first?.amount))),
            2,
            accuracy: 0.000_000_001
        )
        XCTAssertNil(native.first?.tokenAddress)

        let tokenData = """
        {
          "transactions":[
            {
              "transaction_id":"TOKEN-SUCCESS",
              "token_info":{
                "symbol":"USDT",
                "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                "decimals":6,
                "name":"Tether"
              },
              "from":"TOther",
              "to":"TTracked",
              "value":"3500000",
              "block_timestamp":"1700000100000",
              "contract_ret":"SUCCESS"
            },
            {
              "transaction_id":"COUNTERFEIT",
              "token_info":{
                "symbol":"USDT",
                "address":"tr7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                "decimals":6,
                "name":"Counterfeit"
              },
              "from":"TOther",
              "to":"TTracked",
              "value":"99000000",
              "block_timestamp":1700000101000,
              "contract_ret":"SUCCESS"
            },
            {
              "transaction_id":"TOKEN-FAILED",
              "token_info":{
                "symbol":"USDT",
                "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                "decimals":6,
                "name":"Tether"
              },
              "from":"TOther",
              "to":"TTracked",
              "value":"88000000",
              "block_timestamp":1700000102000,
              "contract_ret":"REVERT"
            },
            {
              "transaction_id":"TOKEN-CONFLICT",
              "token_info":{
                "symbol":"USDT",
                "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                "decimals":6,
                "name":"Tether"
              },
              "from":"TOther",
              "to":"TTracked",
              "value":"77000000",
              "block_timestamp":1700000103000,
              "contract_ret":"REVERT",
              "receipt":{"result":"SUCCESS"}
            }
          ]
        }
        """.data(using: .utf8)!
        let tokenResponse = try TransactionService.decodeProviderResponse(
            TRC20TransactionResponse.self,
            from: tokenData
        )
        let tokens = try TransactionService.parseTRC20Transactions(
            tokenResponse,
            address: "TTracked",
            currency: "USDT"
        )
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.hash, "TOKEN-SUCCESS")
        XCTAssertEqual(
            tokens.first?.tokenAddress,
            "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )
        XCTAssertEqual(tokens.first?.timestamp, 1_700_000_100_000)
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(tokens.first?.amount))),
            3.5,
            accuracy: 0.000_000_001
        )
    }

    func testTRC20MissingAuthoritativeTimestampFailsClosed() throws {
        let data = """
        {
          "transactions":[{
            "txID":"TOKEN-NO-TIME",
            "tokenInfo":{
              "symbol":"USDT",
              "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
              "decimals":6,
              "name":"Tether"
            },
            "from":"TOther",
            "to":"TTracked",
            "value":"1000000",
            "contractRet":"SUCCESS"
          }]
        }
        """.data(using: .utf8)!
        let response = try TransactionService.decodeProviderResponse(
            TRC20TransactionResponse.self,
            from: data
        )

        XCTAssertThrowsError(
            try TransactionService.parseTRC20Transactions(
                response,
                address: "TTracked",
                currency: "USDT"
            )
        )
    }

    func testTRC20RejectsDecimalsOutsideUint8AndNonfiniteConvertedAmounts() throws {
        let invalidCases: [(decimals: Int, value: String)] = [
            (-1, "1000000"),
            (256, "1000000"),
            (-308, "1e308")
        ]

        for invalidCase in invalidCases {
            let data = """
            {
              "transactions":[{
                "txID":"TOKEN-BAD-\(invalidCase.decimals)",
                "tokenInfo":{
                  "symbol":"USDT",
                  "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                  "decimals":\(invalidCase.decimals),
                  "name":"Tether"
                },
                "from":"TOther",
                "to":"TTracked",
                "value":"\(invalidCase.value)",
                "timestamp":1700000000000,
                "contractRet":"SUCCESS"
              }]
            }
            """.data(using: .utf8)!
            let response = try TransactionService.decodeProviderResponse(
                TRC20TransactionResponse.self,
                from: data
            )

            XCTAssertThrowsError(
                try TransactionService.parseTRC20Transactions(
                    response,
                    address: "TTracked",
                    currency: "USDT"
                ),
                "decimals=\(invalidCase.decimals), value=\(invalidCase.value)"
            )
        }
    }

    func testTRONCursorPaginationUsesNextOnlyAndRejectsConflictsCyclesAndCaps() async throws {
        let client = TatumClient()
        for isTRC20 in [false, true] {
            let firstRequest = try TransactionService.makeTRONHistoryRequest(
                address: "TTracked",
                trc20: isTRC20,
                nextCursor: nil,
                client: client
            )
            let nextRequest = try TransactionService.makeTRONHistoryRequest(
                address: "TTracked",
                trc20: isTRC20,
                nextCursor: "fingerprint",
                client: client
            )
            let firstItems = URLComponents(
                url: try XCTUnwrap(firstRequest.url),
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []
            let nextItems = URLComponents(
                url: try XCTUnwrap(nextRequest.url),
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []

            XCTAssertFalse(firstItems.contains { $0.name == "pageSize" })
            XCTAssertFalse(nextItems.contains { $0.name == "pageSize" })
            XCTAssertNil(firstItems.first { $0.name == "next" })
            XCTAssertEqual(
                nextItems.first { $0.name == "next" }?.value,
                "fingerprint"
            )
            XCTAssertEqual(
                nextRequest.url?.path.hasSuffix(
                    isTRC20 ? "/trc20" : "/TTracked"
                ),
                true
            )
        }

        func nativeResponse(
            txID: String,
            amount: Int,
            next: String?
        ) throws -> TRXTransactionResponse {
            let nextJSON = next.map { ",\"next\":\"\($0)\"" } ?? ""
            return try TransactionService.decodeProviderResponse(
                TRXTransactionResponse.self,
                from: Data("""
                {
                  "transactions":[{
                    "txID":"\(txID)",
                    "ret":[{"contractRet":"SUCCESS"}],
                    "rawData":{
                      "timestamp":1700000000000,
                      "contract":[{
                        "type":"TransferContract",
                        "parameter":{"value":{
                          "amount":\(amount),
                          "ownerAddressBase58":"TOther",
                          "toAddressBase58":"TTracked"
                        }}
                      }]
                    }
                  }]
                  \(nextJSON)
                }
                """.utf8)
            )
        }

        let nativeSeed = try nativeResponse(
            txID: "ABCDEF",
            amount: 1_000_000,
            next: nil
        )
        let nativeFullPage = TRXTransactionResponse(
            transactions: Array(
                repeating: try XCTUnwrap(nativeSeed.transactions.first),
                count: 200
            ),
            internalTransactions: nil,
            next: "native-next"
        )
        var nativeCursors: [String?] = []
        let native = try await TransactionService.collectTRXTransactionPages(
            maxPages: 3
        ) { cursor in
            nativeCursors.append(cursor)
            return cursor == nil
                ? nativeFullPage
                : try nativeResponse(
                    txID: "123456",
                    amount: 2_000_000,
                    next: nil
                )
        }
        XCTAssertEqual(nativeCursors, [nil, "native-next"])
        XCTAssertEqual(native.map(\.txID), ["ABCDEF", "123456"])

        await XCTAssertThrowsErrorAsync {
            var page = 0
            _ = try await TransactionService.collectTRXTransactionPages(
                maxPages: 3
            ) { _ in
                defer { page += 1 }
                return page == 0
                    ? try nativeResponse(
                        txID: "ABCDEF",
                        amount: 1_000_000,
                        next: "next"
                    )
                    : try nativeResponse(
                        txID: "abcdef",
                        amount: 2_000_000,
                        next: nil
                    )
            }
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectTRXTransactionPages(
                maxPages: 3
            ) { _ in
                try nativeResponse(
                    txID: "ABCDEF",
                    amount: 1_000_000,
                    next: "cycle"
                )
            }
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectTRXTransactionPages(
                maxPages: 1
            ) { _ in
                try nativeResponse(
                    txID: "ABCDEF",
                    amount: 1_000_000,
                    next: "more"
                )
            }
        }

        func tokenResponse(
            txID: String,
            value: String,
            next: String?
        ) throws -> TRC20TransactionResponse {
            let nextJSON = next.map { ",\"next\":\"\($0)\"" } ?? ""
            return try TransactionService.decodeProviderResponse(
                TRC20TransactionResponse.self,
                from: Data("""
                {
                  "transactions":[{
                    "txID":"\(txID)",
                    "tokenInfo":{
                      "symbol":"USDT",
                      "address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                      "decimals":6,
                      "name":"Tether"
                    },
                    "from":"TOther",
                    "to":"TTracked",
                    "value":"\(value)",
                    "timestamp":1700000000000,
                    "contractRet":"SUCCESS"
                  }]
                  \(nextJSON)
                }
                """.utf8)
            )
        }

        let tokenSeed = try tokenResponse(
            txID: "FEDCBA",
            value: "1000000",
            next: nil
        )
        let tokenFullPage = TRC20TransactionResponse(
            transactions: Array(
                repeating: try XCTUnwrap(tokenSeed.transactions.first),
                count: 200
            ),
            next: "token-next"
        )
        var tokenCursors: [String?] = []
        let tokens = try await TransactionService.collectTRC20TransactionPages(
            maxPages: 3
        ) { cursor in
            tokenCursors.append(cursor)
            return cursor == nil
                ? tokenFullPage
                : try tokenResponse(
                    txID: "654321",
                    value: "2000000",
                    next: nil
                )
        }
        XCTAssertEqual(tokenCursors, [nil, "token-next"])
        XCTAssertEqual(tokens.map(\.txID), ["FEDCBA", "654321"])

        await XCTAssertThrowsErrorAsync {
            var page = 0
            _ = try await TransactionService.collectTRC20TransactionPages(
                maxPages: 3
            ) { _ in
                defer { page += 1 }
                return page == 0
                    ? try tokenResponse(
                        txID: "FEDCBA",
                        value: "1000000",
                        next: "next"
                    )
                    : try tokenResponse(
                        txID: "fedcba",
                        value: "2000000",
                        next: nil
                    )
            }
        }
    }

    func testADANetSumsAllTrackedInputsOutputsAndKeepsAuthoritativeOldTime() throws {
        let data = """
        [
          {
            "hash":"ADA-NET",
            "block":{"hash":"block-1","number":42,"time":"1600000000"},
            "inputs":[
              {"address":"addrTracked","symbol":"ADA","value":"5000000"},
              {"address":"addrTracked","symbol":"ADA","value":2000000},
              {"address":"addrOther","symbol":"ADA","value":"1000000"}
            ],
            "outputs":[
              {"address":"addrTracked","symbol":"ADA","value":"3000000"},
              {"address":"addrOther","symbol":"ADA","value":5000000}
            ],
            "fee":"170000"
          },
          {
            "hash":"ADA-SELF",
            "block":{"hash":"block-2","number":43,"time":1600000100},
            "inputs":[{"address":"addrTracked","symbol":"ADA","value":"5000000"}],
            "outputs":[{"address":"addrTracked","symbol":"ADA","value":"5000000"}],
            "fee":"0"
          }
        ]
        """.data(using: .utf8)!
        let decoded = try TransactionService.decodeProviderResponse(
            [TatumADATransaction].self,
            from: data
        )
        let movements = try TransactionService.parseADATransactions(
            decoded,
            address: "addrTracked"
        )

        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movements.first?.hash, "ADA-NET")
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(movements.first?.amount))),
            4,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(movements.first?.transactionSubtype, "sent")
        XCTAssertEqual(movements.first?.timestamp, 1_600_000_000_000)
        XCTAssertLessThan(
            try XCTUnwrap(movements.first?.date),
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testADAMissingTimeOrInvalidTrackedNativeValueFailsClosed() throws {
        let missingTime = """
        [{
          "hash":"ADA-NO-TIME",
          "block":{"hash":"block","number":1},
          "inputs":[{"address":"addrOther","symbol":"ADA","value":"1000000"}],
          "outputs":[{"address":"addrTracked","symbol":"ADA","value":"1000000"}]
        }]
        """.data(using: .utf8)!
        let missingTimeTransactions = try TransactionService.decodeProviderResponse(
            [TatumADATransaction].self,
            from: missingTime
        )
        XCTAssertThrowsError(
            try TransactionService.parseADATransactions(
                missingTimeTransactions,
                address: "addrTracked"
            )
        )

        let invalidValue = """
        [{
          "hash":"ADA-BAD-VALUE",
          "block":{"hash":"block","number":1,"time":1600000000},
          "inputs":[{"address":"addrOther","symbol":"ADA","value":"1000000"}],
          "outputs":[{"address":"addrTracked","symbol":"ADA","value":"not-a-number"}]
        }]
        """.data(using: .utf8)!
        XCTAssertThrowsError(
            try TransactionService.decodeProviderResponse(
                [TatumADATransaction].self,
                from: invalidValue
            )
        ) { error in
            guard case TatumError.decodingError = error else {
                return XCTFail("Expected typed decoding error, got \(error)")
            }
        }
    }

    func testADAHistoryFollowsEveryOffsetPageAndRejectsOverlapConflictsAndCaps() async throws {
        let request = try TransactionService.makeADAHistoryRequest(
            address: "addrTracked",
            offset: 75,
            pageSize: 50,
            client: TatumClient()
        )
        let queryItems = URLComponents(
            url: try XCTUnwrap(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        XCTAssertEqual(queryItems.first { $0.name == "offset" }?.value, "75")
        XCTAssertEqual(queryItems.first { $0.name == "pageSize" }?.value, "50")

        func transaction(
            hash: String,
            value: String,
            timestamp: Int
        ) throws -> TatumADATransaction {
            try TransactionService.decodeProviderResponse(
                TatumADATransaction.self,
                from: Data("""
                {
                  "hash":"\(hash)",
                  "block":{
                    "hash":"block-\(timestamp)",
                    "number":\(timestamp),
                    "time":\(timestamp)
                  },
                  "inputs":[{
                    "address":"addrOther",
                    "symbol":"ADA",
                    "value":"\(value)"
                  }],
                  "outputs":[{
                    "address":"addrTracked",
                    "symbol":"ADA",
                    "value":"\(value)"
                  }],
                  "fee":"0"
                }
                """.utf8)
            )
        }

        let first = try transaction(hash: "AAAA", value: "1000000", timestamp: 1)
        let second = try transaction(hash: "BBBB", value: "2000000", timestamp: 2)
        let third = try transaction(hash: "CCCC", value: "3000000", timestamp: 3)
        var offsets: [Int] = []
        let collected = try await TransactionService.collectADATransactionPages(
            pageSize: 2,
            maxPages: 3
        ) { offset, _ in
            offsets.append(offset)
            return offset == 0 ? [first, second] : [third]
        }
        XCTAssertEqual(offsets, [0, 2])
        XCTAssertEqual(collected.map(\.hash), ["AAAA", "BBBB", "CCCC"])

        await XCTAssertThrowsErrorAsync {
            var page = 0
            _ = try await TransactionService.collectADATransactionPages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                defer { page += 1 }
                return page == 0
                    ? [try transaction(hash: "ABCDEF", value: "1000000", timestamp: 4)]
                    : [try transaction(hash: "abcdef", value: "2000000", timestamp: 4)]
            }
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectADATransactionPages(
                pageSize: 1,
                maxPages: 1
            ) { _, _ in
                [first]
            }
        }
    }

    func testSolanaSignaturePaginationUsesBeforeAndRejectsConflictsCyclesAndCaps() async throws {
        let firstRequest = try TransactionService.makeSolanaSignatureRequest(
            address: "Wallet",
            limit: 5_000,
            before: nil,
            client: TatumClient()
        )
        let nextRequest = try TransactionService.makeSolanaSignatureRequest(
            address: "Wallet",
            limit: 5_000,
            before: "SignatureB",
            client: TatumClient()
        )

        func options(in request: URLRequest) throws -> [String: Any] {
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let params = try XCTUnwrap(json["params"] as? [Any])
            return try XCTUnwrap(params.last as? [String: Any])
        }

        let firstOptions = try options(in: firstRequest)
        let nextOptions = try options(in: nextRequest)
        XCTAssertEqual(firstOptions["limit"] as? Int, 1_000)
        XCTAssertEqual(firstOptions["commitment"] as? String, "confirmed")
        XCTAssertNil(firstOptions["before"])
        XCTAssertEqual(nextOptions["before"] as? String, "SignatureB")

        func signature(
            _ value: String,
            slot: Int
        ) -> SolanaSignature {
            SolanaSignature(
                signature: value,
                slot: slot,
                err: nil,
                memo: nil,
                blockTime: 1_700_000_000 + slot
            )
        }

        let first = signature("SignatureA", slot: 1)
        let second = signature("SignatureB", slot: 2)
        let third = signature("SignatureC", slot: 3)
        var beforeValues: [String?] = []
        let collected = try await TransactionService.collectSolanaSignaturePages(
            pageSize: 2,
            maxPages: 4
        ) { before, _ in
            beforeValues.append(before)
            switch before {
            case nil:
                return [first, second]
            case "SignatureB":
                return [second, third]
            default:
                return []
            }
        }
        XCTAssertEqual(beforeValues, [nil, "SignatureB", "SignatureC"])
        XCTAssertEqual(
            collected.map(\.signature),
            ["SignatureA", "SignatureB", "SignatureC"]
        )

        var detailCalls: [String] = []
        let details = try await TransactionService.collectSolanaTransactionDetails(
            signatures: collected
        ) { value in
            detailCalls.append(value.signature)
            return TatumTransaction(
                hash: value.signature,
                timestamp: 1_700_000_000_000,
                chain: "SOL",
                address: "Wallet",
                transactionType: "solana",
                transactionSubtype: "received",
                amount: "1"
            )
        }
        XCTAssertEqual(detailCalls, ["SignatureA", "SignatureB", "SignatureC"])
        XCTAssertEqual(details.count, 3)

        await XCTAssertThrowsErrorAsync {
            var page = 0
            _ = try await TransactionService.collectSolanaSignaturePages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                defer { page += 1 }
                return page == 0
                    ? [signature("Conflict", slot: 1)]
                    : [signature("Conflict", slot: 2)]
            }
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectSolanaSignaturePages(
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                [signature("Cycle", slot: 1)]
            }
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectSolanaSignaturePages(
                pageSize: 1,
                maxPages: 1
            ) { _, _ in
                [first]
            }
        }
    }

    func testSolanaDetailBatchIsAllOrFailAndRetryFetchesEverySignatureAgain() async throws {
        let signaturesData = """
        [
          {"signature":"SignatureOne","slot":1,"err":null,"blockTime":1600000000},
          {"signature":"SignatureTwo","slot":2,"err":null,"blockTime":1600000001}
        ]
        """.data(using: .utf8)!
        let signatures = try TransactionService.decodeProviderResponse(
            [SolanaSignature].self,
            from: signaturesData
        )
        var firstAttempt: [String] = []

        await XCTAssertThrowsErrorAsync {
            _ = try await TransactionService.collectSolanaTransactionDetails(
                signatures: signatures
            ) { signature in
                firstAttempt.append(signature.signature)
                if signature.signature == "SignatureTwo" {
                    throw TatumError.httpError(503)
                }
                return TatumTransaction(
                    hash: signature.signature,
                    timestamp: 1_600_000_000_000,
                    chain: "SOL",
                    address: "Wallet",
                    transactionType: "solana",
                    transactionSubtype: "received",
                    amount: "1"
                )
            }
        }
        XCTAssertEqual(firstAttempt, ["SignatureOne", "SignatureTwo"])

        var retryAttempt: [String] = []
        let retried = try await TransactionService.collectSolanaTransactionDetails(
            signatures: signatures
        ) { signature in
            retryAttempt.append(signature.signature)
            return TatumTransaction(
                hash: signature.signature,
                timestamp: 1_600_000_000_000,
                chain: "SOL",
                address: "Wallet",
                transactionType: "solana",
                transactionSubtype: "received",
                amount: "1"
            )
        }
        XCTAssertEqual(retryAttempt, ["SignatureOne", "SignatureTwo"])
        XCTAssertEqual(retried.map(\.hash), ["SignatureOne", "SignatureTwo"])
    }

    func testSolanaStringAndObjectErrorsRemainFailuresInsteadOfBecomingNull() throws {
        let signatures = try TransactionService.decodeProviderResponse(
            [SolanaSignature].self,
            from: Data("""
            [
              {"signature":"StringFailure","err":"BlockhashNotFound"},
              {"signature":"ObjectFailure","err":{"InstructionError":1}},
              {"signature":"Success","err":null}
            ]
            """.utf8)
        )
        XCTAssertFalse(signatures[0].isSuccess)
        XCTAssertFalse(signatures[1].isSuccess)
        XCTAssertTrue(signatures[2].isSuccess)

        let transactions = try [
            Data("""
            {
              "meta":{"err":"BlockhashNotFound"},
              "transaction":{"signatures":["StringFailure"]}
            }
            """.utf8),
            Data("""
            {
              "meta":{"err":{"InstructionError":1}},
              "transaction":{"signatures":["ObjectFailure"]}
            }
            """.utf8),
            Data("""
            {
              "meta":{"err":null},
              "transaction":{"signatures":["Success"]}
            }
            """.utf8)
        ].map {
            try TransactionService.decodeProviderResponse(
                TatumSOLTransaction.self,
                from: $0
            )
        }
        XCTAssertFalse(try XCTUnwrap(transactions[0].meta).isSuccess)
        XCTAssertFalse(try XCTUnwrap(transactions[1].meta).isSuccess)
        XCTAssertTrue(try XCTUnwrap(transactions[2].meta).isSuccess)
    }

    func testSolanaMovementRequiresExactSignatureAndAuthoritativeBlockTime() throws {
        let missingTimeData = """
        {
          "meta":{
            "fee":5000,
            "preBalances":[2000000000],
            "postBalances":[1000000000],
            "err":null
          },
          "transaction":{
            "signatures":["CaseSensitiveSignature"],
            "message":{"accountKeys":["Wallet"],"instructions":[]}
          }
        }
        """.data(using: .utf8)!
        let missingTime = try TransactionService.decodeProviderResponse(
            TatumSOLTransaction.self,
            from: missingTimeData
        )
        XCTAssertThrowsError(
            try TransactionService.normalizeSOLTransaction(
                missingTime,
                requestedSignature: "CaseSensitiveSignature",
                targetAddress: "Wallet"
            )
        )

        let validData = """
        {
          "blockTime":1600000000,
          "meta":{
            "fee":5000,
            "preBalances":[2000000000,0],
            "postBalances":[1000000000,1000000000],
            "err":null
          },
          "transaction":{
            "signatures":["CaseSensitiveSignature"],
            "message":{
              "accountKeys":["Wallet","Recipient"],
              "instructions":[]
            }
          }
        }
        """.data(using: .utf8)!
        let valid = try TransactionService.decodeProviderResponse(
            TatumSOLTransaction.self,
            from: validData
        )
        let movement = try XCTUnwrap(
            TransactionService.normalizeSOLTransaction(
                valid,
                requestedSignature: "CaseSensitiveSignature",
                targetAddress: "Wallet"
            )
        )
        XCTAssertEqual(movement.hash, "CaseSensitiveSignature")
        XCTAssertEqual(movement.timestamp, 1_600_000_000_000)
        XCTAssertEqual(movement.transactionSubtype, "sent")
        XCTAssertEqual(
            try XCTUnwrap(Double(try XCTUnwrap(movement.amount))),
            1,
            accuracy: 0.000_000_001
        )

        XCTAssertThrowsError(
            try TransactionService.normalizeSOLTransaction(
                valid,
                requestedSignature: "casesensitivesignature",
                targetAddress: "Wallet"
            )
        )
        XCTAssertEqual(
            TatumTransaction(hash: "no-time").date,
            Date.distantPast
        )
    }

    func testUTXOOffsetPaginationRunsBeyondPageSizeAndDeduplicatesOverlap() async throws {
        func transaction(_ hash: String, _ time: Int) throws -> TatumUTXOTransaction {
            let data = """
            {
              "txid":"\(hash)",
              "ts":\(time),
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"DTracked"}]
            }
            """.data(using: .utf8)!
            return try TransactionService.decodeProviderResponse(
                TatumUTXOTransaction.self,
                from: data
            )
        }
        let one = try transaction("ONE", 100)
        let two = try transaction("TWO", 99)
        let three = try transaction("THREE", 98)
        let pages: [Int: [TatumUTXOTransaction]] = [
            0: [one, two],
            2: [two, three],
            4: []
        ]

        let collected = try await TransactionService.collectUTXOTransactionPages(
            chainId: "DOGE",
            pageSize: 2,
            maxPages: 4
        ) { offset, _ in
            let page = pages[offset] ?? []
            return (page, page.count == 2)
        }
        XCTAssertEqual(collected.map(\.hash), ["ONE", "TWO", "THREE"])
    }

    func testUTXOOffsetPaginationAdvancesByReturnedCountAfterAShortPage() async throws {
        func transaction(_ hash: String, _ time: Int) throws -> TatumUTXOTransaction {
            let data = """
            {
              "txid":"\(hash)",
              "ts":\(time),
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"DTracked"}]
            }
            """.data(using: .utf8)!
            return try TransactionService.decodeProviderResponse(
                TatumUTXOTransaction.self,
                from: data
            )
        }
        var requestedOffsets: [Int] = []
        let one = try transaction("ONE", 100)
        let two = try transaction("TWO", 99)
        let three = try transaction("THREE", 98)

        let collected = try await TransactionService.collectUTXOTransactionPages(
            chainId: "DOGE",
            pageSize: 3,
            maxPages: 3
        ) { offset, _ in
            requestedOffsets.append(offset)
            switch offset {
            case 0: return ([one, two], true)
            case 2: return ([three], false)
            default: return ([], false)
            }
        }

        XCTAssertEqual(requestedOffsets, [0, 2])
        XCTAssertEqual(collected.map(\.hash), ["ONE", "TWO", "THREE"])
    }

    func testUTXOOverlapCanonicalizesHashAndValidBech32CaseButRejectsChangedAmount() async throws {
        func transaction(
            hash: String,
            address: String,
            value: String
        ) throws -> TatumUTXOTransaction {
            let data = """
            {
              "txid":"\(hash)",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{
                "value":"\(value)",
                "scriptPubKey":{"address":"\(address)"}
              }]
            }
            """.data(using: .utf8)!
            return try TransactionService.decodeProviderResponse(
                TatumUTXOTransaction.self,
                from: data
            )
        }
        let lower = try transaction(
            hash: "ABCDEF",
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            value: "1"
        )
        let upper = try transaction(
            hash: "abcdef",
            address: "BC1QXY2KGDYGJRSQTZQ2N0YRF2493P83KKFJHX0WLH",
            value: "1"
        )
        var page = 0
        let deduplicated = try await TransactionService.collectUTXOTransactionPages(
            chainId: "BTC",
            pageSize: 1,
            maxPages: 3
        ) { _, _ in
            defer { page += 1 }
            return page == 0 ? ([lower], true) : ([upper], false)
        }
        XCTAssertEqual(deduplicated.map(\.hash), ["ABCDEF"])

        let changed = try transaction(
            hash: "abcdef",
            address: "BC1QXY2KGDYGJRSQTZQ2N0YRF2493P83KKFJHX0WLH",
            value: "2"
        )
        await XCTAssertThrowsErrorAsync {
            var conflictPage = 0
            _ = try await TransactionService.collectUTXOTransactionPages(
                chainId: "BTC",
                pageSize: 1,
                maxPages: 3
            ) { _, _ in
                defer { conflictPage += 1 }
                return conflictPage == 0 ? ([lower], true) : ([changed], false)
            }
        }
    }

    func testUTXOHashCaseVariantsDeduplicateAcrossFreshImport() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "DTrackedBase58Address"
        let asset = Asset(currency: "DOGE", address: trackedAddress, chainId: "DOGE")
        context.insert(asset)
        try context.save()

        let first = TatumTransaction(
            hash: "ABCDEF012345",
            timestamp: 1_600_000_000_000,
            chain: "DOGE",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1"
        )
        let caseVariant = TatumTransaction(
            hash: "abcdef012345",
            timestamp: 1_600_000_000_000,
            chain: "DOGE",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [first, caseVariant],
                for: asset
            ),
            1
        )
        XCTAssertEqual(asset.transactions?.count, 1)
    }

    func testUTXOLegacyHashCaseFoldUpgradesUniqueRowAndQuarantinesCollision() throws {
        let uniqueContainer = try TestContainer.create()
        let uniqueContext = ModelContext(uniqueContainer)
        let uniqueAsset = Asset(
            currency: "DOGE",
            address: "DTrackedUnique",
            chainId: "DOGE"
        )
        let uniqueLegacy = Transaction(
            amount: 9,
            asset: uniqueAsset,
            date: Date(timeIntervalSince1970: 1_500_000_000),
            source: .onChain,
            externalId: "ABCDEF"
        )
        uniqueContext.insert(uniqueAsset)
        uniqueContext.insert(uniqueLegacy)
        try uniqueContext.save()
        let uniqueID = uniqueLegacy.id

        let refreshed = TatumTransaction(
            hash: "abcdef",
            timestamp: 1_600_000_000_000,
            chain: "DOGE",
            address: "DTrackedUnique",
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: uniqueContext).upsert(
                transactions: [refreshed],
                for: uniqueAsset
            ),
            1
        )
        XCTAssertEqual(uniqueAsset.transactions?.count, 1)
        XCTAssertEqual(uniqueAsset.transactions?.first?.id, uniqueID)
        XCTAssertEqual(uniqueAsset.transactions?.first?.amount, 1)

        let collisionContainer = try TestContainer.create()
        let collisionContext = ModelContext(collisionContainer)
        let collisionAsset = Asset(
            currency: "DOGE",
            address: "DTrackedCollision",
            chainId: "DOGE"
        )
        let upper = Transaction(
            amount: 2,
            asset: collisionAsset,
            source: .onChain,
            externalId: "COLLISION"
        )
        let lower = Transaction(
            amount: 3,
            asset: collisionAsset,
            source: .onChain,
            externalId: "collision"
        )
        collisionContext.insert(collisionAsset)
        collisionContext.insert(upper)
        collisionContext.insert(lower)
        try collisionContext.save()

        let collisionRefresh = TatumTransaction(
            hash: "collision",
            timestamp: 1_600_000_000_000,
            chain: "DOGE",
            address: "DTrackedCollision",
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: collisionContext).upsert(
                transactions: [collisionRefresh],
                for: collisionAsset
            ),
            1
        )
        XCTAssertEqual(collisionAsset.transactions?.count, 3)
        XCTAssertEqual(Set([upper.amount, lower.amount]), Set([2, 3]))
        XCTAssertEqual(Set([upper.externalId, lower.externalId]), Set(["COLLISION", "collision"]))
        let canonical = try XCTUnwrap(
            collisionAsset.transactions?.first {
                $0.id != upper.id && $0.id != lower.id
            }
        )
        XCTAssertEqual(canonical.amount, 1)
        XCTAssertTrue(canonical.externalId?.hasPrefix("onchain_v") == true)
    }

    func testUTXODurableAliasPreventsIdentityDowngradeAndLaterDuplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qdurablealias"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        func movement(
            hash: String,
            aliases: [String]? = nil
        ) -> TatumTransaction {
            TatumTransaction(
                hash: hash,
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1",
                providerHashAliases: aliases
            )
        }

        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(
            try service.upsert(
                transactions: [movement(hash: "witness-hash")],
                for: asset
            ),
            1
        )
        let originalID = try XCTUnwrap(asset.transactions?.first?.id)

        XCTAssertEqual(
            try service.upsert(
                transactions: [
                    movement(
                        hash: "canonical-txid",
                        aliases: ["witness-hash"]
                    )
                ],
                for: asset
            ),
            1
        )
        let strengthenedExternalID = try XCTUnwrap(asset.transactions?.first?.externalId)
        XCTAssertTrue(strengthenedExternalID.contains("canonical-txid"))
        XCTAssertTrue(strengthenedExternalID.contains("witness-hash"))

        XCTAssertEqual(
            try service.upsert(
                transactions: [movement(hash: "witness-hash")],
                for: asset
            ),
            0
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, originalID)
        XCTAssertEqual(asset.transactions?.first?.externalId, strengthenedExternalID)
    }

    func testUTXOPageOverlapCollapsesWeakHashIntoEnrichedTxidIdentity() async throws {
        func transaction(_ json: String) throws -> TatumUTXOTransaction {
            try TransactionService.decodeProviderResponse(
                TatumUTXOTransaction.self,
                from: try XCTUnwrap(json.data(using: .utf8))
            )
        }
        let weak = try transaction(
            """
            {
              "hash":"witness-hash",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """
        )
        let enriched = try transaction(
            """
            {
              "txid":"canonical-txid",
              "hash":"witness-hash",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """
        )
        var page = 0

        let collected = try await TransactionService.collectUTXOTransactionPages(
            chainId: "BTC",
            pageSize: 1,
            maxPages: 3
        ) { _, _ in
            defer { page += 1 }
            return page == 0 ? ([weak], true) : ([enriched], false)
        }

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected.first?.hash, "canonical-txid")
        XCTAssertEqual(collected.first?.providerHashAliases, ["witness-hash"])
    }

    func testFreshUTXOBatchWithSharedAliasFailsBeforeAnyWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qsharedalias"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        func movement(hash: String) -> TatumTransaction {
            TatumTransaction(
                hash: hash,
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1",
                providerHashAliases: ["shared-witness-hash"]
            )
        }

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [
                    movement(hash: "canonical-txid-a"),
                    movement(hash: "canonical-txid-b")
                ],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testComplementaryProviderIndexesFailClosedBeforeAnyWrite() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()
        let transactionIndexed = TatumTransaction(
            hash: "0xcomplementary-indexes",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let logIndexed = TatumTransaction(
            hash: "0xcomplementary-indexes",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            logIndex: 11,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [transactionIndexed, logIndexed],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testLateAliasAmbiguityRollsBackEarlierMutationAndPreservesDurableRows() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qlateambiguity"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        let firstLegacy = Transaction(
            amount: 2,
            asset: asset,
            source: .onChain,
            externalId: "ambiguous-witness-hash",
            comment: "First durable legacy row"
        )
        let secondLegacy = Transaction(
            amount: 3,
            asset: asset,
            source: .onChain,
            externalId: "ambiguous-witness-hash",
            comment: "Second durable legacy row"
        )
        let unrelatedManual = Transaction(
            amount: 4,
            asset: asset,
            source: .manual,
            comment: "Unrelated durable transaction"
        )
        context.insert(asset)
        context.insert(firstLegacy)
        context.insert(secondLegacy)
        context.insert(unrelatedManual)
        try context.save()

        let safeFirst = TatumTransaction(
            hash: "safe-first-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1"
        )
        let ambiguousSecond = TatumTransaction(
            hash: "ambiguous-second-txid",
            timestamp: 1_750_000_001_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["ambiguous-witness-hash"]
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [safeFirst, ambiguousSecond],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.filter { $0.source == .onChain }.count, 2)
        XCTAssertEqual(asset.transactions?.filter { $0.source == .manual }.count, 1)
        XCTAssertEqual(firstLegacy.comment, "First durable legacy row")
        XCTAssertEqual(secondLegacy.comment, "Second durable legacy row")
        XCTAssertEqual(unrelatedManual.comment, "Unrelated durable transaction")
        XCTAssertFalse(context.hasChanges)
    }

    func testCanonicalAndLegacyMetadataConflictFailsClosedWithoutDeletingEitherRow() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qmetadataconflict"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()
        let refreshed = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["legacy-witness-hash"]
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [refreshed],
                for: asset
            ),
            1
        )
        let canonical = try XCTUnwrap(asset.transactions?.first)
        canonical.comment = "Canonical user note"
        canonical.counterparty = "Canonical counterparty"
        let legacy = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "legacy-witness-hash",
            counterparty: "Legacy counterparty",
            comment: "Legacy user note"
        )
        context.insert(legacy)
        try context.save()

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [refreshed],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.filter { $0.source == .onChain }.count, 2)
        XCTAssertEqual(canonical.comment, "Canonical user note")
        XCTAssertEqual(canonical.counterparty, "Canonical counterparty")
        XCTAssertEqual(legacy.comment, "Legacy user note")
        XCTAssertEqual(legacy.counterparty, "Legacy counterparty")
        XCTAssertFalse(context.hasChanges)
    }

    func testCanonicalAndLegacyCounterpartyConflictFailsClosedWithoutUserComments() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qcounterpartyconflict"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()
        let refreshed = TatumTransaction(
            hash: "canonical-counterparty-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["legacy-counterparty-witness"]
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [refreshed],
                for: asset
            ),
            1
        )
        let canonical = try XCTUnwrap(asset.transactions?.first)
        canonical.counterparty = "Canonical counterparty"
        canonical.comment = "On-chain"
        let legacy = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "legacy-counterparty-witness",
            counterparty: "Legacy counterparty"
        )
        context.insert(legacy)
        try context.save()

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [refreshed],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.filter { $0.source == .onChain }.count, 2)
        XCTAssertEqual(canonical.counterparty, "Canonical counterparty")
        XCTAssertEqual(canonical.comment, "On-chain")
        XCTAssertEqual(legacy.counterparty, "Legacy counterparty")
        XCTAssertFalse(context.hasChanges)
    }

    func testRawUTXORejectsBlankPrimaryAndAliasIdentifiers() throws {
        let invalidPayloads = [
            """
            {
              "txid":"   ",
              "hash":"witness-hash",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """,
            """
            {
              "txid":"canonical-txid",
              "hash":"\\n\\t",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """,
            """
            {
              "wtxid":" ",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """
        ]

        for payload in invalidPayloads {
            XCTAssertThrowsError(
                try TransactionService.decodeProviderResponse(
                    TatumUTXOTransaction.self,
                    from: try XCTUnwrap(payload.data(using: .utf8))
                )
            )
        }
    }

    func testUTXOBlankAliasCannotLinkDistinctCanonicalTransactionsAcrossRefreshes() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qblankalias"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        func movement(hash: String) -> TatumTransaction {
            TatumTransaction(
                hash: hash,
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1",
                providerHashAliases: [" \n\t"]
            )
        }

        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertThrowsError(
            try service.upsert(
                transactions: [movement(hash: "canonical-txid-1")],
                for: asset
            )
        )
        XCTAssertThrowsError(
            try service.upsert(
                transactions: [movement(hash: "canonical-txid-2")],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testNegativeProviderIndexesAreRejectedBeforeCorrectedRefreshPublishes() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        func movement(
            transactionIndex: Int?,
            logIndex: Int?
        ) -> TatumTransaction {
            TatumTransaction(
                hash: "0xnegative-provider-index",
                timestamp: 1_750_000_000_000,
                chain: "ethereum-mainnet",
                address: trackedAddress,
                transactionIndex: transactionIndex,
                logIndex: logIndex,
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            )
        }

        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertThrowsError(
            try service.upsert(
                transactions: [movement(transactionIndex: -1, logIndex: nil)],
                for: asset
            )
        )
        XCTAssertThrowsError(
            try service.upsert(
                transactions: [movement(transactionIndex: 7, logIndex: -1)],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 0)
        XCTAssertFalse(context.hasChanges)

        XCTAssertEqual(
            try service.upsert(
                transactions: [movement(transactionIndex: 7, logIndex: 11)],
                for: asset
            ),
            1
        )
        XCTAssertEqual(asset.transactions?.count, 1)
    }

    func testCrossRefreshSharedUTXOAliasCannotRewriteInstalledCanonicalIdentity() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qcrossrefreshalias"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        func movement(hash: String) -> TatumTransaction {
            TatumTransaction(
                hash: hash,
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1",
                providerHashAliases: ["shared-witness-hash"]
            )
        }

        let service = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(
            try service.upsert(
                transactions: [movement(hash: "canonical-txid-1")],
                for: asset
            ),
            1
        )
        let installed = try XCTUnwrap(asset.transactions?.first)
        let installedExternalID = installed.externalId

        XCTAssertThrowsError(
            try service.upsert(
                transactions: [movement(hash: "canonical-txid-2")],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, installed.id)
        XCTAssertEqual(asset.transactions?.first?.externalId, installedExternalID)
        XCTAssertFalse(context.hasChanges)
    }

    func testPreAliasVersionScopedUTXODuplicatesCollapseToExactCanonicalRow() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qscopedduplicates"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let prefix = """
        onchain_v3|btc|\(trackedAddress)|btc|\(asset.id.uuidString.lowercased())|record_v1
        """
        let weak = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|witness-hash|btc|\(trackedAddress)||utxo|",
            counterparty: "Preserve weak counterparty",
            comment: "Preserve weak note"
        )
        let exact = Transaction(
            amount: 8,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|canonical-txid|btc|\(trackedAddress)||utxo|",
            comment: "On-chain"
        )
        context.insert(asset)
        context.insert(weak)
        context.insert(exact)
        try context.save()

        let enriched = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["witness-hash"]
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [enriched],
                for: asset
            ),
            1
        )

        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, exact.id)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.counterparty, "Preserve weak counterparty")
        XCTAssertEqual(rows.first?.comment, "Preserve weak note")
        XCTAssertTrue(rows.first?.externalId?.contains("canonical-txid") == true)
        XCTAssertTrue(rows.first?.externalId?.contains("witness-hash") == true)
        XCTAssertFalse(context.hasChanges)
    }

    func testPreAliasVersionScopedUTXODuplicatesWithMetadataConflictFailClosed() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qscopedconflict"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let prefix = """
        onchain_v3|btc|\(trackedAddress)|btc|\(asset.id.uuidString.lowercased())|record_v1
        """
        let weak = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|witness-hash|btc|\(trackedAddress)||utxo|",
            counterparty: "Weak counterparty",
            comment: "Weak note"
        )
        let exact = Transaction(
            amount: 8,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|canonical-txid|btc|\(trackedAddress)||utxo|",
            counterparty: "Canonical counterparty",
            comment: "Canonical note"
        )
        context.insert(asset)
        context.insert(weak)
        context.insert(exact)
        try context.save()
        let weakExternalID = weak.externalId
        let exactExternalID = exact.externalId

        let enriched = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["witness-hash"]
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [enriched],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.filter { $0.source == .onChain }.count, 2)
        XCTAssertEqual(weak.externalId, weakExternalID)
        XCTAssertEqual(exact.externalId, exactExternalID)
        XCTAssertEqual(weak.comment, "Weak note")
        XCTAssertEqual(exact.comment, "Canonical note")
        XCTAssertFalse(context.hasChanges)
    }

    func testExplicitUTXOTxidProvenanceSurvivesNormalizationAndRejectsCanonicalRewrite()
        async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qexplicitprovenance"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        func normalizedMovement(
            txid: String,
            providerHash: String
        ) async throws -> TatumTransaction {
            let payload = """
            [{
              "txid":"\(txid)",
              "hash":"\(providerHash)",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"100000000","address":"\(trackedAddress)"}]
            }]
            """
            let raw = try TransactionService.decodeProviderResponse(
                [TatumUTXOTransaction].self,
                from: try XCTUnwrap(payload.data(using: .utf8))
            )
            let movements = try await TransactionService.normalizeUTXOTransactions(
                chainId: "BTC",
                address: trackedAddress,
                transactions: raw,
                maxPrevoutLookups: 0
            ) { _ in
                XCTFail("A coinbase transaction must not request a prevout")
                throw TatumError.invalidResponse
            }
            return try XCTUnwrap(movements.first)
        }

        let first = try await normalizedMovement(
            txid: "explicit-txid-1",
            providerHash: "witness-hash"
        )
        XCTAssertEqual(first.providerHashProvenance, .explicitTxid)
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [first],
                for: asset
            ),
            1
        )
        let installed = try XCTUnwrap(asset.transactions?.first)
        let installedExternalID = installed.externalId
        XCTAssertTrue(installedExternalID?.contains("explicit_txid") == true)

        let conflicting = try await normalizedMovement(
            txid: "explicit-txid-2",
            providerHash: "explicit-txid-1"
        )
        XCTAssertEqual(conflicting.providerHashProvenance, .explicitTxid)
        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [conflicting],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, installed.id)
        XCTAssertEqual(asset.transactions?.first?.externalId, installedExternalID)
        XCTAssertFalse(context.hasChanges)
    }

    func testOneDurableProviderIdentityCannotAuthorizeTwoIncomingCanonicalMovements()
        throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qinverseuniqueness"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()

        let durable = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["provider-hash-x", "provider-hash-y"],
            providerHashProvenance: .explicitTxid
        )
        let importer = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(
            try importer.upsert(transactions: [durable], for: asset),
            1
        )
        let installed = try XCTUnwrap(asset.transactions?.first)
        let installedExternalID = installed.externalId

        let weakX = TatumTransaction(
            hash: "provider-hash-x",
            timestamp: 1_750_000_001_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashProvenance: .fallbackIdentifier
        )
        let weakY = TatumTransaction(
            hash: "provider-hash-y",
            timestamp: 1_750_000_002_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashProvenance: .fallbackIdentifier
        )

        XCTAssertThrowsError(
            try importer.upsertWithResult(
                transactions: [weakX, weakY],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, installed.id)
        XCTAssertEqual(asset.transactions?.first?.externalId, installedExternalID)
        XCTAssertFalse(context.hasChanges)
    }

    func testScopedExactAliasAndHashOnlyUTXODuplicatesCollapseAtomically() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qtriplecollapse"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let prefix = """
        onchain_v3|btc|\(trackedAddress)|btc|\(asset.id.uuidString.lowercased())|record_v1
        """
        let exact = Transaction(
            amount: 8,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|canonical-txid|btc|\(trackedAddress)||utxo|",
            comment: "On-chain"
        )
        let scopedAlias = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|witness-hash|btc|\(trackedAddress)||utxo|",
            comment: "Preserve shared note"
        )
        let hashOnlyAlias = Transaction(
            amount: 10,
            asset: asset,
            source: .onChain,
            externalId: "witness-hash",
            counterparty: "Preserve hash-only counterparty",
            comment: "Preserve shared note"
        )
        context.insert(asset)
        context.insert(exact)
        context.insert(scopedAlias)
        context.insert(hashOnlyAlias)
        try context.save()

        let enriched = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["witness-hash"],
            providerHashProvenance: .explicitTxid
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [enriched],
                for: asset
            ),
            1
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, exact.id)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.comment, "Preserve shared note")
        XCTAssertEqual(
            rows.first?.counterparty,
            "Preserve hash-only counterparty"
        )
        XCTAssertTrue(rows.first?.externalId?.contains("canonical-txid") == true)
        XCTAssertTrue(rows.first?.externalId?.contains("witness-hash") == true)
        XCTAssertFalse(context.hasChanges)
    }

    func testTripleUTXODuplicateMetadataConflictFailsWithoutMutation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qtripleconflict"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
        let prefix = """
        onchain_v3|btc|\(trackedAddress)|btc|\(asset.id.uuidString.lowercased())|record_v1
        """
        let exact = Transaction(
            amount: 8,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|canonical-txid|btc|\(trackedAddress)||utxo|",
            comment: "Canonical note"
        )
        let scopedAlias = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|witness-hash|btc|\(trackedAddress)||utxo|",
            comment: "Alias note"
        )
        let hashOnlyAlias = Transaction(
            amount: 10,
            asset: asset,
            source: .onChain,
            externalId: "witness-hash",
            comment: "Hash-only note"
        )
        context.insert(asset)
        context.insert(exact)
        context.insert(scopedAlias)
        context.insert(hashOnlyAlias)
        try context.save()
        let originalIDs = [exact.externalId, scopedAlias.externalId, hashOnlyAlias.externalId]

        let enriched = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["witness-hash"],
            providerHashProvenance: .explicitTxid
        )

        XCTAssertThrowsError(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [enriched],
                for: asset
            )
        )
        XCTAssertEqual(asset.transactions?.filter { $0.source == .onChain }.count, 3)
        XCTAssertEqual(
            [exact.externalId, scopedAlias.externalId, hashOnlyAlias.externalId],
            originalIDs
        )
        XCTAssertEqual(exact.comment, "Canonical note")
        XCTAssertEqual(scopedAlias.comment, "Alias note")
        XCTAssertEqual(hashOnlyAlias.comment, "Hash-only note")
        XCTAssertFalse(context.hasChanges)
    }

    func testPersistedNegativeProviderIndexMigratesToUniqueValidCanonicalRow() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!
        let prefix = """
        onchain_v3|eth|\(trackedAddress)|eth|\(asset.id.uuidString.lowercased())|record_v1
        """
        let invalid = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|negative-index-hash|ethereum-mainnet|\(trackedAddress)|-1|native|",
            comment: "Preserve migrated note"
        )
        context.insert(asset)
        context.insert(invalid)
        try context.save()

        let corrected = TatumTransaction(
            hash: "negative-index-hash",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [corrected],
                for: asset
            ),
            1
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, invalid.id)
        XCTAssertEqual(rows.first?.amount, 1)
        XCTAssertEqual(rows.first?.comment, "Preserve migrated note")
        XCTAssertFalse(rows.first?.externalId?.contains("|-1|") == true)
        XCTAssertTrue(rows.first?.externalId?.contains("|7|") == true)
        XCTAssertFalse(context.hasChanges)
    }

    func testProviderIdentifierGrammarRejectsDelimitersControlsAndWhitespace()
        throws {
        let invalidRawIdentifiers = [
            " txid",
            "txid ",
            "tx|id",
            "tx\\u0000id",
            "tx\\u001Fid"
        ]
        for encodedIdentifier in invalidRawIdentifiers {
            let payload = """
            {
              "txid":"\(encodedIdentifier)",
              "time":1700000000,
              "vin":[{"coinbase":"01"}],
              "vout":[{"value":"1","address":"bc1qtracked"}]
            }
            """
            XCTAssertThrowsError(
                try TransactionService.decodeProviderResponse(
                    TatumUTXOTransaction.self,
                    from: try XCTUnwrap(payload.data(using: .utf8))
                ),
                "Raw identifier must be rejected: \(encodedIdentifier)"
            )
        }

        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qidentifiergrammar"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        context.insert(asset)
        try context.save()
        let importer = OnChainTransactionImportService(modelContext: context)
        let invalidDirectIdentifiers = [
            " canonical",
            "canonical ",
            "canonical|alias",
            "canonical\u{0000}alias",
            "canonical\u{001F}alias"
        ]
        for identifier in invalidDirectIdentifiers {
            let invalidHash = TatumTransaction(
                hash: identifier,
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1"
            )
            XCTAssertThrowsError(
                try importer.upsert(transactions: [invalidHash], for: asset)
            )
            let invalidAlias = TatumTransaction(
                hash: "canonical-txid",
                timestamp: 1_750_000_000_000,
                chain: "BTC",
                address: trackedAddress,
                transactionType: "utxo",
                transactionSubtype: "received",
                amount: "1",
                providerHashAliases: [identifier]
            )
            XCTAssertThrowsError(
                try importer.upsert(transactions: [invalidAlias], for: asset)
            )
        }
        XCTAssertTrue((asset.transactions ?? []).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnmutatedCandidateIsNotPromotedByUnrelatedDurableInsert() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let retained = TatumTransaction(
            hash: "retained-unpublished-candidate",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 1,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [retained],
                for: asset
            ),
            1
        )
        let inserted = TatumTransaction(
            hash: "new-durable-candidate",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 2,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let importer = OnChainTransactionImportService(
            modelContext: context,
            durableCanonicalExternalIDLookup: { _, _, _ in [] }
        )

        let result = try importer.upsertWithResult(
            transactions: [retained, inserted],
            for: asset
        )

        XCTAssertEqual(result.mutationCount, 1)
        XCTAssertEqual(result.acceptedTransactions.map(\.hash), [
            "new-durable-candidate"
        ])
        XCTAssertEqual(asset.transactions?.count, 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testTripleCollapseAllowsExactRowWithDurableAliasMetadata() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "bc1qdurablealiastriple"
        let asset = Asset(currency: "BTC", address: trackedAddress, chainId: "BTC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000206")!
        context.insert(asset)
        try context.save()

        let enriched = TatumTransaction(
            hash: "canonical-txid",
            timestamp: 1_750_000_000_000,
            chain: "BTC",
            address: trackedAddress,
            transactionType: "utxo",
            transactionSubtype: "received",
            amount: "1",
            providerHashAliases: ["witness-hash"],
            providerHashProvenance: .explicitTxid
        )
        let importer = OnChainTransactionImportService(modelContext: context)
        XCTAssertEqual(
            try importer.upsert(transactions: [enriched], for: asset),
            1
        )
        let exact = try XCTUnwrap(asset.transactions?.first)
        XCTAssertTrue(exact.externalId?.contains("identity_v2") == true)

        let prefix = """
        onchain_v3|btc|\(trackedAddress)|btc|\(asset.id.uuidString.lowercased())|record_v1
        """
        let scopedAlias = Transaction(
            amount: 9,
            asset: asset,
            source: .onChain,
            externalId: "\(prefix)|witness-hash|btc|\(trackedAddress)||utxo|",
            comment: "Preserve shared note"
        )
        let hashOnlyAlias = Transaction(
            amount: 10,
            asset: asset,
            source: .onChain,
            externalId: "witness-hash",
            comment: "Preserve shared note"
        )
        context.insert(scopedAlias)
        context.insert(hashOnlyAlias)
        try context.save()

        XCTAssertEqual(
            try importer.upsert(transactions: [enriched], for: asset),
            1
        )
        let rows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, exact.id)
        XCTAssertEqual(rows.first?.comment, "Preserve shared note")
        XCTAssertTrue(rows.first?.externalId?.contains("identity_v2") == true)
        XCTAssertFalse(context.hasChanges)
    }

    func testCounterpartyOnlyProviderCorrectionMigratesLegacyMovementIdentity()
        throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let oldCounterparty = "0x00000000000000000000000000000000000000bb"
        let newCounterparty = "0x00000000000000000000000000000000000000cc"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000207")!
        let original = TatumTransaction(
            hash: "counterparty-correction",
            timestamp: 1_750_000_000_000,
            from: oldCounterparty,
            to: trackedAddress,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 7,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1",
            counterAddress: oldCounterparty
        )
        let route = try BalanceRouteResolver.resolve(
            chainId: "ETH",
            symbol: "ETH",
            chainService: ChainService()
        )
        let legacyExternalID = [
            OnChainIdentifierPolicy.canonicalNamespace(for: route),
            "eth",
            OnChainIdentifierPolicy.normalizedAddress(
                trackedAddress,
                for: route
            ),
            "eth",
            asset.id.uuidString.lowercased(),
            original.movementIdentity(for: route)
        ].joined(separator: "|")
        let stored = Transaction(
            amount: 1,
            asset: asset,
            date: original.date,
            source: .onChain,
            externalId: legacyExternalID,
            counterparty: oldCounterparty,
            comment: "On-chain"
        )
        context.insert(asset)
        context.insert(stored)
        try context.save()

        let corrected = TatumTransaction(
            hash: original.hash,
            timestamp: original.timestamp,
            from: newCounterparty,
            to: trackedAddress,
            chain: original.chain,
            address: trackedAddress,
            transactionIndex: original.transactionIndex,
            transactionType: original.transactionType,
            transactionSubtype: original.transactionSubtype,
            amount: original.amount,
            counterAddress: newCounterparty
        )

        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [corrected],
                for: asset
            ),
            1
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, stored.id)
        XCTAssertNotEqual(stored.externalId, legacyExternalID)
        XCTAssertTrue(stored.externalId?.contains("|record_v1|") == true)
        XCTAssertFalse(context.hasChanges)
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
