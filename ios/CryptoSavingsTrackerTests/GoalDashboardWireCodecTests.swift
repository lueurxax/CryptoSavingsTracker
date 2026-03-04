//
//  GoalDashboardWireCodecTests.swift
//  CryptoSavingsTrackerTests
//
//  Ensures canonical Decimal/Date wire format behavior for dashboard fixtures.
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalDashboardWireCodecTests {
    @Test("Goal dashboard wire fixtures exist")
    func fixtureFilesExist() throws {
        let root = repositoryRoot()
        let expectedFiles = [
            "shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json",
            "shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_parity.v1.schema.json",
            "shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json",
            "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json",
            "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json"
        ]

        for relativePath in expectedFiles {
            let path = root.appendingPathComponent(relativePath)
            #expect(FileManager.default.fileExists(atPath: path.path), "Missing fixture: \(relativePath)")
        }
    }

    @Test("Wire codec decimal/date round-trip matches canonical fixtures")
    func wireCodecRoundTrip() throws {
        let fixture = try loadRoundTripFixture()

        for decimalString in fixture.decimals {
            let decoded = try GoalDashboardWireCodec.decode(decimal: decimalString)
            let reEncoded = GoalDashboardWireCodec.encode(decimal: decoded)
            let roundTrip = try GoalDashboardWireCodec.decode(decimal: reEncoded)
            #expect(roundTrip == decoded, "Decimal round-trip mismatch for \(decimalString)")
        }

        for dateString in fixture.datesUtcMillis {
            let decodedDate = try GoalDashboardWireCodec.decode(date: dateString)
            let reEncoded = GoalDashboardWireCodec.encode(date: decodedDate)
            let roundTrip = try GoalDashboardWireCodec.decode(date: reEncoded)
            #expect(roundTrip == decodedDate, "Date round-trip mismatch for \(dateString)")
            #expect(reEncoded.hasSuffix("Z"))
        }
    }

    private func loadRoundTripFixture() throws -> WireRoundTripFixture {
        let root = repositoryRoot()
        let fixtureURL = root.appendingPathComponent(
            "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(WireRoundTripFixture.self, from: data)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CryptoSavingsTrackerTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository
    }
}

private struct WireRoundTripFixture: Decodable {
    let decimals: [String]
    let datesUtcMillis: [String]
}
