//
//  PlatformCapabilities.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import Combine

// MARK: - Platform Capabilities Protocol

/// Defines platform-specific capabilities and behaviors
protocol PlatformCapabilities {
    /// Whether the platform supports multiple windows
    var supportsMultiWindow: Bool { get }
    
    /// Whether the platform supports keyboard shortcuts
    var supportsKeyboardShortcuts: Bool { get }
    
    /// Whether the platform supports hover states
    var supportsHoverStates: Bool { get }
    
    /// Whether the platform supports widgets
    var supportsWidgets: Bool { get }
    
    /// Whether the platform supports gesture navigation
    var supportsGestureNavigation: Bool { get }
    
    /// Default padding for the platform
    var defaultPadding: CGFloat { get }
    
    /// Minimum touch target size for accessibility
    var minTouchTargetSize: CGFloat { get }
    
    /// Default animation duration
    var defaultAnimationDuration: Double { get }
    
    /// Navigation style preference
    var navigationStyle: NavigationStylePreference { get }
}

// MARK: - Navigation Style Preference

enum NavigationStylePreference {
    case stack          // iPhone-style navigation
    case splitView      // iPad/macOS-style navigation
    case tabs           // Tab-based navigation
}

// MARK: - Platform Implementations

#if os(iOS)
struct iOSCapabilities: PlatformCapabilities {
    var supportsMultiWindow: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var supportsKeyboardShortcuts: Bool { false }
    var supportsHoverStates: Bool { false }
    var supportsWidgets: Bool { true }
    var supportsGestureNavigation: Bool { true }
    var defaultPadding: CGFloat { 16 }
    var minTouchTargetSize: CGFloat { 44 }
    var defaultAnimationDuration: Double { 0.3 }
    var navigationStyle: NavigationStylePreference {
        UIDevice.current.userInterfaceIdiom == .pad ? .splitView : .stack
    }
}
#endif

#if os(macOS)
struct macOSCapabilities: PlatformCapabilities {
    var supportsMultiWindow: Bool { true }
    var supportsKeyboardShortcuts: Bool { true }
    var supportsHoverStates: Bool { true }
    var supportsWidgets: Bool { false }
    var supportsGestureNavigation: Bool { false }
    var defaultPadding: CGFloat { 20 }
    var minTouchTargetSize: CGFloat { 32 }
    var defaultAnimationDuration: Double { 0.2 }
    var navigationStyle: NavigationStylePreference { .splitView }
}
#endif

#if os(visionOS)
struct visionOSCapabilities: PlatformCapabilities {
    var supportsMultiWindow: Bool { true }
    var supportsKeyboardShortcuts: Bool { false }
    var supportsHoverStates: Bool { true }
    var supportsWidgets: Bool { false }
    var supportsGestureNavigation: Bool { true }
    var defaultPadding: CGFloat { 24 }
    var minTouchTargetSize: CGFloat { 48 }
    var defaultAnimationDuration: Double { 0.4 }
    var navigationStyle: NavigationStylePreference { .splitView }
}
#endif

// MARK: - Platform Manager

/// Centralized manager for platform-specific behavior
@MainActor
class PlatformManager: ObservableObject {
    static let shared = PlatformManager()
    
    private init() {}
    
    /// Current platform capabilities
    var capabilities: PlatformCapabilities {
        #if os(iOS)
        return iOSCapabilities()
        #elseif os(macOS)
        return macOSCapabilities()
        #elseif os(visionOS)
        return visionOSCapabilities()
        #else
        return iOSCapabilities() // Fallback
        #endif
    }
    
    /// Get appropriate button style for the platform
    func buttonStyle<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        if capabilities.supportsHoverStates {
            return AnyView(Button(action: {}, label: content).buttonStyle(MacOSHoverButtonStyle()))
        }
        #endif
        return AnyView(Button(action: {}, label: content).buttonStyle(.plain))
    }
    
    /// Get platform-appropriate animation
    func animation() -> Animation {
        return .easeInOut(duration: capabilities.defaultAnimationDuration)
    }
    
    /// Get minimum touch target modifier
    func minTouchTarget() -> some ViewModifier {
        return MinTouchTargetModifier(minSize: capabilities.minTouchTargetSize)
    }
}

// MARK: - Custom Modifiers

struct MinTouchTargetModifier: ViewModifier {
    let minSize: CGFloat
    
    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize)
    }
}

// MARK: - Platform-Specific Button Styles

#if os(macOS)
struct MacOSHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        configuration.isPressed ? 
                        Color.blue.opacity(0.15) : 
                        Color.clear
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

// MARK: - SwiftUI Environment Extensions

private struct PlatformCapabilitiesKey: EnvironmentKey {
    static let defaultValue: PlatformCapabilities = {
        #if os(iOS)
        return iOSCapabilities()
        #elseif os(macOS)
        return macOSCapabilities()
        #elseif os(visionOS)
        return visionOSCapabilities()
        #else
        return iOSCapabilities()
        #endif
    }()
}

extension EnvironmentValues {
    var platformCapabilities: PlatformCapabilities {
        get { self[PlatformCapabilitiesKey.self] }
        set { self[PlatformCapabilitiesKey.self] = newValue }
    }
}

// MARK: - Convenience View Extensions

extension View {
    /// Apply platform-appropriate minimum touch target size
    func platformTouchTarget() -> some View {
        let platform = PlatformManager.shared
        return self.modifier(platform.minTouchTarget())
    }
    
    /// Apply platform-appropriate padding
    func platformPadding() -> some View {
        let platform = PlatformManager.shared
        return self.padding(platform.capabilities.defaultPadding)
    }
    
    /// Apply platform-appropriate animation
    func platformAnimation<T: Equatable>(value: T) -> some View {
        let platform = PlatformManager.shared
        return self.animation(platform.animation(), value: value)
    }
}