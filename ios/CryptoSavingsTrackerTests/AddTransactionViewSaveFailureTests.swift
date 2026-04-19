import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct AddTransactionViewSaveFailureTests {
    @Test("save failure keeps the sheet open and exposes retryable error")
    func saveFailureDoesNotDismissAndKeepsDraftValues() {
        let asset = Asset(currency: "USD")
        let service = FailingTransactionMutationService()
        let transactionDate = Date(timeIntervalSince1970: 1_776_014_400)

        let result = AddTransactionSaveCoordinator.save(
            asset: asset,
            amountText: "125.50",
            date: transactionDate,
            comment: "April deposit",
            autoAllocateGoalId: nil,
            service: service
        )

        #expect(service.receivedAsset === asset)
        #expect(service.receivedAmount == 125.50)
        #expect(service.receivedDate == transactionDate)
        #expect(service.receivedComment == "April deposit")
        #expect(result.shouldDismiss == false)
        #expect(result.error?.title == "Transaction Not Saved")
        #expect(result.error?.isRetryable == true)
        #expect((asset.transactions ?? []).isEmpty)
    }

    @Test("add transaction view wires injectable service, retry alert, and no failure dismiss")
    func addTransactionViewFailureRecoveryContract() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/AddTransactionView.swift")

        #expect(source.contains("transactionServiceFactory"))
        #expect(source.contains("@State private var transactionDate = Date()"))
        #expect(source.contains("DatePicker("))
        #expect(source.contains("date: transactionDate"))
        #expect(source.contains("AddTransactionSaveCoordinator.save"))
        #expect(source.contains("Button(\"Retry\")"))
        #expect(source.contains("if let error = result.error"))
        #expect(source.contains("return\n        }\n\n        if result.shouldDismiss"))
        #expect(!source.contains("TODO: Add error state display"))
        #expect(!source.contains("print("))
        #expect(!source.contains("EmptyView()"))
        #expect(!source.contains("amount = Self.formatAmount"))
        #expect(!source.contains("comment.removeAll()"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

@MainActor
private final class FailingTransactionMutationService: TransactionMutationServiceProtocol {
    enum Failure: Error {
        case forced
    }

    private(set) var receivedAsset: Asset?
    private(set) var receivedAmount: Double?
    private(set) var receivedDate: Date?
    private(set) var receivedComment: String?

    func createTransaction(
        for asset: Asset,
        amount: Double,
        date: Date,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        receivedAsset = asset
        receivedAmount = amount
        receivedDate = date
        receivedComment = comment
        throw Failure.forced
    }

    func deleteTransaction(_ transaction: Transaction) throws {}
}
