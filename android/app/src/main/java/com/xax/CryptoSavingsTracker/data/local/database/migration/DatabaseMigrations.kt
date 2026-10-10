package com.xax.CryptoSavingsTracker.data.local.database.migration

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import java.security.MessageDigest

object DatabaseMigrations {
    val MIGRATION_1_2: Migration = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS monthly_goal_plans (
                    id TEXT NOT NULL,
                    goal_id TEXT NOT NULL,
                    month_label TEXT NOT NULL,
                    required_monthly REAL NOT NULL,
                    remaining_amount REAL NOT NULL,
                    months_remaining INTEGER NOT NULL,
                    currency TEXT NOT NULL,
                    status TEXT NOT NULL,
                    state TEXT NOT NULL,
                    custom_amount REAL,
                    is_protected INTEGER NOT NULL,
                    is_skipped INTEGER NOT NULL,
                    created_at_utc_millis INTEGER NOT NULL,
                    last_modified_at_utc_millis INTEGER NOT NULL,
                    PRIMARY KEY(id)
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_monthly_goal_plans_month_label_goal_id ON monthly_goal_plans(month_label, goal_id)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_monthly_goal_plans_month_label ON monthly_goal_plans(month_label)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_monthly_goal_plans_state ON monthly_goal_plans(state)"
            )
        }
    }

    val MIGRATION_2_3: Migration = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Add can_undo_until_utc_millis column to monthly_execution_records for undo grace period
            db.execSQL(
                "ALTER TABLE monthly_execution_records ADD COLUMN can_undo_until_utc_millis INTEGER DEFAULT NULL"
            )
        }
    }

    val MIGRATION_3_4: Migration = object : Migration(3, 4) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE completed_executions ADD COLUMN undone_at_utc_millis INTEGER DEFAULT NULL"
            )
            db.execSQL(
                "ALTER TABLE completed_executions ADD COLUMN undo_reason TEXT DEFAULT NULL"
            )
        }
    }

    val MIGRATION_4_5: Migration = object : Migration(4, 5) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS completion_events (
                    id TEXT NOT NULL,
                    execution_record_id TEXT NOT NULL,
                    month_label TEXT NOT NULL,
                    sequence INTEGER NOT NULL,
                    source_discriminator TEXT NOT NULL,
                    completed_at_utc_millis INTEGER NOT NULL,
                    completion_snapshot_ref TEXT,
                    created_at_utc_millis INTEGER NOT NULL,
                    undone_at_utc_millis INTEGER,
                    undo_reason TEXT,
                    PRIMARY KEY(id),
                    FOREIGN KEY(execution_record_id) REFERENCES monthly_execution_records(id) ON DELETE CASCADE
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_completion_events_execution_record_id ON completion_events(execution_record_id)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_completion_events_month_label ON completion_events(month_label)"
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_completion_events_execution_record_id_sequence ON completion_events(execution_record_id, sequence)"
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_completion_events_execution_record_id_source_discriminator ON completion_events(execution_record_id, source_discriminator)"
            )

            db.execSQL("ALTER TABLE completed_executions ADD COLUMN completion_event_id TEXT")
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_completed_executions_completion_event_id ON completed_executions(completion_event_id)"
            )

            backfillCompletionEvents(db)
        }
    }

    val MIGRATION_5_6: Migration = object : Migration(5, 6) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE monthly_execution_records ADD COLUMN legacy_rate_snapshot_pending INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL(
                """
                UPDATE monthly_execution_records
                SET legacy_rate_snapshot_pending = 1
                WHERE status = 'executing'
                   OR (
                       status = 'closed'
                       AND can_undo_until_utc_millis >
                           CAST(strftime('%s', 'now') AS INTEGER) * 1000
                   )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS execution_asset_rates (
                    execution_record_id TEXT NOT NULL,
                    asset_id TEXT NOT NULL,
                    snapshot_currency TEXT NOT NULL,
                    rate REAL NOT NULL,
                    captured_at_utc_millis INTEGER NOT NULL,
                    PRIMARY KEY(execution_record_id, asset_id, snapshot_currency),
                    FOREIGN KEY(execution_record_id) REFERENCES monthly_execution_records(id) ON UPDATE NO ACTION ON DELETE CASCADE
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS index_execution_asset_rates_execution_record_id " +
                    "ON execution_asset_rates(execution_record_id)"
            )
        }
    }

    val MIGRATION_6_7: Migration = object : Migration(6, 7) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("DROP INDEX IF EXISTS index_assets_address")
            normalizeAndReconcileAssetIdentities(db)
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS index_assets_address_chain_id_currency " +
                    "ON assets(address, chain_id, currency)"
            )
        }
    }

    private data class MigratingAsset(
        val id: String,
        val currency: String,
        val address: String?,
        val chainId: String?,
        val createdAtUtcMillis: Long
    )

    private data class AssetIdentity(
        val address: String,
        val chainId: String,
        val currency: String
    )

    private data class MigratingAllocation(
        val id: String,
        val goalId: String,
        val amount: Double,
        val createdAtUtcMillis: Long,
        val lastModifiedAtUtcMillis: Long
    )

    private data class MigratingRate(
        val executionRecordId: String,
        val snapshotCurrency: String,
        val rate: Double,
        val capturedAtUtcMillis: Long
    )

    private data class RateEvidenceKey(
        val executionRecordId: String,
        val snapshotCurrency: String
    )

    private data class RateEvidence(
        val rateBits: Long,
        val capturedAtUtcMillis: Long
    )

    private data class MigratingTransaction(
        val id: String,
        val assetId: String,
        val amount: Double,
        val dateUtcMillis: Long,
        val source: String,
        val externalId: String?,
        val counterparty: String?,
        val comment: String?,
        val createdAtUtcMillis: Long
    )

    private data class UtxoTransactionReconciliation(
        val transaction: MigratingTransaction,
        val canonicalExternalId: String
    )

    private data class MigratingUtxoIdentity(
        val transaction: MigratingTransaction,
        val canonicalHash: String,
        val aliases: Set<String>,
        val hasDurableAliasMetadata: Boolean
    ) {
        val providerHashes: Set<String>
            get() = aliases + canonicalHash
    }

    private fun normalizeAndReconcileAssetIdentities(db: SupportSQLiteDatabase) {
        val legacyAssets = buildList {
            db.query(
                """
                SELECT id, currency, address, chain_id, created_at_utc_millis
                FROM assets
                ORDER BY created_at_utc_millis ASC, id ASC
                """.trimIndent()
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    add(
                        MigratingAsset(
                            id = cursor.getString(0),
                            currency = cursor.getString(1),
                            address = cursor.getString(2),
                            chainId = cursor.getString(3),
                            createdAtUtcMillis = cursor.getLong(4)
                        )
                    )
                }
            }
        }

        val canonicalAssets = legacyAssets.map { asset ->
            val canonical = AssetIdentityV7Normalizer.canonicalize(
                currency = asset.currency,
                address = asset.address,
                chainId = asset.chainId
            )

            asset.copy(
                currency = canonical.currency,
                address = canonical.address,
                chainId = if (
                    canonical.hasMalformedAddress &&
                    canonical.chainId != null
                ) {
                    malformedAddressQuarantineChainId(
                        canonicalChainId = canonical.chainId,
                        assetId = asset.id
                    )
                } else {
                    canonical.chainId
                }
            )
        }

        val addressedGroups = canonicalAssets
            .filter { asset -> asset.address != null && asset.chainId != null }
            .groupBy { asset ->
                AssetIdentity(
                    address = requireNotNull(asset.address),
                    chainId = requireNotNull(asset.chainId),
                    currency = asset.currency
                )
            }
            .values

        val rateConflictingAddressedGroups = addressedGroups
            .filter { matchingAssets ->
                matchingAssets.size > 1 &&
                    hasConflictingExecutionRateEvidence(
                        db = db,
                        assetIds = matchingAssets.map { it.id }
                    )
            }
        val rateConflictingAssetIds = rateConflictingAddressedGroups
            .flatten()
            .mapTo(mutableSetOf()) { it.id }
        val allocationConflictingAddressedGroups = addressedGroups
            .filter { matchingAssets ->
                matchingAssets.size > 1 &&
                    matchingAssets.none { asset -> asset.id in rateConflictingAssetIds } &&
                    hasNonFiniteAllocationMerge(
                        db = db,
                        assetIds = matchingAssets.map { it.id }
                    )
            }
        val allocationConflictingAssetIds = allocationConflictingAddressedGroups
            .flatten()
            .mapTo(mutableSetOf()) { it.id }
        val utxoConflictingAddressedGroups = addressedGroups
            .filter { matchingAssets ->
                matchingAssets.size > 1 &&
                    matchingAssets.none { asset -> asset.id in rateConflictingAssetIds } &&
                    matchingAssets.none { asset -> asset.id in allocationConflictingAssetIds } &&
                    !canReconcileUtxoTransactions(
                        db = db,
                        assetIds = matchingAssets.map { it.id },
                        survivorAssetId = matchingAssets
                            .minWith(
                                compareBy<MigratingAsset> { it.createdAtUtcMillis }
                                    .thenBy { it.id }
                            )
                            .id
                    )
            }
        val utxoConflictingAssetIds = utxoConflictingAddressedGroups
            .flatten()
            .mapTo(mutableSetOf()) { it.id }
        val conflictingAddressedGroups =
            rateConflictingAddressedGroups +
                allocationConflictingAddressedGroups +
                utxoConflictingAddressedGroups
        val conflictingAssetIds = conflictingAddressedGroups
            .flatten()
            .mapTo(mutableSetOf()) { it.id }

        canonicalAssets
            .filterNot { asset -> asset.id in conflictingAssetIds }
            .forEach { asset ->
                updateAssetIdentity(db, asset)
            }

        conflictingAddressedGroups.forEach { matchingAssets ->
            val ordered = matchingAssets.sortedWith(
                compareBy<MigratingAsset> { it.createdAtUtcMillis }
                    .thenBy { it.id }
            )
            val canonicalReservation = ordered.first()
            updateAssetIdentity(db, canonicalReservation)
            ordered.drop(1).forEach { quarantined ->
                val quarantineChainId = if (quarantined.id in rateConflictingAssetIds) {
                    rateConflictQuarantineChainId(
                        canonicalChainId = checkNotNull(quarantined.chainId),
                        assetId = quarantined.id
                    )
                } else if (quarantined.id in allocationConflictingAssetIds) {
                    allocationConflictQuarantineChainId(
                        canonicalChainId = checkNotNull(quarantined.chainId),
                        assetId = quarantined.id
                    )
                } else {
                    utxoConflictQuarantineChainId(
                        canonicalChainId = checkNotNull(quarantined.chainId),
                        assetId = quarantined.id
                    )
                }
                updateAssetIdentity(
                    db = db,
                    asset = quarantined.copy(
                        chainId = quarantineChainId
                    )
                )
            }
        }

        addressedGroups
            .filter { matchingAssets ->
                matchingAssets.none { asset -> asset.id in conflictingAssetIds }
            }
            .forEach { matchingAssets ->
                val ordered = matchingAssets.sortedWith(
                    compareBy<MigratingAsset> { it.createdAtUtcMillis }
                    .thenBy { it.id }
                )
                val survivor = ordered.first()
                if (ordered.size > 1) {
                    reconcileUtxoTransactions(
                        db = db,
                        assetIds = ordered.map { it.id },
                        survivorAssetId = survivor.id
                    )
                }
                ordered.drop(1).forEach { duplicate ->
                    mergeAssetInto(db, duplicate.id, survivor.id)
                }
            }
    }

    private fun updateAssetIdentity(
        db: SupportSQLiteDatabase,
        asset: MigratingAsset
    ) {
        db.execSQL(
            """
            UPDATE assets
            SET currency = ?, address = ?, chain_id = ?
            WHERE id = ?
            """.trimIndent(),
            arrayOf<Any?>(asset.currency, asset.address, asset.chainId, asset.id)
        )
    }

    private fun rateConflictQuarantineChainId(
        canonicalChainId: String,
        assetId: String
    ): String = "legacy-rate-conflict:$canonicalChainId:$assetId"

    private fun allocationConflictQuarantineChainId(
        canonicalChainId: String,
        assetId: String
    ): String = "legacy-allocation-conflict:$canonicalChainId:$assetId"

    private fun malformedAddressQuarantineChainId(
        canonicalChainId: String,
        assetId: String
    ): String = "legacy-malformed-address:$canonicalChainId:$assetId"

    private fun utxoConflictQuarantineChainId(
        canonicalChainId: String,
        assetId: String
    ): String = "legacy-utxo-conflict:$canonicalChainId:$assetId"

    private fun hasConflictingExecutionRateEvidence(
        db: SupportSQLiteDatabase,
        assetIds: List<String>
    ): Boolean {
        val evidenceByKey = mutableMapOf<RateEvidenceKey, RateEvidence>()
        assetIds.forEach { assetId ->
            readExecutionAssetRates(db, assetId).forEach { rate ->
                val key = RateEvidenceKey(
                    executionRecordId = rate.executionRecordId,
                    snapshotCurrency = rate.snapshotCurrency
                )
                val evidence = RateEvidence(
                    rateBits = rate.rate.toBits(),
                    capturedAtUtcMillis = rate.capturedAtUtcMillis
                )
                val existing = evidenceByKey.putIfAbsent(key, evidence)
                if (existing != null && existing != evidence) {
                    return true
                }
            }
        }
        return false
    }

    private fun hasNonFiniteAllocationMerge(
        db: SupportSQLiteDatabase,
        assetIds: List<String>
    ): Boolean {
        val amountByGoalId = mutableMapOf<String, Double>()
        assetIds.forEach { assetId ->
            db.query(
                """
                SELECT goal_id, amount
                FROM asset_allocations
                WHERE asset_id = ?
                ORDER BY id ASC
                """.trimIndent(),
                arrayOf(assetId)
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val goalId = cursor.getString(0)
                    val amount = cursor.getDouble(1)
                    if (!amount.isFinite()) {
                        return true
                    }
                    val existing = amountByGoalId[goalId]
                    if (existing == null) {
                        amountByGoalId[goalId] = amount
                    } else {
                        val merged = existing + amount
                        if (!merged.isFinite()) {
                            return true
                        }
                        amountByGoalId[goalId] = merged
                    }
                }
            }
        }
        return false
    }

    private fun mergeAssetInto(
        db: SupportSQLiteDatabase,
        duplicateAssetId: String,
        survivorAssetId: String
    ) {
        mergeAssetAllocations(db, duplicateAssetId, survivorAssetId)
        mergeExecutionAssetRates(db, duplicateAssetId, survivorAssetId)

        db.execSQL(
            "UPDATE transactions SET asset_id = ? WHERE asset_id = ?",
            arrayOf(survivorAssetId, duplicateAssetId)
        )
        db.execSQL(
            "UPDATE allocation_history SET asset_id = ? WHERE asset_id = ?",
            arrayOf(survivorAssetId, duplicateAssetId)
        )
        db.execSQL(
            "DELETE FROM assets WHERE id = ?",
            arrayOf(duplicateAssetId)
        )
    }

    private fun canReconcileUtxoTransactions(
        db: SupportSQLiteDatabase,
        assetIds: List<String>,
        survivorAssetId: String
    ): Boolean {
        val reconciliations = readUtxoTransactionReconciliations(
            db = db,
            assetIds = assetIds,
            survivorAssetId = survivorAssetId
        ) ?: return false

        return reconciliations
            .groupBy { it.canonicalExternalId }
            .all { (canonicalExternalId, candidates) ->
                val rows = candidates.map { it.transaction }
                rows.map { transaction ->
                    Triple(
                        transaction.amount.toBits(),
                        transaction.dateUtcMillis,
                        normalizedTransactionSource(transaction.source)
                    )
                }.distinct().size == 1 &&
                    compatibleMetadata(rows.map { it.counterparty }) &&
                    compatibleUserComments(rows.map { it.comment }) &&
                    canonicalExternalIdBelongsToAssetGroup(
                        db = db,
                        canonicalExternalId = canonicalExternalId,
                        assetIds = assetIds
                    )
            }
    }

    private fun reconcileUtxoTransactions(
        db: SupportSQLiteDatabase,
        assetIds: List<String>,
        survivorAssetId: String
    ) {
        val reconciliations = checkNotNull(
            readUtxoTransactionReconciliations(
                db = db,
                assetIds = assetIds,
                survivorAssetId = survivorAssetId
            )
        ) {
            "UTXO transaction identity cannot be reconciled safely"
        }

        reconciliations
            .groupBy { it.canonicalExternalId }
            .forEach { (canonicalExternalId, candidates) ->
                val rows = candidates.map { it.transaction }
                check(
                    rows.map { transaction ->
                        Triple(
                            transaction.amount.toBits(),
                            transaction.dateUtcMillis,
                            normalizedTransactionSource(transaction.source)
                        )
                    }.distinct().size == 1 &&
                        compatibleMetadata(rows.map { it.counterparty }) &&
                        compatibleUserComments(rows.map { it.comment })
                ) {
                    "UTXO transaction evidence cannot be reconciled safely"
                }

                val survivor = rows.minWith(
                    compareBy<MigratingTransaction> {
                        if (
                            it.assetId == survivorAssetId &&
                            it.externalId == canonicalExternalId
                        ) {
                            0
                        } else {
                            1
                        }
                    }
                        .thenBy { it.createdAtUtcMillis }
                        .thenBy { it.id }
                )
                rows
                    .filterNot { it.id == survivor.id }
                    .forEach { duplicate ->
                        db.execSQL(
                            "DELETE FROM transactions WHERE id = ?",
                            arrayOf(duplicate.id)
                        )
                    }
                db.execSQL(
                    """
                    UPDATE transactions
                    SET external_id = ?,
                        counterparty = ?,
                        comment = ?,
                        created_at_utc_millis = ?
                    WHERE id = ?
                    """.trimIndent(),
                    arrayOf<Any?>(
                        canonicalExternalId,
                        resolvedMetadata(rows.map { it.counterparty }),
                        resolvedUserComment(rows.map { it.comment }),
                        rows.minOf { it.createdAtUtcMillis },
                        survivor.id
                    )
                )
            }
    }

    private fun readUtxoTransactionReconciliations(
        db: SupportSQLiteDatabase,
        assetIds: List<String>,
        survivorAssetId: String
    ): List<UtxoTransactionReconciliation>? {
        if (assetIds.isEmpty()) return emptyList()
        val placeholders = assetIds.joinToString(separator = ",") { "?" }
        val transactions = buildList {
            db.query(
                """
                SELECT id, asset_id, amount, date_utc_millis, source,
                       external_id, counterparty, comment, created_at_utc_millis
                FROM transactions
                WHERE asset_id IN ($placeholders)
                ORDER BY created_at_utc_millis ASC, id ASC
                """.trimIndent(),
                assetIds.toTypedArray()
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    add(
                        MigratingTransaction(
                            id = cursor.getString(0),
                            assetId = cursor.getString(1),
                            amount = cursor.getDouble(2),
                            dateUtcMillis = cursor.getLong(3),
                            source = cursor.getString(4),
                            externalId = cursor.getString(5),
                            counterparty = cursor.getString(6),
                            comment = cursor.getString(7),
                            createdAtUtcMillis = cursor.getLong(8)
                        )
                    )
                }
            }
        }

        val identities = mutableListOf<MigratingUtxoIdentity>()
        transactions.forEach { transaction ->
            val externalId = transaction.externalId ?: return@forEach
            val looksLikeUtxoIdentity =
                externalId.startsWith(LEGACY_UTXO_EXTERNAL_ID_PREFIX) ||
                    externalId.startsWith(
                        "$UTXO_PROVIDER_RECORD_MARKER$UTXO_PROVIDER_RECORD_SEPARATOR"
                    )
            if (!looksLikeUtxoIdentity) {
                return@forEach
            }
            if (!isOnChainTransactionSource(transaction.source)) {
                return null
            }
            identities += parseMigratingUtxoIdentity(
                transaction = transaction,
                externalId = externalId
            ) ?: return null
        }

        val remaining = identities.toMutableList()
        val reconciliations = mutableListOf<UtxoTransactionReconciliation>()
        while (remaining.isNotEmpty()) {
            val component = mutableListOf(remaining.removeAt(0))
            var providerHashes = component.single().providerHashes
            var addedToComponent: Boolean
            do {
                addedToComponent = false
                val iterator = remaining.iterator()
                while (iterator.hasNext()) {
                    val candidate = iterator.next()
                    if (providerHashes.intersect(candidate.providerHashes).isNotEmpty()) {
                        component += candidate
                        providerHashes = providerHashes + candidate.providerHashes
                        iterator.remove()
                        addedToComponent = true
                    }
                }
            } while (addedToComponent)

            val durableCanonicalHashes = component
                .filter { it.hasDurableAliasMetadata }
                .map { it.canonicalHash }
                .distinct()
            if (durableCanonicalHashes.size > 1) {
                return null
            }
            val canonicalHash = durableCanonicalHashes.singleOrNull()
                ?: component.map { it.canonicalHash }.min()
            val aliases = providerHashes - canonicalHash
            val canonicalExternalId = if (aliases.isEmpty()) {
                "$LEGACY_UTXO_EXTERNAL_ID_PREFIX$survivorAssetId:$canonicalHash"
            } else {
                buildList {
                    add(UTXO_PROVIDER_RECORD_MARKER)
                    add(survivorAssetId)
                    add(canonicalHash)
                    add(UTXO_PROVIDER_ALIAS_MARKER)
                    add(aliases.size.toString())
                    addAll(aliases.sorted())
                }.joinToString(UTXO_PROVIDER_RECORD_SEPARATOR)
            }
            component.forEach { identity ->
                reconciliations += UtxoTransactionReconciliation(
                    transaction = identity.transaction,
                    canonicalExternalId = canonicalExternalId
                )
            }
        }
        return reconciliations
    }

    private fun parseMigratingUtxoIdentity(
        transaction: MigratingTransaction,
        externalId: String
    ): MigratingUtxoIdentity? {
        val scopedPrefix = "$LEGACY_UTXO_EXTERNAL_ID_PREFIX${transaction.assetId}:"
        if (externalId.startsWith(scopedPrefix)) {
            val providerHash = externalId.removePrefix(scopedPrefix).trim().lowercase()
            return providerHash.takeIf(String::isNotBlank)?.let {
                MigratingUtxoIdentity(
                    transaction = transaction,
                    canonicalHash = it,
                    aliases = emptySet(),
                    hasDurableAliasMetadata = false
                )
            }
        }
        if (
            !externalId.startsWith(
                "$UTXO_PROVIDER_RECORD_MARKER$UTXO_PROVIDER_RECORD_SEPARATOR"
            )
        ) {
            return null
        }

        val components = externalId.split(UTXO_PROVIDER_RECORD_SEPARATOR)
        if (
            components.size < 6 ||
            components[0] != UTXO_PROVIDER_RECORD_MARKER ||
            components[1] != transaction.assetId ||
            components[2].isBlank() ||
            components[3] != UTXO_PROVIDER_ALIAS_MARKER
        ) {
            return null
        }
        val aliasCount = components[4].toIntOrNull()
        if (aliasCount == null || aliasCount <= 0 || components.size != 5 + aliasCount) {
            return null
        }
        val canonicalHash = components[2].trim().lowercase()
        val aliases = components.drop(5)
            .mapTo(linkedSetOf()) { it.trim().lowercase() }
        if (
            aliases.size != aliasCount ||
            aliases.any { it.isBlank() || it == canonicalHash }
        ) {
            return null
        }
        return MigratingUtxoIdentity(
            transaction = transaction,
            canonicalHash = canonicalHash,
            aliases = aliases,
            hasDurableAliasMetadata = true
        )
    }

    private fun canonicalExternalIdBelongsToAssetGroup(
        db: SupportSQLiteDatabase,
        canonicalExternalId: String,
        assetIds: List<String>
    ): Boolean {
        return db.query(
            "SELECT asset_id FROM transactions WHERE external_id = ?",
            arrayOf(canonicalExternalId)
        ).use { cursor ->
            !cursor.moveToFirst() || cursor.getString(0) in assetIds
        }
    }

    private fun compatibleMetadata(values: List<String?>): Boolean =
        values.mapNotNull { it?.trim()?.takeIf(String::isNotBlank) }.distinct().size <= 1

    private fun resolvedMetadata(values: List<String?>): String? =
        values.firstNotNullOfOrNull { it?.trim()?.takeIf(String::isNotBlank) }

    private fun compatibleUserComments(values: List<String?>): Boolean =
        values.mapNotNull(::userComment).distinct().size <= 1

    private fun resolvedUserComment(values: List<String?>): String? =
        values.firstNotNullOfOrNull(::userComment)

    private fun userComment(value: String?): String? =
        value
            ?.trim()
            ?.takeIf { it.isNotEmpty() && !it.equals(DEFAULT_ON_CHAIN_COMMENT, ignoreCase = true) }

    private fun isOnChainTransactionSource(source: String): Boolean =
        normalizedTransactionSource(source) == NORMALIZED_ON_CHAIN_TRANSACTION_SOURCE

    private fun normalizedTransactionSource(source: String): String =
        source.filter(Char::isLetterOrDigit).lowercase()

    private const val LEGACY_UTXO_EXTERNAL_ID_PREFIX = "utxo:"
    private const val UTXO_PROVIDER_RECORD_MARKER = "utxo-record-v2"
    private const val UTXO_PROVIDER_ALIAS_MARKER = "aliases-v1"
    private const val UTXO_PROVIDER_RECORD_SEPARATOR = "|"
    private const val NORMALIZED_ON_CHAIN_TRANSACTION_SOURCE = "onchain"
    private const val DEFAULT_ON_CHAIN_COMMENT = "On-chain"

    private fun mergeAssetAllocations(
        db: SupportSQLiteDatabase,
        duplicateAssetId: String,
        survivorAssetId: String
    ) {
        val duplicateAllocations = buildList {
            db.query(
                """
                SELECT id, goal_id, amount, created_at_utc_millis, last_modified_at_utc_millis
                FROM asset_allocations
                WHERE asset_id = ?
                ORDER BY id ASC
                """.trimIndent(),
                arrayOf(duplicateAssetId)
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    add(
                        MigratingAllocation(
                            id = cursor.getString(0),
                            goalId = cursor.getString(1),
                            amount = cursor.getDouble(2),
                            createdAtUtcMillis = cursor.getLong(3),
                            lastModifiedAtUtcMillis = cursor.getLong(4)
                        )
                    )
                }
            }
        }

        duplicateAllocations.forEach { duplicate ->
            val existing = readAllocation(db, survivorAssetId, duplicate.goalId)
            if (existing == null) {
                db.execSQL(
                    "UPDATE asset_allocations SET asset_id = ? WHERE id = ?",
                    arrayOf(survivorAssetId, duplicate.id)
                )
            } else {
                db.execSQL(
                    """
                    UPDATE asset_allocations
                    SET amount = ?,
                        created_at_utc_millis = ?,
                        last_modified_at_utc_millis = ?
                    WHERE id = ?
                    """.trimIndent(),
                    arrayOf<Any>(
                        existing.amount + duplicate.amount,
                        minOf(existing.createdAtUtcMillis, duplicate.createdAtUtcMillis),
                        maxOf(existing.lastModifiedAtUtcMillis, duplicate.lastModifiedAtUtcMillis),
                        existing.id
                    )
                )
                db.execSQL(
                    "DELETE FROM asset_allocations WHERE id = ?",
                    arrayOf(duplicate.id)
                )
            }
        }
    }

    private fun readAllocation(
        db: SupportSQLiteDatabase,
        assetId: String,
        goalId: String
    ): MigratingAllocation? {
        return db.query(
            """
            SELECT id, goal_id, amount, created_at_utc_millis, last_modified_at_utc_millis
            FROM asset_allocations
            WHERE asset_id = ? AND goal_id = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(assetId, goalId)
        ).use { cursor ->
            if (!cursor.moveToFirst()) {
                null
            } else {
                MigratingAllocation(
                    id = cursor.getString(0),
                    goalId = cursor.getString(1),
                    amount = cursor.getDouble(2),
                    createdAtUtcMillis = cursor.getLong(3),
                    lastModifiedAtUtcMillis = cursor.getLong(4)
                )
            }
        }
    }

    private fun mergeExecutionAssetRates(
        db: SupportSQLiteDatabase,
        duplicateAssetId: String,
        survivorAssetId: String
    ) {
        val duplicateRates = readExecutionAssetRates(db, duplicateAssetId)

        duplicateRates.forEach { duplicate ->
            val existing = readExecutionAssetRate(
                db = db,
                executionRecordId = duplicate.executionRecordId,
                assetId = survivorAssetId,
                snapshotCurrency = duplicate.snapshotCurrency
            )
            if (existing == null) {
                db.execSQL(
                    """
                    UPDATE execution_asset_rates
                    SET asset_id = ?
                    WHERE execution_record_id = ?
                        AND asset_id = ?
                        AND snapshot_currency = ?
                    """.trimIndent(),
                    arrayOf(
                        survivorAssetId,
                        duplicate.executionRecordId,
                        duplicateAssetId,
                        duplicate.snapshotCurrency
                    )
                )
            } else {
                check(
                    duplicate.rate.toBits() == existing.rate.toBits() &&
                        duplicate.capturedAtUtcMillis == existing.capturedAtUtcMillis
                ) {
                    "Conflicting immutable execution-rate evidence cannot be merged"
                }
                db.execSQL(
                    """
                    DELETE FROM execution_asset_rates
                    WHERE execution_record_id = ?
                        AND asset_id = ?
                        AND snapshot_currency = ?
                    """.trimIndent(),
                    arrayOf(
                        duplicate.executionRecordId,
                        duplicateAssetId,
                        duplicate.snapshotCurrency
                    )
                )
            }
        }
    }

    private fun readExecutionAssetRates(
        db: SupportSQLiteDatabase,
        assetId: String
    ): List<MigratingRate> {
        return buildList {
            db.query(
                """
                SELECT execution_record_id, snapshot_currency, rate, captured_at_utc_millis
                FROM execution_asset_rates
                WHERE asset_id = ?
                ORDER BY execution_record_id ASC, snapshot_currency ASC
                """.trimIndent(),
                arrayOf(assetId)
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    add(
                        MigratingRate(
                            executionRecordId = cursor.getString(0),
                            snapshotCurrency = cursor.getString(1),
                            rate = cursor.getDouble(2),
                            capturedAtUtcMillis = cursor.getLong(3)
                        )
                    )
                }
            }
        }
    }

    private fun readExecutionAssetRate(
        db: SupportSQLiteDatabase,
        executionRecordId: String,
        assetId: String,
        snapshotCurrency: String
    ): MigratingRate? {
        return db.query(
            """
            SELECT execution_record_id, snapshot_currency, rate, captured_at_utc_millis
            FROM execution_asset_rates
            WHERE execution_record_id = ?
                AND asset_id = ?
                AND snapshot_currency = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(executionRecordId, assetId, snapshotCurrency)
        ).use { cursor ->
            if (!cursor.moveToFirst()) {
                null
            } else {
                MigratingRate(
                    executionRecordId = cursor.getString(0),
                    snapshotCurrency = cursor.getString(1),
                    rate = cursor.getDouble(2),
                    capturedAtUtcMillis = cursor.getLong(3)
                )
            }
        }
    }

    private fun backfillCompletionEvents(db: SupportSQLiteDatabase) {
        val now = System.currentTimeMillis()

        // Fetch all needed records in a single query to avoid N+1 performance issues
        val allRowsCursor = db.query(
            """
            SELECT ce.id, ce.goal_id, ce.execution_record_id, ce.completed_at_utc_millis, mer.month_label
            FROM completed_executions ce
            INNER JOIN monthly_execution_records mer ON mer.id = ce.execution_record_id
            ORDER BY ce.execution_record_id ASC, ce.completed_at_utc_millis ASC, ce.id ASC
            """.trimIndent()
        )

        data class TempGroup(
            val recordId: String,
            val monthLabel: String,
            val completedAtMillis: Long,
            val rowIds: MutableList<String> = mutableListOf(),
            val goalIds: MutableList<String> = mutableListOf()
        )

        data class LegacyGroup(
            val recordId: String,
            val monthLabel: String,
            val completedAtMillis: Long,
            val sourceDiscriminator: String,
            val completionSnapshotRef: String
        )

        val recordGroups = mutableMapOf<String, MutableList<TempGroup>>()

        allRowsCursor.use { cursor ->
            val idxId = cursor.getColumnIndexOrThrow("id")
            val idxGoalId = cursor.getColumnIndexOrThrow("goal_id")
            val idxRecordId = cursor.getColumnIndexOrThrow("execution_record_id")
            val idxMonthLabel = cursor.getColumnIndexOrThrow("month_label")
            val idxCompletedAt = cursor.getColumnIndexOrThrow("completed_at_utc_millis")

            var lastKey: String? = null
            var currentGroup: TempGroup? = null

            while (cursor.moveToNext()) {
                val recordId = cursor.getString(idxRecordId)
                val completedAt = cursor.getLong(idxCompletedAt)
                val key = "$recordId|$completedAt"

                if (key != lastKey) {
                    currentGroup = TempGroup(recordId, cursor.getString(idxMonthLabel), completedAt)
                    recordGroups.getOrPut(recordId) { mutableListOf() }.add(currentGroup)
                    lastKey = key
                }
                currentGroup?.rowIds?.add(cursor.getString(idxId))
                currentGroup?.goalIds?.add(cursor.getString(idxGoalId))
            }
        }

        recordGroups.forEach { (recordId, groups) ->
            // Transform and sort according to original logic (by time, then by discriminator)
            val legacyGroups = groups.map { group ->
                val sourceDiscriminator = sha256(
                    group.rowIds.sorted().joinToString(",") +
                        "|" +
                        group.goalIds.sorted().joinToString(",") +
                        "|" +
                        group.rowIds.size +
                        "|" +
                        group.completedAtMillis
                )
                LegacyGroup(
                    recordId = group.recordId,
                    monthLabel = group.monthLabel,
                    completedAtMillis = group.completedAtMillis,
                    sourceDiscriminator = sourceDiscriminator,
                    completionSnapshotRef = "batch:${group.recordId}:${group.completedAtMillis}:$sourceDiscriminator"
                )
            }.sortedWith(
                compareBy<LegacyGroup> { it.completedAtMillis }
                    .thenBy { it.sourceDiscriminator }
            )

            legacyGroups.forEachIndexed { index, group ->
                val sequence = index + 1
                val eventId = "legacy:$recordId:$sequence:${group.sourceDiscriminator.take(16)}"
                db.execSQL(
                    """
                    INSERT OR IGNORE INTO completion_events(
                        id,
                        execution_record_id,
                        month_label,
                        sequence,
                        source_discriminator,
                        completed_at_utc_millis,
                        completion_snapshot_ref,
                        created_at_utc_millis,
                        undone_at_utc_millis,
                        undo_reason
                    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                    """.trimIndent(),
                    arrayOf<Any>(
                        eventId,
                        group.recordId,
                        group.monthLabel,
                        sequence,
                        group.sourceDiscriminator,
                        group.completedAtMillis,
                        group.completionSnapshotRef,
                        now
                    )
                )

                db.execSQL(
                    """
                    UPDATE completed_executions
                    SET completion_event_id = ?
                    WHERE execution_record_id = ?
                        AND completed_at_utc_millis = ?
                    """.trimIndent(),
                    arrayOf<Any>(eventId, group.recordId, group.completedAtMillis)
                )
            }
        }
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
