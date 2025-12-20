import XCTest
import SwiftData
@testable import CryptoSavingsTracker

final class CSVExportServiceTests: XCTestCase {
    func testExportCreatesThreeCSVFiles() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = Goal(
            name: "Hello, \"World\"",
            currency: "USD",
            targetAmount: 123.45,
            deadline: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let asset = Asset(currency: "BTC", address: "0xabc", chainId: "eth")
        let tx = Transaction(
            amount: 0.1,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_100),
            source: .manual,
            comment: "Comma, quote: \"ok\""
        )
        let history = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 0.2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200)
        )

        context.insert(goal)
        context.insert(asset)
        context.insert(tx)
        context.insert(history)
        try context.save()

        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSVExportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let urls = try CSVExportService.exportCSVFiles(
            using: context,
            baseDirectory: baseDirectory,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(urls.map(\.lastPathComponent).sorted(), ["assets.csv", "goals.csv", "value_changes.csv"])

        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(contents.contains("\n"))
        }

        let goalsCSV = try String(contentsOf: urls.first(where: { $0.lastPathComponent == "goals.csv" })!, encoding: .utf8)
        XCTAssertTrue(goalsCSV.starts(with: "id,name,currency,targetAmount,deadline"))
        XCTAssertTrue(goalsCSV.contains("\"Hello, \"\"World\"\"\""))

        let valueChangesCSV = try String(
            contentsOf: urls.first(where: { $0.lastPathComponent == "value_changes.csv" })!,
            encoding: .utf8
        )
        XCTAssertTrue(valueChangesCSV.contains("transaction,"))
        XCTAssertTrue(valueChangesCSV.contains("allocationHistory,"))
        XCTAssertTrue(valueChangesCSV.contains("\"Comma, quote: \"\"ok\"\"\""))
    }
}

