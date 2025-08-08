//
//  DIContainer.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class DIContainer: ObservableObject {
    static let shared = DIContainer()
    
    // MARK: - Services
    lazy var coinGeckoService: CoinGeckoService = CoinGeckoService()
    lazy var tatumService: TatumService = TatumService()
    lazy var exchangeRateService: ExchangeRateService = ExchangeRateService()
    
    private init() {}
    
    // MARK: - ViewModel Factories
    func makeGoalViewModel(for goal: Goal) -> GoalViewModel {
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: tatumService,
            exchangeRateService: exchangeRateService
        )
        return viewModel
    }
    
    func makeAssetViewModel(for asset: Asset) -> AssetViewModel {
        return AssetViewModel(
            asset: asset,
            tatumService: tatumService
        )
    }
    
    func makeCurrencyViewModel() -> CurrencyViewModel {
        return CurrencyViewModel(coinGeckoService: coinGeckoService)
    }
}