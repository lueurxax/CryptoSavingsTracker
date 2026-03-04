package com.xax.CryptoSavingsTracker.presentation.navigation

import com.google.common.truth.Truth.assertThat
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.jupiter.api.Test

class GoalDashboardNavigationContractTest {
    @Test
    fun goalDashboardRoute_isCanonicalAndParameterized() {
        assertThat(Screen.GoalDashboard.route).isEqualTo("goal/{goalId}/dashboard")
        assertThat(Screen.GoalDashboard.createRoute("abc123")).isEqualTo("goal/abc123/dashboard")
    }

    @Test
    fun goalDashboardRoute_hasNoRuntimeFallbackVariants() {
        val route = Screen.GoalDashboard.route
        assertThat(route).doesNotContain("legacy")
        assertThat(route).doesNotContain("v2")
        assertThat(route).doesNotContain("toggle")
    }

    @Test
    fun goalDetailIsCanonicalEntryPointToGoalDashboard() {
        val root = repositoryRoot()
        val goalDetailSource = readSource(
            root,
            "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/GoalDetailScreen.kt"
        )
        val navHostSource = readSource(
            root,
            "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt"
        )

        assertThat(goalDetailSource).contains("Screen.GoalDashboard.createRoute")
        assertThat(navHostSource).contains("route = Screen.GoalDashboard.route")
    }

    @Test
    fun productionPathContainsNoLegacyGoalDashboardRoute() {
        val root = repositoryRoot()
        val screenSource = readSource(
            root,
            "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/Screen.kt"
        )
        val navHostSource = readSource(
            root,
            "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt"
        )

        assertThat(screenSource).doesNotContain("goal_dashboard_v2_enabled")
        assertThat(screenSource).doesNotContain("goal/legacy-dashboard")
        assertThat(navHostSource).doesNotContain("goal_dashboard_v2_enabled")
        assertThat(navHostSource).doesNotContain("legacy-dashboard")
    }

    private fun repositoryRoot(): Path {
        var current = Paths.get(System.getProperty("user.dir")).toAbsolutePath()
        repeat(6) {
            if (Files.exists(current.resolve("android")) && Files.exists(current.resolve("ios"))) {
                return current
            }
            current = current.parent ?: return current
        }
        return Paths.get(System.getProperty("user.dir")).toAbsolutePath()
    }

    private fun readSource(root: Path, relativePath: String): String {
        val absolutePath = root.resolve(relativePath).normalize()
        return String(Files.readAllBytes(absolutePath))
    }
}
