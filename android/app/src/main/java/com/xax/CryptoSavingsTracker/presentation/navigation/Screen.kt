package com.xax.CryptoSavingsTracker.presentation.navigation

/**
 * Navigation routes for the app.
 */
sealed class Screen(val route: String) {
    // Main tabs
    data object Dashboard : Screen("dashboard")
    data object Goals : Screen("goals")
    data object Assets : Screen("assets")
    data object Planning : Screen("planning")

    // Goal screens
    data object GoalDetail : Screen("goal/{goalId}") {
        fun createRoute(goalId: String) = "goal/$goalId"
    }
    data object AddGoal : Screen("goal/add")
    data object EditGoal : Screen("goal/{goalId}/edit") {
        fun createRoute(goalId: String) = "goal/$goalId/edit"
    }

    // Asset screens
    data object AssetDetail : Screen("asset/{assetId}") {
        fun createRoute(assetId: String) = "asset/$assetId"
    }
    data object AddAsset : Screen("asset/add")
    data object EditAsset : Screen("asset/{assetId}/edit") {
        fun createRoute(assetId: String) = "asset/$assetId/edit"
    }

    // Transaction screens
    data object AddTransaction : Screen("asset/{assetId}/transaction/add") {
        fun createRoute(assetId: String) = "asset/$assetId/transaction/add"
    }
    data object TransactionHistory : Screen("asset/{assetId}/transactions") {
        fun createRoute(assetId: String) = "asset/$assetId/transactions"
    }

    // Planning screens
    data object MonthlyPlanning : Screen("planning/monthly")
    data object Execution : Screen("planning/execution")
    data object PlanHistory : Screen("planning/history")

    // Settings
    data object Settings : Screen("settings")
}
