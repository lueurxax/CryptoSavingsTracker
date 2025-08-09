# Screenshot Guide for CryptoSavingsTracker

This guide will help you capture professional screenshots for the README that showcase the app's key features and cross-platform experience.

## 📱 iOS Screenshots (iPhone)

### Setup
1. Use iPhone 15 Pro or iPhone 15 Pro Max simulator for best quality
2. Use Light mode for consistency
3. Create sample data before screenshots

### Required Screenshots

#### 1. `ios-goals-list.png` - Main Goals List
- **What to show**: Main screen with 2-3 sample goals
- **Sample data**: 
  - "Vacation Fund" - $5000 USD, 30% progress
  - "Emergency Savings" - $10000 USD, 67% progress  
  - "New Car" - $25000 USD, 12% progress
- **Key elements**: Progress bars, amounts, deadlines
- **How to capture**: Navigate to main screen, take screenshot with Cmd+Shift+4

#### 2. `ios-goal-details.png` - Goal Detail View
- **What to show**: Detailed view of one goal with assets
- **Sample data**: "Vacation Fund" with BTC, ETH assets
- **Key elements**: 
  - Progress ring at the top
  - Edit/Delete buttons (our new feature!)
  - Asset list with balances
  - Charts section (expanded)
- **How to capture**: Tap on a goal, ensure charts are expanded

#### 3. `ios-add-goal.png` - Add New Goal Screen
- **What to show**: Goal creation form
- **Key elements**:
  - Goal name field
  - Currency picker (USD selected)
  - Target amount field
  - Deadline picker
  - Save button
- **How to capture**: Tap "+" button, fill in sample data partially

#### 4. `ios-add-asset.png` - Add Asset Screen
- **What to show**: Asset creation form
- **Key elements**:
  - Currency selection (BTC or ETH)
  - Optional address field
  - Chain selection if address is filled
  - Form validation
- **How to capture**: From goal detail, tap "Add Asset"

#### 5. `ios-currency-picker.png` - Currency Search & Selection
- **What to show**: Currency picker with search
- **Key elements**:
  - Search bar with "BTC" typed
  - Smart sorting in action (Bitcoin at top)
  - List of cryptocurrencies with symbols and names
- **How to capture**: In Add Asset, tap currency field, type "BTC"

#### 6. `ios-progress.png` - Progress Tracking
- **What to show**: Goal with good progress and charts
- **Key elements**:
  - Large progress ring showing 67%+
  - Balance history chart
  - Asset composition pie chart
  - Timeline view
- **How to capture**: Select goal with multiple assets and transactions

## 💻 macOS Screenshots

### Setup
1. Use standard macOS window size (not fullscreen)
2. Use Light mode for consistency
3. Position window nicely on screen

### Required Screenshots

#### 1. `macos-main.png` - Split View Interface
- **What to show**: Main macOS interface with sidebar
- **Key elements**:
  - Goals sidebar on left with 3-4 goals
  - Goal detail view on right
  - Native macOS styling
  - Toolbar with edit/delete buttons (our new feature!)
- **How to capture**: Cmd+Shift+3 or Cmd+Shift+4 for selection

#### 2. `macos-goal-management.png` - Goal Management
- **What to show**: Context menu or edit functionality
- **Key elements**:
  - Right-click context menu on sidebar goal
  - OR edit goal sheet open
  - Show edit/delete options clearly
- **How to capture**: Right-click on goal in sidebar

#### 3. `macos-assets.png` - Asset Management
- **What to show**: Asset view with macOS-specific features
- **Key elements**:
  - Asset list in detail view
  - macOS-style buttons and controls
  - Add Asset popover (if possible)
- **How to capture**: Click "Add Asset" to show popover

## 🎨 Screenshot Best Practices

### Data Preparation
1. **Create realistic sample data**:
   ```
   Goals:
   - "Emergency Fund" ($10,000 USD, 67% complete, 45 days left)
   - "Vacation Savings" ($5,000 USD, 34% complete, 120 days left)  
   - "New Car" ($25,000 USD, 12% complete, 365 days left)
   
   Assets per goal:
   - Bitcoin (BTC): $2,450
   - Ethereum (ETH): $1,200
   - Solana (SOL): $350
   ```

2. **Use round numbers** for better visual appeal
3. **Show progress** - avoid 0% or 100% goals
4. **Include dates** that make sense (future deadlines)

### Visual Quality
- **High resolution**: Use 2x or 3x simulator scales
- **Good lighting**: Light mode with proper contrast
- **Clean UI**: No debug info or placeholder text
- **Consistent sizing**: All screenshots should be similar scale

### Platform-Specific Tips

#### iOS:
- Show native iOS elements (navigation bars, toolbars)
- Capture swipe actions if possible
- Show context menus on long press
- Demonstrate the new unified currency sorting

#### macOS:
- Show split-view layout clearly
- Highlight toolbar buttons (our edit/delete feature)
- Demonstrate popover vs sheet differences
- Show right-click context menus

## 📸 Taking Screenshots

### iOS Simulator:
1. Open iOS Simulator
2. Choose "Device" > "Screenshot" or Cmd+S
3. Screenshots save to Desktop by default

### macOS App:
1. Use Cmd+Shift+4 for selection tool
2. Cmd+Shift+3 for full screen
3. Use Preview to crop/adjust if needed

### File Naming:
- Use exact names from README: `ios-goals-list.png`, etc.
- Save as PNG format
- Optimize file sizes (under 500KB each)

## 🚀 After Capturing

1. **Review each screenshot** for clarity and content
2. **Resize if needed** to consistent dimensions
3. **Place in `/docs/screenshots/` directory**
4. **Test README** to ensure all images display correctly
5. **Commit and push** the screenshots with the README update

## 📋 Screenshot Checklist

### iOS Screenshots:
- [ ] `ios-goals-list.png` - Main goals screen
- [ ] `ios-goal-details.png` - Goal detail with edit buttons
- [ ] `ios-add-goal.png` - Goal creation form  
- [ ] `ios-add-asset.png` - Asset creation form
- [ ] `ios-currency-picker.png` - Smart currency search
- [ ] `ios-progress.png` - Progress tracking with charts

### macOS Screenshots:
- [ ] `macos-main.png` - Split-view interface
- [ ] `macos-goal-management.png` - Edit/delete functionality
- [ ] `macos-assets.png` - Asset management

### Quality Check:
- [ ] All images under 500KB
- [ ] Consistent lighting/theme
- [ ] Realistic sample data
- [ ] Key features highlighted
- [ ] No debug/placeholder content

Good luck! These screenshots will really showcase the professional quality and cross-platform nature of your app! 📱💻