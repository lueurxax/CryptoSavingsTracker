import Foundation

enum BridgeCanonicalValue {
    case object([(String, BridgeCanonicalValue)])
    case array([BridgeCanonicalValue])
    case string(String)
    case integer(Int64)
    case bool(Bool)
    case null

    func render(into output: inout String) {
        switch self {
        case let .object(pairs):
            output.append("{")
            for (index, pair) in pairs.enumerated() {
                if index > 0 { output.append(",") }
                output.append(bridgeCanonicalEscapedString(pair.0))
                output.append(":")
                pair.1.render(into: &output)
            }
            output.append("}")
        case let .array(values):
            output.append("[")
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(",") }
                value.render(into: &output)
            }
            output.append("]")
        case let .string(value):
            output.append(bridgeCanonicalEscapedString(value))
        case let .integer(value):
            output.append(String(value))
        case let .bool(value):
            output.append(value ? "true" : "false")
        case .null:
            output.append("null")
        }
    }

    var data: Data {
        var output = ""
        render(into: &output)
        return Data(output.utf8)
    }
}

private func bridgeCanonicalObject(_ pairs: [(String, BridgeCanonicalValue)]) -> BridgeCanonicalValue {
    .object(pairs.sorted { lhs, rhs in lhs.0 < rhs.0 })
}

private func bridgeCanonicalEscapedString(_ string: String) -> String {
    let escaped = string.unicodeScalars.reduce(into: "") { result, scalar in
        switch scalar.value {
        case 0x22:
            result.append("\\\"")
        case 0x5C:
            result.append("\\\\")
        case 0x08:
            result.append("\\b")
        case 0x0C:
            result.append("\\f")
        case 0x0A:
            result.append("\\n")
        case 0x0D:
            result.append("\\r")
        case 0x09:
            result.append("\\t")
        case 0x00 ... 0x1F:
            result.append(String(format: "\\u%04X", scalar.value))
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    return "\"\(escaped)\""
}

private func bridgeCanonicalMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000.0).rounded())
}

private func bridgeCanonicalDecimalString(_ value: Double) -> String {
    if value == 0 { return "0" }
    let decimal = Decimal(value)
    var normalized = decimal
    var rendered = NSDecimalString(&normalized, Locale(identifier: "en_US_POSIX"))
    if rendered == "-0" {
        return "0"
    }
    if rendered.contains(".") {
        while rendered.last == "0" {
            rendered.removeLast()
        }
        if rendered.last == "." {
            rendered.removeLast()
        }
    }
    return rendered
}

private func bridgeCanonicalUUID(_ uuid: UUID) -> String {
    uuid.uuidString.lowercased()
}

private func bridgeCanonicalNullableString(_ value: String?) -> BridgeCanonicalValue {
    value.map(BridgeCanonicalValue.string) ?? .null
}

private func bridgeCanonicalNullableUUID(_ value: UUID?) -> BridgeCanonicalValue {
    value.map { .string(bridgeCanonicalUUID($0)) } ?? .null
}

private func bridgeCanonicalNullableDate(_ value: Date?) -> BridgeCanonicalValue {
    value.map { .integer(bridgeCanonicalMilliseconds($0)) } ?? .null
}

private func bridgeCanonicalNullableDecimal(_ value: Double?) -> BridgeCanonicalValue {
    value.map { .string(bridgeCanonicalDecimalString($0)) } ?? .null
}

private func bridgeCanonicalEntityCounts(_ counts: [BridgeEntityCount]) -> BridgeCanonicalValue {
    .array(counts.map { count in
        .object([
            ("count", .integer(Int64(count.count))),
            ("name", .string(count.name))
        ])
    })
}

private func bridgeCanonicalExchangeRates(_ rates: [String: Double]) -> BridgeCanonicalValue {
    .object(rates.keys.sorted().map { key in
        (key, .string(bridgeCanonicalDecimalString(rates[key] ?? 0)))
    })
}

private func bridgeCanonicalGoalSnapshots(_ goalSnapshots: [ExecutionGoalSnapshot]) -> BridgeCanonicalValue {
    .array(goalSnapshots.sorted { $0.goalId.uuidString < $1.goalId.uuidString }.map { snapshot in
        .object([
            ("currency", .string(snapshot.currency.uppercased())),
            ("goalId", .string(bridgeCanonicalUUID(snapshot.goalId))),
            ("goalName", .string(snapshot.goalName)),
            ("isProtected", .bool(snapshot.isProtected)),
            ("isSkipped", .bool(snapshot.isSkipped)),
            ("plannedAmount", .string(bridgeCanonicalDecimalString(snapshot.plannedAmount)))
        ])
    })
}

private func bridgeCanonicalContributionSnapshots(_ snapshots: [CompletedExecutionContributionSnapshot]) -> BridgeCanonicalValue {
    .array(snapshots.sorted {
        if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
        if $0.goalId != $1.goalId { return $0.goalId.uuidString < $1.goalId.uuidString }
        return $0.assetId.uuidString < $1.assetId.uuidString
    }.map { snapshot in
        .object([
            ("amountInGoalCurrency", .string(bridgeCanonicalDecimalString(snapshot.amountInGoalCurrency))),
            ("assetId", .string(bridgeCanonicalUUID(snapshot.assetId))),
            ("assetAmount", .string(bridgeCanonicalDecimalString(snapshot.assetAmount))),
            ("assetCurrency", .string(snapshot.assetCurrency.uppercased())),
            ("exchangeRateUsed", .string(bridgeCanonicalDecimalString(snapshot.exchangeRateUsed))),
            ("goalId", .string(bridgeCanonicalUUID(snapshot.goalId))),
            ("goalCurrency", .string(snapshot.goalCurrency.uppercased())),
            ("source", .string(snapshot.source.rawValue)),
            ("timestamp", .integer(bridgeCanonicalMilliseconds(snapshot.timestamp)))
        ])
    })
}

extension SnapshotManifest {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("appModelSchemaVersion", .string(appModelSchemaVersion)),
            ("baseDatasetFingerprint", .string(baseDatasetFingerprint)),
            ("canonicalEncodingVersion", .string(canonicalEncodingVersion)),
            ("entityCounts", bridgeCanonicalEntityCounts(entityCounts)),
            ("exportedAt", .integer(bridgeCanonicalMilliseconds(exportedAt))),
            ("snapshotID", .string(bridgeCanonicalUUID(snapshotID))),
            ("snapshotSchemaVersion", .integer(Int64(snapshotSchemaVersion)))
        ])
    }
}

extension BridgeGoalSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("currency", .string(currency)),
            ("deadline", .integer(bridgeCanonicalMilliseconds(deadline))),
            ("emoji", bridgeCanonicalNullableString(emoji)),
            ("goalDescription", bridgeCanonicalNullableString(goalDescription)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("lifecycleStatusRawValue", .string(lifecycleStatusRawValue)),
            ("link", bridgeCanonicalNullableString(link)),
            ("name", .string(name)),
            ("recordState", .string(recordState.rawValue)),
            ("startDate", .integer(bridgeCanonicalMilliseconds(startDate))),
            ("targetAmount", .string(bridgeCanonicalDecimalString(targetAmount)))
        ])
    }
}

extension BridgeAssetSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("address", bridgeCanonicalNullableString(address?.lowercased())),
            ("chainId", bridgeCanonicalNullableString(chainId?.lowercased())),
            ("currency", .string(currency.uppercased())),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("recordState", .string(recordState.rawValue))
        ])
    }
}

extension BridgeTransactionSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("amount", .string(bridgeCanonicalDecimalString(amount))),
            ("assetId", bridgeCanonicalNullableUUID(assetId)),
            ("comment", bridgeCanonicalNullableString(comment)),
            ("counterparty", bridgeCanonicalNullableString(counterparty)),
            ("date", .integer(bridgeCanonicalMilliseconds(date))),
            ("externalId", bridgeCanonicalNullableString(externalId)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("recordState", .string(recordState.rawValue)),
            ("sourceRawValue", .string(sourceRawValue))
        ])
    }
}

extension BridgeAssetAllocationSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("amount", .string(bridgeCanonicalDecimalString(amount))),
            ("assetId", bridgeCanonicalNullableUUID(assetId)),
            ("createdDate", .integer(bridgeCanonicalMilliseconds(createdDate))),
            ("goalId", bridgeCanonicalNullableUUID(goalId)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("lastModifiedDate", .integer(bridgeCanonicalMilliseconds(lastModifiedDate))),
            ("recordState", .string(recordState.rawValue))
        ])
    }
}

extension BridgeAllocationHistorySnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("amount", .string(bridgeCanonicalDecimalString(amount))),
            ("assetId", bridgeCanonicalNullableUUID(assetId)),
            ("createdAt", .integer(bridgeCanonicalMilliseconds(createdAt))),
            ("goalId", bridgeCanonicalNullableUUID(goalId)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("monthLabel", .string(monthLabel)),
            ("recordState", .string(recordState.rawValue)),
            ("timestamp", .integer(bridgeCanonicalMilliseconds(timestamp)))
        ])
    }
}

extension BridgeMonthlyPlanSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("createdDate", .integer(bridgeCanonicalMilliseconds(createdDate))),
            ("currency", .string(currency)),
            ("customAmount", bridgeCanonicalNullableDecimal(customAmount)),
            ("executionRecordId", bridgeCanonicalNullableUUID(executionRecordId)),
            ("flexStateRawValue", .string(flexStateRawValue)),
            ("goalId", .string(bridgeCanonicalUUID(goalId))),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("isProtected", .bool(isProtected)),
            ("isSkipped", .bool(isSkipped)),
            ("lastModifiedDate", .integer(bridgeCanonicalMilliseconds(lastModifiedDate))),
            ("monthLabel", .string(monthLabel)),
            ("monthsRemaining", .integer(Int64(monthsRemaining))),
            ("recordState", .string(recordState.rawValue)),
            ("remainingAmount", .string(bridgeCanonicalDecimalString(remainingAmount))),
            ("requiredMonthly", .string(bridgeCanonicalDecimalString(requiredMonthly))),
            ("stateRawValue", .string(stateRawValue)),
            ("statusRawValue", .string(statusRawValue))
        ])
    }
}

extension BridgeMonthlyExecutionRecordSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("canUndoUntil", bridgeCanonicalNullableDate(canUndoUntil)),
            ("completedAt", bridgeCanonicalNullableDate(completedAt)),
            ("completedExecutionId", bridgeCanonicalNullableUUID(completedExecutionId)),
            ("completionEventIds", .array(completionEventIds.sorted { $0.uuidString < $1.uuidString }.map { .string(bridgeCanonicalUUID($0)) })),
            ("createdAt", .integer(bridgeCanonicalMilliseconds(createdAt))),
            ("goalIds", .array(goalIds.sorted { $0.uuidString < $1.uuidString }.map { .string(bridgeCanonicalUUID($0)) })),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("monthLabel", .string(monthLabel)),
            ("planIds", .array(planIds.sorted { $0.uuidString < $1.uuidString }.map { .string(bridgeCanonicalUUID($0)) })),
            ("recordState", .string(recordState.rawValue)),
            ("snapshotId", bridgeCanonicalNullableUUID(snapshotId)),
            ("startedAt", bridgeCanonicalNullableDate(startedAt)),
            ("statusRawValue", .string(statusRawValue))
        ])
    }
}

extension BridgeCompletedExecutionSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("completedAt", .integer(bridgeCanonicalMilliseconds(completedAt))),
            ("contributionSnapshots", bridgeCanonicalContributionSnapshots(contributionSnapshots)),
            ("exchangeRatesSnapshot", bridgeCanonicalExchangeRates(exchangeRatesSnapshot)),
            ("executionRecordId", .string(bridgeCanonicalUUID(executionRecordId))),
            ("goalSnapshots", bridgeCanonicalGoalSnapshots(goalSnapshots)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("monthLabel", .string(monthLabel)),
            ("recordState", .string(recordState.rawValue))
        ])
    }
}

extension BridgeExecutionSnapshotPayload {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("capturedAt", .integer(bridgeCanonicalMilliseconds(capturedAt))),
            ("executionRecordId", .string(bridgeCanonicalUUID(executionRecordId))),
            ("goalSnapshots", bridgeCanonicalGoalSnapshots(goalSnapshots)),
            ("id", .string(bridgeCanonicalUUID(id))),
            ("recordState", .string(recordState.rawValue)),
            ("totalPlanned", .string(bridgeCanonicalDecimalString(totalPlanned)))
        ])
    }
}

extension BridgeCompletionEventSnapshot {
    fileprivate func bridgeCanonicalValue() -> BridgeCanonicalValue {
        bridgeCanonicalObject([
            ("completedAt", .integer(bridgeCanonicalMilliseconds(completedAt))),
            ("completionSnapshotId", .string(bridgeCanonicalUUID(completionSnapshotId))),
            ("createdAt", .integer(bridgeCanonicalMilliseconds(createdAt))),
            ("eventId", .string(bridgeCanonicalUUID(eventId))),
            ("executionRecordId", .string(bridgeCanonicalUUID(executionRecordId))),
            ("monthLabel", .string(monthLabel)),
            ("recordState", .string(recordState.rawValue)),
            ("sequence", .integer(Int64(sequence))),
            ("sourceDiscriminator", .string(sourceDiscriminator)),
            ("undoneAt", bridgeCanonicalNullableDate(undoneAt)),
            ("undoReason", bridgeCanonicalNullableString(undoReason))
        ])
    }
}

extension SnapshotEnvelope {
    func bridgeAppendixCanonicalData(forFingerprinting: Bool) -> Data {
        let normalized = forFingerprinting ? normalizedForFingerprinting() : normalizedForCanonicalEncoding()
        let value = BridgeCanonicalValue.object([
            ("manifest", normalized.manifest.bridgeCanonicalValue()),
            ("goals", .array(normalized.goals.map { $0.bridgeCanonicalValue() })),
            ("assets", .array(normalized.assets.map { $0.bridgeCanonicalValue() })),
            ("transactions", .array(normalized.transactions.map { $0.bridgeCanonicalValue() })),
            ("assetAllocations", .array(normalized.assetAllocations.map { $0.bridgeCanonicalValue() })),
            ("allocationHistories", .array(normalized.allocationHistories.map { $0.bridgeCanonicalValue() })),
            ("monthlyPlans", .array(normalized.monthlyPlans.map { $0.bridgeCanonicalValue() })),
            ("monthlyExecutionRecords", .array(normalized.monthlyExecutionRecords.map { $0.bridgeCanonicalValue() })),
            ("completedExecutions", .array(normalized.completedExecutions.map { $0.bridgeCanonicalValue() })),
            ("executionSnapshots", .array(normalized.executionSnapshots.map { $0.bridgeCanonicalValue() })),
            ("completionEvents", .array(normalized.completionEvents.map { $0.bridgeCanonicalValue() }))
        ])
        return value.data
    }
}

extension SignedImportPackage {
    func bridgeAppendixCanonicalData(includePackageID: Bool, signatureValue: BridgeCanonicalValue?) -> Data {
        let normalizedEnvelope = snapshotEnvelope.normalizedForCanonicalEncoding()
        var pairs: [(String, BridgeCanonicalValue)] = []
        if includePackageID {
            pairs.append(("packageID", .string(packageID)))
        }
        pairs.append(("snapshotID", .string(bridgeCanonicalUUID(snapshotID))))
        pairs.append(("canonicalEncodingVersion", .string(canonicalEncodingVersion)))
        pairs.append(("baseDatasetFingerprint", .string(baseDatasetFingerprint)))
        pairs.append(("editedDatasetFingerprint", .string(editedDatasetFingerprint)))
        pairs.append(("snapshotEnvelope", .object([
            ("manifest", normalizedEnvelope.manifest.bridgeCanonicalValue()),
            ("goals", .array(normalizedEnvelope.goals.map { $0.bridgeCanonicalValue() })),
            ("assets", .array(normalizedEnvelope.assets.map { $0.bridgeCanonicalValue() })),
            ("transactions", .array(normalizedEnvelope.transactions.map { $0.bridgeCanonicalValue() })),
            ("assetAllocations", .array(normalizedEnvelope.assetAllocations.map { $0.bridgeCanonicalValue() })),
            ("allocationHistories", .array(normalizedEnvelope.allocationHistories.map { $0.bridgeCanonicalValue() })),
            ("monthlyPlans", .array(normalizedEnvelope.monthlyPlans.map { $0.bridgeCanonicalValue() })),
            ("monthlyExecutionRecords", .array(normalizedEnvelope.monthlyExecutionRecords.map { $0.bridgeCanonicalValue() })),
            ("completedExecutions", .array(normalizedEnvelope.completedExecutions.map { $0.bridgeCanonicalValue() })),
            ("executionSnapshots", .array(normalizedEnvelope.executionSnapshots.map { $0.bridgeCanonicalValue() })),
            ("completionEvents", .array(normalizedEnvelope.completionEvents.map { $0.bridgeCanonicalValue() }))
        ])))
        pairs.append(("signingKeyID", .string(signingKeyID)))
        pairs.append(("signedAt", .integer(bridgeCanonicalMilliseconds(signedAt))))
        if let signatureValue {
            pairs.append(("signature", signatureValue))
        }
        let value = BridgeCanonicalValue.object(pairs)
        return value.data
    }
}

private let bridgeCanonicalDecimalKeys: Set<String> = [
    "targetAmount",
    "amount",
    "amountInGoalCurrency",
    "assetAmount",
    "exchangeRateUsed",
    "requiredMonthly",
    "remainingAmount",
    "customAmount",
    "totalPlanned",
    "plannedAmount"
]

private func bridgeNormalizeCanonicalJSONObject(_ value: Any, parentKey: String? = nil) -> Any {
    if let dictionary = value as? [String: Any] {
        return Dictionary(uniqueKeysWithValues: dictionary.map { key, child in
            (key, bridgeNormalizeCanonicalJSONObject(child, parentKey: key))
        })
    }
    if let array = value as? [Any] {
        return array.map { bridgeNormalizeCanonicalJSONObject($0, parentKey: parentKey) }
    }
    if let string = value as? String, let parentKey, bridgeCanonicalDecimalKeys.contains(parentKey) {
        return NSDecimalNumber(string: string).doubleValue
    }
    return value
}

func bridgeNormalizedCanonicalDecodingData(_ data: Data) throws -> Data {
    let raw = try JSONSerialization.jsonObject(with: data)
    let normalized = bridgeNormalizeCanonicalJSONObject(raw)
    return try JSONSerialization.data(withJSONObject: normalized, options: [])
}
