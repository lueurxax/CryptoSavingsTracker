# Migration Fix: AssetAllocation fixedAmount

## Problem

When running the app with existing data, SwiftData migration failed with:

```
Error Domain=NSCocoaErrorDomain Code=134110
"An error occurred during persistent store migration."
UserInfo={
  entity=AssetAllocation,
  attribute=fixedAmount,
  reason=Validation error missing attribute values on mandatory destination attribute
}
```

## Root Cause

The `AssetAllocation` model was updated to include a new mandatory property `fixedAmount: Double`, but SwiftData couldn't automatically migrate existing records because:

1. Existing records had no value for `fixedAmount`
2. The property was defined as non-optional without a default value
3. SwiftData requires all mandatory attributes to have values during migration

## Solution

Added a default value to the `fixedAmount` property:

```swift
// Before (caused migration error):
var fixedAmount: Double

// After (allows automatic migration):
var fixedAmount: Double = 0.0
```

## How It Works

1. **SwiftData Automatic Migration**: When SwiftData detects the schema change, it:
   - Creates the new `fixedAmount` column
   - Populates all existing records with the default value `0.0`
   - Allows the app to start successfully

2. **Custom Migration**: After the app starts, our `AllocationMigrationService` runs:
   - Detects allocations with `fixedAmount = 0.0` and `legacyPercentage != nil`
   - Calculates the proper fixed amount from the percentage and current balance
   - Updates the `fixedAmount` to the correct value
   - Creates contribution history records

## Migration Flow

```
App Startup
    ↓
SwiftData Automatic Schema Migration
  • Adds fixedAmount column with default value 0.0
  • Existing records: fixedAmount = 0.0, legacyPercentage = previous %
    ↓
App Init (CryptoSavingsTrackerApp.swift:62)
    ↓
MigrationService.performMigrationIfNeeded()
    ↓
AllocationMigrationService.migrateToFixedAllocations()
  • For each allocation with fixedAmount = 0.0:
    - Calculate: fixedAmount = currentBalance × legacyPercentage
    - Update fixedAmount to calculated value
    - Create Contribution record for history
    ↓
Migration Complete ✅
```

## Testing the Fix

### Before Running:
```bash
# Delete existing database to test clean migration
rm -rf ~/Library/Containers/xax.CryptoSavingsTracker/Data/Library/Application\ Support/default.store*
```

### After Running:
Check migration logs in Console.app for:
```
🔄 Starting allocation migration to v2.0...
📊 Found X allocations to migrate
   Migrating allocation:
      Asset: BTC
      Goal: House Down Payment
      Balance: 1.5 BTC
      Percentage: 50%
      Fixed Amount: 0.75 BTC
      ✅ Created contribution record
✅ Migration completed successfully!
   Processed: X
   Failed: 0
```

## Files Modified

1. **Models/AssetAllocation.swift:16**
   - Added default value: `var fixedAmount: Double = 0.0`

## Related Documentation

- IMPROVEMENT_PLAN_V2.md - Original solution design
- TECHNICAL_FIXES_V2.md - Exchange rate and unit separation fixes
- Services/AllocationMigrationService.swift - Custom migration logic
- Services/MigrationService.swift - Migration orchestration

## Prevention

For future model changes:
1. Always provide default values for new mandatory properties
2. Or make new properties optional during transition period
3. Test migration with existing database before release
4. Consider using SwiftData VersionedSchema for complex migrations
