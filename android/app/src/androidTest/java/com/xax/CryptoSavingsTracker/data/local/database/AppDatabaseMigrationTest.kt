package com.xax.CryptoSavingsTracker.data.local.database

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.migration.DatabaseMigrations
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppDatabaseMigrationTest {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java
    )

    @Test
    fun schemaVersion1_isValid() {
        helper.createDatabase(TEST_DB_V1, 1).close()
        helper.runMigrationsAndValidate(TEST_DB_V1, 1, true)
    }

    @Test
    fun migrate1To7_isValid() {
        helper.createDatabase(TEST_DB_V7, 1).apply {
            execSQL(
                """
                INSERT INTO assets(
                    id, currency, address, chain_id,
                    created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES
                    (?, ?, ?, ?, ?, ?),
                    (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf<Any?>(
                    "legacy-symbol", "usdc", "0xAbC", "ETH", 10L, 11L,
                    "legacy-contract", "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    "0xabc", "ethereum", 20L, 21L
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
                arrayOf<Any?>(
                    "legacy-tx-symbol", "legacy-symbol", 1.25, 100L, "manual", 101L,
                    "legacy-tx-contract", "legacy-contract", 2.75, 200L, "manual", 201L
                )
            )
            execSQL(
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
                arrayOf<Any?>(
                    "legacy-goal", "Legacy Goal", "USD", 1_000.0,
                    21_000L, 20_000L, "active", 1L, 1L
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
                arrayOf<Any?>(
                    "legacy-allocation-symbol", "legacy-symbol", "legacy-goal",
                    10.0, 110L, 111L,
                    "legacy-allocation-contract", "legacy-contract", "legacy-goal",
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
                arrayOf<Any?>(
                    "legacy-history-symbol", "legacy-symbol", "legacy-goal",
                    10.0, "2026-07", 130L, 131L,
                    "legacy-history-contract", "legacy-contract", "legacy-goal",
                    20.0, "2026-07", 140L, 141L
                )
            )
            close()
        }
        val migrated = helper.runMigrationsAndValidate(
            TEST_DB_V7,
            7,
            true,
            DatabaseMigrations.MIGRATION_1_2,
            DatabaseMigrations.MIGRATION_2_3,
            DatabaseMigrations.MIGRATION_3_4,
            DatabaseMigrations.MIGRATION_4_5,
            DatabaseMigrations.MIGRATION_5_6,
            DatabaseMigrations.MIGRATION_6_7
        )

        migrated.query("SELECT id, currency, address, chain_id FROM assets").use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("legacy-symbol", cursor.getString(0))
            assertEquals("USDC", cursor.getString(1))
            assertEquals("0xabc", cursor.getString(2))
            assertEquals("ethereum", cursor.getString(3))
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM transactions
            WHERE id IN ('legacy-tx-symbol', 'legacy-tx-contract')
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(1, cursor.getInt(1))
            assertEquals(4.0, cursor.getDouble(2), 0.0)
        }
        migrated.query(
            """
            SELECT asset_id, amount
            FROM asset_allocations
            WHERE goal_id = 'legacy-goal'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("legacy-symbol", cursor.getString(0))
            assertEquals(30.0, cursor.getDouble(1), 0.0)
            assertTrue(!cursor.moveToNext())
        }
        migrated.query(
            """
            SELECT COUNT(*), COUNT(DISTINCT asset_id), SUM(amount)
            FROM allocation_history
            WHERE goal_id = 'legacy-goal'
            """.trimIndent()
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(2, cursor.getInt(0))
            assertEquals(1, cursor.getInt(1))
            assertEquals(30.0, cursor.getDouble(2), 0.0)
        }
    }

    private companion object {
        const val TEST_DB_V1 = "migration-test-v1"
        const val TEST_DB_V7 = "migration-test-v7"
    }
}
