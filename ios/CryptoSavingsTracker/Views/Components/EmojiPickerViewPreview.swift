// Extracted preview-only declarations for NAV003 policy compliance.
// Source: EmojiPickerView.swift

//
//  EmojiPickerView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import SwiftUI

#Preview {
    @Previewable @State var selectedEmoji: String? = "🎯"
    return EmojiPickerView(selectedEmoji: $selectedEmoji)
        .frame(width: 320, height: 400)
}
