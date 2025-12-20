# Android Development Plan - CryptoSavingsTracker

## Overview

This document outlines the comprehensive plan to build the Android version of CryptoSavingsTracker, ensuring feature parity with the iOS/macOS app while following Android best practices and Modern Android Development (MAD) guidelines.

---

## Table of Contents

1. [Scope & Parity Definition](#1-scope--parity-definition)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Data Layer](#4-data-layer)
5. [Domain Layer](#5-domain-layer)
6. [Presentation Layer](#6-presentation-layer)
7. [API & Security](#7-api--security)
8. [Implementation Phases](#8-implementation-phases)
9. [Testing Strategy](#9-testing-strategy)
10. [Platform-Specific Considerations](#10-platform-specific-considerations)

---

## 1. Scope & Parity Definition

### 1.1 Feature Parity Checklist

| Feature | iOS Status | Android Target | Priority | Notes |
|---------|------------|----------------|----------|-------|
| **Goal Management** | | | | |
| Create/Edit/Delete goals | ✅ | Required | P0 | Core feature |
| Goal lifecycle (active/cancelled/finished) | ✅ | Required | P0 | |
| Emoji picker with smart suggestions | ✅ | Required | P1 | |
| Goal description and external links | ✅ | Required | P1 | |
| Reminder scheduling | ✅ | Required | P1 | WorkManager |
| **Asset Management** | | | | |
| Create/Edit/Delete assets | ✅ | Required | P0 | Core feature |
| Manual transaction entry | ✅ | Required | P0 | |
| On-chain balance fetching | ✅ | Required | P1 | Tatum API |
| Transaction history import | ✅ | Required | P1 | |
| **Allocation System** | | | | |
| Fixed-amount asset allocation | ✅ | Required | P0 | Core feature |
| Allocation history snapshots | ✅ | Required | P0 | For execution |
| Auto-allocation for single-goal assets | ✅ | Required | P1 | |
| Over-allocation detection | ✅ | Required | P1 | |
| **Monthly Planning** | | | | |
| Zero-input requirement calculation | ✅ | Required | P0 | Core feature |
| Flex adjustment slider (0-150%) | ✅ | Required | P0 | |
| Protected/skipped goal flags | ✅ | Required | P1 | |
| Custom amount override | ✅ | Required | P1 | |
| **Execution Tracking** | | | | |
| Timestamp-based progress derivation | ✅ | Required | P0 | Core innovation |
| Execution state machine (draft→executing→closed) | ✅ | Required | P0 | |
| ExecutionSnapshot capture | ✅ | Required | P0 | |
| 24-hour undo windows | ✅ | Required | P1 | |
| CompletedExecution history | ✅ | Required | P1 | |
| **Dashboard** | | | | |
| Portfolio overview | ✅ | Required | P0 | |
| Goal progress summary | ✅ | Required | P0 | |
| Monthly planning widget | ✅ | Required | P1 | |
| **Multi-Currency** | | | | |
| Real-time exchange rates (CoinGecko) | ✅ | Required | P0 | |
| Batch currency conversion | ✅ | Required | P0 | |
| Display currency preference | ✅ | Required | P1 | |
| **Data Export** | | | | |
| CSV export | ✅ | Required | P2 | |

### 1.2 Non-Goals (v1.0)

The following features are explicitly **out of scope** for the initial Android release:

| Feature | Reason | Future Consideration |
|---------|--------|---------------------|
| iCloud sync | Apple-only technology | Firebase/custom backend v2.0 |
| visionOS support | iOS-only | N/A |
| Siri Shortcuts | iOS-only | Android Shortcuts v1.1 |
| Apple Watch widget | iOS-only | Wear OS v2.0 |
| Biometric auth for app lock | Scope creep | v1.1 |
| Dark mode toggle | Use system setting only | v1.1 if requested |
| Landscape tablet layout | Complexity | v1.1 |
| Localization (non-English) | Scope | v1.2 |

### 1.3 Acceptance Criteria

#### Release Criteria (Must Pass All)

1. **Functional Parity**: All P0 features implemented and working
2. **Data Integrity**:
   - All CRUD operations persist correctly
   - No data loss on app restart/kill
   - Allocation calculations match iOS within 0.01% tolerance
3. **Performance**:
   - Cold start < 2 seconds on mid-range device (Pixel 6a)
   - Goal list scroll at 60fps with 50+ goals
   - API responses cached, no redundant network calls
4. **Stability**:
   - Crash-free rate > 99.5% (Firebase Crashlytics)
   - No ANRs in normal usage
5. **Testing**:
   - Unit test coverage > 80% for domain layer
   - All critical user journeys have UI tests
   - Manual QA sign-off on test matrix

#### Device Test Matrix

| Device | OS Version | Form Factor | Priority |
|--------|------------|-------------|----------|
| Pixel 8 | Android 14 | Phone | P0 |
| Pixel 6a | Android 13 | Phone | P0 |
| Samsung S23 | Android 14 | Phone | P0 |
| Samsung A54 | Android 13 | Phone | P1 |
| Pixel Tablet | Android 14 | Tablet | P2 |

---

## 2. Technology Stack

### Core Technologies

| Category | iOS (Reference) | Android (Target) |
|----------|-----------------|------------------|
| **UI Framework** | SwiftUI | Jetpack Compose |
| **Database** | SwiftData | Room 2.6+ |
| **Reactive** | Combine | Kotlin Flow + StateFlow |
| **DI** | DIContainer (custom) | Hilt 2.52+ |
| **Architecture** | MVVM | MVVM + Clean Architecture |
| **Networking** | URLSession | Retrofit 2.11 + OkHttp 4.12 |
| **JSON** | Codable | Kotlinx Serialization 1.7 |
| **Async** | async/await | Kotlin Coroutines 1.9 |
| **Navigation** | NavigationStack | Navigation Compose 2.8 |
| **Testing** | XCTest | JUnit 5 + MockK + Turbine |

### Dependencies

```kotlin
// build.gradle.kts (app)
//
// PACKAGE NAMING: com.xax.CryptoSavingsTracker
// This mixed-case package is used consistently throughout:
// - namespace and applicationId (below)
// - folder structure: java/com/xax/CryptoSavingsTracker/
// - HiltTestRunner package
// - Room schema export path

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.xax.CryptoSavingsTracker"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.xax.CryptoSavingsTracker"
        minSdk = 34  // Android 14+ (modern baseline, no desugaring needed)
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "com.xax.CryptoSavingsTracker.HiltTestRunner"

        // Room schema export for migrations
        ksp {
            arg("room.schemaLocation", "$projectDir/schemas")
            arg("room.incremental", "true")
            arg("room.generateKotlin", "true")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // No desugaring needed - minSdk 34 has full java.time support
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // Core Android
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Jetpack Compose (BOM)
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")

    // Room Database
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Hilt DI
    implementation("com.google.dagger:hilt-android:2.52")
    ksp("com.google.dagger:hilt-compiler:2.52")

    // Networking
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")

    // DataStore (preferences)
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Security (API key storage)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // WorkManager (reminders)
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("androidx.hilt:hilt-work:1.2.0")
    ksp("androidx.hilt:hilt-compiler:1.2.0")

    // Charts
    implementation("com.patrykandpatrick.vico:compose-m3:2.0.0-beta.2")

    // Firebase Crashlytics (stability monitoring)
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-crashlytics-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")

    // ========== TESTING ==========

    // Unit Tests (JUnit 5)
    testImplementation(platform("org.junit:junit-bom:5.11.3"))
    testImplementation("org.junit.jupiter:junit-jupiter-api")
    testImplementation("org.junit.jupiter:junit-jupiter-params")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine")

    // Mocking & Assertions
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("com.google.truth:truth:1.4.4")
    testImplementation("app.cash.turbine:turbine:1.2.0")

    // Coroutines Testing
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")

    // Room Testing
    testImplementation("androidx.room:room-testing:2.6.1")

    // Network Mocking
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")

    // Android Instrumented Tests
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.12.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit-ktx:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("com.google.dagger:hilt-android-testing:2.52")
    kspAndroidTest("com.google.dagger:hilt-compiler:2.52")
    androidTestImplementation("io.mockk:mockk-android:1.13.13")
}

tasks.withType<Test> {
    useJUnitPlatform()  // Enable JUnit 5
}
```

---

## 3. Project Structure

```
android/app/src/
├── main/
│   ├── java/com/xax/CryptoSavingsTracker/
│   │   ├── CryptoSavingsTrackerApp.kt
│   │   ├── MainActivity.kt
│   │   │
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   ├── database/
│   │   │   │   │   ├── AppDatabase.kt
│   │   │   │   │   ├── DatabaseMigrations.kt
│   │   │   │   │   ├── dao/
│   │   │   │   │   ├── entity/
│   │   │   │   │   └── converter/
│   │   │   │   ├── datastore/
│   │   │   │   └── cache/
│   │   │   ├── remote/
│   │   │   │   ├── api/
│   │   │   │   ├── dto/
│   │   │   │   └── interceptor/
│   │   │   └── repository/
│   │   │
│   │   ├── domain/
│   │   │   ├── model/
│   │   │   ├── repository/
│   │   │   └── usecase/
│   │   │
│   │   ├── presentation/
│   │   │   ├── navigation/
│   │   │   ├── theme/
│   │   │   ├── common/
│   │   │   ├── goals/
│   │   │   ├── assets/
│   │   │   ├── planning/
│   │   │   ├── execution/
│   │   │   ├── dashboard/
│   │   │   └── transactions/
│   │   │
│   │   └── di/
│   │
│   └── res/
│
├── test/                          # Unit tests
│   └── java/com/xax/CryptoSavingsTracker/
│       ├── data/
│       │   ├── repository/
│       │   └── local/
│       ├── domain/usecase/
│       ├── presentation/
│       └── testutil/
│           ├── MainDispatcherExtension.kt
│           ├── TestFixtures.kt
│           └── FakeRepositories.kt
│
├── androidTest/                   # Instrumented tests
│   └── java/com/xax/CryptoSavingsTracker/
│       ├── HiltTestRunner.kt
│       ├── data/local/
│       ├── presentation/
│       └── e2e/
│
└── schemas/                       # Room schema exports
    └── com.xax.CryptoSavingsTracker.data.local.database.AppDatabase/
        ├── 1.json
        ├── 2.json
        └── ...
```

---

## 4. Data Layer

### 4.1 Room Database Configuration

```kotlin
@Database(
    entities = [
        GoalEntity::class,
        AssetEntity::class,
        TransactionEntity::class,
        AssetAllocationEntity::class,
        AllocationHistoryEntity::class,
        MonthlyPlanEntity::class,
        MonthlyExecutionRecordEntity::class,
        ExecutionSnapshotEntity::class,
        CompletedExecutionEntity::class
    ],
    version = 1,
    exportSchema = true,
    autoMigrations = []  // Manual migrations for control
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun goalDao(): GoalDao
    abstract fun assetDao(): AssetDao
    abstract fun transactionDao(): TransactionDao
    abstract fun allocationDao(): AllocationDao
    abstract fun allocationHistoryDao(): AllocationHistoryDao
    abstract fun monthlyPlanDao(): MonthlyPlanDao
    abstract fun executionRecordDao(): ExecutionRecordDao
    abstract fun executionSnapshotDao(): ExecutionSnapshotDao
    abstract fun completedExecutionDao(): CompletedExecutionDao
}
```

### 4.2 Entity Definitions with Constraints

```kotlin
/**
 * DATE vs TIMESTAMP STORAGE STRATEGY:
 *
 * - DATE-ONLY fields (deadline, startDate, firstReminderDate):
 *   Stored as Int using LocalDate.toEpochDay() - days since 1970-01-01.
 *   This avoids timezone shifting issues with midnight UTC.
 *
 * - TIMESTAMP fields (createdAt, lastModifiedAt, reminderTime):
 *   Stored as Long using epoch milliseconds UTC.
 *   These represent specific instants in time.
 */
@Entity(
    tableName = "goals",
    indices = [
        Index(value = ["name"], unique = false),
        Index(value = ["lifecycle_status"]),
        Index(value = ["deadline_epoch_day"])
    ]
)
data class GoalEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "currency")
    val currency: String,  // ISO 4217 or crypto symbol

    @ColumnInfo(name = "target_amount")
    val targetAmount: Double,

    // DATE-ONLY: Stored as epoch day (Int) to avoid timezone shifting
    // Use LocalDate.toEpochDay() to convert, LocalDate.ofEpochDay() to read
    @ColumnInfo(name = "deadline_epoch_day")
    val deadlineEpochDay: Int,

    @ColumnInfo(name = "start_date_epoch_day")
    val startDateEpochDay: Int,

    @ColumnInfo(name = "lifecycle_status")
    val lifecycleStatus: String,  // "active", "cancelled", "finished", "deleted"

    @ColumnInfo(name = "emoji")
    val emoji: String?,

    @ColumnInfo(name = "description")
    val description: String?,

    @ColumnInfo(name = "link")
    val link: String?,

    @ColumnInfo(name = "reminder_frequency")
    val reminderFrequency: String?,

    // TIMESTAMP: Specific time of day for reminder (epoch millis UTC)
    @ColumnInfo(name = "reminder_time_utc_millis")
    val reminderTimeUtcMillis: Long?,

    // DATE-ONLY: First reminder date (epoch day)
    @ColumnInfo(name = "first_reminder_epoch_day")
    val firstReminderEpochDay: Int?,

    // TIMESTAMPS: Audit fields (epoch millis UTC, no defaultValue - set in code)
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "asset_allocations",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = GoalEntity::class,
            parentColumns = ["id"],
            childColumns = ["goal_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["asset_id"]),
        Index(value = ["goal_id"]),
        Index(value = ["asset_id", "goal_id"], unique = true)  // Unique constraint
    ]
)
data class AssetAllocationEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,  // Must be >= 0

    // TIMESTAMPS: No defaultValue - set in Kotlin code
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "transactions",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["asset_id"]),
        Index(value = ["date_utc_millis"]),
        Index(value = ["external_id"], unique = true)  // Prevent duplicate imports
    ]
)
data class TransactionEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,  // Positive = deposit, Negative = withdrawal

    // TIMESTAMP: Transaction occurred at specific instant (epoch millis UTC)
    @ColumnInfo(name = "date_utc_millis")
    val dateUtcMillis: Long,

    @ColumnInfo(name = "source")
    val source: String,  // "manual" or "onChain"

    @ColumnInfo(name = "external_id")
    val externalId: String?,  // Blockchain tx hash (nullable, unique when present)

    @ColumnInfo(name = "counterparty")
    val counterparty: String?,

    @ColumnInfo(name = "comment")
    val comment: String?,

    // TIMESTAMP: No defaultValue - set in Kotlin code
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
```

### 4.3 Date & Timestamp Handling

```kotlin
/**
 * DATE vs TIMESTAMP STORAGE RULES
 *
 * DATE-ONLY FIELDS (deadline, startDate, firstReminderDate):
 *   - Stored as Int using LocalDate.toEpochDay() (days since 1970-01-01)
 *   - Timezone-agnostic: "2025-01-15" is the same epoch day everywhere
 *   - No risk of shifting across timezone boundaries
 *
 * TIMESTAMP FIELDS (createdAt, lastModifiedAt, reminderTime, transaction dates):
 *   - Stored as Long using epoch milliseconds UTC
 *   - Represents a specific instant in time
 *   - Converted to local timezone only for display
 *
 * MONTH LABELS (for execution tracking):
 *   - Stored as String "yyyy-MM" in UTC
 *   - Consistent across timezones for grouping
 */
object DateTimeUtils {

    // ========== DATE-ONLY CONVERSIONS (epoch day) ==========

    fun LocalDate.toEpochDayInt(): Int = this.toEpochDay().toInt()

    fun Int.toLocalDate(): LocalDate = LocalDate.ofEpochDay(this.toLong())

    // ========== TIMESTAMP CONVERSIONS (epoch millis) ==========

    fun Instant.toUtcMillis(): Long = this.toEpochMilli()

    fun Long.toInstant(): Instant = Instant.ofEpochMilli(this)

    fun Long.toLocalDateTime(zone: ZoneId = ZoneId.systemDefault()): LocalDateTime {
        return Instant.ofEpochMilli(this).atZone(zone).toLocalDateTime()
    }

    fun Long.toZonedDateTime(zone: ZoneId = ZoneId.systemDefault()): ZonedDateTime {
        return Instant.ofEpochMilli(this).atZone(zone)
    }

    // ========== MONTH LABEL UTILITIES ==========

    fun monthLabelFromMillis(millis: Long): String {
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM")
        return Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).format(formatter)
    }

    fun currentMonthLabel(): String = monthLabelFromMillis(System.currentTimeMillis())

    fun parseMonthLabel(label: String): YearMonth = YearMonth.parse(label)
}
```

### 4.4 Room Migration Strategy

```kotlin
object DatabaseMigrations {

    /**
     * Migration Strategy:
     *
     * 1. Schema versions are exported to /schemas/ directory
     * 2. Every migration has a corresponding test in DatabaseMigrationTest
     * 3. Destructive migrations are NEVER used for UPGRADES
     * 4. Large data migrations run in batches to avoid ANRs
     * 5. DOWNGRADES are unsupported in production:
     *    - Downgrading schema version implies rolling back to older app version
     *    - We use fallbackToDestructiveMigrationOnDowngrade() to wipe data
     *    - This is acceptable because:
     *      a) Downgrades only happen in dev (installing older APK over newer)
     *      b) Production users can't downgrade past Play Store's minimum version
     *      c) Data loss on downgrade is preferable to crash loops
     *
     * NOTE: The migrations below are TEMPLATES for future schema changes.
     * Initial release uses version = 1 with no migrations needed.
     * When you need to change the schema:
     *   1. Increment @Database(version = N)
     *   2. Add MIGRATION_(N-1)_N following the patterns below
     *   3. Add a test for the new migration
     */

    // === FUTURE MIGRATION TEMPLATES ===
    // Uncomment and modify when schema changes are needed

    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Example: Add new column with default value
            db.execSQL("""
                ALTER TABLE goals
                ADD COLUMN priority INTEGER NOT NULL DEFAULT 0
            """)
        }
    }

    val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Example: Create new table
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS goal_tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    goal_id TEXT NOT NULL,
                    tag TEXT NOT NULL,
                    FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE CASCADE
                )
            """)
            db.execSQL("CREATE INDEX IF NOT EXISTS index_goal_tags_goal_id ON goal_tags(goal_id)")
        }
    }

    // For complex migrations with data transformation
    val MIGRATION_3_4 = object : Migration(3, 4) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // 1. Create new table with updated schema
            db.execSQL("""
                CREATE TABLE goals_new (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    -- ... new schema
                )
            """)

            // 2. Copy data with transformation (batch for large tables)
            db.execSQL("""
                INSERT INTO goals_new (id, name, ...)
                SELECT id, name, ... FROM goals
            """)

            // 3. Drop old table
            db.execSQL("DROP TABLE goals")

            // 4. Rename new table
            db.execSQL("ALTER TABLE goals_new RENAME TO goals")

            // 5. Recreate indices
            db.execSQL("CREATE INDEX IF NOT EXISTS index_goals_deadline ON goals(deadline_epoch_day)")
        }
    }

    val ALL_MIGRATIONS = arrayOf(
        MIGRATION_1_2,
        MIGRATION_2_3,
        MIGRATION_3_4
    )
}

// DatabaseModule.kt
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "crypto_savings_tracker.db"
        )
        .addMigrations(*DatabaseMigrations.ALL_MIGRATIONS)
        .fallbackToDestructiveMigrationOnDowngrade()  // Only on downgrade
        .build()
    }
}
```

### 4.5 Migration Testing

```kotlin
@RunWith(AndroidJUnit4::class)
class DatabaseMigrationTest {

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java
    )

    @Test
    fun migrate1To2() {
        // Create database at version 1
        // Note: Column names must match GoalEntity schema exactly
        helper.createDatabase("test_db", 1).apply {
            execSQL("""
                INSERT INTO goals (
                    id, name, currency, target_amount,
                    deadline_epoch_day, start_date_epoch_day,
                    lifecycle_status, created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES (
                    'test-id', 'Test Goal', 'USD', 1000.0,
                    20089, 19724,  -- epochDay values (2025-01-01, 2024-01-01)
                    'active', 1704067200000, 1704067200000
                )
            """)
            close()
        }

        // Migrate to version 2
        val db = helper.runMigrationsAndValidate("test_db", 2, true, DatabaseMigrations.MIGRATION_1_2)

        // Verify data preserved and new column exists with default
        val cursor = db.query("SELECT priority FROM goals WHERE id = 'test-id'")
        assertTrue(cursor.moveToFirst())
        assertEquals(0, cursor.getInt(0))  // Default value
        cursor.close()
    }

    @Test
    fun migrateAllVersions() {
        helper.createDatabase("test_db", 1).close()
        helper.runMigrationsAndValidate(
            "test_db",
            AppDatabase.VERSION,
            true,
            *DatabaseMigrations.ALL_MIGRATIONS
        )
    }
}
```

---

## 5. Domain Layer

### 5.1 Domain Models

```kotlin
data class Goal(
    val id: String,
    val name: String,
    val currency: String,
    val targetAmount: Double,
    val deadline: LocalDate,
    val startDate: LocalDate,
    val lifecycleStatus: GoalLifecycleStatus,
    val emoji: String?,
    val description: String?,
    val link: String?,
    val reminderFrequency: ReminderFrequency?,
    val allocations: List<AssetAllocation> = emptyList()
) {
    val daysRemaining: Int
        get() = ChronoUnit.DAYS.between(LocalDate.now(), deadline).toInt()

    val isExpired: Boolean
        get() = daysRemaining < 0

    val isAchieved: Boolean
        get() = lifecycleStatus == GoalLifecycleStatus.FINISHED
}

data class MonthlyRequirement(
    val id: String,
    val goalId: String,
    val goalName: String,
    val currency: String,
    val targetAmount: Double,
    val currentTotal: Double,
    val remainingAmount: Double,
    val monthsRemaining: Int,
    val requiredMonthly: Double,
    val progress: Double,
    val deadline: LocalDate,
    val status: RequirementStatus
)
```

### 5.2 Key Use Cases

```kotlin
class CalculateMonthlyRequirementsUseCase @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) {
    suspend operator fun invoke(displayCurrency: String): List<MonthlyRequirement> {
        val goals = goalRepository.getActiveGoals().first()

        return goals.map { goal ->
            val currentTotal = calculateCurrentTotal(goal)
            val remainingAmount = (goal.targetAmount - currentTotal).coerceAtLeast(0.0)
            val monthsRemaining = calculateMonthsRemaining(goal.deadline)
            val requiredMonthly = if (monthsRemaining > 0) {
                remainingAmount / monthsRemaining
            } else 0.0

            val progress = if (goal.targetAmount > 0) {
                (currentTotal / goal.targetAmount).coerceIn(0.0, 1.0)
            } else 0.0

            MonthlyRequirement(
                id = UUID.randomUUID().toString(),
                goalId = goal.id,
                goalName = goal.name,
                currency = goal.currency,
                targetAmount = goal.targetAmount,
                currentTotal = currentTotal,
                remainingAmount = remainingAmount,
                monthsRemaining = monthsRemaining,
                requiredMonthly = requiredMonthly,
                progress = progress,
                deadline = goal.deadline,
                status = determineStatus(progress, monthsRemaining, remainingAmount)
            )
        }
    }
}
```

---

## 6. Presentation Layer

*(Section unchanged - see original)*

---

## 7. API & Security

### 7.1 API Key Management

```kotlin
/**
 * Secure API Key Storage using EncryptedSharedPreferences
 *
 * Keys are stored encrypted at rest using AES-256-GCM.
 * Master key is stored in Android Keystore (hardware-backed when available).
 */
@Singleton
class SecureApiKeyStorage @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val encryptedPrefs = EncryptedSharedPreferences.create(
        context,
        "secure_api_keys",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun getApiKey(key: ApiKeyType): String? {
        return encryptedPrefs.getString(key.prefKey, null)
    }

    fun setApiKey(key: ApiKeyType, value: String) {
        encryptedPrefs.edit().putString(key.prefKey, value).apply()
    }

    fun hasApiKey(key: ApiKeyType): Boolean {
        return encryptedPrefs.contains(key.prefKey)
    }

    enum class ApiKeyType(val prefKey: String) {
        COINGECKO("coingecko_api_key"),
        TATUM("tatum_api_key"),
        QUICKNODE("quicknode_api_key"),
        NOWNODES("nownodes_api_key")
    }
}

// Usage in DI Module
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideCoinGeckoApi(
        okHttpClient: OkHttpClient,
        apiKeyStorage: SecureApiKeyStorage
    ): CoinGeckoApi {
        return Retrofit.Builder()
            .baseUrl("https://api.coingecko.com/api/v3/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(CoinGeckoApi::class.java)
    }
}
```

### 7.2 API Key Injection via Interceptor

```kotlin
/**
 * Injects API keys into requests based on host.
 * Keys are loaded from secure storage, NOT hardcoded.
 */
class ApiKeyInterceptor @Inject constructor(
    private val apiKeyStorage: SecureApiKeyStorage
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val host = originalRequest.url.host

        val apiKey = when {
            host.contains("coingecko.com") ->
                apiKeyStorage.getApiKey(SecureApiKeyStorage.ApiKeyType.COINGECKO)
            host.contains("tatum.io") ->
                apiKeyStorage.getApiKey(SecureApiKeyStorage.ApiKeyType.TATUM)
            else -> null
        }

        val newRequest = if (apiKey != null) {
            val headerName = when {
                host.contains("coingecko.com") -> "x-cg-demo-api-key"
                host.contains("tatum.io") -> "x-api-key"
                else -> return chain.proceed(originalRequest)
            }
            originalRequest.newBuilder()
                .addHeader(headerName, apiKey)
                .build()
        } else {
            originalRequest
        }

        return chain.proceed(newRequest)
    }
}
```

### 7.3 Rate Limiting (Token Bucket Algorithm)

```kotlin
/**
 * Token Bucket Rate Limiter
 *
 * - CoinGecko free tier: 10 requests/minute
 * - Tatum free tier: 5 requests/second
 *
 * Uses suspend instead of Thread.sleep to avoid blocking.
 */
class TokenBucketRateLimiter(
    private val maxTokens: Int,
    private val refillRatePerSecond: Double
) {
    private var tokens: Double = maxTokens.toDouble()
    private var lastRefillTime: Long = System.nanoTime()
    private val mutex = Mutex()

    suspend fun acquire() {
        mutex.withLock {
            refill()
            while (tokens < 1.0) {
                val waitTime = ((1.0 - tokens) / refillRatePerSecond * 1000).toLong()
                delay(waitTime.coerceAtLeast(10))
                refill()
            }
            tokens -= 1.0
        }
    }

    private fun refill() {
        val now = System.nanoTime()
        val elapsed = (now - lastRefillTime) / 1_000_000_000.0
        tokens = (tokens + elapsed * refillRatePerSecond).coerceAtMost(maxTokens.toDouble())
        lastRefillTime = now
    }
}

// Rate limiters per API
@Module
@InstallIn(SingletonComponent::class)
object RateLimiterModule {

    @Provides
    @Singleton
    @Named("coingecko")
    fun provideCoinGeckoRateLimiter(): TokenBucketRateLimiter {
        // 10 requests per minute = 0.167 per second
        return TokenBucketRateLimiter(maxTokens = 10, refillRatePerSecond = 10.0 / 60.0)
    }

    @Provides
    @Singleton
    @Named("tatum")
    fun provideTatumRateLimiter(): TokenBucketRateLimiter {
        // 5 requests per second
        return TokenBucketRateLimiter(maxTokens = 5, refillRatePerSecond = 5.0)
    }
}

// Usage in Repository
class ExchangeRateRepositoryImpl @Inject constructor(
    private val api: CoinGeckoApi,
    @Named("coingecko") private val rateLimiter: TokenBucketRateLimiter,
    private val cache: ExchangeRateCache
) : ExchangeRateRepository {

    override suspend fun getExchangeRate(from: String, to: String): Result<Double> {
        // Check cache first (no rate limit consumed)
        cache.get(from, to)?.let { cached ->
            if (!cached.isExpired) return Result.success(cached.rate)
        }

        // Acquire rate limit token (suspends if needed)
        rateLimiter.acquire()

        return try {
            val response = api.getExchangeRates(from, to)
            val rate = response[from]?.get(to)
                ?: return Result.failure(RateNotFoundException(from, to))
            cache.put(from, to, rate)
            Result.success(rate)
        } catch (e: Exception) {
            // Return stale cache on error
            cache.get(from, to)?.let { Result.success(it.rate) }
                ?: Result.failure(e)
        }
    }
}
```

### 7.4 Network Security Configuration

```xml
<!-- res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>

    <!-- Pin certificates for critical APIs (optional but recommended) -->
    <domain-config>
        <domain includeSubdomains="true">api.coingecko.com</domain>
        <pin-set expiration="2025-12-31">
            <pin digest="SHA-256">AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</pin>
            <!-- Add backup pin -->
            <pin digest="SHA-256">BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=</pin>
        </pin-set>
    </domain-config>
</network-security-config>
```

---

## 8. Implementation Phases

### Phase 1: Foundation
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Project setup with Hilt, Room, Compose | `./gradlew build` succeeds |
| Database schema (all entities) | Schema exports to /schemas/1.json |
| Basic DAOs with tests | 100% DAO test coverage |
| Navigation structure | Can navigate between all placeholder screens |
| Theme + common components | Design tokens match iOS Figma |

**Exit Gate**: Demo navigation between screens, insert/query one Goal entity.

---

### Phase 2: Core Features
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Goal CRUD operations | Create, read, update, delete all work |
| Goals list screen | List loads, scrolls at 60fps, taps navigate |
| Goal detail screen | Shows all fields, edit navigates correctly |
| Asset CRUD | Same as Goal |
| Transaction recording | Can add manual deposit/withdrawal |
| Basic progress calculations | Progress matches iOS calculation |

**Exit Gate**: Create 10 goals with transactions, verify progress calculations match iOS app within 0.01%.

---

### Phase 3: Allocation System
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| AssetAllocation model | CRUD with unique constraint enforced |
| AllocationHistory snapshots | Snapshots created on allocation changes |
| Auto-allocation logic | Auto-allocates when asset has single goal |
| Over-allocation detection | Warning shown when over-allocated |
| Asset sharing UI | Can split asset across multiple goals |

**Exit Gate**: Allocate 1 asset to 3 goals, verify totals match, allocation history recorded.

---

### Phase 4: Monthly Planning
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Monthly requirements calculation | Calculations match iOS |
| Flex adjustment slider (0-150%) | Slider updates amounts in real-time |
| Protected/skipped goal flags | UI toggles persist and affect calculation |
| Custom amount override | Can set custom amount per goal |
| Planning UI complete | All components match iOS design |

**Exit Gate**: 5 goals with mixed flex states, flex slider adjusts correctly, amounts match iOS.

---

### Phase 5: Execution Tracking
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| MonthlyExecutionRecord management | State transitions work correctly |
| ExecutionSnapshot capture | Snapshot frozen at execution start |
| Timestamp-based progress derivation | Progress derived from transactions + allocations |
| 24-hour undo windows | Undo available within window, disabled after |
| CompletedExecution history | History persisted and viewable |
| Execution UI | All states displayed correctly |

**Exit Gate**: Full execution cycle (start → add transactions → complete), verify derived progress matches expected.

---

### Phase 6: API Integration
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| CoinGecko integration | Exchange rates fetched and cached |
| Tatum blockchain integration | Balances fetched for test addresses |
| Rate limiting | No 429 errors in normal usage |
| Caching | Cache hit ratio > 90% in typical usage |
| Fallback handling | Stale cache returned on API failure |

**Exit Gate**: Fetch rates for 10 currencies, verify cache works, simulate API failure and verify fallback.

---

### Phase 7: Dashboard & Polish
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Dashboard screen | Portfolio total, goal summary displayed |
| Charts (Vico) | Progress charts render correctly |
| Accessibility audit | TalkBack works on all screens |
| Performance optimization | Cold start < 2s, scroll 60fps |
| Edge case handling | Empty states, error states handled |

**Exit Gate**: Accessibility review pass, performance benchmarks met.

---

### Phase 8: Testing & Release
**Duration**: 3 weeks
**Staffing**: 1 Android developer + 0.5 QA

| Task | Exit Criteria |
|------|---------------|
| Unit test coverage | Domain layer > 80% coverage |
| UI tests | All critical journeys have tests |
| Migration tests | All Room migrations tested |
| Manual QA | Test matrix complete, no P0/P1 bugs |
| Beta release | Internal testing track published |
| Production release | Play Store approved |

**Exit Gate**: All acceptance criteria met (see Section 1.3).

---

## 9. Testing Strategy

### 9.1 Test Framework Setup

```kotlin
// JUnit 5 Extension for Main Dispatcher
@ExtendWith(MainDispatcherExtension::class)
class MonthlyPlanningViewModelTest {
    // Tests run on TestDispatcher
}

class MainDispatcherExtension : BeforeEachCallback, AfterEachCallback {
    private val testDispatcher = UnconfinedTestDispatcher()

    override fun beforeEach(context: ExtensionContext) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun afterEach(context: ExtensionContext) {
        Dispatchers.resetMain()
    }
}
```

### 9.2 Unit Tests (JUnit 5 + MockK + Turbine)

```kotlin
@ExtendWith(MainDispatcherExtension::class)
class MonthlyPlanningViewModelTest {

    private val calculateRequirementsUseCase = mockk<CalculateMonthlyRequirementsUseCase>()
    private val applyFlexAdjustmentUseCase = mockk<ApplyFlexAdjustmentUseCase>()
    private val preferencesDataStore = mockk<PreferencesDataStore> {
        every { displayCurrency } returns flowOf("USD")
    }

    private lateinit var viewModel: MonthlyPlanningViewModel

    @BeforeEach
    fun setup() {
        viewModel = MonthlyPlanningViewModel(
            calculateRequirementsUseCase = calculateRequirementsUseCase,
            applyFlexAdjustmentUseCase = applyFlexAdjustmentUseCase,
            monthlyPlanRepository = mockk(),
            preferencesDataStore = preferencesDataStore
        )
    }

    @Test
    fun `loadRequirements emits loading then success`() = runTest {
        // Given
        val mockRequirements = listOf(TestFixtures.createRequirement("goal1", 1000.0))
        coEvery { calculateRequirementsUseCase("USD") } returns mockRequirements

        // When & Then
        viewModel.uiState.test {
            assertThat(awaitItem().isLoading).isFalse()  // Initial

            viewModel.loadRequirements()

            assertThat(awaitItem().isLoading).isTrue()   // Loading
            assertThat(awaitItem().isLoading).isFalse()  // Success
        }

        viewModel.requirements.test {
            assertThat(awaitItem()).isEqualTo(mockRequirements)
        }
    }

    @Test
    fun `toggleProtected adds and removes goal from protected set`() {
        // When
        viewModel.toggleProtected("goal1")

        // Then
        assertThat(viewModel.uiState.value.protectedGoalIds).contains("goal1")

        // When toggled again
        viewModel.toggleProtected("goal1")

        // Then removed
        assertThat(viewModel.uiState.value.protectedGoalIds).doesNotContain("goal1")
    }
}
```

### 9.3 Network Testing (MockWebServer)

```kotlin
class ExchangeRateRepositoryTest {

    private lateinit var mockWebServer: MockWebServer
    private lateinit var api: CoinGeckoApi
    private lateinit var repository: ExchangeRateRepositoryImpl

    @BeforeEach
    fun setup() {
        mockWebServer = MockWebServer()
        mockWebServer.start()

        api = Retrofit.Builder()
            .baseUrl(mockWebServer.url("/"))
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(CoinGeckoApi::class.java)

        repository = ExchangeRateRepositoryImpl(
            api = api,
            rateLimiter = TokenBucketRateLimiter(10, 10.0),
            cache = InMemoryExchangeRateCache()
        )
    }

    @AfterEach
    fun teardown() {
        mockWebServer.shutdown()
    }

    @Test
    fun `getExchangeRate returns cached value on network error`() = runTest {
        // Given - prime cache
        mockWebServer.enqueue(MockResponse()
            .setBody("""{"bitcoin":{"usd":50000.0}}""")
            .setResponseCode(200))

        repository.getExchangeRate("BTC", "USD")

        // When - network fails
        mockWebServer.enqueue(MockResponse().setResponseCode(500))

        val result = repository.getExchangeRate("BTC", "USD")

        // Then - returns cached value
        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrNull()).isEqualTo(50000.0)
    }

    @Test
    fun `rate limiter prevents burst requests`() = runTest {
        repeat(15) {
            mockWebServer.enqueue(MockResponse()
                .setBody("""{"bitcoin":{"usd":50000.0}}""")
                .setResponseCode(200))
        }

        val startTime = System.currentTimeMillis()

        // Make 15 requests (rate limit is 10/minute)
        repeat(15) {
            repository.getExchangeRate("BTC", "USD")
        }

        val elapsed = System.currentTimeMillis() - startTime

        // Should take at least 30 seconds for 15 requests at 10/min
        // (Actually less due to initial bucket, but > 0)
        assertThat(elapsed).isGreaterThan(0)
    }
}
```

### 9.4 UI Tests (Compose Testing)

**Running UI Tests:**
```bash
# Run all instrumented tests (includes Compose UI tests)
./gradlew connectedDebugAndroidTest

# Run a specific test class
./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.xax.CryptoSavingsTracker.GoalsListScreenTest
```

**Required Dependencies** (already included in Section 2):
- `androidTestImplementation("androidx.compose.ui:ui-test-junit4")` - Compose test APIs
- `debugImplementation("androidx.compose.ui:ui-test-manifest")` - Required for createAndroidComposeRule
- `androidTestImplementation("com.google.dagger:hilt-android-testing:2.52")` - Hilt test support

```kotlin
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class GoalsListScreenTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var goalRepository: GoalRepository

    @Before
    fun setup() {
        hiltRule.inject()
    }

    @Test
    fun goalsListDisplaysGoals() = runTest {
        // Given
        val goal = TestFixtures.createGoal(name = "Buy a car")
        goalRepository.insert(goal)

        // Navigate to goals list
        composeRule.onNodeWithText("Goals").performClick()

        // Then
        composeRule.onNodeWithText("Buy a car").assertIsDisplayed()
    }

    @Test
    fun tapGoalNavigatesToDetail() = runTest {
        // Given
        val goal = TestFixtures.createGoal(name = "Vacation fund")
        goalRepository.insert(goal)

        composeRule.onNodeWithText("Goals").performClick()

        // When
        composeRule.onNodeWithText("Vacation fund").performClick()

        // Then - verify on detail screen
        composeRule.onNodeWithTag("goal_detail_screen").assertIsDisplayed()
    }
}
```

### 9.5 E2E Test Harness

```kotlin
/**
 * End-to-end test for complete monthly planning flow.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class MonthlyPlanningE2ETest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun completeMonthlyPlanningFlow() {
        // 1. Create goals
        composeRule.onNodeWithContentDescription("Add goal").performClick()
        composeRule.onNodeWithTag("goal_name_input").performTextInput("Emergency Fund")
        composeRule.onNodeWithTag("goal_amount_input").performTextInput("10000")
        composeRule.onNodeWithText("Save").performClick()

        // 2. Add assets with transactions
        composeRule.onNodeWithText("Assets").performClick()
        composeRule.onNodeWithContentDescription("Add asset").performClick()
        // ... add asset flow

        // 3. Go to Monthly Planning
        composeRule.onNodeWithText("Planning").performClick()

        // 4. Verify requirements calculated
        composeRule.onNodeWithText("Emergency Fund").assertIsDisplayed()
        composeRule.onNodeWithTextContaining("$/month").assertIsDisplayed()

        // 5. Adjust flex slider
        composeRule.onNodeWithTag("flex_slider").performTouchInput {
            swipeRight()
        }

        // 6. Start tracking
        composeRule.onNodeWithText("Start Tracking").performClick()

        // 7. Verify execution screen
        composeRule.onNodeWithTag("execution_screen").assertIsDisplayed()
        composeRule.onNodeWithText("Executing").assertIsDisplayed()
    }
}
```

### 9.6 CI/CD Integration

```yaml
# .github/workflows/android-tests.yml
name: Android Tests

on:
  push:
    paths: ['android/**']
  pull_request:
    paths: ['android/**']

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Run unit tests
        working-directory: android
        run: ./gradlew testDebugUnitTest

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: unit-test-results
          path: android/app/build/reports/tests/

  instrumented-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Enable KVM (for emulator)
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Run instrumented tests
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: x86_64
          script: cd android && ./gradlew connectedDebugAndroidTest
```

```kotlin
// HiltTestRunner.kt - Required for Hilt instrumented tests
package com.xax.CryptoSavingsTracker

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner
import dagger.hilt.android.testing.HiltTestApplication

class HiltTestRunner : AndroidJUnitRunner() {
    override fun newApplication(
        cl: ClassLoader?,
        className: String?,
        context: Context?
    ): Application {
        return super.newApplication(cl, HiltTestApplication::class.java.name, context)
    }
}
```

---

## 10. Platform-Specific Considerations

### Android-Specific Features (v1.0)
- **Material You**: Dynamic theming from wallpaper colors
- **Notifications**: Reminder notifications via WorkManager
- **Edge-to-edge**: Full edge-to-edge display support

### Deferred to v1.1+
- Home screen widgets
- Wear OS companion
- Biometric app lock
- Tablet landscape layouts

---

## 11. CSV Export Format Specification

CSV export **must match iOS format exactly** for cross-platform data exchange compatibility.

**iOS exports 3 files:**
1. `goals.csv` - with allocations embedded as JSON
2. `assets.csv` - with allocations embedded as JSON
3. `value_changes.csv` - combined transactions and allocation history events

### 11.1 goals.csv

```csv
id,name,currency,targetAmount,deadline,startDate,lifecycleStatusRawValue,lifecycleStatusChangedAt,lastModifiedDate,reminderFrequency,reminderTime,firstReminderDate,emoji,goalDescription,link,allocationCount,allocationIds,allocationsJson
"uuid-1","Emergency Fund","USD",10000.0,"2024-01-01T00:00:00.000Z","2024-01-01T00:00:00.000Z","active","","2024-03-15T10:00:00.000Z","monthly","","","💰","6 months expenses","",2,"alloc-1;alloc-2","[{...}]"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| id | String | UUID | Primary key |
| name | String | UTF-8 | Goal name |
| currency | String | ISO 4217 / crypto | e.g., "USD", "BTC" |
| targetAmount | Double | Full precision | Target value |
| deadline | String | ISO 8601 | Full timestamp with fractional seconds |
| startDate | String | ISO 8601 | Full timestamp |
| lifecycleStatusRawValue | String | Enum | "active", "cancelled", "finished", "deleted" |
| lifecycleStatusChangedAt | String | ISO 8601 | Optional |
| lastModifiedDate | String | ISO 8601 | Last update |
| reminderFrequency | String | Enum | Optional: "daily", "weekly", "monthly" |
| reminderTime | String | ISO 8601 | Optional |
| firstReminderDate | String | ISO 8601 | Optional |
| emoji | String | UTF-8 emoji | Optional |
| goalDescription | String | UTF-8 | Optional |
| link | String | URL | Optional |
| allocationCount | Int | Count | Number of allocations |
| allocationIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationsJson | String | JSON array | Embedded allocation objects |

### 11.2 assets.csv

```csv
id,currency,address,chainId,transactionCount,transactionIds,allocationCount,allocationIds,allocationsJson
"uuid-1","BTC","bc1q...xyz","bitcoin",5,"tx-1;tx-2;tx-3;tx-4;tx-5",2,"alloc-1;alloc-2","[{...}]"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| id | String | UUID | Primary key |
| currency | String | Symbol | e.g., "BTC", "ETH", "USD" |
| address | String | Blockchain address | Optional, empty for fiat |
| chainId | String | Chain identifier | Optional, empty for fiat |
| transactionCount | Int | Count | Number of transactions |
| transactionIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationCount | Int | Count | Number of allocations |
| allocationIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationsJson | String | JSON array | Embedded allocation objects |

### 11.3 value_changes.csv

Combines transactions and allocation history into a single chronological event stream.

```csv
eventType,eventId,timestamp,amount,amountSemantics,assetId,assetCurrency,assetChainId,assetAddress,goalId,goalName,transactionSource,transactionExternalId,transactionCounterparty,transactionComment,allocationMonthLabel,allocationCreatedAt
"transaction","tx-uuid-1","2024-03-15T09:00:00.000Z",0.05,"delta","asset-uuid-1","BTC","bitcoin","bc1q...","","","manual","","","Monthly DCA","",""
"allocationHistory","ah-uuid-1","2024-03-15T10:00:00.000Z",5000.0,"allocationTargetSnapshot","asset-uuid-1","BTC","bitcoin","bc1q...","goal-uuid-1","Emergency Fund","","","","","2024-03","2024-03-15T10:00:00.000Z"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| eventType | String | Enum | "transaction" or "allocationHistory" |
| eventId | String | UUID | Event ID |
| timestamp | String | ISO 8601 | Event timestamp |
| amount | Double | Full precision | Transaction delta or allocation snapshot |
| amountSemantics | String | Enum | "delta" (tx) or "allocationTargetSnapshot" (history) |
| assetId | String | UUID | Asset reference |
| assetCurrency | String | Symbol | Asset currency |
| assetChainId | String | Chain ID | Optional |
| assetAddress | String | Address | Optional |
| goalId | String | UUID | Only for allocationHistory |
| goalName | String | UTF-8 | Only for allocationHistory |
| transactionSource | String | Enum | "manual" or "onChain" (tx only) |
| transactionExternalId | String | Tx hash | On-chain tx hash (tx only) |
| transactionCounterparty | String | UTF-8 | Optional (tx only) |
| transactionComment | String | UTF-8 | Optional (tx only) |
| allocationMonthLabel | String | "yyyy-MM" | Month label (history only) |
| allocationCreatedAt | String | ISO 8601 | Creation time (history only) |

### 11.4 Allocations JSON Schema (embedded in goals.csv and assets.csv)

```json
[
  {
    "id": "uuid",
    "amount": 5000.0,
    "createdDate": "2024-01-15T10:00:00.000Z",
    "lastModifiedDate": "2024-03-15T10:00:00.000Z",
    "assetId": "asset-uuid",
    "goalId": "goal-uuid",
    "assetCurrency": "BTC",
    "goalName": "Emergency Fund"
  }
]
```

### 11.5 Export Implementation

```kotlin
class CsvExportService @Inject constructor(
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository
) {
    private val isoFormatter = DateTimeFormatter.ISO_INSTANT

    /**
     * Exports 3 files matching iOS format:
     * - goals.csv (with embedded allocations JSON)
     * - assets.csv (with embedded allocations JSON)
     * - value_changes.csv (combined transactions + allocation history)
     */
    suspend fun exportAll(outputDir: File): List<File> {
        val goals = goalRepository.getAllGoals().first()
        val assets = assetRepository.getAllAssets().first()
        val transactions = transactionRepository.getAllTransactions().first()
        val allocationHistories = allocationHistoryRepository.getAll().first()

        val timestamp = Instant.now().toString()
            .replace(":", "-").replace(".", "-")
        val exportDir = File(outputDir, "CryptoSavingsTracker-CSV-$timestamp")
        exportDir.mkdirs()

        return listOf(
            exportGoals(goals, File(exportDir, "goals.csv")),
            exportAssets(assets, File(exportDir, "assets.csv")),
            exportValueChanges(transactions, allocationHistories, goals, assets,
                File(exportDir, "value_changes.csv"))
        )
    }

    private fun exportGoals(goals: List<Goal>, file: File): File {
        val header = "id,name,currency,targetAmount,deadline,startDate," +
            "lifecycleStatusRawValue,lifecycleStatusChangedAt,lastModifiedDate," +
            "reminderFrequency,reminderTime,firstReminderDate,emoji,goalDescription,link," +
            "allocationCount,allocationIds,allocationsJson"

        file.bufferedWriter().use { writer ->
            writer.write(header + "\n")
            goals.forEach { goal ->
                val allocationIds = goal.allocations.joinToString(";") { it.id }
                val allocationsJson = Json.encodeToString(goal.allocations.map { it.toExportDto() })
                writer.write(csvLine(
                    goal.id, goal.name, goal.currency, goal.targetAmount.toString(),
                    goal.deadline.format(isoFormatter), goal.startDate.format(isoFormatter),
                    goal.lifecycleStatus.name.lowercase(), goal.lifecycleStatusChangedAt?.format(isoFormatter) ?: "",
                    goal.lastModifiedDate.format(isoFormatter),
                    goal.reminderFrequency ?: "", goal.reminderTime?.format(isoFormatter) ?: "",
                    goal.firstReminderDate?.format(isoFormatter) ?: "",
                    goal.emoji ?: "", goal.description ?: "", goal.link ?: "",
                    goal.allocations.size.toString(), allocationIds, allocationsJson
                ))
            }
        }
        return file
    }

    private fun exportValueChanges(
        transactions: List<Transaction>,
        histories: List<AllocationHistory>,
        goals: List<Goal>,
        assets: List<Asset>,
        file: File
    ): File {
        val goalNameById = goals.associate { it.id to it.name }
        val assetById = assets.associateBy { it.id }

        data class Event(val timestamp: Instant, val row: List<String>)
        val events = mutableListOf<Event>()

        // Add transaction events
        transactions.forEach { tx ->
            val asset = assetById[tx.assetId]
            events += Event(tx.date, listOf(
                "transaction", tx.id, tx.date.format(isoFormatter), tx.amount.toString(), "delta",
                tx.assetId, asset?.currency ?: "", asset?.chainId ?: "", asset?.address ?: "",
                "", "", tx.source.name.lowercase(), tx.externalId ?: "",
                tx.counterparty ?: "", tx.comment ?: "", "", ""
            ))
        }

        // Add allocation history events
        histories.forEach { history ->
            val asset = assetById[history.assetId]
            val goalName = goalNameById[history.goalId] ?: ""
            events += Event(history.timestamp, listOf(
                "allocationHistory", history.id, history.timestamp.format(isoFormatter),
                history.amount.toString(), "allocationTargetSnapshot",
                history.assetId, asset?.currency ?: "", asset?.chainId ?: "", asset?.address ?: "",
                history.goalId, goalName, "", "", "", "", history.monthLabel,
                history.createdAt.format(isoFormatter)
            ))
        }

        // Sort chronologically and write
        val header = "eventType,eventId,timestamp,amount,amountSemantics,assetId,assetCurrency," +
            "assetChainId,assetAddress,goalId,goalName,transactionSource,transactionExternalId," +
            "transactionCounterparty,transactionComment,allocationMonthLabel,allocationCreatedAt"

        file.bufferedWriter().use { writer ->
            writer.write(header + "\n")
            events.sortedBy { it.timestamp }.forEach { event ->
                writer.write(csvLine(*event.row.toTypedArray()))
            }
        }
        return file
    }

    private fun csvLine(vararg values: String): String {
        return values.joinToString(",") { value ->
            if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
                "\"${value.replace("\"", "\"\"")}\""
            } else value
        } + "\n"
    }
}
```

---

## Appendix: iOS-Android Model Mapping

| iOS (SwiftData) | Android (Room) | Notes |
|-----------------|----------------|-------|
| `@Model` | `@Entity` | Class annotation |
| `@Attribute(.unique)` | `@Index(unique = true)` | Unique constraint |
| `@Relationship` | `@ForeignKey` + `@Relation` | Relationships |
| `#Predicate` | `@Query` with SQL | Filtering |
| `Codable` (JSON) | `@TypeConverter` | Complex types |
| `UUID` | `String` (UUID.toString()) | ID storage |
| `Date` (date-only) | `Int` (epochDay) | Use `LocalDate.toEpochDay()` |
| `Date` (timestamp) | `Long` (epochMillis) | Use `Instant.toEpochMilli()` |

---

*Last Updated: December 2024*
