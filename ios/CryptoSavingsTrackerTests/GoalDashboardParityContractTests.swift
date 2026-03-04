//
//  GoalDashboardParityContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalDashboardParityContractTests {
    @Test("Parity artifact matches iOS dashboard contract constants")
    func parityArtifactMatchesConstants() throws {
        let artifact = try loadParityArtifact()

        #expect(artifact.version == GoalDashboardContract.parityVersion)
        #expect(artifact.moduleIds == GoalDashboardModuleID.allCases.map(\.rawValue))
        #expect(artifact.resolverStateIds == GoalDashboardContract.resolverStateIDs)
        #expect(artifact.copyKeys == GoalDashboardContract.nextActionReasonCopyKeys)
        #expect(artifact.statusChipIds == GoalDashboardContract.statusChipIDs)
    }

    private func loadParityArtifact() throws -> ParityArtifact {
        let root = repositoryRoot()
        let artifactURL = root.appendingPathComponent("shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json")
        let data = try Data(contentsOf: artifactURL)
        return try JSONDecoder().decode(ParityArtifact.self, from: data)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ParityArtifact: Decodable {
    let version: String
    let moduleIds: [String]
    let resolverStateIds: [String]
    let copyKeys: [String]
    let statusChipIds: [String]
}
