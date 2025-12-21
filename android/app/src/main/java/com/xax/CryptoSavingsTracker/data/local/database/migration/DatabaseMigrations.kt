package com.xax.CryptoSavingsTracker.data.local.database.migration

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

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
}

