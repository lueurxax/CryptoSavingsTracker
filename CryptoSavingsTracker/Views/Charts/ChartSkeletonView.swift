//
//  ChartSkeletonView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct ChartSkeletonView: View {
    let height: CGFloat
    let type: ChartType
    @State private var shimmerOffset: CGFloat = -200
    
    enum ChartType {
        case line
        case ring
        case bar
        case heatmap
        case general
    }
    
    var body: some View {
        Group {
            switch type {
            case .line:
                LineChartSkeleton(height: height)
            case .ring:
                RingChartSkeleton()
            case .bar:
                BarChartSkeleton(height: height)
            case .heatmap:
                HeatmapSkeleton()
            case .general:
                GeneralChartSkeleton(height: height)
            }
        }
        .redacted(reason: .placeholder)
        .overlay(
            // Shimmer effect
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: shimmerOffset)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        shimmerOffset = 200
                    }
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Loading chart data")
        .accessibilityHint("Chart is loading, please wait")
    }
}

struct LineChartSkeleton: View {
    let height: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 16)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 12)
                }
                Spacer()
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 32)
            }
            
            // Chart area
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: height)
                
                // Fake chart line
                Path { path in
                    let width: CGFloat = 300
                    path.move(to: CGPoint(x: 0, y: height * 0.7))
                    path.addCurve(
                        to: CGPoint(x: width * 0.3, y: height * 0.4),
                        control1: CGPoint(x: width * 0.15, y: height * 0.6),
                        control2: CGPoint(x: width * 0.25, y: height * 0.5)
                    )
                    path.addCurve(
                        to: CGPoint(x: width * 0.7, y: height * 0.3),
                        control1: CGPoint(x: width * 0.5, y: height * 0.2),
                        control2: CGPoint(x: width * 0.6, y: height * 0.25)
                    )
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.6),
                        control1: CGPoint(x: width * 0.8, y: height * 0.4),
                        control2: CGPoint(x: width * 0.9, y: height * 0.5)
                    )
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct RingChartSkeleton: View {
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 20)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 16)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 12)
                }
            }
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 12)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct BarChartSkeleton: View {
    let height: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 140, height: 16)
                Spacer()
            }
            
            // Bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<5) { _ in
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: CGFloat.random(in: 20...height))
                        .cornerRadius(4)
                }
            }
            .frame(height: height)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct HeatmapSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 16)
                Spacer()
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 12)
            }
            
            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 10), spacing: 2) {
                ForEach(0..<50) { _ in
                    Rectangle()
                        .fill(Color.gray.opacity(Double.random(in: 0.1...0.4)))
                        .frame(height: 12)
                        .cornerRadius(2)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct GeneralChartSkeleton: View {
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 16)
                Spacer()
            }
            
            // Content
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: height)
                .cornerRadius(8)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        ChartSkeletonView(height: 200, type: .line)
        ChartSkeletonView(height: 150, type: .ring)
        ChartSkeletonView(height: 120, type: .bar)
        ChartSkeletonView(height: 100, type: .heatmap)
    }
    .padding()
}