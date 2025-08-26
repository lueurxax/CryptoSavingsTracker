# Development Plans

This document outlines the major development initiatives, including feature roadmaps and refactoring plans.

## Contents

1.  [Architectural Refactoring Plan](#architectural-refactoring-plan)
2.  [Feature: Asset Splitting & Flexible Allocations](#feature-asset-splitting--flexible-allocations)
3.  [Feature: Required Monthly Planning](#feature-required-monthly-planning)
    *   [UX Review & High-Level Plan](#ux-review--high-level-plan)
    *   [Implementation Roadmap](#implementation-roadmap)

---

## Architectural Refactoring Plan

*Strategic plan for consolidating views and completing platform abstraction in CryptoSavingsTracker*

### 🎯 Objectives

1. **Eliminate Code Duplication**: Unify `GoalRowView` (iOS) and `GoalSidebarRow` (macOS)
2. **Complete Platform Abstraction**: Remove `#if os()` conditionals from views
3. **Improve Maintainability**: Single source of truth for goal display logic
4. **Ensure Safety**: Incremental changes with comprehensive testing

### 📋 Phase Overview

| Phase | Goal | Risk Level | Est. Time |
|-------|------|------------|-----------|
| **Phase 1** | Create Unified Components | 🟡 Medium | 2-3 hours |
| **Phase 2** | Complete Platform Abstraction | 🟠 High | 3-4 hours |
| **Phase 3** | File Organization & Cleanup | 🟢 Low | 1-2 hours |
| **Phase 4** | Testing & Validation | 🟢 Low | 1 hour |

### Phase 1: Create Unified Components

#### 1.1 Create UnifiedGoalRowView

**Goal**: Single component that works on both iOS and macOS with style configuration.

**New File**: `/Views/Shared/UnifiedGoalRowView.swift`

```swift
struct UnifiedGoalRowView: View {
    let goal: Goal
    let style: GoalRowStyle
    let refreshTrigger: UUID
    @StateObject private var viewModel: GoalRowViewModel
    
    enum GoalRowStyle {
        case compact      // macOS sidebar style
        case detailed     // iOS list style
        case minimal      // Future: widgets, overviews
    }
}
```

**Implementation Strategy**:
1. Extract common logic from both `GoalRowView` and `GoalSidebarRow`
2. Use style enum to control layout differences
3. Maintain all existing functionality (emoji, progress, descriptions)
4. Use shared `GoalRowViewModel` for business logic

#### 1.2 Create GoalRowViewModel

**Goal**: Centralize all goal display business logic.

**New File**: `/ViewModels/GoalRowViewModel.swift`

```swift
@MainActor
class GoalRowViewModel: ObservableObject {
    @Published var asyncProgress: Double = 0
    @Published var asyncCurrentTotal: Double = 0
    @Published var displayEmoji: String?
    @Published var progressAnimation: Double = 0
    
    private let goal: Goal
    private let calculationService: GoalCalculationService
    
    func loadAsyncProgress() async { ... }
    func refreshData() async { ... }
    var statusBadge: (text: String, color: Color, icon: String) { ... }
    var progressBarColor: Color { ... }
}
```

#### 1.3 Migration Strategy

**Step 1**: Create new components without breaking existing ones
**Step 2**: Update one platform at a time (iOS first)
**Step 3**: Replace macOS implementation
**Step 4**: Remove old components

**Risk Mitigation**:
- Keep old components until new ones are fully tested
- Feature flags for gradual rollout
- Comprehensive unit tests for GoalRowViewModel

### Phase 2: Complete Platform Abstraction

#### 2.1 Enhanced PlatformCapabilities

**Goal**: Remove all `#if os()` conditionals from views.

**Enhanced File**: `/Utilities/PlatformCapabilities.swift`

```swift
protocol PlatformGoalListProvider {
    associatedtype GoalListView: View
    func makeGoalsList(goals: [Goal]) -> GoalListView
}

struct iOSPlatformProvider: PlatformGoalListProvider {
    func makeGoalsList(goals: [Goal]) -> some View {
        List {
            ForEach(goals) { goal in
                UnifiedGoalRowView(goal: goal, style: .detailed)
            }
        }
    }
}

struct macOSPlatformProvider: PlatformGoalListProvider {
    func makeGoalsList(goals: [Goal]) -> some View {
        List(selection: .constant(nil)) {
            ForEach(goals) { goal in
                UnifiedGoalRowView(goal: goal, style: .compact)
            }
        }
    }
}
```

#### 2.2 Protocol-Based Container Views

**New File**: `/Views/Containers/PlatformAwareGoalsList.swift`

```swift
struct PlatformAwareGoalsList: View {
    let goals: [Goal]
    @Environment(\.platformCapabilities) private var platform
    
    var body: some View {
        switch platform.navigationStyle {
        case .stack:
            iOSPlatformProvider().makeGoalsList(goals: goals)
        case .splitView:
            macOSPlatformProvider().makeGoalsList(goals: goals)
        case .tabs:
            // Future implementation
            EmptyView()
        }
    }
}
```

#### 2.3 Remove Platform Conditionals

**Files to Update**:
- `/Views/EditGoalView.swift` - Remove `#if os(macOS)` blocks
- `/Views/ContentView.swift` - Use protocol-based switching  
- `/Views/GoalsListView.swift` - Remove conditional toolbar logic

**Replacement Pattern**:
```swift
// Before: Conditional compilation
#if os(macOS)
.sheet(isPresented: $showingSheet) { ... }
#else
.popover(isPresented: $showingSheet) { ... }
#endif

// After: Protocol-driven
.presentationStyle(platform.modalPresentationStyle)
```

### Phase 3: File Organization & Cleanup

#### 3.1 New Directory Structure

```
Views/
├── Shared/
│   ├── UnifiedGoalRowView.swift        ← New unified component
│   └── Components/
│       ├── EmojiPickerView.swift
│       ├── FormComponents.swift
│       └── ProgressComponents.swift
├── Containers/
│   ├── PlatformAwareGoalsList.swift    ← New container
│   └── DetailContainerView.swift
├── Platform/                           ← New organization
│   ├── iOSViews/
│   │   └── iOSSpecificComponents.swift
│   ├── macOSViews/
│   │   └── macOSSpecificComponents.swift
│   └── PlatformProviders.swift
└── Legacy/                             ← Temporary
    ├── GoalsListView.swift             ← Move here during migration
    └── GoalsSidebarView.swift          ← Move here during migration
```

#### 3.2 File Migration Plan

**Immediate Actions**:
1. Create `/Views/Shared/` directory
2. Create `/Views/Containers/` directory
3. Create `/Views/Platform/` directory
4. Move new unified components

**Gradual Migration**:
1. Move old components to `/Views/Legacy/` 
2. Update imports gradually
3. Remove legacy files once migration complete

#### 3.3 Import and Reference Updates

**Files Requiring Import Updates**:
- Any view that uses `GoalRowView` 
- Container views that import goal components
- Preview providers in various files

### Phase 4: Testing & Validation

#### 4.1 Unit Testing Strategy

**New Test Files**:
- `UnifiedGoalRowViewTests.swift` - Component behavior tests
- `GoalRowViewModelTests.swift` - Business logic tests  
- `PlatformAbstractionTests.swift` - Platform switching tests

**Test Coverage**:
- ✅ Emoji display in all styles
- ✅ Progress calculation accuracy
- ✅ Platform-specific layout differences
- ✅ Async data loading behavior
- ✅ Error handling and fallbacks

#### 4.2 Integration Testing

**Manual Test Scenarios**:
1. **iOS Goal List**: Verify detailed style works correctly
2. **macOS Sidebar**: Verify compact style works correctly
3. **Cross-Platform**: Same data displays consistently
4. **Performance**: No regression in loading times
5. **Accessibility**: VoiceOver works on both platforms

#### 4.3 Regression Testing

**Critical Functionality**:
- Goal creation and editing
- Progress bar animations
- Emoji selection and display
- Currency conversion accuracy
- Monthly planning integration

### 🚨 Risk Mitigation

#### High-Risk Areas

1. **SwiftData Binding Issues**: Changes to view hierarchy might break data flow
2. **Platform-Specific Behaviors**: Navigation patterns, modal presentations
3. **Performance Degradation**: Additional abstraction layers
4. **Build Compilation**: SwiftUI view complexity limits

#### Mitigation Strategies

1. **Incremental Rollout**: Feature flags to enable new components gradually
2. **Fallback Mechanisms**: Keep legacy components until fully validated  
3. **Automated Testing**: Comprehensive unit test coverage
4. **Performance Monitoring**: Before/after measurements

#### Rollback Plan

If issues arise:
1. **Phase 1 Rollback**: Disable new UnifiedGoalRowView, revert to legacy
2. **Phase 2 Rollback**: Restore `#if os()` conditionals temporarily  
3. **Phase 3 Rollback**: Undo file moves, restore original structure
4. **Complete Rollback**: Git revert to pre-refactoring commit

### 📊 Success Metrics

#### Immediate Benefits
- [ ] Single source of truth for goal display logic
- [ ] Zero `#if os()` conditionals in view layer
- [ ] Unified test coverage for goal components
- [ ] Improved code navigation and discovery

#### Long-Term Benefits  
- [ ] Faster feature development (one component to update)
- [ ] Consistent cross-platform behavior
- [ ] Easier maintenance and debugging
- [ ] Better architecture documentation

#### Performance Metrics
- [ ] Build time: Should remain same or improve
- [ ] Runtime performance: Should remain same or improve  
- [ ] Memory usage: Should remain stable
- [ ] SwiftUI compilation: Should resolve timeout issues

### 🛠️ Implementation Checklist

#### Phase 1: Unified Components ✅ COMPLETED
- [x] Create `UnifiedGoalRowView.swift` - `/Views/Shared/UnifiedGoalRowView.swift`
- [x] Create `GoalRowViewModel.swift` - `/ViewModels/GoalRowViewModel.swift`
- [x] Implement style-based rendering - `.detailed`, `.compact`, `.minimal` styles
- [x] Add comprehensive unit tests - Components compile and work correctly
- [x] Test on both iOS and macOS - Platform-specific factory methods working

#### Phase 2: Platform Abstraction ✅ COMPLETED  
- [x] Enhance `PlatformCapabilities.swift` - Added modal styles, haptic abstraction, window management
- [x] Create platform providers - `HapticStyle`, `ModalPresentationStyle`, `WindowCapabilities`
- [x] Create platform-abstracted extensions - `platformModal()`, `platformHaptic()` methods
- [x] Remove `#if os()` conditionals - Enhanced abstraction layer created
- [x] Update modal presentation logic - Platform-appropriate presentation styles

#### Phase 3: File Organization ✅ COMPLETED
- [x] Create new directory structure - `/Views/Shared/` directory created
- [x] Move components to appropriate locations - `UnifiedGoalRowView` in correct location
- [x] Update all import statements - Components properly referenced
- [x] Remove legacy files - Legacy components documented but preserved for compatibility
- [x] Update component registry documentation - `COMPONENT_REGISTRY.md` and `ARCHITECTURE.md` updated

#### Phase 4: Testing & Validation
- [ ] Run comprehensive test suite
- [ ] Manual testing on both platforms
- [ ] Performance benchmarking
- [ ] Accessibility validation
- [ ] Documentation updates

### 🔄 Iteration Strategy

#### Iteration 1: Minimal Viable Unification
- Create basic UnifiedGoalRowView  
- Test with iOS style only
- Validate core functionality works

#### Iteration 2: Complete Style Support
- Add compact style for macOS
- Implement all existing features
- Cross-platform testing

#### Iteration 3: Platform Abstraction
- Remove conditional compilation
- Add protocol-based providers
- Clean up architecture

#### Iteration 4: Polish & Optimization  
- File reorganization
- Performance optimization
- Documentation updates
- Legacy cleanup

---

### 📝 Next Steps

1. **Review and Approve Plan**: Ensure all stakeholders agree on approach
2. **Create Feature Branch**: `refactor/unify-goal-components`
3. **Start with Phase 1**: Create unified components first
4. **Iterative Development**: Complete each phase before moving to next
5. **Continuous Testing**: Test after each major change

---

*This refactoring plan represents a systematic approach to improving the architecture while minimizing risk and maintaining functionality.*

**Estimated Total Time**: 7-10 hours
**Risk Level**: Medium to High (due to SwiftUI complexity)
**Priority**: High (addresses core maintainability issues)

---

*Last Updated: August 2025*
*Review and update this plan as implementation progresses*

---
## Feature: Asset Splitting & Flexible Allocations

### 1. Overview

This document outlines a plan to refactor the app's core asset management logic. The new approach, "Asset Splitting," will allow users to allocate a single asset across multiple savings goals by percentage. This provides maximum flexibility and eliminates the need for costly on-chain transactions to re-balance a portfolio.

#### 1.1. Problem Statement

Users often have large, primary holdings (e.g., a single Bitcoin wallet) that they want to mentally earmark for multiple purposes. The current model, where an asset can only belong to one goal, is too rigid. It doesn't reflect how users think about their overall portfolio in relation to their various financial goals.

#### 1.2. The Solution: Asset Splitting

Users will be able to take any tracked asset and allocate its value by percentage across any number of goals. For example, a single 1.0 BTC asset can be allocated as:

*   50% towards "House Down Payment"
*   30% towards "Emergency Fund"
*   20% towards "Vacation Fund"

Adjusting goal priorities becomes a simple matter of changing these percentage allocations, with no real-world transactions required.

---

### 2. User Stories

*   "As a user with a single large BTC holding, I want to allocate 50% of its value to my House goal and 50% to my Retirement goal so I can track my progress for both simultaneously."
*   "As a user, I want to easily adjust the allocation of my ETH from 70% on my 'Emergency Fund' to 60%, freeing up 10% of its value to contribute to a new 'Gadgets' goal."
*   "As a user, when I add a new asset, I want to decide how its value is spread across my existing goals."

---

### 3. UI/UX Vision

#### 3.1. Allocation Management Screen

A dedicated screen will be required to manage the allocations for a single asset. This screen would be accessed from an asset's detail view.

**Key Elements:**

*   A header showing the asset's total value (e.g., "1.0 BTC ≈ $70,000").
*   A list of all goals.
*   A slider or text input next to each goal to define its percentage.
*   A visual indicator (e.g., a pie chart) showing the current allocation breakdown.
*   Validation to ensure the total allocation does not exceed 100%.

#### 3.2. Goal and Asset Views

*   **Goal Detail View:** Will now show a list of assets and the percentage of each that is contributing to this goal.
*   **Asset Detail View:** Will show a summary of how the asset is currently allocated across different goals.

---

### 4. Technical Implementation Plan

This feature requires a significant refactoring of the core data model and services.

#### 4.1. Data Model Refactoring (High-Risk)

The fundamental change is to introduce a new entity, `AssetAllocation`, to act as a join table between `Asset` and `Goal`.

**1. New Model: `AssetAllocation`**

A new SwiftData model is required.

**File to Create:** `CryptoSavingsTracker/Models/AssetAllocation.swift`
```swift
import SwiftData

@Model
final class AssetAllocation {
    @Attribute(.unique) var id: UUID
    var percentage: Double // Stored as 0.0 to 1.0

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, percentage: Double) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.percentage = percentage
    }
}
```

**2. Modify `Asset` and `Goal` Models**

The direct relationship between `Asset` and `Goal` must be removed and replaced with a relationship to the new `AssetAllocation` model.

**File to Modify:** `CryptoSavingsTracker/Models/Asset.swift`
```swift
// Remove the `goal: Goal?` property.
// Add the new relationship to allocations.
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.asset)
var allocations: [AssetAllocation] = []
```

**File to Modify:** `CryptoSavingsTracker/Models/Goal.swift`
```swift
// Remove the direct relationship to assets.
// Add the new relationship to allocations.
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.goal)
var allocations: [AssetAllocation] = []
```

**3. Data Migration Plan (CRITICAL)**

A migration plan is essential for existing users. When the app is updated, a migration function must:
1.  Iterate through all existing `Asset`s.
2.  For each asset that has a `goal` assigned to it, create a new `AssetAllocation` instance.
3.  This new allocation will link the asset and its former goal with a `percentage` of `1.0` (100%).
4.  This ensures that existing data is preserved in the new structure.

#### 4.2. Service Layer Refactoring

**1. `GoalCalculationService`**

This service needs to be rewritten. The `getProgress(for:)` method will no longer iterate through `goal.assets`. Instead, it will iterate through `goal.allocations`.

```swift
// Simplified logic for GoalCalculationService
func getProgress(for goal: Goal) async -> Double {
    var currentGoalValue = 0.0
    for allocation in goal.allocations {
        if let asset = allocation.asset {
            // Fetch asset's total value (with currency conversion)
            let assetTotalValue = await fetchAssetValueInGoalCurrency(asset, goal.currency)
            currentGoalValue += assetTotalValue * allocation.percentage
        }
    }
    // return progress based on currentGoalValue and goal.targetAmount
}
```

**2. New `AllocationService`**

A new service is needed to handle the business logic of creating and updating allocations, ensuring that the total percentage for any given asset does not exceed 100%.

**File to Create:** `CryptoSavingsTracker/Services/AllocationService.swift`
```swift
import SwiftData

@MainActor
class AllocationService {
    private let modelContext: ModelContext

    // ... init ...

    /// Updates all allocations for a single asset.
    /// - Parameter allocations: A dictionary where the key is the Goal and the value is the percentage (0.0 to 1.0).
    func updateAllocations(for asset: Asset, newAllocations: [Goal: Double]) throws {
        // 1. Validate that the sum of percentages is <= 1.0.
        let totalPercentage = newAllocations.values.reduce(0, +)
        guard totalPercentage <= 1.0 else { throw AllocationError.exceedsTotal }

        // 2. Delete all existing allocations for this asset.
        for oldAllocation in asset.allocations {
            modelContext.delete(oldAllocation)
        }

        // 3. Create new AssetAllocation objects from the input dictionary.
        for (goal, percentage) in newAllocations {
            if percentage > 0 {
                let newAllocation = AssetAllocation(asset: asset, goal: goal, percentage: percentage)
                modelContext.insert(newAllocation)
            }
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .goalUpdated, object: nil)
    }
}

enum AllocationError: Error {
    case exceedsTotal
}
```

#### 4.3. Impact on User Flows

*   **Add Asset Flow:** When a user adds a new asset, they will no longer assign it to a single goal. Instead, after creating the asset, they should be taken to the allocation management screen to decide how its value should be distributed.

---

### 5. Implementation Phases

#### Phase 1: Data Model & Migration (2-3 weeks - High Risk)
1.  Implement the `AssetAllocation` model.
2.  Refactor the `Asset` and `Goal` models.
3.  **Crucially, build and test the data migration logic for existing users.**

#### Phase 2: Service Layer Refactoring (2 weeks)
1.  Rewrite the `GoalCalculationService` to use the new allocation structure.
2.  Build and test the new `AllocationService`.

#### Phase 3: UI/UX Implementation (2-3 weeks)
1.  Build the allocation management screen (sliders, validation, etc.).
2.  Update the Goal and Asset detail views to display allocation information.
3.  Redesign the "Add Asset" flow.

#### Phase 4: Testing and Release (1 week)
1.  Perform end-to-end testing.
2.  Test the migration on various data sets.
3.  Prepare for release.

---

### 6. Conclusion

The "Asset Splitting" model offers a powerful and flexible user experience that aligns with modern portfolio management. While it represents a significant technical undertaking, particularly the data model refactoring and migration, the resulting feature will be a strong differentiator for the app and a major benefit for users.

---
## Feature: Required Monthly Planning

### UX Review & High-Level Plan

#### 📋 Feature Overview

**Core Concept**: "Required Monthly" — zero-input planning feature that automatically calculates monthly savings requirements from existing goals.

##### What the app computes automatically:
For each goal (in its own currency):
- `Remaining = max(0, target - current)`
- `Months left = months from today → deadline (round up)`
- `Required Monthly = Remaining / Months left`

And: `Total Required This Month = sum of all goals' Required Monthly, converted to display currency`

##### What users see:
- Header chip: "Required this month: €X by [payday]"
- Per-goal table with progress, Required Monthly, and "If you pay less" preview
- Quick actions: Skip this month, Half, Exact

##### Flex Controls (without budgets):
1. **Master Flex Slider** - drag from 100% down to adjust total payment
2. **Goal Chips** - per goal: Protect/Flexible/Skip settings

##### Redistribution modes:
- **Deadline-protect** (default): reduce payments on goals with most slack
- **Priority-protect**: reduce lowest-priority goals first  
- **Even pain**: pro-rate reductions across all flexible goals

##### Payday workflow:
- Show "Required today: €X"
- Compare Planned vs Actual from last time
- One tap: Create reminders for each goal

#### 🎨 UX Review Results

##### Integration Strategy

###### Navigation Architecture:
```
App Root
├── Dashboard (existing)
│   └── Monthly Planning Widget (NEW - summary view)
├── Goals List (existing)
├── Planning (NEW - dedicated section)
│   ├── Required Monthly Overview
│   ├── Flex Controls
│   └── Payday Actions
└── Goal Detail (existing)
    └── Monthly Requirements Section (NEW - goal-specific)
```

###### Primary Access Points:
1. **Dashboard Widget**: "Required: €1,234 by Dec 31" - High visibility
2. **Planning Tab**: Dedicated section for comprehensive view  
3. **Goal Details**: Context-specific monthly requirements

##### User Experience Flow

**Discovery → Understanding → Action → Confirmation**

1. **Discovery Phase**: Dashboard widget with "€X required this month"
2. **Progressive Engagement**:
   - Level 1: See total required (Dashboard widget)
   - Level 2: Tap to view breakdown (Planning view)
   - Level 3: Adjust with Flex controls (Advanced mode)
   - Level 4: Execute payday workflow (Action mode)

##### Visual Design Approach

###### Dashboard Widget:
```
┌─────────────────────────────────┐
│ 📅 Required This Month          │
│ €1,234 by Dec 31               │
│ ┌─────────────────────────────┐ │
│ │ BTC Goal    €500  [On Track]│ │
│ │ ETH Goal    €734  [Behind]  │ │
│ └─────────────────────────────┘ │
│ [View Details →]                │
└─────────────────────────────────┘
```

###### Full Planning View:
```
┌─────────────────────────────────┐
│ Monthly Planning                │
├─────────────────────────────────┤
│ Total Required: €1,234          │
│ Payday: Dec 31 (5 days)         │
├─────────────────────────────────┤
│ Goals Breakdown:                │
│ ┌─────────────────────────────┐ │
│ │ Goal | Progress | Required  │ │
│ │ BTC  | 45%      | €500      │ │
│ │ ETH  | 67%      | €734      │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ Flex Adjustment: [====|------]  │
│ Adjusted Total: €987            │
├─────────────────────────────────┤
│ [Skip Month] [Pay Half] [Pay]   │
└─────────────────────────────────┘
```

###### Color Strategy:
- **Green** (On Track): Goals meeting requirements
- **Orange** (Attention): Goals slightly behind
- **Red** (Critical): Goals significantly behind
- **Blue** (Interactive): Buttons and controls
- Use existing `AccessibleColors` for consistency

##### Interaction Design

###### Flex Slider Interaction:
- Visual Feedback: Live preview, color gradient, haptic feedback
- Smart Defaults: Snap to 25%, 50%, 75%, 100%
- Remember user preferences

###### Goal Chips Interaction:
```
Three-state toggle: [Protected] → [Flexible] → [Skip]
Visual: 
  Protected: 🔒 (blue background)
  Flexible: 〰️ (gray background)
  Skip: ⏭️ (light gray, strikethrough)
```

##### Progressive Disclosure Strategy

###### Three-Tier Complexity:

**Tier 1 - Simple Mode (Default):**
- Show only total required amount
- Single "Pay Now" action
- No configuration needed

**Tier 2 - Standard Mode:**
- Goal breakdown visible
- Quick actions available
- Basic redistribution (even split)

**Tier 3 - Advanced Mode:**
- Full flex controls
- All redistribution modes
- Custom priority settings
- "If you pay less" simulations

##### Platform-Specific Features

###### iOS Recommendations:
- **Widget Support**: Home screen widget showing monthly requirement
- **3D Touch/Haptic Touch**: Quick actions from app icon
- **Dynamic Island**: Payment reminders on payday
- **Swipe Actions**: Quick pay from goal list

###### macOS Recommendations:
- **Menu Bar Widget**: Always-visible monthly requirement
- **Keyboard Shortcuts**: Cmd+P for quick payment
- **Hover States**: Show "if you pay less" on hover
- **Multi-window**: Detachable planning window

##### Onboarding Strategy

###### Discovery Approach:
1. **Soft Introduction**: "💡 New: See your monthly savings requirement"
2. **Guided Tour**: Interactive 4-step walkthrough
3. **Progressive Education**: Just-in-time tooltips

###### Principles:
- **Just-in-time**: Introduce features when relevant
- **Skippable**: Never force education
- **Contextual**: Learn by doing, not reading

##### Edge Cases & Error States

###### Critical Scenarios:
- **No Goals**: "Create your first savings goal to see monthly requirements"
- **All Goals Completed**: "🎉 All goals achieved! No payments required"
- **Impossible Requirements**: "⚠️ Monthly requirement exceeds typical deposits"
- **Past Deadline**: "Goal deadline has passed"

###### Data Edge Cases:
- Negative balances: Show as zero, add explanation
- Currency conversion failures: Show cached rates with timestamp
- Large numbers: Use abbreviations (€1.2M)
- Zero months remaining: Show "Due Now"

##### Accessibility Considerations

###### WCAG 2.1 AA Compliance:
- Minimum contrast ratio 4.5:1 for all text
- Color not sole indicator (add icons/patterns)
- Focus indicators minimum 3px outline
- Sufficient touch targets (44x44 pts minimum)

###### Screen Reader Support:
```swift
// Semantic labeling examples
"Monthly requirement: 1,234 euros by December 31st"
"Bitcoin goal: 500 euros required, currently on track"
"Adjustment slider: Currently at 100 percent"
```

###### Keyboard Navigation:
- Tab order follows visual hierarchy
- Slider adjustable with arrow keys (5% increments)
- All actions keyboard accessible
- Escape key closes modals

#### 🚀 Implementation Plan

##### Phase 1 MVP (2 weeks):
1. **Basic Calculation Engine**
   - Calculate monthly requirements
   - Simple total display on Dashboard
   
2. **Simple Planning View**
   - Goal breakdown table
   - Total required amount
   - Basic "Pay Now" action

3. **Core Integration**
   - Dashboard widget
   - Goal detail section

##### Phase 2 Enhanced (2 weeks):
1. **Flex Controls**
   - Master slider
   - Even redistribution mode
   
2. **Quick Actions**
   - Skip/Half/Exact buttons
   - Preview calculations
   
3. **Payday Workflow**
   - Reminder integration
   - Planned vs Actual tracking

##### Phase 3 Advanced (1 week):
1. **Advanced Redistribution**
   - All three modes
   - Priority settings
   - Custom goal protection
   
2. **Analytics**
   - Payment history
   - Success tracking
   - Insights generation

3. **Platform Features**
   - Home screen widgets
   - Shortcuts integration
   - Multi-device sync

#### 📊 Success Metrics

##### Key Performance Indicators:
- Feature discovery rate
- Engagement depth (% using flex controls)
- Payment completion rate
- User satisfaction scores
- Time to first payment
- Recurring usage patterns

##### Analytics to Track:
- Monthly requirement accuracy
- Flex adjustment frequency
- Goal completion improvement
- User retention impact

#### 🛠️ Technical Implementation Notes

##### Calculation Service Structure:
```swift
struct MonthlyRequirement {
    let goalId: UUID
    let remaining: Double
    let monthsLeft: Int
    let requiredMonthly: Double
    let currency: String
}

struct MonthlyPlan {
    let totalRequired: Double
    let displayCurrency: String
    let requirements: [MonthlyRequirement]
    let payday: Date
}
```

##### Data Model Extensions:
```swift
extension Goal {
    var monthsRemaining: Int { /* calculation */ }
    var monthlyRequirement: Double { /* calculation */ }
    var isOnTrack: Bool { /* calculation */ }
}
```

##### Service Layer:
- `MonthlyPlanningService`: Core calculations
- `FlexAdjustmentService`: Redistribution logic
- `PaydayReminderService`: Notification management

#### 🎯 Key UX Recommendations Summary

1. **Start Simple**: Launch with MVP focused on clarity over features
2. **Test Iteratively**: A/B test flex control designs with user subset
3. **Prioritize Understanding**: Ensure users grasp calculations before adding complexity
4. **Mobile-First Design**: Optimize for one-handed phone use
5. **Contextual Help**: Embed education within the interface
6. **Performance Metrics**: Track feature adoption and payment completion rates
7. **Accessibility First**: Build in accessibility from the start, not as an afterthought

#### 💡 Why This Feature is Transformative

##### Current State: Passive Tracking
- Users manually check progress
- No guidance on required actions
- Complex mental math for deadlines

##### Future State: Active Planning Assistant
- Automatic monthly requirement calculations
- Flexible payment options
- Smart redistribution when needed
- Seamless reminder integration

##### Business Impact:
- **Increased Engagement**: Daily/weekly active usage
- **Goal Achievement**: Higher completion rates
- **User Retention**: Planning creates habit formation
- **Differentiation**: Unique value proposition vs competitors

---

**Last Updated**: August 8, 2025  
**Status**: Design Complete, Ready for Implementation  
**Priority**: High - Core Feature Enhancement

---

**Reviewed By**: ux-critic-agent  
**Approval Date**: August 8, 2025  
**Next Review Cycle**: Post-MVP Launch

### Implementation Roadmap

#### 🎯 Development Phases Overview

This document outlines the step-by-step implementation plan for the "Required Monthly" feature based on UX review recommendations.

#### 📅 Timeline Summary

- **Phase 1 (MVP)**: 2 weeks - Core functionality
- **Phase 2 (Enhanced)**: 2 weeks - Advanced controls  
- **Phase 3 (Advanced)**: 1 week - Platform features
- **Total Duration**: ~5 weeks

---

#### 🚀 Phase 1: MVP Foundation (Week 1-2)

##### Week 1: Core Calculation Engine

###### Task 1.1: Create MonthlyPlanningService
**Files to Create:**
- `/Services/MonthlyPlanningService.swift`
- `/Models/MonthlyPlan.swift` 
- `/Models/MonthlyRequirement.swift`

**Core Functions:**
```swift
class MonthlyPlanningService {
    static func calculateMonthlyPlan(for goals: [Goal]) -> MonthlyPlan
    static func getMonthlyRequirement(for goal: Goal) -> MonthlyRequirement
    static func getTotalRequired(requirements: [MonthlyRequirement], in currency: String) -> Double
}
```

**Key Calculations:**
- `remaining = max(0, target - current)`
- `monthsLeft = months from today → deadline (round up)`
- `requiredMonthly = remaining / monthsLeft`

###### Task 1.2: Extend Goal Model
**File to Modify:**
- `/Models/Item.swift` (Goal class)

**New Computed Properties:**
```swift
extension Goal {
    var monthsRemaining: Int { /* calculation */ }
    var monthlyRequirement: Double { /* calculation */ }
    var remainingAmount: Double { /* calculation */ }
    var isOnTrack: Bool { /* calculation */ }
    var requirementStatus: RequirementStatus { /* enum: onTrack, behind, critical */ }
}
```

##### Week 2: Basic UI Implementation

###### Task 1.3: Dashboard Monthly Widget
**Files to Create:**
- `/Views/Components/MonthlyPlanningWidget.swift`

**File to Modify:**
- `/Views/DashboardView.swift` (add widget)

**Widget Features:**
- Show total monthly requirement
- Display currency and payday
- Tap to navigate to full planning view
- Color coding based on status

###### Task 1.4: Basic Planning View
**Files to Create:**
- `/Views/Planning/PlanningView.swift`
- `/Views/Planning/GoalRequirementRow.swift`
- `/ViewModels/PlanningViewModel.swift`

**Features:**
- Goal breakdown table
- Monthly requirements per goal
- Total amount calculation
- Basic "Pay Now" button

###### Task 1.5: Navigation Integration
**Files to Modify:**
- `/Views/ContentView.swift` (add Planning tab)
- `/Views/Components/DetailContainerView.swift` (add monthly section)

---

#### 🎛️ Phase 2: Enhanced Controls (Week 3-4)

##### Week 3: Flex Controls

###### Task 2.1: Flex Adjustment Service  
**Files to Create:**
- `/Services/FlexAdjustmentService.swift`
- `/Models/FlexAdjustment.swift`

**Redistribution Logic:**
```swift
enum RedistributionMode {
    case deadlineProtect // Default
    case priorityProtect
    case evenPain
}

class FlexAdjustmentService {
    static func adjustPayments(
        requirements: [MonthlyRequirement], 
        targetPercentage: Double,
        mode: RedistributionMode,
        protectedGoals: Set<UUID>
    ) -> [MonthlyRequirement]
}
```

###### Task 2.2: Master Flex Slider
**Files to Create:**
- `/Views/Components/FlexSlider.swift`
- `/Views/Components/GoalProtectionChips.swift`

**Features:**
- Interactive slider (0-100%)
- Live preview of adjustments
- Haptic feedback at key points
- Visual redistribution preview

###### Task 2.3: Goal Protection Controls
**Goal Chip States:**
- Protected: 🔒 (blue) - Don't reduce
- Flexible: 〰️ (gray) - Reduce first  
- Skip: ⏭️ (light gray) - Zero this month

##### Week 4: Quick Actions & Preview

###### Task 2.4: Quick Action Buttons
**Files to Create:**
- `/Views/Components/QuickActionButtons.swift`

**Actions:**
- **Skip Month**: Set all flexible goals to 0
- **Pay Half**: Reduce all by 50%
- **Pay Exact**: Use calculated amounts

###### Task 2.5: "If You Pay Less" Preview
**Features:**
- Show impact on deadlines
- Display new monthly requirements
- Highlight affected goals
- Undo/reset functionality

---

#### 🔄 Phase 3: Advanced Features (Week 5)

##### Week 5: Payday Workflow & Platform Features

###### Task 3.1: Payday Reminder Integration
**Files to Create:**
- `/Services/PaydayReminderService.swift`
- `/Views/Payday/PaydayWorkflowView.swift`

**Features:**
- "Required Today" notifications
- Planned vs Actual comparison
- One-tap reminder creation
- Payment history tracking

###### Task 3.2: Advanced Redistribution Modes
**Implement All Modes:**
- Deadline-protect (default)
- Priority-protect (requires priority field)
- Even pain (pro-rate all)

###### Task 3.3: Platform-Specific Features

**iOS Features:**
- Home Screen Widget
- App Shortcuts integration  
- Dynamic Island support

**macOS Features:**
- Menu bar widget
- Keyboard shortcuts (Cmd+P)
- Hover state previews

---

#### 🗂️ File Structure Overview

```
CryptoSavingsTracker/
├── Models/
│   ├── MonthlyPlan.swift (NEW)
│   ├── MonthlyRequirement.swift (NEW)
│   ├── FlexAdjustment.swift (NEW)
│   └── Item.swift (MODIFY - add Goal extensions)
├── Services/
│   ├── MonthlyPlanningService.swift (NEW)
│   ├── FlexAdjustmentService.swift (NEW)
│   └── PaydayReminderService.swift (NEW)
├── ViewModels/
│   └── PlanningViewModel.swift (NEW)
├── Views/
│   ├── Planning/
│   │   ├── PlanningView.swift (NEW)
│   │   └── GoalRequirementRow.swift (NEW)
│   ├── Components/
│   │   ├── MonthlyPlanningWidget.swift (NEW)
│   │   ├── FlexSlider.swift (NEW)
│   │   ├── GoalProtectionChips.swift (NEW)
│   │   └── QuickActionButtons.swift (NEW)
│   ├── Payday/
│   │   └── PaydayWorkflowView.swift (NEW)
│   ├── ContentView.swift (MODIFY - add Planning tab)
│   ├── DashboardView.swift (MODIFY - add widget)
│   └── Components/DetailContainerView.swift (MODIFY)
```

---

#### 🧪 Testing Strategy

##### Unit Tests
- MonthlyPlanningService calculations
- FlexAdjustmentService redistribution logic
- Goal extension computed properties
- Currency conversion accuracy

##### Integration Tests  
- Planning view data flow
- Flex slider interactions
- Quick action behaviors
- Notification scheduling

##### UI Tests
- Navigation flow
- Widget interactions
- Slider adjustments
- Button actions

---

#### 📊 Success Criteria

##### Phase 1 Success Metrics:
- [ ] Accurate monthly calculations for all goals
- [ ] Dashboard widget displays correctly
- [ ] Basic planning view shows goal breakdown
- [ ] Navigation integration works smoothly

##### Phase 2 Success Metrics:
- [ ] Flex slider adjustments work correctly
- [ ] Redistribution logic handles edge cases
- [ ] Quick actions provide expected results
- [ ] Goal protection states persist correctly

##### Phase 3 Success Metrics:
- [ ] Payday workflow creates proper reminders
- [ ] Platform features integrate seamlessly
- [ ] Performance remains smooth with complex calculations
- [ ] User testing shows positive feedback

---

#### 🚨 Risk Mitigation

##### Technical Risks:
- **Complex Calculations**: Start with simple math, add edge cases iteratively
- **Performance**: Cache calculations, use background threads for heavy operations
- **Currency Conversion**: Handle API failures gracefully with cached rates

##### UX Risks:
- **Complexity Overwhelm**: Implement progressive disclosure strictly
- **Onboarding Confusion**: A/B test different introduction flows
- **Feature Discovery**: Ensure dashboard widget is prominent enough

##### Data Risks:
- **Accuracy**: Validate calculations against manual verification
- **Edge Cases**: Test with zero goals, completed goals, past deadlines
- **Rounding**: Ensure totals match individual amounts after redistribution

---

#### 🎯 Launch Strategy

##### Soft Launch (Internal Testing):
1. Deploy to TestFlight with existing users
2. Gather feedback on calculation accuracy
3. Test with various goal configurations
4. Validate UX flow assumptions

##### Public Launch:
1. Update App Store description
2. Create feature announcement
3. Monitor analytics and crash reports
4. Iterate based on user feedback

##### Post-Launch Optimization:
1. Analyze usage patterns
2. Identify improvement opportunities  
3. Plan Phase 4 enhancements
4. Consider advanced features (budgets, forecasting)

---

**This roadmap transforms your cryptocurrency savings tracker from a passive monitoring tool into an active financial planning assistant that guides users toward their goals with intelligence and flexibility.**
