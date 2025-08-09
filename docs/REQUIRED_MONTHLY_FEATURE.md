# Required Monthly Feature - Complete UX Review & Implementation Plan

## 📋 Feature Overview

**Core Concept**: "Required Monthly" — zero-input planning feature that automatically calculates monthly savings requirements from existing goals.

### What the app computes automatically:
For each goal (in its own currency):
- `Remaining = max(0, target - current)`
- `Months left = months from today → deadline (round up)`
- `Required Monthly = Remaining / Months left`

And: `Total Required This Month = sum of all goals' Required Monthly, converted to display currency`

### What users see:
- Header chip: "Required this month: €X by [payday]"
- Per-goal table with progress, Required Monthly, and "If you pay less" preview
- Quick actions: Skip this month, Half, Exact

### Flex Controls (without budgets):
1. **Master Flex Slider** - drag from 100% down to adjust total payment
2. **Goal Chips** - per goal: Protect/Flexible/Skip settings

### Redistribution modes:
- **Deadline-protect** (default): reduce payments on goals with most slack
- **Priority-protect**: reduce lowest-priority goals first  
- **Even pain**: pro-rate reductions across all flexible goals

### Payday workflow:
- Show "Required today: €X"
- Compare Planned vs Actual from last time
- One tap: Create reminders for each goal

## 🎨 UX Review Results

### Integration Strategy

#### Navigation Architecture:
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

#### Primary Access Points:
1. **Dashboard Widget**: "Required: €1,234 by Dec 31" - High visibility
2. **Planning Tab**: Dedicated section for comprehensive view  
3. **Goal Details**: Context-specific monthly requirements

### User Experience Flow

**Discovery → Understanding → Action → Confirmation**

1. **Discovery Phase**: Dashboard widget with "€X required this month"
2. **Progressive Engagement**:
   - Level 1: See total required (Dashboard widget)
   - Level 2: Tap to view breakdown (Planning view)
   - Level 3: Adjust with Flex controls (Advanced mode)
   - Level 4: Execute payday workflow (Action mode)

### Visual Design Approach

#### Dashboard Widget:
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

#### Full Planning View:
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

#### Color Strategy:
- **Green** (On Track): Goals meeting requirements
- **Orange** (Attention): Goals slightly behind
- **Red** (Critical): Goals significantly behind
- **Blue** (Interactive): Buttons and controls
- Use existing `AccessibleColors` for consistency

### Interaction Design

#### Flex Slider Interaction:
- Visual Feedback: Live preview, color gradient, haptic feedback
- Smart Defaults: Snap to 25%, 50%, 75%, 100%
- Remember user preferences

#### Goal Chips Interaction:
```
Three-state toggle: [Protected] → [Flexible] → [Skip]
Visual: 
  Protected: 🔒 (blue background)
  Flexible: 〰️ (gray background)
  Skip: ⏭️ (light gray, strikethrough)
```

### Progressive Disclosure Strategy

#### Three-Tier Complexity:

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

### Platform-Specific Features

#### iOS Recommendations:
- **Widget Support**: Home screen widget showing monthly requirement
- **3D Touch/Haptic Touch**: Quick actions from app icon
- **Dynamic Island**: Payment reminders on payday
- **Swipe Actions**: Quick pay from goal list

#### macOS Recommendations:
- **Menu Bar Widget**: Always-visible monthly requirement
- **Keyboard Shortcuts**: Cmd+P for quick payment
- **Hover States**: Show "if you pay less" on hover
- **Multi-window**: Detachable planning window

### Onboarding Strategy

#### Discovery Approach:
1. **Soft Introduction**: "💡 New: See your monthly savings requirement"
2. **Guided Tour**: Interactive 4-step walkthrough
3. **Progressive Education**: Just-in-time tooltips

#### Principles:
- **Just-in-time**: Introduce features when relevant
- **Skippable**: Never force education
- **Contextual**: Learn by doing, not reading

### Edge Cases & Error States

#### Critical Scenarios:
- **No Goals**: "Create your first savings goal to see monthly requirements"
- **All Goals Completed**: "🎉 All goals achieved! No payments required"
- **Impossible Requirements**: "⚠️ Monthly requirement exceeds typical deposits"
- **Past Deadline**: "Goal deadline has passed"

#### Data Edge Cases:
- Negative balances: Show as zero, add explanation
- Currency conversion failures: Show cached rates with timestamp
- Large numbers: Use abbreviations (€1.2M)
- Zero months remaining: Show "Due Now"

### Accessibility Considerations

#### WCAG 2.1 AA Compliance:
- Minimum contrast ratio 4.5:1 for all text
- Color not sole indicator (add icons/patterns)
- Focus indicators minimum 3px outline
- Sufficient touch targets (44x44 pts minimum)

#### Screen Reader Support:
```swift
// Semantic labeling examples
"Monthly requirement: 1,234 euros by December 31st"
"Bitcoin goal: 500 euros required, currently on track"
"Adjustment slider: Currently at 100 percent"
```

#### Keyboard Navigation:
- Tab order follows visual hierarchy
- Slider adjustable with arrow keys (5% increments)
- All actions keyboard accessible
- Escape key closes modals

## 🚀 Implementation Plan

### Phase 1 MVP (2 weeks):
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

### Phase 2 Enhanced (2 weeks):
1. **Flex Controls**
   - Master slider
   - Even redistribution mode
   
2. **Quick Actions**
   - Skip/Half/Exact buttons
   - Preview calculations
   
3. **Payday Workflow**
   - Reminder integration
   - Planned vs Actual tracking

### Phase 3 Advanced (1 week):
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

## 📊 Success Metrics

### Key Performance Indicators:
- Feature discovery rate
- Engagement depth (% using flex controls)
- Payment completion rate
- User satisfaction scores
- Time to first payment
- Recurring usage patterns

### Analytics to Track:
- Monthly requirement accuracy
- Flex adjustment frequency
- Goal completion improvement
- User retention impact

## 🛠️ Technical Implementation Notes

### Calculation Service Structure:
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

### Data Model Extensions:
```swift
extension Goal {
    var monthsRemaining: Int { /* calculation */ }
    var monthlyRequirement: Double { /* calculation */ }
    var isOnTrack: Bool { /* calculation */ }
}
```

### Service Layer:
- `MonthlyPlanningService`: Core calculations
- `FlexAdjustmentService`: Redistribution logic
- `PaydayReminderService`: Notification management

## 🎯 Key UX Recommendations Summary

1. **Start Simple**: Launch with MVP focused on clarity over features
2. **Test Iteratively**: A/B test flex control designs with user subset
3. **Prioritize Understanding**: Ensure users grasp calculations before adding complexity
4. **Mobile-First Design**: Optimize for one-handed phone use
5. **Contextual Help**: Embed education within the interface
6. **Performance Metrics**: Track feature adoption and payment completion rates
7. **Accessibility First**: Build in accessibility from the start, not as an afterthought

## 💡 Why This Feature is Transformative

### Current State: Passive Tracking
- Users manually check progress
- No guidance on required actions
- Complex mental math for deadlines

### Future State: Active Planning Assistant
- Automatic monthly requirement calculations
- Flexible payment options
- Smart redistribution when needed
- Seamless reminder integration

### Business Impact:
- **Increased Engagement**: Daily/weekly active usage
- **Goal Achievement**: Higher completion rates
- **User Retention**: Planning creates habit formation
- **Differentiation**: Unique value proposition vs competitors

---

**Last Updated**: August 8, 2025  
**Status**: Design Complete, Ready for Implementation  
**Priority**: High - Core Feature Enhancement