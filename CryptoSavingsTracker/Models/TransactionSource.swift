//
//  TransactionSource.swift
//  CryptoSavingsTracker
//

import Foundation

enum TransactionSource: String, Codable, Sendable {
    case manual
    case onChain
}

