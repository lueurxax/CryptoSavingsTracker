//
//  MonthlyCycleStateResolverParityTests.swift
//  CryptoSavingsTrackerTests
//
//  Shared fixture parity tests for iOS/Android monthly cycle resolver behavior.
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct MonthlyCycleStateResolverParityTests {

    @Test("MonthlyCycleStateResolver matches shared monthly-cycle fixtures")
    func testResolverParityFixtures() throws {
        let resolver = MonthlyCycleStateResolver()
        let fixtureFiles = try Self.fixtureFiles()
        #expect(!fixtureFiles.isEmpty)

        for fileURL in fixtureFiles {
            let fixture = try Self.decodeFixture(fileURL)
            try fixture.expected.validateUnion()
            let actual = resolver.resolve(try fixture.toResolverInput())
            let expected = try fixture.expected.toUiCycleState()

            #expect(
                actual == expected,
                "Mismatch for fixture \(fileURL.lastPathComponent): expected \(expected), got \(actual)"
            )
        }
    }

    @Test("Fixture expected union validator rejects mixed state payloads")
    func testExpectedUnionValidationRejectsMixedPayload() throws {
        let invalidJson = """
        {
          "state": "planning",
          "planning": { "month": "2026-03", "source": "currentMonth" },
          "executing": { "month": "2026-03", "canFinish": true, "canUndoStart": true }
        }
        """

        let expected = try JSONDecoder().decode(FixtureExpected.self, from: Data(invalidJson.utf8))
        var didThrow = false
        do {
            try expected.validateUnion()
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    private static func fixtureFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CryptoSavingsTrackerTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository root

        let directory = root.appendingPathComponent("shared-test-fixtures/monthly-cycle", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files
    }

    private static func decodeFixture(_ url: URL) throws -> Fixture {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }
}

private struct Fixture: Decodable {
    let displayTimeZone: String
    let nowUtc: String
    let currentStorageMonthLabelUtc: String
    let undoWindowSeconds: Double
    let records: [FixtureRecord]
    let expected: FixtureExpected

    func toResolverInput() throws -> ResolverInput {
        guard let tz = TimeZone(identifier: displayTimeZone) else {
            throw FixtureParseError.invalidTimeZone(displayTimeZone)
        }
        let now = try FixtureDateParser.parse(nowUtc)
        let mapped = try records.map { record in
            ExecutionRecordSnapshot(
                monthLabel: record.monthLabel,
                status: try record.toStatus(),
                completedAt: try record.completedAt.map(FixtureDateParser.parse),
                startedAt: try record.startedAt.map(FixtureDateParser.parse),
                canUndoUntil: try record.canUndoUntil.map(FixtureDateParser.parse)
            )
        }

        return ResolverInput(
            nowUtc: now,
            displayTimeZone: tz,
            currentStorageMonthLabelUtc: currentStorageMonthLabelUtc,
            records: mapped,
            undoWindowSeconds: undoWindowSeconds
        )
    }
}

private struct FixtureRecord: Decodable {
    let monthLabel: String
    let status: String
    let startedAt: String?
    let completedAt: String?
    let canUndoUntil: String?

    func toStatus() throws -> MonthlyExecutionRecord.ExecutionStatus {
        guard let value = MonthlyExecutionRecord.ExecutionStatus(rawValue: status.lowercased()) else {
            throw FixtureParseError.invalidStatus(status)
        }
        return value
    }
}

private struct FixtureExpected: Decodable {
    let state: String
    let planning: FixtureExpectedPlanning?
    let executing: FixtureExpectedExecuting?
    let closed: FixtureExpectedClosed?
    let conflict: FixtureExpectedConflict?

    func validateUnion() throws {
        let nonNilCount = [planning != nil, executing != nil, closed != nil, conflict != nil]
            .filter { $0 }
            .count
        guard nonNilCount == 1 else {
            throw FixtureParseError.invalidExpectedUnion("Exactly one expected state payload is required")
        }

        switch state {
        case "planning":
            guard planning != nil, executing == nil, closed == nil, conflict == nil else {
                throw FixtureParseError.invalidExpectedUnion("Planning state must include only planning payload")
            }
        case "executing":
            guard planning == nil, executing != nil, closed == nil, conflict == nil else {
                throw FixtureParseError.invalidExpectedUnion("Executing state must include only executing payload")
            }
        case "closed":
            guard planning == nil, executing == nil, closed != nil, conflict == nil else {
                throw FixtureParseError.invalidExpectedUnion("Closed state must include only closed payload")
            }
        case "conflict":
            guard planning == nil, executing == nil, closed == nil, conflict != nil else {
                throw FixtureParseError.invalidExpectedUnion("Conflict state must include only conflict payload")
            }
        default:
            throw FixtureParseError.invalidExpectedUnion("Unknown expected state '\(state)'")
        }
    }

    func toUiCycleState() throws -> UiCycleState {
        switch state {
        case "planning":
            guard let planning else { throw FixtureParseError.invalidExpectedUnion("Missing planning payload") }
            return .planning(month: planning.month, source: try planning.toSource())
        case "executing":
            guard let executing else { throw FixtureParseError.invalidExpectedUnion("Missing executing payload") }
            return .executing(
                month: executing.month,
                canFinish: executing.canFinish,
                canUndoStart: executing.canUndoStart
            )
        case "closed":
            guard let closed else { throw FixtureParseError.invalidExpectedUnion("Missing closed payload") }
            return .closed(month: closed.month, canUndoCompletion: closed.canUndoCompletion)
        case "conflict":
            guard let conflict else { throw FixtureParseError.invalidExpectedUnion("Missing conflict payload") }
            return .conflict(month: conflict.month, reason: try conflict.toReason())
        default:
            throw FixtureParseError.invalidExpectedUnion("Unknown expected state '\(state)'")
        }
    }
}

private struct FixtureExpectedPlanning: Decodable {
    let month: String
    let source: String

    func toSource() throws -> PlanningSource {
        switch source {
        case "currentMonth":
            return .currentMonth
        case "nextMonthAfterClosed":
            return .nextMonthAfterClosed
        default:
            throw FixtureParseError.invalidSource(source)
        }
    }
}

private struct FixtureExpectedExecuting: Decodable {
    let month: String
    let canFinish: Bool
    let canUndoStart: Bool
}

private struct FixtureExpectedClosed: Decodable {
    let month: String
    let canUndoCompletion: Bool
}

private struct FixtureExpectedConflict: Decodable {
    let month: String?
    let reason: String

    func toReason() throws -> CycleConflictReason {
        switch reason {
        case "duplicateActiveRecords":
            return .duplicateActiveRecords
        case "invalidMonthLabel":
            return .invalidMonthLabel
        case "futureRecord":
            return .futureRecord
        default:
            throw FixtureParseError.invalidReason(reason)
        }
    }
}

private enum FixtureDateParser {
    private static let parsers: [ISO8601DateFormatter] = {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return [full, basic]
    }()

    static func parse(_ value: String) throws -> Date {
        for parser in parsers {
            if let parsed = parser.date(from: value) {
                return parsed
            }
        }
        throw FixtureParseError.invalidDate(value)
    }
}

private enum FixtureParseError: Error {
    case invalidDate(String)
    case invalidTimeZone(String)
    case invalidStatus(String)
    case invalidSource(String)
    case invalidReason(String)
    case invalidExpectedUnion(String)
}
