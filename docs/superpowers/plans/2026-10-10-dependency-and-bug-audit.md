# Dependency Update and Bug Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update compatible dependencies and identify reproducible defects in the current Apple and Android apps.

**Architecture:** Keep the existing Apple framework-only build and the Android version catalog. Preserve the current SDK and build-plugin generation, and make only compatibility changes required by dependency upgrades. Audit existing application behavior separately from the dependency patch.

**Tech Stack:** Swift/SwiftUI/SwiftData, XCTest/Swift Testing, Kotlin/Compose/Room/Hilt, Gradle, JUnit.

**Spec:** User request: "Обнови зависимости и поищи баги"; repository `AGENTS.md`.

## Global Constraints

- Preserve all pre-existing staged and unstaged changes.
- Keep Android compile/target SDK 36, min SDK 34 and AGP 8.13.2.
- Select published stable versions whose compiler and AAR requirements fit the existing build.
- Do not disable, skip, or comment out failing tests.
- Do not read, print, modify, or commit credentials.
- Leave confirmed application bugs as findings unless a fix is required for the dependency update or test run.

## Review Focus

- Mixed asset/goal currencies must not be compared or summed as identical units.
- Reapplying flex adjustments must not multiply an already-adjusted amount.
- Removing a skip must restore the effective planned amount.
- Multi-page balance responses must not treat absence on the first page as a zero balance.
- Both JUnit generations must participate in the Android unit-test run.

## Task 1: Establish baseline and dependency constraints

**Files:** Read `ios/Package.swift`, `ios/CryptoSavingsTracker.xcodeproj/project.pbxproj`, `android/gradle/libs.versions.toml`, `android/app/build.gradle.kts`.

- [x] Capture source-file and index fingerprints before edits.
- [x] Run the Apple unit-test scheme and Android unit tests/debug assembly.
- [x] Query official Maven metadata and inspect AAR/compiler requirements.
- [x] Separate dependency compatibility issues from existing application defects.

## Task 2: Apply and verify compatible updates

**Files:** Modify `android/gradle/libs.versions.toml`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, and the converter import in `android/app/src/main/java/com/xax/CryptoSavingsTracker/di/NetworkModule.kt`. Apply required compiler/API compatibility changes in `DatabaseMigrations.kt`, `DatabaseMigrationTest.kt` and `DashboardScreen.kt`. Repair lint blockers in `HeatmapCalendar.kt`, `MonthlyPlanningContainer.kt` and `GoalReminderWorker.kt`. Repair the two reproduced Apple test defects without weakening their assertions.

- [x] Upgrade Gradle to 8.14.6 with its verified checksum, Kotlin to 2.3.21, KSP to 2.3.12 and compatible runtime/test libraries.
- [x] Replace the archived serialization converter with Retrofit's maintained converter.
- [x] Include JUnit Vintage and the platform launcher so existing JUnit 4 tests run.
- [x] Replace the rate-drift test's yield-count polling with event-based waiting; make the camera contract independent of directive indentation.
- [x] Fix compiler diagnostics without changing SQL bindings or chart spacing; fix four lint errors without suppressions.
- [x] Run complete Apple and Android unit suites, Android debug and instrumentation assembly, and lint; inspect failures before any repair.

## Task 3: Verify findings and deliver reviewable evidence

**Files:** Create `docs/reports/2026-10-10-dependencies-and-bugs.md`.

- [x] Independently run deterministic reproductions and inspect their source/consumer paths.
- [x] Record dependency versions, held migrations, confirmed bugs and verification limits.
- [x] Obtain a fresh review of the dependency patch, including later compiler and lint repairs.
- [x] Check task additions for whitespace, compare original-file fingerprints and confirm the index is unchanged. Whole-worktree whitespace findings predate this task.

## Execution Note

The requested maintenance is reversible and already authorized. Changes are made in the existing checkout so the audit includes the user's current worktree; there is no reset, stash, branch publication or commit.
