# iOS UI Kit

Interactive HTML recreation of CryptoSavingsTracker's iOS surface. Pixel‑adjacent (not pixel‑perfect) reproductions of the three primary screens.

## Screens

| Screen | Source | File |
|---|---|---|
| Goals list | `ios/.../GoalsListView.swift` + `Shared/UnifiedGoalRowView.swift` | `GoalsListScreen.jsx` |
| Goal dashboard | `ios/.../Dashboard/GoalDashboardScreen.swift` | `GoalDashboardScreen.jsx` |
| Monthly plan | `ios/.../Planning/MonthlyPlanningContainer.swift` + `CompactGoalRequirementRow.swift` | `MonthlyPlanningScreen.jsx` |
| Log contribution sheet | `Views/AddTransactionView.swift` | `LogContributionSheet.jsx` |

Device chrome uses the shared `ios-frame.jsx` starter.

## What's working

- Tap a goal in the list → opens that goal's dashboard (with back nav)
- "Log" on the dashboard → opens the bottom‑sheet
- Sliders in the Monthly Plan screen adjust live totals and the % of income indicator
- Dark mode toggle (bottom right of page)
- Tab bar switches between Goals / Plan / Forecast / Profile

## What's intentionally skipped

- Forecast and Profile tabs are stubbed — the kit focuses on the dashboard + planning loop
- Family Sharing, Onboarding, What‑If scenarios, Heatmap Calendar
- Real currency conversion / live rate indicators

These surfaces exist in the codebase but weren't included in this slice. See the file index in the root repo tree for pointers if you want to extend.
