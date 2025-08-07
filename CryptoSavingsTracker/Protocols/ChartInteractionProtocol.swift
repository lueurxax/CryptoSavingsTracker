//
//  ChartInteractionProtocol.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftUI

// MARK: - Chart Point Protocol
protocol ChartPoint: Identifiable {
    var id: UUID { get }
    var date: Date { get }
    var value: Double { get }
    var displayValue: String { get }
    var accessibilityLabel: String { get }
}

// MARK: - Chart Interaction Events
enum ChartInteractionEvent {
    case tap(any ChartPoint)
    case longPress(any ChartPoint)
    case hover((any ChartPoint)?)
    case dragStart(any ChartPoint)
    case dragEnd
    case doubleTap(any ChartPoint)
}

// MARK: - Chart Interaction Protocol
protocol InteractiveChart: View {
    associatedtype DataPoint: ChartPoint
    
    var dataPoints: [DataPoint] { get }
    var selectedPoint: DataPoint? { get set }
    var hoveredPoint: DataPoint? { get set }
    
    func onInteraction(_ event: ChartInteractionEvent)
    func canInteract(with point: DataPoint) -> Bool
    func interactionFeedback(for event: ChartInteractionEvent)
}

// MARK: - Default Implementation
extension InteractiveChart {
    func canInteract(with point: DataPoint) -> Bool {
        return true
    }
    
    func interactionFeedback(for event: ChartInteractionEvent) {
        switch event {
        case .tap:
            // Light haptic feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            #endif
        case .longPress:
            // Medium haptic feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            #endif
        case .doubleTap:
            // Heavy haptic feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            #endif
        default:
            break
        }
    }
}

// MARK: - Chart Interaction Gesture Modifier
struct ChartInteractionModifier<DataPoint: ChartPoint>: ViewModifier {
    let point: DataPoint
    let onInteraction: (ChartInteractionEvent) -> Void
    let canInteract: (DataPoint) -> Bool
    
    @State private var dragStart: CGPoint = .zero
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if canInteract(point) {
                    onInteraction(.tap(point))
                }
            }
            .onLongPressGesture {
                if canInteract(point) {
                    onInteraction(.longPress(point))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging && canInteract(point) {
                            isDragging = true
                            dragStart = value.startLocation
                            onInteraction(.dragStart(point))
                        }
                    }
                    .onEnded { _ in
                        if isDragging {
                            isDragging = false
                            onInteraction(.dragEnd)
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        if canInteract(point) {
                            onInteraction(.doubleTap(point))
                        }
                    }
            )
            #if os(macOS)
            .onHover { hovering in
                if canInteract(point) {
                    onInteraction(.hover(hovering ? point : nil))
                }
            }
            #endif
    }
}

// MARK: - View Extension for Easy Usage
extension View {
    func chartInteraction<DataPoint: ChartPoint>(
        point: DataPoint,
        canInteract: @escaping (DataPoint) -> Bool = { _ in true },
        onInteraction: @escaping (ChartInteractionEvent) -> Void
    ) -> some View {
        self.modifier(ChartInteractionModifier(
            point: point,
            onInteraction: onInteraction,
            canInteract: canInteract
        ))
    }
}