//
//  OnboardingTooltip.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct OnboardingTooltip: View {
    let message: String
    let arrowDirection: ArrowDirection
    @Binding var isVisible: Bool
    
    enum ArrowDirection {
        case up, down, left, right
    }
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                if arrowDirection == .down {
                    Arrow()
                        .fill(Color.purple)
                        .frame(width: 20, height: 10)
                        .rotationEffect(.degrees(180))
                }
                
                HStack {
                    if arrowDirection == .right {
                        Arrow()
                            .fill(Color.purple)
                            .frame(width: 10, height: 20)
                            .rotationEffect(.degrees(90))
                    }
                    
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.white)
                            .imageScale(.small)
                        
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        
                        Button(action: {
                            withAnimation {
                                isVisible = false
                            }
                            // Store that user has seen this tooltip
                            UserDefaults.standard.set(true, forKey: "hasSeenAllocationTooltip")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.8))
                                .imageScale(.small)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .cornerRadius(8)
                    
                    if arrowDirection == .left {
                        Arrow()
                            .fill(Color.purple)
                            .frame(width: 10, height: 20)
                            .rotationEffect(.degrees(-90))
                    }
                }
                
                if arrowDirection == .up {
                    Arrow()
                        .fill(Color.purple)
                        .frame(width: 20, height: 10)
                }
            }
            .shadow(radius: 4)
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                // Auto-dismiss after 8 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}