# Professional Logging System

## Requirements

1. **Always use AppLog (AppLogger)** for all logging
   - Located in `/CryptoSavingsTracker/Utilities/Logger.swift`
   - Type alias: `AppLog = AppLogger`

2. **Never use print() statements**
   - Replace all `print()` with appropriate `AppLog` calls
   - Remove debug print statements before committing

3. **Log Categories**
   - Use existing categories from `AppLogger.Category` enum
   - Categories: goalList, goalEdit, transactionHistory, exchangeRate, balanceService, chainService, notification, dataCompatibility, swiftData, ui, api, cache, validation, performance, monthlyPlanning, accessibility

4. **Log Levels**
   - debug: Development debugging information
   - info: General information about app state
   - warning: Potential issues that don't prevent operation
   - error: Errors that affect functionality
   - fault: Critical errors that may crash the app

5. **Usage Example**
   ```swift
   AppLog.debug("Loading transactions - Goal: \(goal.name), Total: \(count)", category: .transactionHistory)
   AppLog.error("Failed to load: \(error)", category: .api)
   ```

6. **Formatting**
   - Logs automatically include: emoji, category, message, file, function, line
   - Output format: `🔍 [TransactionHistory] Loading transactions... (File.swift:functionName():123)`

## Violations
- Using `print()` statements
- Using custom debug prefixes like "🔍 DEBUG:"
- Not using appropriate categories
- Creating inline debug output with `let _ = print()`