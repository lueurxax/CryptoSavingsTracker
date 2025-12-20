package com.xax.CryptoSavingsTracker.presentation.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.xax.CryptoSavingsTracker.presentation.assets.AssetsScreen
import com.xax.CryptoSavingsTracker.presentation.dashboard.DashboardScreen
import com.xax.CryptoSavingsTracker.presentation.goals.GoalsScreen
import com.xax.CryptoSavingsTracker.presentation.planning.PlanningScreen

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: ImageVector
)

val bottomNavItems = listOf(
    BottomNavItem(Screen.Dashboard, "Dashboard", Icons.Default.Dashboard),
    BottomNavItem(Screen.Goals, "Goals", Icons.Default.Flag),
    BottomNavItem(Screen.Assets, "Assets", Icons.Default.AccountBalance),
    BottomNavItem(Screen.Planning, "Planning", Icons.Default.CalendarMonth)
)

@Composable
fun AppNavHost() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    // Determine if we should show bottom nav (only on main tabs)
    val showBottomNav = bottomNavItems.any { item ->
        currentDestination?.hierarchy?.any { it.route == item.screen.route } == true
    }

    Scaffold(
        bottomBar = {
            if (showBottomNav) {
                NavigationBar {
                    bottomNavItems.forEach { item ->
                        NavigationBarItem(
                            icon = { Icon(item.icon, contentDescription = item.label) },
                            label = { Text(item.label) },
                            selected = currentDestination?.hierarchy?.any { it.route == item.screen.route } == true,
                            onClick = {
                                navController.navigate(item.screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Dashboard.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            // Main tabs
            composable(Screen.Dashboard.route) {
                DashboardScreen(navController = navController)
            }
            composable(Screen.Goals.route) {
                GoalsScreen(navController = navController)
            }
            composable(Screen.Assets.route) {
                AssetsScreen(navController = navController)
            }
            composable(Screen.Planning.route) {
                PlanningScreen(navController = navController)
            }

            // TODO: Add detail screens as we implement them
        }
    }
}
