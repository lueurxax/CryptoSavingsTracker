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
