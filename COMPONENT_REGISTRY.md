# 🔍 Component Registry - Quick Reference Guide

*Searchable index of all UI components in CryptoSavingsTracker*

## 🎯 Goal Display Components

### Primary Components
- **`GoalRowView`** - iOS goal list row display
  - **File**: `/Views/GoalsListView.swift:183`
  - **Platform**: iOS 
  - **Features**: Emoji, progress bar, status badges, description preview
  - **Dependencies**: `GoalCalculationService`, `AccessibleColors`

- **`GoalSidebarRow`** - macOS sidebar goal entry
  - **File**: `/Views/Components/GoalsSidebarView.swift:89`
  - **Platform**: macOS
  - **Features**: Emoji, progress bar, progress percentage
  - **Dependencies**: `GoalCalculationService`

### Supporting Components
- **`GoalRowIconView`** - Emoji/icon display
  - **File**: `/Views/GoalsListView.swift:386`
  - **Purpose**: Unified emoji or SF Symbol fallback

- **`GoalRowContentView`** - Main content layout
  - **File**: `/Views/GoalsListView.swift:400`
  - **Purpose**: Name, status badge, details

- **`GoalRowDetailsView`** - Secondary information
  - **File**: `/Views/GoalsListView.swift:440`
  - **Purpose**: Days remaining, target amounts

- **`GoalRowProgressView`** - Animated progress bar
  - **File**: `/Views/GoalsListView.swift:465`
  - **Purpose**: Color-coded progress visualization

- **`GoalRowChevronView`** - Navigation indicator
  - **File**: `/Views/GoalsListView.swift:482`
  - **Purpose**: Right-pointing chevron

## 📝 Goal Management Components

### Editing Components
- **`EditGoalView`** - Main goal editing interface
  - **File**: `/Views/EditGoalView.swift:12`
  - **Platform**: Universal
  - **Features**: All goal properties, validation, preview

- **`CustomizationSection`** - Visual customization
  - **File**: `/Views/EditGoalView.swift:437`
  - **Features**: Emoji picker, description, link fields

- **`EmojiPickerField`** - Emoji selection interface
  - **File**: `/Views/EditGoalView.swift:471`
  - **Features**: Current emoji display, smart suggestions

- **`EmojiPickerView`** - Full emoji selection modal
  - **File**: `/Views/Components/EmojiPickerView.swift:1`
  - **Features**: 120+ emojis, 10 categories, search

### Form Components
- **`FormSection`** - Styled form sections
  - **File**: `/Views/EditGoalView.swift:283`
  - **Purpose**: Consistent section headers with icons

- **`FormField`** - Form field layout
  - **File**: `/Views/EditGoalView.swift:319`
  - **Purpose**: Label + content standardization

- **`ValidationErrorsView`** - Error display
  - **File**: `/Views/EditGoalView.swift:340`
  - **Purpose**: User-friendly error messaging

## 📊 List and Container Components

### List Views
- **`GoalsListView`** - iOS main goal list
  - **File**: `/Views/GoalsListView.swift:12`
  - **Platform**: iOS
  - **Features**: Monthly planning widget, goal rows, swipe actions

- **`GoalsList`** - Alternative list implementation
  - **File**: `/Views/ContentView.swift:110`
  - **Platform**: Universal
  - **Features**: Empty states, monthly planning

- **`GoalsListContainer`** - iOS container view
  - **File**: `/Views/Goals/GoalsListContainer.swift:14`
  - **Platform**: iOS
  - **Features**: Navigation stack, context menus

### Sidebar Components
- **`GoalsSidebarView`** - macOS sidebar container
  - **File**: `/Views/Components/GoalsSidebarView.swift:12`
  - **Platform**: macOS
  - **Features**: Portfolio overview, goal list, context menus

- **`GoalSidebarContextMenu`** - Context menu actions
  - **File**: `/Views/Components/GoalsSidebarView.swift:170`
  - **Purpose**: Edit, delete, add actions

## 🎨 Visual Components

### Progress Visualization
- **`HeroProgressView`** - Large progress display
  - **File**: `/Views/Components/HeroProgressView.swift`
  - **Features**: Circular progress, animations

- **`ProgressRingView`** - Animated progress ring
  - **File**: `/Views/Charts/ProgressRingView.swift`
  - **Features**: SVG-style ring with percentage

### Charts and Analytics
- **`LineChartView`** - Line chart visualization
  - **File**: `/Views/Charts/LineChartView.swift`
  - **Features**: Trend visualization

- **`SimpleLineChartView`** - Simplified line chart
  - **File**: `/Views/Charts/SimpleLineChartView.swift`
  - **Features**: Basic trend display

## 🏗️ Layout and Navigation

### Platform-Specific Views
- **`ContentView`** - Platform router
  - **File**: `/Views/ContentView.swift:14`
  - **Purpose**: Platform-specific navigation

- **`iOSContentView`** - iOS navigation
  - **File**: `/Views/ContentView.swift:30` *(inferred)*
  - **Platform**: iOS
  - **Pattern**: NavigationStack

- **`macOSContentView`** - macOS navigation
  - **File**: `/Views/ContentView.swift` *(inferred)*
  - **Platform**: macOS  
  - **Pattern**: NavigationSplitView

### Empty States
- **`EmptyStateView`** - No data states
  - **File**: `/Views/Components/EmptyStateView.swift`
  - **Purpose**: User-friendly empty states

- **`EmptyGoalsView`** - No goals state
  - **File**: `/Views/Components/EmptyGoalsView.swift`
  - **Features**: Onboarding prompts

## 🔧 Utility Components

### Interactive Elements
- **`FlexAdjustmentSlider`** - Payment adjustment
  - **File**: `/Views/Components/FlexAdjustmentSlider.swift`
  - **Features**: 0-200% payment adjustment

- **`MonthlyPlanningWidget`** - Planning overview
  - **File**: `/Views/Components/MonthlyPlanningWidget.swift`
  - **Features**: Required payments display

### UI Helpers
- **`AccessibleColors`** - Color system
  - **File**: `/Utilities/AccessibleColors.swift`
  - **Purpose**: WCAG-compliant color palette

- **`HapticManager`** - Haptic feedback
  - **File**: `/Utilities/HapticManager.swift`
  - **Purpose**: Contextual vibrations

## 🔍 Search Guide

### Finding Components by Purpose

**Goal Display**: Search for `GoalRow`, `GoalSidebar`
```bash
grep -r "GoalRow\|GoalSidebar" --include="*.swift" .
```

**Progress Bars**: Search for `progress`, `ProgressView`
```bash
grep -r "progress.*bar\|ProgressView" --include="*.swift" .
```

**Emoji Components**: Search for `emoji`, `EmojiPicker`
```bash
grep -r "emoji\|EmojiPicker" --include="*.swift" .
```

**Platform-Specific**: Search for `#if os`, platform conditionals
```bash
grep -r "#if os\|platform\|iOS\|macOS" --include="*.swift" .
```

### Finding Components by File

**Main Lists**: Look in `/Views/GoalsListView.swift`, `/Views/Components/GoalsSidebarView.swift`
**Editing**: Look in `/Views/EditGoalView.swift`
**Components**: Look in `/Views/Components/`
**Charts**: Look in `/Views/Charts/`

### Finding Components by Platform

**iOS-Specific**:
- `GoalRowView` in `GoalsListView.swift`
- `GoalsListContainer.swift`
- Navigation patterns in `ContentView.swift`

**macOS-Specific**:
- `GoalSidebarRow` in `GoalsSidebarView.swift`
- Sidebar patterns
- Sheet presentations

**Universal**:
- All service layer components
- Model definitions
- Utility components

## 📋 Component Status

### ✅ Well-Architected
- Service layer (calculation, exchange rates)
- SwiftData models
- Logging system
- Platform capabilities

### ⚠️ Needs Refactoring
- **Goal display duplication** (iOS vs macOS)
- **Mixed async patterns** (deprecated methods still used)
- **Platform conditionals** (should use abstraction)

### ❌ Missing
- **Unified goal row component**
- **Complete platform abstraction**
- **Component composition system**
- **Comprehensive testing components**

## 🚀 Quick Actions

### To Modify Goal Display:
1. Update `GoalRowView` in `/Views/GoalsListView.swift:183`
2. Update `GoalSidebarRow` in `/Views/Components/GoalsSidebarView.swift:89`
3. Test on both iOS and macOS
4. Update this registry

### To Add New Goal Feature:
1. Update `Goal` model in `/Models/Item.swift`
2. Update `EditGoalView` customization section
3. Update all goal display components
4. Update calculation services if needed

### To Fix Platform Issues:
1. Check platform abstraction in `/Views/ContentView.swift`
2. Look for `#if os()` conditionals
3. Consider moving to protocol-based abstraction

---

*Last Updated: August 2025*
*Update this registry when adding, modifying, or removing components*