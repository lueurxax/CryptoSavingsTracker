package com.xax.CryptoSavingsTracker.data.local.database

import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.migration.DatabaseMigrations
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.security.MessageDigest

@RunWith(AndroidJUnit4::class)
class DatabaseMigrationTest {
    private val testDb = "migration-test.db"

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java,
        emptyList(),
        FrameworkSQLiteOpenHelperFactory()
    )

    @Test
    fun migrate1To2_createsMonthlyGoalPlansTable() {
        helper.createDatabase(testDb, 1).apply { close() }
        helper.runMigrationsAndValidate(
            testDb,
            2,
            true,
            DatabaseMigrations.MIGRATION_1_2
        )
    }

    @Test
    fun migrate4To5_backfillsCompletionEventsDeterministically() {
        helper.createDatabase(testDb, 4).apply {
            seedLegacyCompletionData(this)
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            testDb,
            5,
            true,
            DatabaseMigrations.MIGRATION_4_5
        )

        val events = readCompletionEvents(migrated, "record-1")
        assertEquals(2, events.size)

        val expectedFirstHash = expectedSourceDiscriminator(
            rowIds = listOf("row-a1", "row-a2"),
            goalIds = listOf("goal-1", "goal-2"),
            completedAtMillis = 1_700_000_000_000
        )
        val expectedSecondHash = expectedSourceDiscriminator(
            rowIds = listOf("row-b1"),
            goalIds = listOf("goal-1"),
            completedAtMillis = 1_700_100_000_000
        )

        assertEquals(1, events[0].sequence)
        assertEquals(1_700_000_000_000, events[0].completedAtMillis)
        assertEquals(expectedFirstHash, events[0].sourceDiscriminator)
        assertEquals("batch:record-1:1700000000000:$expectedFirstHash", events[0].snapshotRef)

        assertEquals(2, events[1].sequence)
        assertEquals(1_700_100_000_000, events[1].completedAtMillis)
        assertEquals(expectedSecondHash, events[1].sourceDiscriminator)
        assertEquals("batch:record-1:1700100000000:$expectedSecondHash", events[1].snapshotRef)

        // Every legacy completed row is linked to the migrated completion event.
        migrated.query(
            "SELECT completion_event_id FROM completed_executions WHERE execution_record_id = 'record-1'"
        ).use { cursor ->
            var count = 0
            while (cursor.moveToNext()) {
                val eventId = cursor.getString(0)
                assertNotNull(eventId)
                count += 1
            }
            assertEquals(3, count)
        }
    }

    @Test
    fun migrate4To5_sameSeedProducesIdenticalBackfill() {
        val dbA = "migration-test-a.db"
        val dbB = "migration-test-b.db"

        helper.createDatabase(dbA, 4).apply {
            seedLegacyCompletionData(this)
            close()
        }
        helper.createDatabase(dbB, 4).apply {
            seedLegacyCompletionData(this)
            close()
        }

        val migratedA = helper.runMigrationsAndValidate(dbA, 5, true, DatabaseMigrations.MIGRATION_4_5)
        val migratedB = helper.runMigrationsAndValidate(dbB, 5, true, DatabaseMigrations.MIGRATION_4_5)

        val eventsA = readCompletionEvents(migratedA, "record-1")
        val eventsB = readCompletionEvents(migratedB, "record-1")

        assertEquals(eventsA, eventsB)
    }

    @Test
    fun migrate5To6_createsExecutionAssetRatesTable() {
        helper.createDatabase(testDb, 5).apply {
            seedExecutingRecordWithoutRateSnapshot(this)
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            testDb,
            6,
            true,
            DatabaseMigrations.MIGRATION_5_6
        )

        migrated.query("PRAGMA table_info(execution_asset_rates)").use { cursor ->
            val columnNames = buildSet {
                val nameIndex = cursor.getColumnIndexOrThrow("name")
                while (cursor.moveToNext()) add(cursor.getString(nameIndex))
            }
            assertEquals(
                setOf(
                    "execution_record_id",
                    "asset_id",
                    "snapshot_currency",
                    "rate",
                    "captured_at_utc_millis"
                ),
                columnNames
            )
        }
        migrated.query(
            "SELECT legacy_rate_snapshot_pending FROM monthly_execution_records WHERE id = 'executing-record'"
        ).use { cursor ->
            assertEquals(true, cursor.moveToFirst())
            assertEquals(1, cursor.getInt(0))
        }
    }

    @Test
    fun migrate5To6_marksClosedUndoableRecordForRateSnapshotBackfill() {
        val dbName = "closed-undoable-migration-test.db"
        helper.createDatabase(dbName, 5).apply {
            seedClosedUndoableRecordWithoutRateSnapshot(this)
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            6,
            true,
            DatabaseMigrations.MIGRATION_5_6
        )

        migrated.query(
            "SELECT legacy_rate_snapshot_pending FROM monthly_execution_records " +
                "WHERE id = 'closed-undoable-record'"
        ).use { cursor ->
            assertEquals(true, cursor.moveToFirst())
            assertEquals(1, cursor.getInt(0))
        }
    }

    @Test
    fun migrate6To7_canonicalizesAndReconcilesLegacyOnChainIdentitiesWithoutFinancialLoss() {
        val dbName = "asset-composite-identity-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            seedGoalForAssetIdentityMigration(this)
            seedExecutionRecordForAssetIdentityMigration(this)

            val usdcContract = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "usdc-symbol", "usdc", "0xAbC", "ETH", 10L, 11L,
                    "usdc-contract", usdcContract, "0xabc", "ethereum", 20L, 21L,
                    "polygon-matic", "MATIC", "0xPoLy", "MATIC", 30L, 31L,
                    "polygon-pol", "POL", "0xpoly", "polygon", 40L, 41L,
                    "quick-current", "0xB5C064F955D8e7F38fE0460C556a72987494eE17",
                    "0xQuIcK", "polygon", 50L, 51L,
                    "quick-legacy", "0x831753DD7087CaC61aB5644b308642cc1c33Dc13",
                    "0xquick", "polygon", 60L, 61L,
                    "tron-contract", "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                    "TCaseSensitiveWallet", "TRX", 70L, 71L
                )
            )
            execSQL(
                """
                INSERT INTO transactions(
                    id, asset_id, amount, date_utc_millis, source,
                    external_id, counterparty, comment, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, NULL, NULL, NULL, ?),
                    (?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
                """.trimIndent(),
                arrayOf(
                    "tx-symbol", "usdc-symbol", 1.25, 100L, "manual", 101L,
                    "tx-contract", "usdc-contract", 2.75, 200L, "manual", 201L
                )
            )
            execSQL(
                """
                INSERT INTO asset_allocations(
                    id, asset_id, goal_id, amount,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "allocation-symbol", "usdc-symbol", "migration-goal", 10.0, 110L, 111L,
                    "allocation-contract", "usdc-contract", "migration-goal", 20.0, 120L, 121L
                )
            )
            execSQL(
                """
                INSERT INTO allocation_history(
                    id, asset_id, goal_id, amount, month_label,
                    timestamp_utc_millis, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "history-symbol", "usdc-symbol", "migration-goal", 10.0,
                    "2026-07", 130L, 131L,
                    "history-contract", "usdc-contract", "migration-goal", 20.0,
                    "2026-07", 140L, 141L
                )
            )
            execSQL(
                """
                INSERT INTO execution_asset_rates(
                    execution_record_id, asset_id, snapshot_currency,
                    rate, captured_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "migration-record", "usdc-symbol", "USD", 1.0, 150L,
                    "migration-record", "usdc-contract", "USD", 1.0, 150L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query("SELECT COUNT(*) FROM assets").use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(5, cursor.getInt(0))
        }
        migrated.query(
            "SELECT currency, address, chain_id FROM assets WHERE id = 'usdc-symbol'"
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("USDC", cursor.getString(0))
            assertEquals("0xabc", cursor.getString(1))
            assertEquals("ethereum", cursor.getString(2))
        }
        migrated.query(
            "SELECT currency, address, chain_id FROM assets WHERE id = 'polygon-matic'"
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("POL", cursor.getString(0))
            assertEquals("0xpoly", cursor.getString(1))
            assertEquals("polygon", cursor.getString(2))
        }
        migrated.query(
            "SELECT currency, address, chain_id FROM assets WHERE id = 'tron-contract'"
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("USDT", cursor.getString(0))
            assertEquals("TCaseSensitiveWallet", cursor.getString(1))
            assertEquals("tron", cursor.getString(2))
        }
        migrated.query(
            """
            SELECT id, currency
            FROM assets
            WHERE address = '0xquick' AND chain_id = 'polygon'
            ORDER BY id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("quick-current", cursor.getString(0))
            assertEquals("QUICK", cursor.getString(1))
            assertTrue(cursor.moveToNext())
            assertEquals("quick-legacy", cursor.getString(0))
            assertEquals("QUICK_LEGACY", cursor.getString(1))
            assertTrue(!cursor.moveToNext())
        }

        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM transactions
            WHERE id IN ('tx-symbol', 'tx-contract')
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(1, cursor.getInt(1))
            assertEquals(4.0, cursor.getDouble(2), 0.0)
        }
        migrated.query(
            """
            SELECT asset_id, amount, created_at_utc_millis, last_modified_at_utc_millis
            FROM asset_allocations
            WHERE goal_id = 'migration-goal'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("usdc-symbol", cursor.getString(0))
            assertEquals(30.0, cursor.getDouble(1), 0.0)
            assertEquals(110L, cursor.getLong(2))
            assertEquals(121L, cursor.getLong(3))
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM allocation_history
            WHERE id IN ('history-symbol', 'history-contract')
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(1, cursor.getInt(1))
            assertEquals(30.0, cursor.getDouble(2), 0.0)
        }
        migrated.query(
            """
            SELECT asset_id, COUNT(*)
            FROM execution_asset_rates
            WHERE execution_record_id = 'migration-record'
            GROUP BY asset_id
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("usdc-symbol", cursor.getString(0))
            assertEquals(1, cursor.getInt(1))
            assertTrue(!cursor.moveToNext())
        }

        var duplicateRejected = false
        try {
            migrated.execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES(?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf("duplicate-usdc", "USDC", "0xabc", "ethereum", 60L, 61L)
            )
        } catch (_: Exception) {
            duplicateRejected = true
        }
        assertTrue("same address + chain + currency must stay unique", duplicateRejected)
    }

    @Test
    fun migrate6To7_quarantinesMalformedLegacyUtxoAddressesWithoutAbortingUpgrade() {
        val dbName = "asset-malformed-utxo-address-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "malformed-bch",
                    "bch",
                    " 1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggx ",
                    "BCH",
                    10L,
                    11L,
                    "malformed-ltc",
                    "ltc",
                    " MWWunwFdsSzsi44wARi2zJJGju6VqMMGtP ",
                    "LTC",
                    20L,
                    21L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query(
            """
            SELECT id, currency, address, chain_id
            FROM assets
            WHERE id IN ('malformed-bch', 'malformed-ltc')
            ORDER BY id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("malformed-bch", cursor.getString(0))
            assertEquals("BCH", cursor.getString(1))
            assertEquals("1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggx", cursor.getString(2))
            assertEquals(
                "legacy-malformed-address:bitcoin-cash:malformed-bch",
                cursor.getString(3)
            )

            assertTrue(cursor.moveToNext())
            assertEquals("malformed-ltc", cursor.getString(0))
            assertEquals("LTC", cursor.getString(1))
            assertEquals("MWWunwFdsSzsi44wARi2zJJGju6VqMMGtP", cursor.getString(2))
            assertEquals(
                "legacy-malformed-address:litecoin:malformed-ltc",
                cursor.getString(3)
            )
            assertTrue(!cursor.moveToNext())
        }
    }

    @Test
    fun migrate6To7_quarantinesDuplicateAllocationsWhenTheirSumIsNotFinite() {
        val dbName = "asset-allocation-overflow-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            seedGoalForAssetIdentityMigration(this)
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "overflow-symbol",
                    "USDC",
                    "0xOVERFLOW",
                    "ETH",
                    10L,
                    11L,
                    "overflow-contract",
                    "USDC",
                    "0xoverflow",
                    "ethereum",
                    20L,
                    21L
                )
            )
            execSQL(
                """
                INSERT INTO asset_allocations(
                    id, asset_id, goal_id, amount,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "overflow-allocation-symbol",
                    "overflow-symbol",
                    "migration-goal",
                    Double.MAX_VALUE,
                    30L,
                    31L,
                    "overflow-allocation-contract",
                    "overflow-contract",
                    "migration-goal",
                    Double.MAX_VALUE,
                    40L,
                    41L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query(
            """
            SELECT id, chain_id
            FROM assets
            WHERE id IN ('overflow-symbol', 'overflow-contract')
            ORDER BY id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("overflow-contract", cursor.getString(0))
            assertEquals(
                "legacy-allocation-conflict:ethereum:overflow-contract",
                cursor.getString(1)
            )
            assertTrue(cursor.moveToNext())
            assertEquals("overflow-symbol", cursor.getString(0))
            assertEquals("ethereum", cursor.getString(1))
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT asset_id, amount
            FROM asset_allocations
            WHERE goal_id = 'migration-goal'
            ORDER BY asset_id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("overflow-contract", cursor.getString(0))
            assertEquals(Double.MAX_VALUE, cursor.getDouble(1), 0.0)
            assertTrue(cursor.getDouble(1).isFinite())
            assertTrue(cursor.moveToNext())
            assertEquals("overflow-symbol", cursor.getString(0))
            assertEquals(Double.MAX_VALUE, cursor.getDouble(1), 0.0)
            assertTrue(cursor.getDouble(1).isFinite())
            assertTrue(!cursor.moveToNext())
        }
    }

    @Test
    fun migrate6To7_rewritesAndDeduplicatesLegacyUtxoIdentityWithoutDoubleBalance() {
        val dbName = "asset-utxo-identity-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "current-btc", "BTC", "BC1QWALLET", "bitcoin", 10L, 11L,
                    "duplicate-btc", "btc", "bc1qwallet", "BTC", 20L, 21L
                )
            )
            execSQL(
                """
                INSERT INTO transactions(
                    id, asset_id, amount, date_utc_millis, source,
                    external_id, counterparty, comment, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?, NULL, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "current-provider-row",
                    "current-btc",
                    1.25,
                    1_000L,
                    "on_chain",
                    "utxo-record-v2|current-btc|canonical-txid|" +
                        "aliases-v1|1|provider-hash",
                    "provider-sender",
                    "On-chain",
                    200L,
                    "legacy-alias-row",
                    "duplicate-btc",
                    1.25,
                    1_000L,
                    "on_chain",
                    "utxo:duplicate-btc:provider-hash",
                    "User note",
                    100L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query(
            """
            SELECT id, asset_id, amount, external_id, counterparty, comment,
                   created_at_utc_millis
            FROM transactions
            WHERE external_id LIKE '%provider-hash%'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("current-provider-row", cursor.getString(0))
            assertEquals("current-btc", cursor.getString(1))
            assertEquals(1.25, cursor.getDouble(2), 0.0)
            assertEquals(
                "utxo-record-v2|current-btc|canonical-txid|" +
                    "aliases-v1|1|provider-hash",
                cursor.getString(3)
            )
            assertEquals("provider-sender", cursor.getString(4))
            assertEquals("User note", cursor.getString(5))
            assertEquals(100L, cursor.getLong(6))
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM transactions
            WHERE external_id LIKE '%provider-hash%'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(1, cursor.getInt(0))
            assertEquals(1, cursor.getInt(1))
            assertEquals(1.25, cursor.getDouble(2), 0.0)
        }
        migrated.query(
            "SELECT COUNT(*) FROM assets WHERE id IN ('current-btc', 'duplicate-btc')"
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(1, cursor.getInt(0))
        }
    }

    @Test
    fun migrate6To7_keepsAssetsSeparateWhenUtxoMetadataConflicts() {
        val dbName = "asset-utxo-metadata-conflict-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "current-btc-conflict", "BTC", "BC1QCONFLICT", "bitcoin", 10L, 11L,
                    "duplicate-btc-conflict", "btc", "bc1qconflict", "BTC", 20L, 21L
                )
            )
            execSQL(
                """
                INSERT INTO transactions(
                    id, asset_id, amount, date_utc_millis, source,
                    external_id, counterparty, comment, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "current-conflict-row",
                    "current-btc-conflict",
                    2.0,
                    2_000L,
                    "on_chain",
                    "utxo:current-btc-conflict:conflicting-hash",
                    "provider-sender",
                    "First user note",
                    100L,
                    "legacy-conflict-row",
                    "duplicate-btc-conflict",
                    2.0,
                    2_000L,
                    "on_chain",
                    "utxo:duplicate-btc-conflict:conflicting-hash",
                    "provider-sender",
                    "Second user note",
                    200L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM transactions
            WHERE external_id LIKE 'utxo:%:conflicting-hash'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(2, cursor.getInt(1))
            assertEquals(4.0, cursor.getDouble(2), 0.0)
        }
        migrated.query(
            """
            SELECT comment
            FROM transactions
            WHERE external_id LIKE 'utxo:%:conflicting-hash'
            ORDER BY id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("First user note", cursor.getString(0))
            assertTrue(cursor.moveToNext())
            assertEquals("Second user note", cursor.getString(0))
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT currency, address, chain_id
            FROM assets
            WHERE id = 'duplicate-btc-conflict'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("BTC", cursor.getString(0))
            assertEquals("bc1qconflict", cursor.getString(1))
            assertEquals(
                "legacy-utxo-conflict:bitcoin:duplicate-btc-conflict",
                cursor.getString(2)
            )
        }
    }

    @Test
    fun migrate6To7_quarantinesConflictingRateDuplicateAndReservesCanonicalIdentity() {
        val dbName = "asset-conflicting-rate-identity-migration-test.db"
        helper.createDatabase(dbName, 6).apply {
            seedGoalForAssetIdentityMigration(this)
            seedExecutionRecordForAssetIdentityMigration(this)
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "rate-symbol", "USDC", "0xRaTe", "ETH", 10L, 11L,
                    "rate-contract", "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    "0xrate", "ethereum", 20L, 21L
                )
            )
            execSQL(
                """
                INSERT INTO execution_asset_rates(
                    execution_record_id, asset_id, snapshot_currency,
                    rate, captured_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "migration-record", "rate-symbol", "USD", 1.0, 150L,
                    "migration-record", "rate-contract", "USD", 1.1, 150L
                )
            )
            execSQL(
                """
                INSERT INTO transactions(
                    id, asset_id, amount, date_utc_millis, source,
                    external_id, counterparty, comment, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, NULL, NULL, NULL, ?),
                    (?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
                """.trimIndent(),
                arrayOf(
                    "rate-tx-symbol", "rate-symbol", -1.25, 100L, "manual", 101L,
                    "rate-tx-contract", "rate-contract", 2.75, 200L, "manual", 201L
                )
            )
            execSQL(
                """
                INSERT INTO asset_allocations(
                    id, asset_id, goal_id, amount,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "rate-allocation-symbol", "rate-symbol", "migration-goal",
                    10.0, 110L, 111L,
                    "rate-allocation-contract", "rate-contract", "migration-goal",
                    20.0, 120L, 121L
                )
            )
            execSQL(
                """
                INSERT INTO allocation_history(
                    id, asset_id, goal_id, amount, month_label,
                    timestamp_utc_millis, created_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "rate-history-symbol", "rate-symbol", "migration-goal",
                    10.0, "2026-07", 130L, 131L,
                    "rate-history-contract", "rate-contract", "migration-goal",
                    20.0, "2026-07", 140L, 141L
                )
            )
            close()
        }

        val migrated = helper.runMigrationsAndValidate(
            dbName,
            7,
            true,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query(
            """
            SELECT id, currency, address, chain_id
            FROM assets
            WHERE id IN ('rate-symbol', 'rate-contract')
            ORDER BY id ASC
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("rate-contract", cursor.getString(0))
            assertEquals("USDC", cursor.getString(1))
            assertEquals("0xrate", cursor.getString(2))
            assertEquals(
                "legacy-rate-conflict:ethereum:rate-contract",
                cursor.getString(3)
            )
            assertTrue(cursor.moveToNext())
            assertEquals("rate-symbol", cursor.getString(0))
            assertEquals("USDC", cursor.getString(1))
            assertEquals("0xrate", cursor.getString(2))
            assertEquals("ethereum", cursor.getString(3))
            assertTrue(!cursor.moveToNext())
        }
        assertPreservedRowsByDistinctAsset(
            migrated,
            table = "transactions",
            idPredicate = "id IN ('rate-tx-symbol', 'rate-tx-contract')",
            expectedAmountSum = 1.5
        )
        assertPreservedRowsByDistinctAsset(
            migrated,
            table = "asset_allocations",
            idPredicate = "goal_id = 'migration-goal'",
            expectedAmountSum = 30.0
        )
        assertPreservedRowsByDistinctAsset(
            migrated,
            table = "allocation_history",
            idPredicate = "goal_id = 'migration-goal'",
            expectedAmountSum = 30.0
        )
        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(rate)
            FROM execution_asset_rates
            WHERE execution_record_id = 'migration-record'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(2, cursor.getInt(1))
            assertEquals(2.1, cursor.getDouble(2), 0.0000001)
        }

        var duplicateRejected = false
        try {
            migrated.execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES(?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "third-logical-duplicate",
                    "USDC",
                    "0xrate",
                    "ethereum",
                    30L,
                    31L
                )
            )
        } catch (_: Exception) {
            duplicateRejected = true
        }
        assertTrue(
            "the canonical row must reserve the live identity beside quarantined evidence",
            duplicateRejected
        )
    }

    private fun assertPreservedRowsByDistinctAsset(
        db: androidx.sqlite.db.SupportSQLiteDatabase,
        table: String,
        idPredicate: String,
        expectedAmountSum: Double
    ) {
        db.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM $table
            WHERE $idPredicate
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(2, cursor.getInt(1))
            assertEquals(expectedAmountSum, cursor.getDouble(2), 0.0000001)
        }
    }

    private fun seedGoalForAssetIdentityMigration(
        db: androidx.sqlite.db.SupportSQLiteDatabase
    ) {
        db.execSQL(
            """
            INSERT INTO goals(
                id, name, currency, target_amount, deadline_epoch_day, start_date_epoch_day,
                lifecycle_status, lifecycle_status_changed_at_utc_millis,
                emoji, description, link, reminder_frequency, reminder_time_utc_millis,
                first_reminder_epoch_day, created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(
                ?, ?, ?, ?, ?, ?, ?, NULL,
                NULL, NULL, NULL, NULL, NULL,
                NULL, ?, ?
            )
            """.trimIndent(),
            arrayOf(
                "migration-goal", "Migration Goal", "USD", 1_000.0,
                21_000L, 20_000L, "active", 1L, 1L
            )
        )
    }

    private fun seedExecutionRecordForAssetIdentityMigration(
        db: androidx.sqlite.db.SupportSQLiteDatabase
    ) {
        db.execSQL(
            """
            INSERT INTO monthly_plans(
                id, month_label, status, flex_percentage, total_required, requirements_json,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf("migration-plan", "2026-07", "draft", 1.0, 0.0, "[]", 1L, 1L)
        )
        db.execSQL(
            """
            INSERT INTO monthly_execution_records(
                id, plan_id, month_label, status, started_at_utc_millis,
                closed_at_utc_millis, can_undo_until_utc_millis,
                legacy_rate_snapshot_pending,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?)
            """.trimIndent(),
            arrayOf(
                "migration-record", "migration-plan", "2026-07", "executing",
                1L, 0, 1L, 1L
            )
        )
    }

    private fun seedExecutingRecordWithoutRateSnapshot(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        val now = 1_700_000_000_000L
        db.execSQL(
            """
            INSERT INTO monthly_plans(
                id, month_label, status, flex_percentage, total_required, requirements_json,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf("legacy-plan", "2026-07", "draft", 1.0, 0.0, "[]", now, now)
        )
        db.execSQL(
            """
            INSERT INTO monthly_execution_records(
                id, plan_id, month_label, status, started_at_utc_millis,
                closed_at_utc_millis, can_undo_until_utc_millis,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, NULL, NULL, ?, ?)
            """.trimIndent(),
            arrayOf("executing-record", "legacy-plan", "2026-07", "executing", now, now, now)
        )
    }

    private fun seedClosedUndoableRecordWithoutRateSnapshot(
        db: androidx.sqlite.db.SupportSQLiteDatabase
    ) {
        val now = System.currentTimeMillis()
        db.execSQL(
            """
            INSERT INTO monthly_plans(
                id, month_label, status, flex_percentage, total_required, requirements_json,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf("closed-plan", "2026-06", "draft", 1.0, 0.0, "[]", now, now)
        )
        db.execSQL(
            """
            INSERT INTO monthly_execution_records(
                id, plan_id, month_label, status, started_at_utc_millis,
                closed_at_utc_millis, can_undo_until_utc_millis,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(
                "closed-undoable-record",
                "closed-plan",
                "2026-06",
                "closed",
                now - 1_000,
                now,
                Long.MAX_VALUE,
                now - 1_000,
                now
            )
        )
    }

    private data class CompletionEventRow(
        val sequence: Int,
        val completedAtMillis: Long,
        val sourceDiscriminator: String,
        val snapshotRef: String?
    )

    private fun readCompletionEvents(
        db: androidx.sqlite.db.SupportSQLiteDatabase,
        recordId: String
    ): List<CompletionEventRow> {
        return buildList {
            db.query(
                """
                SELECT sequence, completed_at_utc_millis, source_discriminator, completion_snapshot_ref
                FROM completion_events
                WHERE execution_record_id = ?
                ORDER BY sequence ASC
                """.trimIndent(),
                arrayOf(recordId)
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    add(
                        CompletionEventRow(
                            sequence = cursor.getInt(0),
                            completedAtMillis = cursor.getLong(1),
                            sourceDiscriminator = cursor.getString(2),
                            snapshotRef = cursor.getString(3)
                        )
                    )
                }
            }
        }
    }

    private fun seedLegacyCompletionData(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        val created = 1_699_000_000_000L

        db.execSQL(
            """
            INSERT INTO monthly_plans(
                id, month_label, status, flex_percentage, total_required, requirements_json, created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf("plan-1", "2026-01", "draft", 1.0, 1000.0, "[]", created, created)
        )

        db.execSQL(
            """
            INSERT INTO monthly_execution_records(
                id, plan_id, month_label, status, started_at_utc_millis, closed_at_utc_millis, can_undo_until_utc_millis, created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf("record-1", "plan-1", "2026-01", "closed", created, created, created + 86_400_000L, created, created)
        )

        db.execSQL(
            """
            INSERT INTO goals(
                id, name, currency, target_amount, deadline_epoch_day, start_date_epoch_day, lifecycle_status,
                lifecycle_status_changed_at_utc_millis, emoji, description, link, reminder_frequency, reminder_time_utc_millis, first_reminder_epoch_day,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?)
            """.trimIndent(),
            arrayOf("goal-1", "Goal 1", "USD", 5000.0, 21000, 20000, "active", created, created)
        )
        db.execSQL(
            """
            INSERT INTO goals(
                id, name, currency, target_amount, deadline_epoch_day, start_date_epoch_day, lifecycle_status,
                lifecycle_status_changed_at_utc_millis, emoji, description, link, reminder_frequency, reminder_time_utc_millis, first_reminder_epoch_day,
                created_at_utc_millis, last_modified_at_utc_millis
            ) VALUES(?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?)
            """.trimIndent(),
            arrayOf("goal-2", "Goal 2", "USD", 7000.0, 21030, 20010, "active", created, created)
        )

        // Batch 1: two goal rows at same completion timestamp.
        db.execSQL(
            """
            INSERT INTO completed_executions(
                id, execution_record_id, goal_id, goal_name, currency, required_amount, actual_amount,
                completed_at_utc_millis, can_undo_until_utc_millis, created_at_utc_millis, undone_at_utc_millis, undo_reason
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
            """.trimIndent(),
            arrayOf("row-a1", "record-1", "goal-1", "Goal 1", "USD", 100.0, 100.0, 1_700_000_000_000L, 1_700_086_400_000L, created)
        )
        db.execSQL(
            """
            INSERT INTO completed_executions(
                id, execution_record_id, goal_id, goal_name, currency, required_amount, actual_amount,
                completed_at_utc_millis, can_undo_until_utc_millis, created_at_utc_millis, undone_at_utc_millis, undo_reason
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
            """.trimIndent(),
            arrayOf("row-a2", "record-1", "goal-2", "Goal 2", "USD", 200.0, 190.0, 1_700_000_000_000L, 1_700_086_400_000L, created)
        )

        // Batch 2: one row at newer completion timestamp.
        db.execSQL(
            """
            INSERT INTO completed_executions(
                id, execution_record_id, goal_id, goal_name, currency, required_amount, actual_amount,
                completed_at_utc_millis, can_undo_until_utc_millis, created_at_utc_millis, undone_at_utc_millis, undo_reason
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
            """.trimIndent(),
            arrayOf("row-b1", "record-1", "goal-1", "Goal 1", "USD", 120.0, 110.0, 1_700_100_000_000L, 1_700_186_400_000L, created)
        )
    }

    private fun expectedSourceDiscriminator(
        rowIds: List<String>,
        goalIds: List<String>,
        completedAtMillis: Long
    ): String {
        val payload = rowIds.sorted().joinToString(",") +
            "|" +
            goalIds.sorted().joinToString(",") +
            "|" +
            rowIds.size +
            "|" +
            completedAtMillis
        val bytes = MessageDigest.getInstance("SHA-256").digest(payload.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
