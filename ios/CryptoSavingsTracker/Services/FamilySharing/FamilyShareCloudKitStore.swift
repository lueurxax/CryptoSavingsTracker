//
//  FamilyShareCloudKitStore.swift
//  CryptoSavingsTracker
//

#if canImport(CloudKit)
import CloudKit
import Foundation

enum FamilyShareCloudKitError: LocalizedError {
    case rolloutDisabled
    case rootRecordMissing
    case sharedProjectionMissing
    case accountUnavailable
    case malformedProjection

    var errorDescription: String? {
        switch self {
        case .rolloutDisabled:
            return "Family sharing is currently disabled."
        case .rootRecordMissing:
            return "The shared projection root record could not be found."
        case .sharedProjectionMissing:
            return "Shared goals are not available yet."
        case .accountUnavailable:
            return "iCloud account is unavailable for family sharing."
        case .malformedProjection:
            return "The shared projection is malformed and cannot be rendered safely."
        }
    }
}

protocol FamilyShareCloudSyncing {
    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws
    func prepareShare(for request: FamilyShareCloudSharingPreparationRequest) async throws -> (share: CKShare, container: CKContainer)
    func fetchAcceptedProjection(from snapshot: FamilyShareInvitationMetadataSnapshot) async throws -> FamilyShareSeededNamespaceState
    func refreshProjection(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareSeededNamespaceState
    func revoke(namespaceID: FamilyShareNamespaceID) async throws
}

final class DefaultFamilyShareCloudKitStore: FamilyShareCloudSyncing {
    private enum RecordType {
        static let root = "FamilyShareProjectionRoot"
        static let goal = "FamilySharedGoalProjection"
    }

    private enum Field {
        static let namespaceKey = "namespaceKey"
        static let ownerID = "ownerID"
        static let shareID = "shareID"
        static let ownerDisplayName = "ownerDisplayName"
        static let schemaVersion = "schemaVersion"
        static let projectionVersion = "projectionVersion"
        static let activeProjectionVersion = "activeProjectionVersion"
        static let freshnessState = "freshnessStateRawValue"
        static let lifecycleState = "lifecycleStateRawValue"
        static let publishedAt = "publishedAt"
        static let lastReconciledAt = "lastReconciledAt"
        static let lastRefreshAttemptAt = "lastRefreshAttemptAt"
        static let lastRefreshErrorCode = "lastRefreshErrorCode"
        static let lastRefreshErrorMessage = "lastRefreshErrorMessage"
        static let summaryTitle = "summaryTitle"
        static let summaryCopy = "summaryCopy"
        static let participantCount = "participantCount"
        static let pendingParticipantCount = "pendingParticipantCount"
        static let revokedParticipantCount = "revokedParticipantCount"
        static let shareRecordName = "shareRecordName"
        static let rootReference = "rootReference"
        static let goalID = "goalID"
        static let goalName = "goalName"
        static let goalEmoji = "goalEmoji"
        static let currency = "currency"
        static let targetAmount = "targetAmount"
        static let currentAmount = "currentAmount"
        static let progressRatio = "progressRatio"
        static let deadline = "deadline"
        static let goalStatus = "goalStatusRawValue"
        static let forecastState = "forecastStateRawValue"
        static let lastUpdatedAt = "lastUpdatedAt"
        static let summaryCopyGoal = "goalSummaryCopy"
        static let sortIndex = "sortIndex"
    }

    private let container: CKContainer
    private let environment: FamilyShareCacheStoreEnvironment
    private let telemetry: FamilyShareTelemetryTracking
    private let rollout: FamilyShareRollout

    init(
        container: CKContainer = .default(),
        environment: FamilyShareCacheStoreEnvironment = .current(),
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker(),
        rollout: FamilyShareRollout = .shared
    ) {
        self.container = container
        self.environment = environment
        self.telemetry = telemetry
        self.rollout = rollout
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
        guard rollout.isEnabled() else {
            throw FamilyShareCloudKitError.rolloutDisabled
        }
        guard environment.isTestRun == false else { return }

        let database = container.privateCloudDatabase
        try await ensureZoneExists(for: payload.namespaceID, in: database)
        let rootRecord = rootRecord(for: payload)
        let goalRecords = payload.goals.map { goalRecord(for: $0, rootRecordID: rootRecord.recordID) }
        let existingGoalIDs = try await existingGoalRecordIDs(namespaceID: payload.namespaceID, in: database)
        let desiredGoalIDs = Set(goalRecords.map(\.recordID))
        let recordIDsToDelete = Array(existingGoalIDs.subtracting(desiredGoalIDs))

        telemetry.track(
            .sharePublished,
            payload: [
                "namespace": payload.namespaceID.namespaceKey,
                "projection_version": "\(payload.projectionVersion)",
                "goal_count": "\(payload.goals.count)"
            ]
        )

        try await modify(recordsToSave: [rootRecord] + goalRecords, recordIDsToDelete: recordIDsToDelete, in: database)
    }

    func prepareShare(for request: FamilyShareCloudSharingPreparationRequest) async throws -> (share: CKShare, container: CKContainer) {
        guard rollout.isEnabled() else {
            throw FamilyShareCloudKitError.rolloutDisabled
        }

        telemetry.track(.sharePrepareStarted, payload: ["namespace": request.namespaceID.namespaceKey])

        let database = container.privateCloudDatabase
        try await ensureZoneExists(for: request.namespaceID, in: database)
        let rootID = Self.rootRecordID(for: request.namespaceID)
        let rootRecord = try await fetchRecord(recordID: rootID, in: database)

        if let shareRecordName = rootRecord[Field.shareRecordName] as? String {
            let shareID = CKRecord.ID(recordName: shareRecordName)
            if let existingShare = try? await fetchRecord(recordID: shareID, in: database) as? CKShare {
                telemetry.track(.sharePrepared, payload: ["namespace": request.namespaceID.namespaceKey, "mode": "existing"])
                return (existingShare, container)
            }
        }

        let shareRecordID = Self.shareRecordID(for: request.namespaceID)
        let share = CKShare(rootRecord: rootRecord, shareID: shareRecordID)
        share[CKShare.SystemFieldKey.title] = request.shareTitle as CKRecordValue
        rootRecord[Field.shareRecordName] = share.recordID.recordName as CKRecordValue

        try await modify(recordsToSave: [rootRecord, share], recordIDsToDelete: [], in: database)
        telemetry.track(.sharePrepared, payload: ["namespace": request.namespaceID.namespaceKey, "mode": "new"])
        return (share, container)
    }

    func fetchAcceptedProjection(from snapshot: FamilyShareInvitationMetadataSnapshot) async throws -> FamilyShareSeededNamespaceState {
        guard rollout.isEnabled() else {
            throw FamilyShareCloudKitError.rolloutDisabled
        }
        let rootRecordID = Self.recordID(
            recordName: snapshot.rootRecordName ?? snapshot.hierarchicalRootRecordName ?? "",
            zoneName: snapshot.rootZoneName ?? snapshot.hierarchicalRootZoneName,
            zoneOwnerName: snapshot.rootZoneOwnerName ?? snapshot.hierarchicalRootZoneOwnerName
        )
        guard rootRecordID.recordName.isEmpty == false else {
            throw FamilyShareCloudKitError.rootRecordMissing
        }
        let rootRecord = try await fetchRecord(recordID: rootRecordID, in: container.sharedCloudDatabase)
        return try await seededState(from: rootRecord, in: container.sharedCloudDatabase)
    }

    func refreshProjection(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareSeededNamespaceState {
        guard rollout.isEnabled() else {
            throw FamilyShareCloudKitError.rolloutDisabled
        }
        let rootRecord = try await fetchRecord(recordID: Self.rootRecordID(for: namespaceID), in: container.sharedCloudDatabase)
        return try await seededState(from: rootRecord, in: container.sharedCloudDatabase)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
        guard rollout.isEnabled() else {
            throw FamilyShareCloudKitError.rolloutDisabled
        }
        guard environment.isTestRun == false else { return }

        let database = container.privateCloudDatabase
        let rootID = Self.rootRecordID(for: namespaceID)
        var recordIDsToDelete: [CKRecord.ID] = [rootID]
        let goalIDs = try await existingGoalRecordIDs(namespaceID: namespaceID, in: database)
        recordIDsToDelete.append(contentsOf: goalIDs)

        if let rootRecord = try? await fetchRecord(recordID: rootID, in: database),
           let shareRecordName = rootRecord[Field.shareRecordName] as? String {
            recordIDsToDelete.append(CKRecord.ID(recordName: shareRecordName))
        }

        try await modify(recordsToSave: [], recordIDsToDelete: recordIDsToDelete, in: database)
        telemetry.track(.revoked, payload: ["namespace": namespaceID.namespaceKey])
    }

    private func seededState(from rootRecord: CKRecord, in database: CKDatabase) async throws -> FamilyShareSeededNamespaceState {
        let namespaceID = try namespaceID(from: rootRecord)
        let goals = try await fetchGoalRecords(namespaceID: namespaceID, in: database)
        let payload = try projectionPayload(from: rootRecord, goals: goals, namespaceID: namespaceID)
        let lifecycleState = FamilyShareLifecycleState(rawValue: payload.freshnessStateRawValue) ?? .active
        let ownerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: FamilyShareOwnerLifecycleState(rawValue: payload.lifecycleStateRawValue) ?? .sharedActive,
            participantCount: payload.participantCount,
            pendingParticipantCount: payload.pendingParticipantCount,
            activeParticipantCount: max(0, payload.participantCount - payload.pendingParticipantCount - payload.revokedParticipantCount),
            revokedParticipantCount: payload.revokedParticipantCount,
            failedParticipantCount: lifecycleState == .temporarilyUnavailable ? 1 : 0,
            summaryCopy: payload.summaryCopy,
            primaryActionCopy: payload.lifecycleStateRawValue == FamilyShareOwnerLifecycleState.notShared.rawValue ? "Share with Family" : "Manage Participants"
        )
        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: payload.ownerDisplayName,
            lifecycleState: lifecycleState,
            goalCount: payload.goals.count,
            lastUpdatedAt: payload.lastReconciledAt ?? payload.publishedAt,
            asOfCopy: payload.publishedAt.map { "As of \($0.formatted(date: .abbreviated, time: .shortened))" },
            titleCopy: payload.summaryTitle,
            messageCopy: payload.summaryCopy,
            primaryActionCopy: FamilyShareSurfaceState(rawValue: lifecycleState.rawValue)?.primaryActionTitle ?? "Retry",
            isReadOnly: true
        )
        return FamilyShareSeededNamespaceState(
            ownerDisplayName: payload.ownerDisplayName,
            ownerState: ownerState,
            inviteeState: inviteeState,
            projectionPayload: payload
        )
    }

    private func projectionPayload(
        from rootRecord: CKRecord,
        goals: [CKRecord],
        namespaceID: FamilyShareNamespaceID
    ) throws -> FamilyShareProjectionPayload {
        let ownerDisplayName = rootRecord[Field.ownerDisplayName] as? String ?? "Shared Family"
        let goalPayloads = try goals.map { record in
            FamilyShareProjectedGoalPayload(
                id: record.recordID.recordName,
                namespaceID: namespaceID,
                ownerID: rootRecord[Field.ownerID] as? String ?? namespaceID.ownerID,
                ownerDisplayName: ownerDisplayName,
                goalID: try stringField(Field.goalID, record: record),
                goalName: try stringField(Field.goalName, record: record),
                goalEmoji: record[Field.goalEmoji] as? String,
                currency: try stringField(Field.currency, record: record),
                targetAmount: try decimalField(Field.targetAmount, record: record),
                currentAmount: try decimalField(Field.currentAmount, record: record),
                progressRatio: record[Field.progressRatio] as? Double ?? 0,
                deadline: try dateField(Field.deadline, record: record),
                goalStatusRawValue: try stringField(Field.goalStatus, record: record),
                forecastStateRawValue: record[Field.forecastState] as? String,
                freshnessStateRawValue: try stringField(Field.freshnessState, record: record),
                lastUpdatedAt: record[Field.lastUpdatedAt] as? Date,
                summaryCopy: record[Field.summaryCopyGoal] as? String ?? "",
                sortIndex: Int(record[Field.sortIndex] as? Int64 ?? 0)
            )
        }
        .sorted(by: { $0.sortIndex < $1.sortIndex })

        return FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            schemaVersion: Int(rootRecord[Field.schemaVersion] as? Int64 ?? 1),
            projectionVersion: Int(rootRecord[Field.projectionVersion] as? Int64 ?? 1),
            activeProjectionVersion: Int(rootRecord[Field.activeProjectionVersion] as? Int64 ?? 1),
            freshnessStateRawValue: rootRecord[Field.freshnessState] as? String ?? FamilyShareLifecycleState.active.rawValue,
            lifecycleStateRawValue: rootRecord[Field.lifecycleState] as? String ?? FamilyShareOwnerLifecycleState.sharedActive.rawValue,
            publishedAt: rootRecord[Field.publishedAt] as? Date,
            lastReconciledAt: rootRecord[Field.lastReconciledAt] as? Date,
            lastRefreshAttemptAt: rootRecord[Field.lastRefreshAttemptAt] as? Date,
            lastRefreshErrorCode: rootRecord[Field.lastRefreshErrorCode] as? String,
            lastRefreshErrorMessage: rootRecord[Field.lastRefreshErrorMessage] as? String,
            summaryTitle: rootRecord[Field.summaryTitle] as? String ?? "Shared Goals",
            summaryCopy: rootRecord[Field.summaryCopy] as? String ?? "Shared goals are read-only.",
            participantCount: Int(rootRecord[Field.participantCount] as? Int64 ?? 0),
            pendingParticipantCount: Int(rootRecord[Field.pendingParticipantCount] as? Int64 ?? 0),
            revokedParticipantCount: Int(rootRecord[Field.revokedParticipantCount] as? Int64 ?? 0),
            goals: goalPayloads,
            ownerSections: [
                FamilyShareOwnerSectionPayload(
                    id: "\(namespaceID.namespaceKey)|owner-section",
                    namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: ownerDisplayName,
                    goalCount: goalPayloads.count,
                    freshnessStateRawValue: rootRecord[Field.freshnessState] as? String ?? FamilyShareLifecycleState.active.rawValue,
                    sortIndex: 0,
                    inlineChipCopy: "Shared by \(ownerDisplayName)"
                )
            ]
        )
    }

    private func namespaceID(from rootRecord: CKRecord) throws -> FamilyShareNamespaceID {
        guard let ownerID = rootRecord[Field.ownerID] as? String,
              let shareID = rootRecord[Field.shareID] as? String else {
            throw FamilyShareCloudKitError.malformedProjection
        }
        return FamilyShareNamespaceID(ownerID: ownerID, shareID: shareID)
    }

    private func existingGoalRecordIDs(namespaceID: FamilyShareNamespaceID, in database: CKDatabase) async throws -> Set<CKRecord.ID> {
        let query = CKQuery(recordType: RecordType.goal, predicate: NSPredicate(format: "%K == %@", Field.namespaceKey, namespaceID.namespaceKey))
        let results: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (results, _) = try await database.records(matching: query)
        } catch {
            guard Self.isMissingRecordTypeError(error) else {
                throw error
            }
            AppLog.warning(
                "Family sharing bootstrap treated missing goal projection schema as empty result for namespace \(namespaceID.namespaceKey)",
                category: .ui
            )
            return []
        }
        return Set(results.compactMap { key, result in
            switch result {
            case .success:
                return key
            case .failure:
                return nil
            }
        })
    }

    private func fetchGoalRecords(namespaceID: FamilyShareNamespaceID, in database: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: RecordType.goal, predicate: NSPredicate(format: "%K == %@", Field.namespaceKey, namespaceID.namespaceKey))
        let results: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (results, _) = try await database.records(matching: query)
        } catch {
            guard Self.isMissingRecordTypeError(error) else {
                throw error
            }
            AppLog.warning(
                "Family sharing read treated missing goal projection schema as empty result for namespace \(namespaceID.namespaceKey)",
                category: .ui
            )
            return []
        }
        return results.compactMap { _, result in
            switch result {
            case let .success(record):
                return record
            case .failure:
                return nil
            }
        }
    }

    private func rootRecord(for payload: FamilyShareProjectionPayload) -> CKRecord {
        let record = CKRecord(recordType: RecordType.root, recordID: Self.rootRecordID(for: payload.namespaceID))
        record[Field.namespaceKey] = payload.namespaceID.namespaceKey as CKRecordValue
        record[Field.ownerID] = payload.namespaceID.ownerID as CKRecordValue
        record[Field.shareID] = payload.namespaceID.shareID as CKRecordValue
        record[Field.ownerDisplayName] = payload.ownerDisplayName as CKRecordValue
        record[Field.schemaVersion] = Int64(payload.schemaVersion) as CKRecordValue
        record[Field.projectionVersion] = Int64(payload.projectionVersion) as CKRecordValue
        record[Field.activeProjectionVersion] = Int64(payload.activeProjectionVersion) as CKRecordValue
        record[Field.freshnessState] = payload.freshnessStateRawValue as CKRecordValue
        record[Field.lifecycleState] = payload.lifecycleStateRawValue as CKRecordValue
        record[Field.publishedAt] = payload.publishedAt as CKRecordValue?
        record[Field.lastReconciledAt] = payload.lastReconciledAt as CKRecordValue?
        record[Field.lastRefreshAttemptAt] = payload.lastRefreshAttemptAt as CKRecordValue?
        record[Field.lastRefreshErrorCode] = payload.lastRefreshErrorCode as CKRecordValue?
        record[Field.lastRefreshErrorMessage] = payload.lastRefreshErrorMessage as CKRecordValue?
        record[Field.summaryTitle] = payload.summaryTitle as CKRecordValue
        record[Field.summaryCopy] = payload.summaryCopy as CKRecordValue
        record[Field.participantCount] = Int64(payload.participantCount) as CKRecordValue
        record[Field.pendingParticipantCount] = Int64(payload.pendingParticipantCount) as CKRecordValue
        record[Field.revokedParticipantCount] = Int64(payload.revokedParticipantCount) as CKRecordValue
        return record
    }

    private func goalRecord(for payload: FamilyShareProjectedGoalPayload, rootRecordID: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: RecordType.goal, recordID: Self.goalRecordID(for: payload.namespaceID, goalID: payload.goalID))
        record[Field.rootReference] = CKRecord.Reference(recordID: rootRecordID, action: .none)
        record[Field.namespaceKey] = payload.namespaceID.namespaceKey as CKRecordValue
        record[Field.ownerID] = payload.ownerID as CKRecordValue
        record[Field.shareID] = payload.namespaceID.shareID as CKRecordValue
        record[Field.ownerDisplayName] = payload.ownerDisplayName as CKRecordValue
        record[Field.goalID] = payload.goalID as CKRecordValue
        record[Field.goalName] = payload.goalName as CKRecordValue
        record[Field.goalEmoji] = payload.goalEmoji as CKRecordValue?
        record[Field.currency] = payload.currency as CKRecordValue
        record[Field.targetAmount] = payload.targetAmount.description as CKRecordValue
        record[Field.currentAmount] = payload.currentAmount.description as CKRecordValue
        record[Field.progressRatio] = payload.progressRatio as CKRecordValue
        record[Field.deadline] = payload.deadline as CKRecordValue
        record[Field.goalStatus] = payload.goalStatusRawValue as CKRecordValue
        record[Field.forecastState] = payload.forecastStateRawValue as CKRecordValue?
        record[Field.freshnessState] = payload.freshnessStateRawValue as CKRecordValue
        record[Field.lastUpdatedAt] = payload.lastUpdatedAt as CKRecordValue?
        record[Field.summaryCopyGoal] = payload.summaryCopy as CKRecordValue
        record[Field.sortIndex] = Int64(payload.sortIndex) as CKRecordValue
        return record
    }

    private func modify(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID], in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
            operation.savePolicy = .changedKeys
            operation.isAtomic = true
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func ensureZoneExists(for namespaceID: FamilyShareNamespaceID, in database: CKDatabase) async throws {
        let zone = CKRecordZone(zoneID: Self.zoneID(for: namespaceID))
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: [])
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func fetchRecord(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [recordID])
            var fetchedRecord: CKRecord?
            operation.perRecordResultBlock = { _, result in
                if case let .success(record) = result {
                    fetchedRecord = record
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let fetchedRecord {
                        continuation.resume(returning: fetchedRecord)
                    } else {
                        continuation.resume(throwing: FamilyShareCloudKitError.rootRecordMissing)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func stringField(_ key: String, record: CKRecord) throws -> String {
        guard let value = record[key] as? String else {
            throw FamilyShareCloudKitError.malformedProjection
        }
        return value
    }

    private func decimalField(_ key: String, record: CKRecord) throws -> Decimal {
        guard let raw = record[key] as? String, let decimal = Decimal(string: raw) else {
            throw FamilyShareCloudKitError.malformedProjection
        }
        return decimal
    }

    private func dateField(_ key: String, record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw FamilyShareCloudKitError.malformedProjection
        }
        return value
    }

    private static func zoneID(for namespaceID: FamilyShareNamespaceID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "family-share.\(namespaceID.ownerID).\(namespaceID.shareID).zone",
            ownerName: CKCurrentUserDefaultName
        )
    }

    private static func recordID(recordName: String, zoneName: String?, zoneOwnerName: String?) -> CKRecord.ID {
        guard let zoneName, zoneName.isEmpty == false else {
            return CKRecord.ID(recordName: recordName)
        }
        let ownerName = (zoneOwnerName?.isEmpty == false ? zoneOwnerName : nil) ?? CKCurrentUserDefaultName
        return CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }

    private static func rootRecordID(for namespaceID: FamilyShareNamespaceID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "family-share.\(namespaceID.ownerID).\(namespaceID.shareID).root",
            zoneID: zoneID(for: namespaceID)
        )
    }

    private static func shareRecordID(for namespaceID: FamilyShareNamespaceID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "family-share.\(namespaceID.ownerID).\(namespaceID.shareID).share",
            zoneID: zoneID(for: namespaceID)
        )
    }

    private static func goalRecordID(for namespaceID: FamilyShareNamespaceID, goalID: String) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "family-share.\(namespaceID.ownerID).\(namespaceID.shareID).goal.\(goalID)",
            zoneID: zoneID(for: namespaceID)
        )
    }

    static func isMissingRecordTypeError(_ error: Error) -> Bool {
        if let ckError = error as? CKError, ckError.code == .unknownItem {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code),
           code == .unknownItem {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        return description.contains("did not find record type")
            || description.contains("unknown record type")
    }
}
#endif
