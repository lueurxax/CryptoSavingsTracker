//
//  EmojiPickerView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import SwiftUI

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss
    
    let emojiCategories: [(name: String, emojis: [String])] = [
        ("Popular", ["🎯", "💰", "🏠", "🚗", "✈️", "🎓", "💻", "📱", "🎮", "💪", "🎁", "💼"]),
        ("Finance", ["💰", "💵", "💴", "💶", "💷", "💸", "💳", "🏦", "📈", "📊", "💹", "₿"]),
        ("Home", ["🏠", "🏡", "🏢", "🏘️", "🏚️", "🏗️", "🛏️", "🛋️", "🪑", "🚪", "🪟", "🔑"]),
        ("Transport", ["🚗", "🚙", "🚕", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "✈️", "🚁", "🚢"]),
        ("Education", ["🎓", "📚", "📖", "📝", "✏️", "📐", "📏", "🖊️", "🖍️", "📎", "🔬", "🔭"]),
        ("Tech", ["💻", "🖥️", "⌨️", "🖱️", "📱", "☎️", "📞", "📠", "📹", "📷", "🎮", "🕹️"]),
        ("Health", ["💪", "🏃", "🤸", "⛹️", "🏋️", "🚴", "🏊", "🧘", "🏥", "💊", "🩺", "🦷"]),
        ("Events", ["🎉", "🎊", "🎈", "🎁", "🎂", "🍰", "💒", "👶", "🍼", "🎄", "🎃", "🎆"]),
        ("Nature", ["🌳", "🌲", "🌴", "🌵", "🌻", "🌺", "🌸", "🌷", "🌹", "🏔️", "🏖️", "🏝️"]),
        ("Food", ["🍕", "🍔", "🍟", "🌭", "🥗", "🍜", "🍱", "🍣", "🍰", "🍩", "☕", "🍷"])
    ]
    
    @State private var searchText = ""
    @State private var selectedCategory = 0
    
    private var filteredEmojis: [String] {
        if searchText.isEmpty {
            return emojiCategories[selectedCategory].emojis
        } else {
            return emojiCategories.flatMap { $0.emojis }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Emoji")
                    .font(.headline)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.body.weight(.medium))
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.accessibleSecondary)
                TextField("Search emoji", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Category picker
            if searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(emojiCategories.indices, id: \.self) { index in
                            Button(action: {
                                selectedCategory = index
                            }) {
                                Text(emojiCategories[index].name)
                                    .font(.caption)
                                    .fontWeight(selectedCategory == index ? .semibold : .regular)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == index ? AccessibleColors.primaryInteractive : Color.gray.opacity(0.1))
                                    .foregroundColor(selectedCategory == index ? .white : .primary)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Emoji grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(filteredEmojis, id: \.self) { emoji in
                        Button(action: {
                            selectedEmoji = emoji
                            dismiss()
                        }) {
                            Text(emoji)
                                .font(.largeTitle)
                                .frame(width: 44, height: 44)
                                .background(selectedEmoji == emoji ? AccessibleColors.primaryInteractive.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            
            // Clear button
            if selectedEmoji != nil {
                Divider()
                
                Button(action: {
                    selectedEmoji = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Clear Emoji")
                    }
                    .foregroundColor(AccessibleColors.error)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AccessibleColors.error.opacity(0.1))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedEmoji: String? = "🎯"
    return EmojiPickerView(selectedEmoji: $selectedEmoji)
        .frame(width: 320, height: 400)
}