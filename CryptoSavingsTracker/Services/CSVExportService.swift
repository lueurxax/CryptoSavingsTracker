//
//  CSVExportService.swift
//  CryptoSavingsTracker
//
//  Exports SwiftData models to CSV files (Goals, Assets, Value Changes).
//

import Foundation
import SwiftData

enum CSVExportError: LocalizedError {
    case exportDirectoryUnavailable
    case failedToWriteFile(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .exportDirectoryUnavailable:
            return "Export directory unavailable."
        case .failedToWriteFile(let url, let underlying):
            return "Failed to write export file \(url.lastPathComponent): \(underlying.localizedDescription)"
        }
    }
}

struct CSVExportService {
    static func exportCSVFiles(
        using modelContext: ModelContext,
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        exportedAt: Date = Date()
    ) throws -> [URL] {
        let goals = try modelContext.fetch(
            FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.name)])
        )
        let assets = try modelContext.fetch(
            FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.currency)])
        )
        let transactions = try modelContext.fetch(
            FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        )
        let allocationHistories = try modelContext.fetch(
            FetchDescriptor<AllocationHistory>(sortBy: [SortDescriptor(\.timestamp)])
        )

        let exportDirectory = try makeExportDirectory(baseDirectory: baseDirectory, exportedAt: exportedAt)

        let goalsURL = exportDirectory.appendingPathComponent("goals.csv")
        let assetsURL = exportDirectory.appendingPathComponent("assets.csv")
        let valueChangesURL = exportDirectory.appendingPathComponent("value_changes.csv")

        try write(makeGoalsCSV(goals: goals), to: goalsURL)
        try write(makeAssetsCSV(assets: assets), to: assetsURL)
        try write(
            makeValueChangesCSV(
                transactions: transactions,
                allocationHistories: allocationHistories,
                goals: goals,
                assets: assets
            ),
            to: valueChangesURL
        )

        return [goalsURL, assetsURL, valueChangesURL]
    }
}

private extension CSVExportService {
    static func makeExportDirectory(baseDirectory: URL, exportedAt: Date) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: baseDirectory.path) else {
            throw CSVExportError.exportDirectoryUnavailable
        }

        let timestamp = CSVFormatting.safeTimestamp(exportedAt)
        let exportDirectory = baseDirectory.appendingPathComponent("CryptoSavingsTracker-CSV-\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        return exportDirectory
    }

    static func write(_ contents: String, to url: URL) throws {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CSVExportError.failedToWriteFile(url, underlying: error)
        }
    }

    static func makeGoalsCSV(goals: [Goal]) -> String {
        let header = [
            "id",
            "name",
            "currency",
            "targetAmount",
            "deadline",
            "startDate",
            "lifecycleStatusRawValue",
            "lifecycleStatusChangedAt",
            "lastModifiedDate",
            "reminderFrequency",
            "reminderTime",
            "firstReminderDate",
            "emoji",
            "goalDescription",
            "link",
            "allocationCount",
            "allocationIds",
            "allocationsJson"
        ]

        let rows: [[String]] = goals.map { goal in
            let allocationIds = goal.allocations.map { $0.id.uuidString }.joined(separator: ";")
            return [
                goal.id.uuidString,
                goal.name,
                goal.currency,
                CSVFormatting.double(goal.targetAmount),
                CSVFormatting.date(goal.deadline),
                CSVFormatting.date(goal.startDate),
                goal.lifecycleStatusRawValue,
                CSVFormatting.dateOptional(goal.lifecycleStatusChangedAt),
                CSVFormatting.date(goal.lastModifiedDate),
                goal.reminderFrequency ?? "",
                CSVFormatting.dateOptional(goal.reminderTime),
                CSVFormatting.dateOptional(goal.firstReminderDate),
                goal.emoji ?? "",
                goal.goalDescription ?? "",
                goal.link ?? "",
                String(goal.allocations.count),
                allocationIds,
                allocationsJSON(goal.allocations)
            ]
        }

        return CSVWriter.csv(header: header, rows: rows)
    }

    static func makeAssetsCSV(assets: [Asset]) -> String {
        let header = [
            "id",
            "currency",
            "address",
            "chainId",
            "transactionCount",
            "transactionIds",
            "allocationCount",
            "allocationIds",
            "allocationsJson"
        ]

        let rows: [[String]] = assets.map { asset in
            let transactionIds = asset.transactions.map { $0.id.uuidString }.joined(separator: ";")
            let allocationIds = asset.allocations.map { $0.id.uuidString }.joined(separator: ";")
            return [
                asset.id.uuidString,
                asset.currency,
                asset.address ?? "",
                asset.chainId ?? "",
                String(asset.transactions.count),
                transactionIds,
                String(asset.allocations.count),
                allocationIds,
                allocationsJSON(asset.allocations)
            ]
        }

        return CSVWriter.csv(header: header, rows: rows)
    }

    static func makeValueChangesCSV(
        transactions: [Transaction],
        allocationHistories: [AllocationHistory],
        goals: [Goal],
        assets: [Asset]
    ) -> String {
        let goalNameById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.name) })
        let assetById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        struct ValueChangeEvent {
            let timestamp: Date
            let row: [String]
        }

        let header = [
            "eventType",
            "eventId",
            "timestamp",
            "amount",
            "amountSemantics",
            "assetId",
            "assetCurrency",
            "assetChainId",
            "assetAddress",
            "goalId",
            "goalName",
            "transactionSource",
            "transactionExternalId",
            "transactionCounterparty",
            "transactionComment",
            "allocationMonthLabel",
            "allocationCreatedAt"
        ]

        var events: [ValueChangeEvent] = []
        events.reserveCapacity(transactions.count + allocationHistories.count)

        for tx in transactions {
            let asset = tx.asset
            let row = [
                "transaction",
                tx.id.uuidString,
                CSVFormatting.date(tx.date),
                CSVFormatting.double(tx.amount),
                "delta",
                asset.id.uuidString,
                asset.currency,
                asset.chainId ?? "",
                asset.address ?? "",
                "",
                "",
                tx.sourceRawValue,
                tx.externalId ?? "",
                tx.counterparty ?? "",
                tx.comment ?? "",
                "",
                ""
            ]
            events.append(ValueChangeEvent(timestamp: tx.date, row: row))
        }

        for history in allocationHistories {
            let assetId = history.assetId ?? history.asset?.id
            let goalId = history.goalId ?? history.goal?.id
            let asset = assetId.flatMap { assetById[$0] }
            let goalName = goalId.flatMap { goalNameById[$0] } ?? ""

            let row = [
                "allocationHistory",
                history.id.uuidString,
                CSVFormatting.date(history.timestamp),
                CSVFormatting.double(history.amount),
                "allocationTargetSnapshot",
                assetId?.uuidString ?? "",
                asset?.currency ?? "",
                asset?.chainId ?? "",
                asset?.address ?? "",
                goalId?.uuidString ?? "",
                goalName,
                "",
                "",
                "",
                "",
                history.monthLabel,
                CSVFormatting.dateOptional(history.createdAt)
            ]
            events.append(ValueChangeEvent(timestamp: history.timestamp, row: row))
        }

        let sortedRows = events
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map(\.row)

        return CSVWriter.csv(header: header, rows: sortedRows)
    }

    static func allocationsJSON(_ allocations: [AssetAllocation]) -> String {
        struct ExportAllocation: Encodable {
            let id: String
            let amount: Double
            let createdDate: String
            let lastModifiedDate: String
            let assetId: String
            let goalId: String
            let assetCurrency: String
            let goalName: String
        }

        let exportAllocations: [ExportAllocation] = allocations.map { allocation in
            ExportAllocation(
                id: allocation.id.uuidString,
                amount: allocation.amount,
                createdDate: CSVFormatting.date(allocation.createdDate),
                lastModifiedDate: CSVFormatting.date(allocation.lastModifiedDate),
                assetId: allocation.asset?.id.uuidString ?? "",
                goalId: allocation.goal?.id.uuidString ?? "",
                assetCurrency: allocation.asset?.currency ?? "",
                goalName: allocation.goal?.name ?? ""
            )
        }

        do {
            let data = try JSONEncoder().encode(exportAllocations)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

private enum CSVFormatting {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func safeTimestamp(_ date: Date) -> String {
        let raw = isoFormatter.string(from: date)
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    static func date(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func dateOptional(_ date: Date?) -> String {
        guard let date else { return "" }
        return isoFormatter.string(from: date)
    }

    static func double(_ value: Double) -> String {
        String(value)
    }
}

private enum CSVWriter {
    static func csv(header: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(line(header))
        for row in rows {
            lines.append(line(row))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(_ values: [String]) -> String {
        values.map(escape).joined(separator: ",")
    }

    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
