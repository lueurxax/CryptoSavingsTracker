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
    
    /// Whether the platform supports haptic feedback
    var supportsHapticFeedback: Bool { get }
    
    /// Default padding for the platform
    var defaultPadding: CGFloat { get }
    
    /// Minimum touch target size for accessibility
    var minTouchTargetSize: CGFloat { get }
    
    /// Default animation duration
    var defaultAnimationDuration: Double { get }
    
    /// Navigation style preference
    var navigationStyle: NavigationStylePreference { get }
    
    /// Modal presentation style preference
    var modalPresentationStyle: ModalPresentationStyle { get }
    
    /// Window management capabilities
    var windowCapabilities: WindowCapabilities { get }
}

// MARK: - Supporting Types

enum NavigationStylePreference {
    case stack          // iPhone-style navigation
    case splitView      // iPad/macOS-style navigation
    case tabs           // Tab-based navigation
}

enum ModalPresentationStyle {
    case sheet          // Full screen or form sheet
    case popover        // Small contextual overlay
    case fullScreen     // Complete takeover
}

struct WindowCapabilities {
    let supportsMultiple: Bool
    let supportsResizing: Bool
    let supportsMinimumSize: Bool
    let defaultSize: (width: CGFloat, height: CGFloat)?
}

enum HapticStyle {
    case light
    case medium
    case heavy
    
    #if os(iOS)
    func mapToHapticManager() -> HapticManager.ImpactStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        }
    }
    #endif
}

enum HapticNotificationType {
    case success
    case warning
    case error
    
    #if os(iOS)
    func mapToHapticManager() -> HapticManager.NotificationType {
        switch self {
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
    #endif
}

// MARK: - Platform Implementations

#if os(iOS)
struct iOSCapabilities: PlatformCapabilities {
    var supportsMultiWindow: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var supportsKeyboardShortcuts: Bool { false }
    var supportsHoverStates: Bool { false }
    var supportsWidgets: Bool { true }
    var supportsGestureNavigation: Bool { true }
    var supportsHapticFeedback: Bool { true }
    var defaultPadding: CGFloat { 16 }
    var minTouchTargetSize: CGFloat { 44 }
    var defaultAnimationDuration: Double { 0.3 }
    
    var navigationStyle: NavigationStylePreference {
        UIDevice.current.userInterfaceIdiom == .pad ? .splitView : .stack
    }
    
    var modalPresentationStyle: ModalPresentationStyle {
        UIDevice.current.userInterfaceIdiom == .pad ? .popover : .sheet
    }
    
    var windowCapabilities: WindowCapabilities {
        WindowCapabilities(
            supportsMultiple: UIDevice.current.userInterfaceIdiom == .pad,
            supportsResizing: false,
            supportsMinimumSize: false,
            defaultSize: nil
        )
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
    var supportsHapticFeedback: Bool { false }
    var defaultPadding: CGFloat { 20 }
    var minTouchTargetSize: CGFloat { 32 }
    var defaultAnimationDuration: Double { 0.2 }
    
    var navigationStyle: NavigationStylePreference { .splitView }
    
    var modalPresentationStyle: ModalPresentationStyle { .sheet }
    
    var windowCapabilities: WindowCapabilities {
        WindowCapabilities(
            supportsMultiple: true,
            supportsResizing: true,
            supportsMinimumSize: true,
            defaultSize: (width: 900, height: 600)
        )
    }
}
#endif

#if os(visionOS)
struct visionOSCapabilities: PlatformCapabilities {
    var supportsMultiWindow: Bool { true }
    var supportsKeyboardShortcuts: Bool { false }
    var supportsHoverStates: Bool { true }
    var supportsWidgets: Bool { false }
    var supportsGestureNavigation: Bool { true }
    var supportsHapticFeedback: Bool { false }
    var defaultPadding: CGFloat { 24 }
    var minTouchTargetSize: CGFloat { 48 }
    var defaultAnimationDuration: Double { 0.4 }
    
    var navigationStyle: NavigationStylePreference { .splitView }
    
    var modalPresentationStyle: ModalPresentationStyle { .fullScreen }
    
    var windowCapabilities: WindowCapabilities {
        WindowCapabilities(
            supportsMultiple: true,
            supportsResizing: true,
            supportsMinimumSize: true,
            defaultSize: (width: 1000, height: 700)
        )
    }
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
    
    /// Provide haptic feedback if supported by the platform
    func hapticFeedback(_ style: HapticStyle = .light) {
        guard capabilities.supportsHapticFeedback else { return }
        
        #if os(iOS)
        HapticManager.shared.impact(style.mapToHapticManager())
        #endif
    }
    
    /// Provide notification feedback if supported by the platform
    func hapticNotification(_ type: HapticNotificationType) {
        guard capabilities.supportsHapticFeedback else { return }
        
        #if os(iOS)
        HapticManager.shared.notification(type.mapToHapticManager())
        #endif
    }
    
    /// Get platform-appropriate presentation modifier
    func presentationStyle<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        switch capabilities.modalPresentationStyle {
        case .sheet:
            return AnyView(EmptyView().sheet(isPresented: isPresented, content: content))
        case .popover:
            return AnyView(EmptyView().popover(isPresented: isPresented, content: content))
        case .fullScreen:
            #if os(iOS)
            return AnyView(EmptyView().fullScreenCover(isPresented: isPresented, content: content))
            #else
            return AnyView(EmptyView().sheet(isPresented: isPresented, content: content))
            #endif
        }
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
    
    /// Add platform-appropriate haptic feedback on value change
    func platformHaptic<T: Equatable>(_ style: HapticStyle = .light, on trigger: T) -> some View {
        let platform = PlatformManager.shared
        return self.onChange(of: trigger) { _, _ in
            platform.hapticFeedback(style)
        }
    }
    
    /// Add success haptic feedback on value change
    func platformSuccessHaptic<T: Equatable>(on trigger: T) -> some View {
        let platform = PlatformManager.shared
        return self.onChange(of: trigger) { _, _ in
            platform.hapticNotification(.success)
        }
    }
    
    /// Add error haptic feedback on value change
    func platformErrorHaptic<T: Equatable>(on trigger: T) -> some View {
        let platform = PlatformManager.shared
        return self.onChange(of: trigger) { _, _ in
            platform.hapticNotification(.error)
        }
    }
    
    /// Present modal using platform-appropriate style
    func platformModal<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        @Environment(\.platformCapabilities) var platform
        
        switch platform.modalPresentationStyle {
        case .sheet:
            return AnyView(self.sheet(isPresented: isPresented, content: content))
        case .popover:
            return AnyView(self.popover(isPresented: isPresented, content: content))
        case .fullScreen:
            #if os(iOS)
            return AnyView(self.fullScreenCover(isPresented: isPresented, content: content))
            #else
            return AnyView(self.sheet(isPresented: isPresented, content: content))
            #endif
        }
    }
}