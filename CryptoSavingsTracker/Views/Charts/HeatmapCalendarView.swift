//
//  HeatmapCalendarView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct HeatmapCalendarView: View {
    let heatmapData: [HeatmapDay]
    let year: Int
    let title: String
    let showLegend: Bool
    let animateOnAppear: Bool
    
    @State private var animationProgress: Double = 0
    @State private var selectedDay: HeatmapDay?
    @State private var hoveredDay: HeatmapDay?
    
    init(
        heatmapData: [HeatmapDay],
        year: Int = Calendar.current.component(.year, from: Date()),
        title: String = "Activity Heatmap",
        showLegend: Bool = true,
        animateOnAppear: Bool = true
    ) {
        self.heatmapData = heatmapData
        self.year = year
        self.title = title
        self.showLegend = showLegend
        self.animateOnAppear = animateOnAppear
    }
    
    private var calendar: Calendar {
        Calendar.current
    }
    
    private var monthsInYear: [Date] {
        (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }
    
    private func weeksInMonth(_ month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        
        var weeks: [Date] = []
        var currentWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start ?? monthInterval.start
        
        while currentWeek < monthInterval.end {
            weeks.append(currentWeek)
            currentWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek) ?? monthInterval.end
        }
        
        return weeks
    }
    
    private func daysInWeek(_ week: Date, for month: Date) -> [Date?] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: week) else { return [] }
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        
        var days: [Date?] = []
        var currentDay = weekInterval.start
        
        for _ in 0..<7 {
            if calendar.isDate(currentDay, inSameDayAs: monthInterval.start) ||
               (currentDay >= monthInterval.start && currentDay < monthInterval.end) {
                days.append(currentDay)
            } else {
                days.append(nil)
            }
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay
        }
        
        return days
    }
    
    private func dataFor(date: Date) -> HeatmapDay? {
        heatmapData.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    private var totalValue: Double {
        heatmapData.reduce(0) { $0 + $1.value }
    }
    
    private var maxValue: Double {
        heatmapData.map { $0.value }.max() ?? 1
    }
    
    private var averageValue: Double {
        heatmapData.isEmpty ? 0 : totalValue / Double(heatmapData.count)
    }
    
    private var streakCount: Int {
        let sortedDates = heatmapData
            .filter { $0.value > 0 }
            .map { $0.date }
            .sorted()
        
        guard !sortedDates.isEmpty else { return 0 }
        
        var currentStreak = 1
        var maxStreak = 1
        
        for i in 1..<sortedDates.count {
            let currentDate = sortedDates[i]
            let previousDate = sortedDates[i - 1]
            
            if calendar.isDate(currentDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: previousDate) ?? Date()) {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }
        
        return maxStreak
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    MetricTooltips.heatmap
                    
                    Spacer()
                    
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundColor(.accessibleSecondary)
                }
                
                // Stats
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text(String(format: "%.0f", totalValue))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Avg")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text(String(format: "%.1f", averageValue))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best Streak")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text("\(streakCount) days")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
            }
            
            // Calendar heatmap
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(monthsInYear, id: \.self) { month in
                        VStack(alignment: .leading, spacing: 4) {
                            // Month label
                            Text(month, format: .dateTime.month(.abbreviated))
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Week grid
                            VStack(spacing: 2) {
                                ForEach(weeksInMonth(month), id: \.self) { week in
                                    HStack(spacing: 2) {
                                        ForEach(Array(daysInWeek(week, for: month).enumerated()), id: \.offset) { _, day in
                                            if let date = day {
                                                let dayData = dataFor(date: date)
                                                let intensity = animateOnAppear ? (dayData?.intensity ?? 0) * animationProgress : (dayData?.intensity ?? 0)
                                                
                                                #if os(macOS)
                                                if let dayData = dayData {
                                                    HoverTooltipView(
                                                        title: dayData.date.formatted(.dateTime.month().day()),
                                                        value: "\(dayData.transactionCount) txns",
                                                        description: "Volume: \(String(format: "%.1f", dayData.value)) | \(String(format: "%.0f", dayData.intensity * 100))% intensity"
                                                    ) {
                                                        Rectangle()
                                                            .fill(dayData.color.opacity(intensity))
                                                            .frame(width: 12, height: 12)
                                                            .cornerRadius(2)
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 2)
                                                                    .stroke(
                                                                        selectedDay?.id == dayData.id ? AccessibleColors.primaryInteractive : Color.clear,
                                                                        lineWidth: 2
                                                                    )
                                                            )
                                                            .onTapGesture {
                                                                selectedDay = dayData
                                                            }
                                                    }
                                                } else {
                                                    Rectangle()
                                                        .fill(Color.gray.opacity(0.1))
                                                        .frame(width: 12, height: 12)
                                                        .cornerRadius(2)
                                                }
                                                #else
                                                Rectangle()
                                                    .fill(dayData?.color.opacity(intensity) ?? Color.gray.opacity(0.1))
                                                    .frame(width: 12, height: 12)
                                                    .cornerRadius(2)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 2)
                                                            .stroke(
                                                                selectedDay?.id == dayData?.id ? AccessibleColors.primaryInteractive :
                                                                hoveredDay?.id == dayData?.id ? AccessibleColors.secondaryText : Color.clear,
                                                                lineWidth: selectedDay?.id == dayData?.id ? 2 : 1
                                                            )
                                                    )
                                                    .onTapGesture {
                                                        selectedDay = dayData
                                                    }
                                                    .onHover { hovering in
                                                        hoveredDay = hovering ? dayData : nil
                                                    }
                                                #endif
                                            } else {
                                                Rectangle()
                                                    .fill(Color.clear)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Legend
            if showLegend {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaction Activity")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 12) {
                        // Transaction count legend
                        HStack(spacing: 4) {
                            Text("0")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                            
                            Rectangle()
                                .fill(AccessibleColors.lightBackground)
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                            
                            Rectangle()
                                .fill(AccessibleColors.chartColor(at: 0).opacity(0.5))
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                            
                            Rectangle()
                                .fill(AccessibleColors.chartColor(at: 1).opacity(0.7))
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                                
                            Rectangle()
                                .fill(AccessibleColors.chartColor(at: 2).opacity(0.8))
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                                
                            Rectangle()
                                .fill(AccessibleColors.achievement.opacity(0.9))
                                .frame(width: 12, height: 12)
                                .cornerRadius(2)
                            
                            Text("10+")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text("Color indicates transaction count per day")
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                }
            }
            
            // Selected day detail
            if let selected = selectedDay {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selected.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Button("Dismiss") {
                            selectedDay = nil
                        }
                        .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Transactions:")
                            Spacer()
                            Text("\(selected.transactionCount)")
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Volume:")
                            Spacer()
                            Text(String(format: "%.2f", selected.value))
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Intensity:")
                            Spacer()
                            Text("\(String(format: "%.0f", selected.intensity * 100))%")
                                .fontWeight(.medium)
                        }
                        
                        if selected.transactionCount > 5 {
                            Text("High activity day!")
                                .font(.caption)
                                .foregroundColor(AccessibleColors.success)
                        } else if selected.transactionCount == 0 {
                            Text("No transactions")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                        } else if selected.transactionCount == 1 {
                            Text("Light activity")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                        }
                    }
                    .font(.caption)
                }
                .padding(12)
                .background(Color.gray.opacity(0.03))
                .cornerRadius(8)
            }
            
            // Tooltip for hovered day
            if let hovered = hoveredDay, selectedDay == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hovered.date, format: .dateTime.day().month())
                        .font(.caption)
                        .fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text("\(hovered.transactionCount) txns")
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text(String(format: "%.1f", hovered.value))
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                    }
                }
                .padding(6)
                .background(Color.white)
                .cornerRadius(6)
                .shadow(radius: 2)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            if animateOnAppear {
                withAnimation(.easeOut(duration: 2.0)) {
                    animationProgress = 1.0
                }
            } else {
                animationProgress = 1.0
            }
        }
    }
}

// Compact heatmap for smaller views
struct CompactHeatmapView: View {
    let heatmapData: [HeatmapDay]
    let timeRange: Int // Days to show
    let size: CGFloat
    
    init(heatmapData: [HeatmapDay], timeRange: Int = 30, size: CGFloat = 200) {
        self.heatmapData = heatmapData
        self.timeRange = timeRange
        self.size = size
    }
    
    private var recentData: [HeatmapDay] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -timeRange, to: Date()) ?? Date()
        return heatmapData.filter { $0.date >= cutoffDate }.sorted { $0.date < $1.date }
    }
    
    private var gridColumns: Int {
        Int(size / 15)
    }
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 2), count: gridColumns), spacing: 2) {
            ForEach(recentData.prefix(gridColumns * 6)) { day in
                Rectangle()
                    .fill(day.color)
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
            }
        }
        .frame(width: size)
    }
}

#Preview("Heatmap Calendar") {
    let sampleData = (0..<365).compactMap { dayOffset -> HeatmapDay? in
        guard let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
        
        let value = Double.random(in: 0...100)
        let intensity = value / 100.0
        let transactionCount = Int.random(in: 0...15) // Random transaction count for preview
        
        return HeatmapDay(date: date, value: value, intensity: intensity, transactionCount: transactionCount)
    }
    
    return VStack(spacing: 20) {
        HeatmapCalendarView(heatmapData: sampleData)
        
        HStack(spacing: 16) {
            CompactHeatmapView(heatmapData: sampleData, timeRange: 30, size: 120)
            CompactHeatmapView(heatmapData: sampleData, timeRange: 60, size: 180)
        }
    }
    .padding()
}