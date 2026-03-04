package com.xax.CryptoSavingsTracker.data.local.database

import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.migration.DatabaseMigrations
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
