//
//  ProgressRingView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct ProgressRingView: View {
    let progress: Double // 0.0 to 1.0
    let current: Double
    let target: Double
    let currency: String
    let lineWidth: CGFloat
    let showLabels: Bool
    
    @State private var animatedProgress: Double = 0
    @State private var animatedCurrent: Double = 0
    @State private var animatedTarget: Double = 0
    
    init(
        progress: Double,
        current: Double,
        target: Double,
        currency: String,
        lineWidth: CGFloat = 20,
        showLabels: Bool = true
    ) {
        self.progress = min(max(progress, 0), 1.5) // Allow up to 150% for over-achievement
        self.current = current
        self.target = target
        self.currency = currency
        self.lineWidth = lineWidth
        self.showLabels = showLabels
    }
    
    private var progressColor: Color {
        switch progress {
        case 0..<0.25:
            return AccessibleColors.error
        case 0.25..<0.5:
            return AccessibleColors.warning
        case 0.5..<0.75:
            return AccessibleColors.chartColor(at: 5) // Accessible yellow
        case 0.75..<1.0:
            return AccessibleColors.success
        case 1.0...:
            return AccessibleColors.chartColor(at: 0) // Accessible blue
        default:
            return AccessibleColors.secondaryText
        }
    }
    
    private var gradientColors: [Color] {
        if progress >= 1.0 {
            return [AccessibleColors.chartColor(at: 0), AccessibleColors.chartColor(at: 3)]
        } else if progress >= 0.75 {
            return [AccessibleColors.success, AccessibleColors.chartColor(at: 0)]
        } else if progress >= 0.5 {
            return [AccessibleColors.chartColor(at: 5), AccessibleColors.success]
        } else if progress >= 0.25 {
            return [AccessibleColors.warning, AccessibleColors.chartColor(at: 5)]
        } else {
            return [AccessibleColors.error, AccessibleColors.warning]
        }
    }
    
    var body: some View {
        #if os(macOS)
        HoverTooltipView(
            title: "Goal Progress",
            value: "\(Int(progress * 100))%",
            description: "Current: \(String(format: "%.2f", current)) \(currency) • Target: \(String(format: "%.2f", target)) \(currency)"
        ) {
            ringContent
        }
        #else
        ringContent
        #endif
    }
    
    private var ringContent: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = (size - lineWidth) / 2
            
            ZStack {
                // Background ring
                Circle()
                    .stroke(
                        AccessibleColors.tertiaryText.opacity(0.3),
                        lineWidth: lineWidth
                    )
                    .frame(width: size, height: size)
                
                // Progress ring with gradient
                Circle()
                    .trim(from: 0, to: min(animatedProgress, 1.0))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: gradientColors),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * min(animatedProgress, 1.0))
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.2).delay(0.1), value: animatedProgress)
                
                // Over-achievement indicator
                if animatedProgress > 1.0 {
                    Circle()
                        .trim(from: 0, to: animatedProgress - 1.0)
                        .stroke(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(
                                lineWidth: lineWidth * 0.6,
                                lineCap: .round,
                                dash: [5, 3]
                            )
                        )
                        .frame(width: size - lineWidth, height: size - lineWidth)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.2).delay(0.5), value: animatedProgress)
                }
                
                // Center content
                if showLabels {
                    VStack(spacing: 4) {
                        // Percentage
                        HStack(spacing: 2) {
                            Text("\(Int(animatedProgress * 100))%")
                                .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                                .foregroundColor(progressColor)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.8).delay(0.3), value: animatedProgress)
                            MetricTooltips.progress
                        }
                        
                        // Current value
                        HStack(spacing: 2) {
                            Text("\(String(format: "%.2f", animatedCurrent)) \(currency)")
                                .font(.system(size: size * 0.08, weight: .medium))
                                .foregroundColor(.primary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.8).delay(0.4), value: animatedCurrent)
                            MetricTooltips.currentTotal
                        }
                        
                        // Target value
                        Text("of \(String(format: "%.2f", animatedTarget))")
                            .font(.system(size: size * 0.06))
                            .foregroundColor(.accessibleSecondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.8).delay(0.2), value: animatedTarget)
                        
                        // Achievement badge
                        if animatedProgress >= 1.0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: size * 0.05))
                                Text("ACHIEVED!")
                                    .font(.system(size: size * 0.05, weight: .bold))
                            }
                            .foregroundColor(.accessibleAchievement)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AccessibleColors.achievementBackground)
                            )
                        }
                    }
                }
                
                // Progress indicator dot
                Circle()
                    .fill(progressColor)
                    .frame(width: lineWidth * 0.8, height: lineWidth * 0.8)
                    .shadow(color: progressColor.opacity(0.5), radius: 4)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(360 * min(animatedProgress, 1.0) - 90))
                    .animation(.easeInOut(duration: 1.2).delay(0.1), value: animatedProgress)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2)) {
                animatedProgress = progress
            }
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                animatedCurrent = current
                animatedTarget = target
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedProgress = newValue
            }
        }
        .onChange(of: current) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedCurrent = newValue
            }
        }
        .onChange(of: target) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedTarget = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress Ring")
        .accessibilityValue("\(Int(progress * 100))% complete. Current: \(String(format: "%.2f", current)) \(currency) of \(String(format: "%.2f", target)) \(currency) target")
        .accessibilityHint(progress >= 1.0 ? "Goal achieved!" : "Progress toward savings goal")
    }
}

// Compact version for smaller displays
struct CompactProgressRingView: View {
    let progress: Double
    let size: CGFloat
    
    private var progressColor: Color {
        switch progress {
        case 0..<0.25: return AccessibleColors.error
        case 0.25..<0.5: return AccessibleColors.warning
        case 0.5..<0.75: return AccessibleColors.chartColor(at: 5)
        case 0.75..<1.0: return AccessibleColors.success
        default: return AccessibleColors.chartColor(at: 0)
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(AccessibleColors.tertiaryText.opacity(0.3), lineWidth: 4)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                .foregroundColor(progressColor)
        }
    }
}

#Preview("Progress Ring") {
    VStack(spacing: 20) {
        ProgressRingView(
            progress: 0.75,
            current: 7500,
            target: 10000,
            currency: "USD"
        )
        .frame(width: 200, height: 200)
        
        ProgressRingView(
            progress: 1.25,
            current: 12500,
            target: 10000,
            currency: "EUR"
        )
        .frame(width: 200, height: 200)
        
        HStack(spacing: 20) {
            CompactProgressRingView(progress: 0.3, size: 60)
            CompactProgressRingView(progress: 0.6, size: 60)
            CompactProgressRingView(progress: 0.9, size: 60)
            CompactProgressRingView(progress: 1.2, size: 60)
        }
    }
    .padding()
}