package com.xax.CryptoSavingsTracker.data.local.database

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.migration.DatabaseMigrations
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
    fun migrate1To5_isValid() {
        helper.createDatabase(TEST_DB_V5, 1).close()
        helper.runMigrationsAndValidate(
            TEST_DB_V5,
            5,
            true,
            DatabaseMigrations.MIGRATION_1_2,
            DatabaseMigrations.MIGRATION_2_3,
            DatabaseMigrations.MIGRATION_3_4,
            DatabaseMigrations.MIGRATION_4_5
        )
    }

    private companion object {
        const val TEST_DB_V1 = "migration-test-v1"
        const val TEST_DB_V5 = "migration-test-v5"
    }
}
