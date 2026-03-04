//
//  VisualComponentTokens.swift
//  CryptoSavingsTracker
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum VisualComponentTokens {
    static let planningCardCornerRadius: CGFloat = 12
    static let planningRowCornerRadius: CGFloat = 12
    static let dashboardSummaryCornerRadius: CGFloat = 12
    static let settingsRowCornerRadius: CGFloat = 10
    static let financeSurfaceFill = AnyShapeStyle(.regularMaterial)
    static let settingsRowFill = AnyShapeStyle(Color.accessibleSurfaceSubtle)

    static var financeSurfaceStroke: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator).opacity(0.55)
        #elseif canImport(AppKit)
        return Color(NSColor.separatorColor).opacity(0.55)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }
}
