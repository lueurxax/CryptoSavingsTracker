# Required Monthly Feature - Migration Guide

## Quick Migration Checklist

### ✅ Required Changes (Must Do)

#### 1. Update Model Container
```swift
// BEFORE
let container = try ModelContainer(for: Goal.self, Asset.self, Transaction.self)

// AFTER  
let container = try ModelContainer(for: 
    Goal.self, 
    Asset.self, 
    Transaction.self,
    MonthlyPlan.self  // 👈 Add this new model
)
```

#### 2. Update DIContainer
Add these methods to your `DIContainer.swift`:

```swift
// Add private property
private lazy var _monthlyPlanningService = MonthlyPlanningService(
    exchangeRateService: exchangeRateService
)

// Add public accessor
var monthlyPlanningService: MonthlyPlanningService {
    return _monthlyPlanningService
}

// Add factory method
func makeFlexAdjustmentService(modelContext: ModelContext) -> FlexAdjustmentService {
    return FlexAdjustmentService(
        planningService: monthlyPlanningService,
        modelContext: modelContext
    )
}
```

### 🎯 Optional Enhancements (Recommended)

#### 3. Add Planning Tab
```swift
TabView {
    // Your existing tabs...
    
    NavigationView {
        PlanningView(viewModel: MonthlyPlanningViewModel(modelContext: modelContext))
    }
    .tabItem {
        Image(systemName: "calendar.badge.clock")
        Text("Planning")
    }
}
```

#### 4. Add Dashboard Widget
```swift
// In your main dashboard view
VStack(spacing: 16) {
    // Existing dashboard widgets...
    
    MonthlyPlanningWidget(
        viewModel: MonthlyPlanningViewModel(modelContext: modelContext)
    )
}
```

---

## File Additions

Copy these new files to your project:

### Core Services
- `Services/MonthlyPlanningService.swift`
- `Services/FlexAdjustmentService.swift` 
- `Services/ExchangeRateService.swift` (enhanced)

### Data Models  
- `Models/MonthlyPlan.swift`
- `Models/MonthlyRequirement.swift`

### ViewModels
- `ViewModels/MonthlyPlanningViewModel.swift`

### UI Components
- `Views/Components/MonthlyPlanningWidget.swift`
- `Views/Components/FlexAdjustmentSlider.swift`
- `Views/Planning/PlanningView.swift`
- `Views/Planning/iOSCompactPlanningView.swift`
- `Views/Planning/iOSRegularPlanningView.swift` 
- `Views/Planning/macOSPlanningView.swift`
- `Views/Planning/GoalRequirementRow.swift`

### Utilities & Performance
- `Utilities/PerformanceOptimizer.swift`
- `Utilities/AccessibilityManager.swift`
- `Utilities/AccessibilityViewModifiers.swift`
- `Utilities/AccessibleColors.swift` (enhanced)

### Testing
- `CryptoSavingsTrackerTests/MonthlyPlanningTests.swift`
- `CryptoSavingsTrackerTests/FlexAdjustmentTests.swift`
- `CryptoSavingsTrackerTests/AccessibilityTests.swift`
- `CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`

---

## Common Migration Issues

### Issue 1: "Cannot find MonthlyPlan in scope"
**Solution**: Make sure you added `MonthlyPlan.swift` to your project and included it in ModelContainer.

### Issue 2: "No member 'monthlyPlanningService'"  
**Solution**: Update DIContainer.swift with the new service properties and methods.

### Issue 3: Build errors with AccessibleColors
**Solution**: The enhanced AccessibleColors file has new properties. Make sure you're using the updated version.

### Issue 4: Currency conversion not working
**Solution**: Verify your CoinGecko API key is set in Config.plist and not the placeholder value.

---

## Testing Your Migration

Run these tests to verify everything is working:

### 1. Basic Functionality Test
```swift
// In your app, create a test goal and verify monthly calculation appears
let testGoal = Goal(name: "Test", targetAmount: 12000, deadline: Date().addingTimeInterval(86400 * 365))
// Should see monthly requirement of ~$1000
```

### 2. Widget Test
- Open dashboard
- Look for "Required This Month" widget
- Tap "Show more" to expand
- Verify goal breakdown appears

### 3. Planning View Test
- Navigate to Planning tab
- Verify goals list appears  
- Test flex adjustment slider
- Check that adjustments update in real-time

### 4. Accessibility Test
- Enable VoiceOver (Settings > Accessibility > VoiceOver)
- Navigate through planning interface
- Verify currency amounts are spoken clearly
- Test focus indicators are visible

---

## Build Configuration

### Xcode Project Settings
Make sure these files are added to your target:
- All new Swift files should be added to main app target
- Test files should be added to appropriate test targets
- No changes to Info.plist required

### Dependencies
No new external dependencies required. The feature uses:
- SwiftUI (built-in)
- SwiftData (built-in)
- Combine (built-in)
- UserNotifications (built-in)

---

## Rollback Plan

If you need to rollback the migration:

### 1. Remove New Files
Delete all files listed in "File Additions" section above.

### 2. Revert Model Container
```swift  
// Revert to original
let container = try ModelContainer(for: Goal.self, Asset.self, Transaction.self)
```

### 3. Revert DIContainer
Remove the new monthlyPlanningService properties and methods.

### 4. Remove Navigation
Remove Planning tab from your main TabView.

**Note**: Your existing data (Goals, Assets, Transactions) will remain intact. Only the new monthly planning data will be lost.

---

## Performance Considerations

### Memory Usage
- Expected increase: ~10-50MB for caching
- Automatic cache cleanup every hour
- Memory pressure handling included

### CPU Usage  
- Background processing for calculations
- Batch API calls to reduce network overhead
- Intelligent caching reduces repeated calculations

### Battery Impact
- Minimal - calculations run on-demand
- Background processing uses .utility QoS
- Haptic feedback respects user preferences

---

## Support

After migration, if you encounter issues:

1. **Check Build Errors**: Usually missing files or incorrect ModelContainer setup
2. **Verify API Configuration**: CoinGecko API key in Config.plist  
3. **Run Tests**: Use included test suite to verify functionality
4. **Check Console**: Look for error messages with solutions

For detailed troubleshooting, see the full documentation: `REQUIRED_MONTHLY_DOCUMENTATION.md`

---

*Migration Guide v2.0.0 - Updated August 9, 2025*