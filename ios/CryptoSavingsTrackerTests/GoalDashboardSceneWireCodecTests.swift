//
//  GoalDashboardSceneWireCodecTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalDashboardSceneWireCodecTests {
    @Test("Scene fixture decodes with canonical wire codec")
    func decodeSceneFixture() throws {
        let fixtureURL = repositoryRoot().appendingPathComponent(
            "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"
        )
        let data = try Data(contentsOf: fixtureURL)

        let scene = try GoalDashboardSceneWireCodec.decodeScene(data: data)

        #expect(scene.currency == "USD")
        #expect(scene.snapshot.currentAmount == Decimal(string: "1500.25"))
        #expect(scene.nextAction.resolverState == .onTrack)
        #expect(scene.forecastRisk.confidence == .medium)
    }

    @Test("Scene wire codec round-trip preserves canonical decimal/date strings")
    func sceneRoundTripPreservesWireCanonical() throws {
        let fixtureURL = repositoryRoot().appendingPathComponent(
            "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"
        )
        let data = try Data(contentsOf: fixtureURL)

        let scene = try GoalDashboardSceneWireCodec.decodeScene(data: data)
        let encoded = try GoalDashboardSceneWireCodec.encode(scene: scene)
        let wire = try GoalDashboardSceneWireCodec.decodeWireModel(data: encoded)

        #expect(wire.snapshot.currentAmount == "1500.25")
        #expect(wire.forecastRisk.projectedAmount == "3200")
        #expect(wire.generatedAt.hasSuffix("Z"))
        #expect(wire.snapshot.lastUpdatedAt?.hasSuffix("Z") == true)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
