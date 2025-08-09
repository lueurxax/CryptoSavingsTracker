# Required Monthly Feature - Implementation Roadmap

## 🎯 Development Phases Overview

This document outlines the step-by-step implementation plan for the "Required Monthly" feature based on UX review recommendations.

## 📅 Timeline Summary

- **Phase 1 (MVP)**: 2 weeks - Core functionality
- **Phase 2 (Enhanced)**: 2 weeks - Advanced controls  
- **Phase 3 (Advanced)**: 1 week - Platform features
- **Total Duration**: ~5 weeks

---

## 🚀 Phase 1: MVP Foundation (Week 1-2)

### Week 1: Core Calculation Engine

#### Task 1.1: Create MonthlyPlanningService
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

#### Task 1.2: Extend Goal Model
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

### Week 2: Basic UI Implementation

#### Task 1.3: Dashboard Monthly Widget
**Files to Create:**
- `/Views/Components/MonthlyPlanningWidget.swift`

**File to Modify:**
- `/Views/DashboardView.swift` (add widget)

**Widget Features:**
- Show total monthly requirement
- Display currency and payday
- Tap to navigate to full planning view
- Color coding based on status

#### Task 1.4: Basic Planning View
**Files to Create:**
- `/Views/Planning/PlanningView.swift`
- `/Views/Planning/GoalRequirementRow.swift`
- `/ViewModels/PlanningViewModel.swift`

**Features:**
- Goal breakdown table
- Monthly requirements per goal
- Total amount calculation
- Basic "Pay Now" button

#### Task 1.5: Navigation Integration
**Files to Modify:**
- `/Views/ContentView.swift` (add Planning tab)
- `/Views/Components/DetailContainerView.swift` (add monthly section)

---

## 🎛️ Phase 2: Enhanced Controls (Week 3-4)

### Week 3: Flex Controls

#### Task 2.1: Flex Adjustment Service  
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

#### Task 2.2: Master Flex Slider
**Files to Create:**
- `/Views/Components/FlexSlider.swift`
- `/Views/Components/GoalProtectionChips.swift`

**Features:**
- Interactive slider (0-100%)
- Live preview of adjustments
- Haptic feedback at key points
- Visual redistribution preview

#### Task 2.3: Goal Protection Controls
**Goal Chip States:**
- Protected: 🔒 (blue) - Don't reduce
- Flexible: 〰️ (gray) - Reduce first  
- Skip: ⏭️ (light gray) - Zero this month

### Week 4: Quick Actions & Preview

#### Task 2.4: Quick Action Buttons
**Files to Create:**
- `/Views/Components/QuickActionButtons.swift`

**Actions:**
- **Skip Month**: Set all flexible goals to 0
- **Pay Half**: Reduce all by 50%
- **Pay Exact**: Use calculated amounts

#### Task 2.5: "If You Pay Less" Preview
**Features:**
- Show impact on deadlines
- Display new monthly requirements
- Highlight affected goals
- Undo/reset functionality

---

## 🔄 Phase 3: Advanced Features (Week 5)

### Week 5: Payday Workflow & Platform Features

#### Task 3.1: Payday Reminder Integration
**Files to Create:**
- `/Services/PaydayReminderService.swift`
- `/Views/Payday/PaydayWorkflowView.swift`

**Features:**
- "Required Today" notifications
- Planned vs Actual comparison
- One-tap reminder creation
- Payment history tracking

#### Task 3.2: Advanced Redistribution Modes
**Implement All Modes:**
- Deadline-protect (default)
- Priority-protect (requires priority field)
- Even pain (pro-rate all)

#### Task 3.3: Platform-Specific Features

**iOS Features:**
- Home Screen Widget
- App Shortcuts integration  
- Dynamic Island support

**macOS Features:**
- Menu bar widget
- Keyboard shortcuts (Cmd+P)
- Hover state previews

---

## 🗂️ File Structure Overview

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

## 🧪 Testing Strategy

### Unit Tests
- MonthlyPlanningService calculations
- FlexAdjustmentService redistribution logic
- Goal extension computed properties
- Currency conversion accuracy

### Integration Tests  
- Planning view data flow
- Flex slider interactions
- Quick action behaviors
- Notification scheduling

### UI Tests
- Navigation flow
- Widget interactions
- Slider adjustments
- Button actions

---

## 📊 Success Criteria

### Phase 1 Success Metrics:
- [ ] Accurate monthly calculations for all goals
- [ ] Dashboard widget displays correctly
- [ ] Basic planning view shows goal breakdown
- [ ] Navigation integration works smoothly

### Phase 2 Success Metrics:
- [ ] Flex slider adjustments work correctly
- [ ] Redistribution logic handles edge cases
- [ ] Quick actions provide expected results
- [ ] Goal protection states persist correctly

### Phase 3 Success Metrics:
- [ ] Payday workflow creates proper reminders
- [ ] Platform features integrate seamlessly
- [ ] Performance remains smooth with complex calculations
- [ ] User testing shows positive feedback

---

## 🚨 Risk Mitigation

### Technical Risks:
- **Complex Calculations**: Start with simple math, add edge cases iteratively
- **Performance**: Cache calculations, use background threads for heavy operations
- **Currency Conversion**: Handle API failures gracefully with cached rates

### UX Risks:
- **Complexity Overwhelm**: Implement progressive disclosure strictly
- **Onboarding Confusion**: A/B test different introduction flows
- **Feature Discovery**: Ensure dashboard widget is prominent enough

### Data Risks:
- **Accuracy**: Validate calculations against manual verification
- **Edge Cases**: Test with zero goals, completed goals, past deadlines
- **Rounding**: Ensure totals match individual amounts after redistribution

---

## 🎯 Launch Strategy

### Soft Launch (Internal Testing):
1. Deploy to TestFlight with existing users
2. Gather feedback on calculation accuracy
3. Test with various goal configurations
4. Validate UX flow assumptions

### Public Launch:
1. Update App Store description
2. Create feature announcement
3. Monitor analytics and crash reports
4. Iterate based on user feedback

### Post-Launch Optimization:
1. Analyze usage patterns
2. Identify improvement opportunities  
3. Plan Phase 4 enhancements
4. Consider advanced features (budgets, forecasting)

---

**This roadmap transforms your cryptocurrency savings tracker from a passive monitoring tool into an active financial planning assistant that guides users toward their goals with intelligence and flexibility.**