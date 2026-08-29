import Foundation

struct AssetBalanceAccountingEvidence: Equatable, Sendable {
    let hasTrackedWallet: Bool
    let hasManualTransactions: Bool
}

enum AssetBalanceAccountingModeResolver {
    static func resolve(_ evidence: AssetBalanceAccountingEvidence) -> AssetBalanceAccountingMode {
        guard evidence.hasTrackedWallet else { return .manual }
        return evidence.hasManualTransactions ? .mixed : .onChain
    }

    @MainActor
    static func resolve(asset: Asset) -> AssetBalanceAccountingMode {
        let hasTrackedWallet = asset.address?.isEmpty == false && asset.chainId?.isEmpty == false
        let hasManualTransactions = (asset.transactions ?? []).contains { $0.source == .manual }
        return resolve(
            AssetBalanceAccountingEvidence(
                hasTrackedWallet: hasTrackedWallet,
                hasManualTransactions: hasManualTransactions
            )
        )
    }
}
