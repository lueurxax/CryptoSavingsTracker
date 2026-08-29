import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct AssetBalanceAccountingModeResolverTests {
    @Test(arguments: [
        (nil as String?, nil as String?),
        ("" as String?, "ethereum" as String?),
        ("0xabc" as String?, "" as String?)
    ])
    func missingWalletPairIsManual(address: String?, chainID: String?) {
        let evidence = AssetBalanceAccountingEvidence(
            hasTrackedWallet: address?.isEmpty == false && chainID?.isEmpty == false,
            hasManualTransactions: false
        )
        #expect(AssetBalanceAccountingModeResolver.resolve(evidence) == .manual)
    }

    @Test("tracked wallet without manual transactions is on-chain even without a cached balance")
    func trackedWalletIsOnChain() {
        let asset = Asset(
            currency: "USDT",
            address: "0x\(UUID().uuidString)",
            chainId: "ethereum"
        )
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .onChain)
    }

    @Test("any manual transaction makes a tracked wallet mixed")
    func trackedWalletWithManualHistoryIsMixed() {
        let asset = Asset(currency: "USDT", address: "0xabc", chainId: "ethereum")
        asset.transactions = [Transaction(amount: 1, asset: asset, source: .manual)]
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .mixed)
    }

    @Test("zero net manual history remains mixed")
    func zeroNetManualHistoryIsMixed() {
        let asset = Asset(currency: "USDT", address: "0xabc", chainId: "ethereum")
        asset.transactions = [
            Transaction(amount: 1, asset: asset, source: .manual),
            Transaction(amount: -1, asset: asset, source: .manual)
        ]
        #expect(asset.manualBalance == 0)
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .mixed)
    }
}
