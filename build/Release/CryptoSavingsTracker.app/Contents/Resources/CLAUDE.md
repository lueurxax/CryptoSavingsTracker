# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CryptoSavingsTracker is a cross-platform SwiftUI application that helps users track cryptocurrency savings goals. The app supports iOS, macOS, visionOS, and uses SwiftData for local persistence.

## Architecture

The application follows the standard SwiftUI + SwiftData pattern:

- **App Entry Point**: `CryptoSavingsTrackerApp.swift` - Sets up the main app with ModelContainer for SwiftData
- **Data Models**: `Item.swift` - Contains two main models:
  - `Goal`: Represents a savings goal with currency, target amount, deadline, and transactions
  - `Transaction`: Individual deposits/contributions to a goal
- **Views**: `ContentView.swift` - Main interface (currently placeholder structure)

The data model uses SwiftData relationships where Goal has many Transactions (cascade delete), and Transaction belongs to one Goal.

## Development Commands

### Building and Running
```bash
# Open in Xcode
open CryptoSavingsTracker.xcodeproj

# Build from command line
xcodebuild -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -configuration Debug

# Build for specific destination
xcodebuild -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

### Testing
```bash
# Run unit tests
xcodebuild test -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination "platform=iOS Simulator,name=iPhone 15 Pro"

# Run UI tests  
xcodebuild test -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

## Key Configuration Details

- **Bundle ID**: `xax.CryptoSavingsTracker`
- **Deployment Targets**: iOS 26.0, macOS 15.5, visionOS 26.0
- **Swift Version**: 5.0
- **Uses SwiftData**: For local data persistence
- **Multi-platform**: Supports iPhone, iPad, Mac, and Vision Pro
- **App Sandbox**: Enabled for security
- **File Access**: Read-only user selected files enabled