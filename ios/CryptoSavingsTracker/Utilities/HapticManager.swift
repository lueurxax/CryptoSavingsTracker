//
//  HapticManager.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// Manages haptic feedback with proper simulator handling to prevent console warnings
final class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    /// Provides light haptic feedback (button taps, selections)
    func impact(_ style: ImpactStyle = .light) {
        #if os(iOS) && !targetEnvironment(simulator)
        // Only run haptics on real devices to prevent CHHapticPattern warnings
        let impactGenerator = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        impactGenerator.prepare()
        impactGenerator.impactOccurred()
        #endif
    }
    
    /// Provides notification feedback (success, error, warning)
    func notification(_ type: NotificationType) {
        #if os(iOS) && !targetEnvironment(simulator)
        // Only run haptics on real devices to prevent CHHapticPattern warnings
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type.uiKitType)
        #endif
    }
    
    /// Provides selection feedback (picker changes, toggles)
    func selection() {
        #if os(iOS) && !targetEnvironment(simulator)
        // Only run haptics on real devices to prevent CHHapticPattern warnings
        let selectionGenerator = UISelectionFeedbackGenerator()
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
        #endif
    }
}

// MARK: - Supporting Types

extension HapticManager {
    enum ImpactStyle {
        case light
        case medium
        case heavy
        
        #if os(iOS)
        var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: return .light
            case .medium: return .medium
            case .heavy: return .heavy
            }
        }
        #endif
    }
    
    enum NotificationType {
        case success
        case warning
        case error
        
        #if os(iOS)
        var uiKitType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            }
        }
        #endif
    }
}

// MARK: - SwiftUI Integration

#if os(iOS)
import SwiftUI

extension View {
    /// Adds haptic feedback to button taps and interactions
    func hapticFeedback(_ style: HapticManager.ImpactStyle = .light, on trigger: some Equatable) -> some View {
        self.onChange(of: trigger) { _, _ in
            HapticManager.shared.impact(style)
        }
    }
    
    /// Adds haptic feedback for successful actions
    func successHaptic(on trigger: some Equatable) -> some View {
        self.onChange(of: trigger) { _, _ in
            HapticManager.shared.notification(.success)
        }
    }
    
    /// Adds haptic feedback for error states
    func errorHaptic(on trigger: some Equatable) -> some View {
        self.onChange(of: trigger) { _, _ in
            HapticManager.shared.notification(.error)
        }
    }
}
#endif