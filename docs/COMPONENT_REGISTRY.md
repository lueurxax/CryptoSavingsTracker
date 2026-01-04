# Component Registry

> Registry of reusable UI components in the iOS/macOS codebase

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-01-04 |
| Platform | iOS |
| Audience | Developers |

---

This document provides a registry of all reusable UI components in the CryptoSavingsTracker project.

## Components

### ChartErrorView

*   **File**: `/Views/Components/ChartErrorView.swift`
*   **Purpose**: A view that displays an error message for a chart.
*   **Dependencies**: `ChartError`, `AccessibleColors`

### CompactChartErrorView

*   **File**: `/Views/Components/ChartErrorView.swift`
*   **Purpose**: A compact version of the `ChartErrorView` for smaller spaces.
*   **Dependencies**: `ChartError`, `AccessibleColors`

### DashboardMetricsGrid

*   **File**: `/Views/Components/DashboardMetricsGrid.swift`
*   **Purpose**: A grid of metric cards that displays key information about a goal.
*   **Dependencies**: `Goal`, `GoalCalculationService`, `AccessibleColors`

### MetricCard

*   **File**: `/Views/Components/DashboardMetricsGrid.swift`
*   **Purpose**: A card that displays a single metric.
*   **Dependencies**: `AccessibleColors`

### EmojiPickerView

*   **File**: `/Views/Components/EmojiPickerView.swift`
*   **Purpose**: A view that allows the user to pick an emoji.
*   **Dependencies**: `AccessibleColors`

### EmptyDetailView

*   **File**: `/Views/Components/EmptyDetailView.swift`
*   **Purpose**: A view that is displayed when no goal is selected in the detail pane.
*   **Dependencies**: `MonthlyPlanningWidget`

### EmptyGoalsView

*   **File**: `/Views/Components/EmptyGoalsView.swift`
*   **Purpose**: A view that is displayed when there are no goals.
*   **Dependencies**: None

### FlexAdjustmentSlider

*   **File**: `/Views/Components/FlexAdjustmentSlider.swift`
*   **Purpose**: An interactive slider that allows the user to adjust the monthly payment for all flexible goals.
*   **Dependencies**: `MonthlyPlanningViewModel`, `FlexAdjustmentService`, `AccessibleColors`, `AccessibilityManager`

### GoalsSidebarView

*   **File**: `/Views/Components/GoalsSidebarView.swift`
*   **Purpose**: A sidebar view for macOS that displays a list of goals.
*   **Dependencies**: `UnifiedGoalRowView`

### GoalSidebarContextMenu

*   **File**: `/Views/Components/GoalsSidebarView.swift`
*   **Purpose**: A context menu for the goal actions in the sidebar.
*   **Dependencies**: None

### GoalSwitcherBar

*   **File**: `/Views/Components/GoalSwitcherBar.swift`
*   **Purpose**: A horizontal bar that allows the user to switch between goals.
*   **Dependencies**: `Goal`, `GoalCalculationService`, `AccessibleColors`

### GoalPill

*   **File**: `/Views/Components/GoalSwitcherBar.swift`
*   **Purpose**: A pill-shaped view that displays a summary of a goal.
*   **Dependencies**: `Goal`, `GoalCalculationService`, `AccessibleColors`

### EmptyGoalSwitcher

*   **File**: `/Views/Components/GoalSwitcherBar.swift`
*   **Purpose**: A view that is displayed when there are no goals to switch between.
*   **Dependencies**: `AccessibleColors`

### HelpTooltip

*   **File**: `/Views/Components/HelpTooltip.swift`
*   **Purpose**: A reusable tooltip component that provides contextual help for metrics and UI elements.
*   **Dependencies**: `AccessibleColors`

### TooltipContent

*   **File**: `/Views/Components/HelpTooltip.swift`
*   **Purpose**: The content view for the tooltip popover.
*   **Dependencies**: `AccessibleColors`

### MetricTooltips

*   **File**: `/Views/Components/HelpTooltip.swift`
*   **Purpose**: A struct that provides predefined tooltip content for common metrics.
*   **Dependencies**: `HelpTooltip`

### HoverTooltipView

*   **File**: `/Views/Components/HoverTooltipView.swift`
*   **Purpose**: A view that displays a tooltip when the user hovers over it.
*   **Dependencies**: `AccessibleColors`

### ImpactPreviewCard

*   **File**: `/Views/Components/ImpactPreviewCard.swift`
*   **Purpose**: A card that displays a preview of the impact of a change to a goal.
*   **Dependencies**: `GoalImpact`, `AccessibleColors`

### MonthlyPlanningWidget

*   **File**: `/Views/Components/MonthlyPlanningWidget.swift`
*   **Purpose**: A widget that displays the monthly savings requirements.
*   **Dependencies**: `MonthlyPlanningViewModel`, `AccessibleColors`, `AccessibilityManager`

### ChangeRow

*   **File**: `/Views/Components/ImpactPreviewCard.swift`
*   **Purpose**: A row that displays a change in a value.
*   **Dependencies**: `AccessibleColors`

### CircularProgressView

*   **File**: `/Views/Components/ImpactPreviewCard.swift`
*   **Purpose**: A circular progress view.
*   **Dependencies**: None

### ReminderConfigurationView

*   **File**: `/Views/Components/ReminderConfigurationView.swift`
*   **Purpose**: A view that allows the user to configure reminders for a goal.
*   **Dependencies**: `ReminderFrequency`, `AccessibleColors`

### HeroProgressView

*   **File**: `/Views/Components/HeroProgressView.swift`
*   **Purpose**: A view that displays the progress of a goal in a prominent way.
*   **Dependencies**: `Goal`, `GoalCalculationService`, `AccessibleColors`

### CompactMetric

*   **File**: `/Views/Components/HeroProgressView.swift`
*   **Purpose**: A compact view that displays a single metric.
*   **Dependencies**: `AccessibleColors`

### EmptyStateView

*   **File**: `/Views/Components/EmptyStateView.swift`
*   **Purpose**: A generic empty state view that can be customized with an icon, title, description, and actions.
*   **Dependencies**: `AccessibleColors`, `OnboardingManager`

### ExchangeRateWarningView

*   **File**: `/Views/Components/ExchangeRateWarningView.swift`
*   **Purpose**: A view that displays a warning when exchange rates are unavailable.
*   **Dependencies**: None

### ExchangeRateStatusBadge

*   **File**: `/Views/Components/ExchangeRateWarningView.swift`
*   **Purpose**: A badge that indicates the status of the exchange rates.
*   **Dependencies**: `DIContainer`
