import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct BalanceStateTests {
    private struct FailingBalanceTatumService: TatumServiceProtocol {
        var supportedChains: [TatumChain] { [] }

        func predictChain(for symbol: String) -> TatumChain? {
            nil
        }

        func fetchBalance(
            chainId: String,
            address: String,
            symbol: String,
            forceRefresh: Bool
        ) async throws -> Double {
            throw TatumError.invalidResponse
        }

        func fetchTransactionHistory(
            chainId: String,
            address: String,
            currency: String?,
            limit: Int,
            forceRefresh: Bool
        ) async throws -> [TatumTransaction] {
            []
        }

        func hasValidConfiguration() -> Bool {
            true
        }

        func setOfflineMode(_ offline: Bool) {}
    }

    @Test("TRX account accepts numeric TRC10 key-value object arrays")
    func trxAccountAcceptsNumericTRC10ObjectArray() throws {
        let account = try JSONDecoder().decode(
            TRXAccountResponse.self,
            from: Data("""
            {
              "balance":1000000,
              "createTime":0,
              "trc10":[
                {"value":992000000000,"key":"1001388"}
              ],
              "trc20":[]
            }
            """.utf8)
        )

        #expect(account.balanceTRX == 1)
        #expect(account.trc10.tokens == ["1001388": "992000000000"])
    }

    @Test("TRX account accepts string TRC10 key-value object arrays")
    func trxAccountAcceptsStringTRC10ObjectArray() throws {
        let account = try JSONDecoder().decode(
            TRXAccountResponse.self,
            from: Data("""
            {
              "balance":0,
              "createTime":0,
              "trc10":[
                {"key":"1002000","value":"42.5"}
              ],
              "trc20":[]
            }
            """.utf8)
        )

        #expect(account.trc10.tokens == ["1002000": "42.5"])
    }

    @Test("TRX account rejects malformed, nonfinite, and negative TRC10 object entries")
    func trxAccountRejectsInvalidTRC10ObjectEntries() {
        let invalidTRC10Payloads = [
            #"[{"value":1}]"#,
            #"[{"key":"1001388"}]"#,
            #"[{"key":"","value":1}]"#,
            #"[{"key":"   ","value":1}]"#,
            #"[{"key":"1001388","value":{"raw":1}}]"#,
            #"[{"key":"1001388","value":"inf"}]"#,
            #"[{"key":"1001388","value":-1}]"#,
            #"[{"key":"1001388","value":"-1"}]"#
        ]

        for trc10Payload in invalidTRC10Payloads {
            let payload = Data("""
            {
              "balance":0,
              "createTime":0,
              "trc10":\(trc10Payload),
              "trc20":[]
            }
            """.utf8)

            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(TRXAccountResponse.self, from: payload)
            }
        }
    }

    @Test("TRX account rejects empty and whitespace TRC10 dictionary keys")
    func trxAccountRejectsInvalidTRC10DictionaryKeys() {
        for trc10Payload in [#"{"":"1"}"#, #"{"   ":"1"}"#] {
            let payload = Data("""
            {
              "balance":0,
              "createTime":0,
              "trc10":\(trc10Payload),
              "trc20":[]
            }
            """.utf8)

            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(TRXAccountResponse.self, from: payload)
            }
        }
    }

    @Test("TRX account rejects duplicate TRC10 object keys")
    func trxAccountRejectsDuplicateTRC10ObjectKeys() {
        let payload = Data("""
        {
          "balance":0,
          "createTime":0,
          "trc10":[
            {"key":"1001388","value":1},
            {"key":"1001388","value":"2"}
          ],
          "trc20":[]
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TRXAccountResponse.self, from: payload)
        }
    }

    @Test("TRX account accepts a nonempty legacy TRC10 dictionary")
    func trxAccountAcceptsNonemptyTRC10Dictionary() throws {
        let account = try JSONDecoder().decode(
            TRXAccountResponse.self,
            from: Data("""
            {
              "balance":0,
              "createTime":0,
              "trc10":{"1001388":"992000000000"},
              "trc20":[]
            }
            """.utf8)
        )

        #expect(account.trc10.tokens == ["1001388": "992000000000"])
    }

    @Test("TRX account preserves native, TRC10, and TRC20 balances together")
    func trxAccountPreservesCombinedBalances() throws {
        let account = try JSONDecoder().decode(
            TRXAccountResponse.self,
            from: Data("""
            {
              "balance":12500000,
              "createTime":1750000000000,
              "trc10":[
                {"key":"1001388","value":992000000000}
              ],
              "trc20":[
                {"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t":"42500000"}
              ]
            }
            """.utf8)
        )

        #expect(account.balanceTRX == 12.5)
        #expect(account.getTokenBalance(symbol: "1001388") == 992_000)
        #expect(account.getTokenBalance(symbol: "USDT") == 42.5)
    }

    @Test("Balance provider payloads reject malformed numerics while legitimate zero remains valid")
    func balanceProviderPayloadsValidateNumericsBeforeCaching() throws {
        let malformedPayloads: [(Data, (Data) throws -> Void)] = [
            (
                Data("""
                {
                  "result":[{
                    "chain":"ethereum-mainnet",
                    "address":"0xwallet",
                    "balance":"0",
                    "denominatedBalance":"not-a-number",
                    "decimals":6,
                    "type":"native"
                  }]
                }
                """.utf8),
                { data in
                    _ = try JSONDecoder().decode(TatumV4PortfolioResponse.self, from: data)
                }
            ),
            (
                Data("""
                {
                  "incoming":"inf",
                  "outgoing":"0",
                  "incomingPending":"0",
                  "outgoingPending":"0"
                }
                """.utf8),
                { data in
                    _ = try JSONDecoder().decode(TatumUTXOBalance.self, from: data)
                }
            ),
            (
                Data(#"{"balance":"nan","assets":[]}"#.utf8),
                { data in
                    _ = try JSONDecoder().decode(TatumXRPBalanceResponse.self, from: data)
                }
            ),
            (
                Data("""
                {
                  "balance":0,
                  "createTime":0,
                  "trc10":[],
                  "trc20":[{
                    "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t":"inf"
                  }]
                }
                """.utf8),
                { data in
                    _ = try JSONDecoder().decode(TRXAccountResponse.self, from: data)
                }
            ),
            (
                Data("""
                [{
                  "value":"not-a-number",
                  "currency":{"symbol":"ADA","decimals":6}
                }]
                """.utf8),
                { data in
                    _ = try JSONDecoder().decode([TatumADABalanceResponse].self, from: data)
                }
            ),
            (
                Data(#"{"balance":"inf"}"#.utf8),
                { data in
                    _ = try JSONDecoder().decode(TatumSOLBalanceResponse.self, from: data)
                }
            )
        ]

        for (payload, decode) in malformedPayloads {
            #expect(throws: DecodingError.self) {
                try decode(payload)
            }
        }

        let zeroV4 = try JSONDecoder().decode(
            TatumV4PortfolioResponse.self,
            from: Data("""
            {
              "result":[{
                "chain":"ethereum-mainnet",
                "address":"0xwallet",
                "balance":"0",
                "denominatedBalance":"0",
                "decimals":18,
                "type":"native"
              }]
            }
            """.utf8)
        )
        let zeroUTXO = try JSONDecoder().decode(
            TatumUTXOBalance.self,
            from: Data("""
            {
              "incoming":"0",
              "outgoing":"0",
              "incomingPending":"0",
              "outgoingPending":"0"
            }
            """.utf8)
        )
        let zeroXRP = try JSONDecoder().decode(
            TatumXRPBalanceResponse.self,
            from: Data(#"{"balance":"0","assets":[]}"#.utf8)
        )
        let zeroTRX = try JSONDecoder().decode(
            TRXAccountResponse.self,
            from: Data("""
            {"balance":0,"createTime":0,"trc10":[],"trc20":[]}
            """.utf8)
        )
        let zeroADA = try JSONDecoder().decode(
            [TatumADABalanceResponse].self,
            from: Data("""
            [{"value":"0","currency":{"symbol":"ADA","decimals":6}}]
            """.utf8)
        )
        let zeroSOL = try JSONDecoder().decode(
            TatumSOLBalanceResponse.self,
            from: Data(#"{"balance":"0"}"#.utf8)
        )

        #expect(zeroV4.result.first?.humanReadableBalance == 0)
        #expect(zeroUTXO.confirmedBalance == 0)
        #expect(zeroXRP.balanceInXRP == 0)
        #expect(zeroTRX.balanceTRX == 0)
        #expect(zeroADA.first?.humanReadableBalance == 0)
        #expect(zeroSOL.solBalance == 0)
    }

    @Test("Balance provider payloads reject decimals outside the supported range")
    func balanceProviderPayloadsRejectInvalidDecimals() {
        let negativeDecimals = Data("""
        {
          "result":[{
            "chain":"ethereum-mainnet",
            "address":"0xwallet",
            "balance":"0",
            "denominatedBalance":"0",
            "decimals":-1,
            "type":"native"
          }]
        }
        """.utf8)
        let excessiveDecimals = Data("""
        [{
          "value":"0",
          "currency":{"symbol":"ADA","decimals":256}
        }]
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                TatumV4PortfolioResponse.self,
                from: negativeDecimals
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                [TatumADABalanceResponse].self,
                from: excessiveDecimals
            )
        }
    }

    @Test("Expired balance cache remains visible for recovery but cannot fund operations")
    func expiredBalanceFallbackIsPresentationOnly() async {
        let address = "solana-\(UUID().uuidString)"
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "SOL",
            address: address,
            symbol: "SOL"
        )
        BalanceCacheManager.shared.cacheBalance(
            10,
            for: cacheKey,
            timestamp: Date().addingTimeInterval(-3_600),
            expiresAt: Date().addingTimeInterval(-1)
        )

        let asset = Asset(currency: "SOL", address: address, chainId: "SOL")
        let manualTransaction = Transaction(amount: 2, asset: asset)
        asset.transactions = [manualTransaction]

        #expect(BalanceCacheManager.shared.getCachedBalance(for: cacheKey) == nil)
        #expect(BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) == 10)
        #expect(asset.cachedOnChainBalance == 0)
        #expect(asset.fallbackOnChainBalance == 10)
        #expect(asset.currentAmount == 2)
        #expect(asset.unallocatedAmount == 2)

        let viewModel = AssetViewModel(
            asset: asset,
            tatumService: FailingBalanceTatumService()
        )
        await viewModel.refreshBalances(forceRefresh: true)

        #expect(viewModel.onChainBalance == 0)
        #expect(viewModel.totalBalance == 2)
        guard case .error(_, let cachedBalance, _) = viewModel.balanceState else {
            Issue.record("Expected a recovery presentation backed by the retained value")
            return
        }
        #expect(cachedBalance == 10)
    }

    @Test("Forced refresh reports rate limiting instead of presenting stale cache as live data")
    @MainActor
    func forcedRefreshDoesNotReturnFallbackCacheAsSuccess() async {
        let address = "cardano-\(UUID().uuidString)"
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ADA",
            address: address,
            symbol: "ADA"
        )
        BalanceCacheManager.shared.cacheBalance(42, for: cacheKey)

        let rateLimiter = RateLimiter(timeInterval: 60)
        rateLimiter.recordRequest(for: cacheKey)
        let service = BalanceService(
            client: TatumClient(),
            chainService: ChainService(),
            rateLimiter: rateLimiter
        )

        await #expect(throws: TatumError.self) {
            _ = try await service.fetchBalance(
                chainId: "ADA",
                address: address,
                symbol: "ADA",
                forceRefresh: true
            )
        }
        #expect(BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) == 42)
    }

    @Test("Native-only routes reject mismatched symbols before cached balances")
    @MainActor
    func nativeOnlyRouteRejectsMismatchedCachedBalance() async {
        let address = "cardano-\(UUID().uuidString)"
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ADA",
            address: address,
            symbol: "PEPE"
        )
        BalanceCacheManager.shared.cacheBalance(42, for: cacheKey)
        let service = BalanceService(
            client: TatumClient(),
            chainService: ChainService()
        )

        await #expect(throws: TatumError.self) {
            _ = try await service.fetchBalance(
                chainId: "ADA",
                address: address,
                symbol: "PEPE",
                forceRefresh: false
            )
        }
    }

    @Test("Unsupported EVM token pairs reject cached balances")
    @MainActor
    func unsupportedEVMTokenRejectsCachedBalance() async {
        let address = "0x00000000000000000000000000000000000000ab"
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: address,
            symbol: "PEPE"
        )
        BalanceCacheManager.shared.cacheBalance(99, for: cacheKey)
        let service = BalanceService(
            client: TatumClient(),
            chainService: ChainService()
        )

        await #expect(throws: TatumError.self) {
            _ = try await service.fetchBalance(
                chainId: "ETH",
                address: address,
                symbol: "PEPE",
                forceRefresh: false
            )
        }
    }

    @Test("Ethereum fungible routes carry the canonical token contract")
    func ethereumTokenRouteUsesCanonicalContract() throws {
        let route = try BalanceRouteResolver.resolve(
            chainId: "ETH",
            symbol: "USDT",
            chainService: ChainService()
        )

        guard case let .v4Token(v4Chain, canonicalContracts) = route else {
            Issue.record("Expected an Ethereum fungible-token route")
            return
        }

        #expect(v4Chain == "ethereum-mainnet")
        #expect(canonicalContracts == ["0xdAC17F958D2ee523a2206206994597C13D831ec7"])
    }

    @Test("Canonical contract identity wins over a counterfeit matching symbol")
    func canonicalContractSelectsTokenBalance() throws {
        let counterfeit = TatumV4BalanceItem(
            chain: "ethereum-mainnet",
            address: "0xwallet",
            balance: "999",
            denominatedBalance: "999000000",
            decimals: 6,
            type: "fungible",
            tokenAddress: "0x0000000000000000000000000000000000000bad",
            tokenName: "Counterfeit Tether",
            tokenSymbol: "USDT"
        )
        let canonical = TatumV4BalanceItem(
            chain: "ethereum-mainnet",
            address: "0xwallet",
            balance: "1.25",
            denominatedBalance: "1250000",
            decimals: 6,
            type: "fungible",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            tokenName: "Tether",
            tokenSymbol: "NOT-USDT"
        )

        let selected = BalanceRouteResolver.matchingCanonicalToken(
            in: [counterfeit, canonical],
            canonicalContracts: ["0xdAC17F958D2ee523a2206206994597C13D831ec7"]
        )

        #expect(selected?.tokenAddress == canonical.tokenAddress)
        #expect(selected?.humanReadableBalance == 1.25)
    }

    @Test("Wallet portfolio chain identifiers match the supported API enum")
    func walletPortfolioChainIdentifiersAreValid() {
        let chainService = ChainService()

        #expect(chainService.getV4ChainName(for: "AVAX") == "avax-mainnet")
        #expect(chainService.getV4ChainName(for: "CELO") == "celo-mainnet")
        #expect(chainService.getV4ChainName(for: "FTM") == nil)
        #expect(chainService.supportsV4API("FTM") == false)
    }

    @Test("Polygon uses POL as its canonical native currency while legacy MATIC remains native-compatible")
    func polygonNativeCurrencyUsesPOLWithLegacyMATICCompatibility() throws {
        let chainService = ChainService()
        let polygon = try #require(chainService.getChain(by: "MATIC"))

        #expect(polygon.nativeCurrencySymbol == "POL")
        #expect(chainService.predictChain(for: "POL")?.id == "MATIC")
        #expect(chainService.predictChain(for: "MATIC")?.id == "MATIC")

        guard case .v4Native(let canonicalChain) = try BalanceRouteResolver.resolve(
            chainId: "MATIC",
            symbol: "POL",
            chainService: chainService
        ) else {
            Issue.record("POL must resolve to Polygon's native route")
            return
        }
        guard case .v4Native(let legacyChain) = try BalanceRouteResolver.resolve(
            chainId: "MATIC",
            symbol: "MATIC",
            chainService: chainService
        ) else {
            Issue.record("Legacy persisted MATIC must remain a native Polygon route")
            return
        }

        #expect(canonicalChain == "polygon-mainnet")
        #expect(legacyChain == "polygon-mainnet")
    }

    @Test("Automatic QUICK tracking accepts only the current Polygon contract")
    func quickTrackingUsesOnlyCurrentContract() throws {
        let currentContract = "0xB5C064F955D8e7F38fE0460C556a72987494eE17"
        let legacyContract = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13"
        let route = try BalanceRouteResolver.resolve(
            chainId: "MATIC",
            symbol: "QUICK",
            chainService: ChainService()
        )

        guard case let .v4Token(v4Chain, canonicalContracts) = route else {
            Issue.record("Expected QUICK to resolve to a Polygon fungible-token route")
            return
        }

        #expect(v4Chain == "polygon-mainnet")
        #expect(canonicalContracts == [currentContract])
        #expect(
            BalanceRouteResolver.matchingCanonicalToken(
                in: [Self.tokenBalance(address: legacyContract)],
                canonicalContracts: canonicalContracts
            ) == nil
        )
        #expect(
            BalanceRouteResolver.matchingCanonicalToken(
                in: [Self.tokenBalance(address: currentContract)],
                canonicalContracts: canonicalContracts
            )?.tokenAddress == currentContract
        )
    }

    @Test("UTXO balance requests use Tatum v3 API-key authentication")
    func utxoBalanceRequestsUseAPIKeyHeader() throws {
        let client = TatumClient()
        let expectedPaths = [
            "BTC": "/bitcoin/address/balance/wallet",
            "LTC": "/litecoin/address/balance/wallet",
            "BCH": "/bcash/address/balance/wallet",
            "DOGE": "/dogecoin/address/balance/wallet"
        ]

        for (chainID, expectedPath) in expectedPaths {
            let request = try #require(
                BalanceService.makeUTXOBalanceRequest(
                    chainId: chainID,
                    address: "wallet",
                    client: client
                )
            )

            #expect(request.url?.path == "/v3\(expectedPath)")
            #expect(request.value(forHTTPHeaderField: "x-api-key") != nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test("Wallet portfolio requests carry explicit page size and offset")
    func walletPortfolioRequestsCarryPagination() {
        let queryItems = BalanceService.v4PortfolioQueryItems(
            v4Chain: "ethereum-mainnet",
            address: "0xwallet",
            tokenTypes: ["fungible"],
            pageSize: 50,
            offset: 100
        )
        let values = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(values["chain"] == "ethereum-mainnet")
        #expect(values["addresses"] == "0xwallet")
        #expect(values["tokenTypes"] == "fungible")
        #expect(values["pageSize"] == "50")
        #expect(values["offset"] == "100")
    }

    @Test("Canonical token lookup follows portfolio pagination")
    func canonicalTokenLookupFollowsPortfolioPagination() async throws {
        let canonicalAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        var requestedOffsets: [Int] = []

        let balance = try await BalanceService.canonicalTokenBalance(
            canonicalContracts: [canonicalAddress],
            pageSize: 2,
            maxPages: 3
        ) { offset, _ in
            requestedOffsets.append(offset)
            if offset == 0 {
                return TatumV4PortfolioResponse(
                    result: [
                        Self.tokenBalance(address: "0x0000000000000000000000000000000000000001"),
                        Self.tokenBalance(address: "0x0000000000000000000000000000000000000002")
                    ],
                    prevPage: nil,
                    nextPage: "offset=2"
                )
            }
            return TatumV4PortfolioResponse(
                result: [
                    Self.tokenBalance(
                        address: canonicalAddress,
                        balance: "1.25",
                        denominatedBalance: "1250000"
                    )
                ],
                prevPage: "offset=0",
                nextPage: nil
            )
        }

        #expect(balance == 1.25)
        #expect(requestedOffsets == [0, 2])
    }

    @Test("Canonical token lookup fails instead of returning zero at its pagination safety limit")
    func canonicalTokenLookupFailsAtSafetyLimit() async {
        await #expect(throws: TatumError.self) {
            _ = try await BalanceService.canonicalTokenBalance(
                canonicalContracts: ["0xdAC17F958D2ee523a2206206994597C13D831ec7"],
                pageSize: 1,
                maxPages: 2
            ) { offset, _ in
                TatumV4PortfolioResponse(
                    result: [
                        Self.tokenBalance(
                            address: "0x000000000000000000000000000000000000000\(offset)"
                        )
                    ],
                    prevPage: offset == 0 ? nil : "previous",
                    nextPage: "more"
                )
            }
        }
    }

    @Test("EVM chains without a documented balance route fail closed")
    func unsupportedEVMBalanceRoutesFailClosed() {
        for (chainId, symbol) in [("FTM", "FTM"), ("ONE", "ONE"), ("KLAY", "KLAY")] {
            #expect(throws: TatumError.self) {
                _ = try BalanceRouteResolver.resolve(
                    chainId: chainId,
                    symbol: symbol,
                    chainService: ChainService()
                )
            }
        }
    }

    @Test("Raw Tatum balances always honor declared token decimals")
    func rawTatumBalanceAlwaysUsesDeclaredDecimals() {
        let response = TatumBalanceResponse(
            balance: "500",
            tokenAddress: "0xlow",
            tokenName: "Low Supply Token",
            tokenSymbol: "LOW",
            tokenDecimals: 3
        )

        #expect(response.humanReadableBalance == 0.5)
    }

    @Test("Balance cache keys invalidate values created before canonical routing")
    func balanceCacheKeyUsesCurrentNormalizationVersion() {
        let key = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: "0xWallet",
            symbol: "USDT"
        )

        #expect(key == "balance_v5_eth_0xwallet_usdt")
        #expect(key != "balance_v4_eth_0xwallet_usdt")
    }

    @Test("Transaction cache keys invalidate unfiltered history entries")
    func transactionCacheKeyUsesFilteredHistoryVersion() {
        let key = BalanceCacheManager.transactionsCacheKey(
            chainId: "ETH",
            address: "0xWallet",
            currency: "USDT"
        )

        #expect(key == "transactions_v4_eth_0xwallet_usdt")
        #expect(key != "transactions_v3_eth_0xwallet_usdt")
    }

    @Test("Cache keys fold EVM addresses but preserve case-sensitive route addresses")
    func cacheKeysUseRouteAwareAddressNormalization() {
        let evmUpper = "0xAbCdEf0000000000000000000000000000000000"
        let evmLower = evmUpper.lowercased()

        #expect(
            BalanceCacheManager.balanceCacheKey(chainId: "ETH", address: evmUpper, symbol: "ETH")
                == BalanceCacheManager.balanceCacheKey(chainId: "ETH", address: evmLower, symbol: "ETH")
        )
        #expect(
            BalanceCacheManager.transactionsCacheKey(chainId: "ETH", address: evmUpper, currency: "ETH")
                == BalanceCacheManager.transactionsCacheKey(chainId: "ETH", address: evmLower, currency: "ETH")
        )

        for (chainID, symbol) in [("SOL", "SOL"), ("TRX", "TRX"), ("XRP", "XRP"), ("BTC", "BTC")] {
            let mixedCaseAddress = "\(chainID)-CaseSensitiveWallet"
            let caseVariant = mixedCaseAddress.lowercased()

            #expect(
                BalanceCacheManager.balanceCacheKey(
                    chainId: chainID,
                    address: mixedCaseAddress,
                    symbol: symbol
                ) != BalanceCacheManager.balanceCacheKey(
                    chainId: chainID,
                    address: caseVariant,
                    symbol: symbol
                )
            )
            #expect(
                BalanceCacheManager.transactionsCacheKey(
                    chainId: chainID,
                    address: mixedCaseAddress,
                    currency: symbol
                ) != BalanceCacheManager.transactionsCacheKey(
                    chainId: chainID,
                    address: caseVariant,
                    currency: symbol
                )
            )
        }

        let lowerBech32 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let upperBech32 = lowerBech32.uppercased()
        #expect(
            BalanceCacheManager.balanceCacheKey(chainId: "BTC", address: lowerBech32, symbol: "BTC")
                == BalanceCacheManager.balanceCacheKey(chainId: "BTC", address: upperBech32, symbol: "BTC")
        )

        let cashAddress = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let prefixedUpperCashAddress = "BITCOINCASH:\(cashAddress.uppercased())"
        #expect(
            BalanceCacheManager.transactionsCacheKey(chainId: "BCH", address: cashAddress, currency: "BCH")
                == BalanceCacheManager.transactionsCacheKey(
                    chainId: "BCH",
                    address: prefixedUpperCashAddress,
                    currency: "BCH"
                )
        )

        let mixedCaseCashAddress = "bitcoincash:Qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        #expect(
            BalanceCacheManager.transactionsCacheKey(
                chainId: "BCH",
                address: mixedCaseCashAddress,
                currency: "BCH"
            ) != BalanceCacheManager.transactionsCacheKey(
                chainId: "BCH",
                address: cashAddress,
                currency: "BCH"
            )
        )
    }

    @Test("Public crypto tracking vocabulary matches retained proposal states")
    func publicCryptoTrackingVocabulary() {
        #expect(BalanceState.CryptoTrackingStatus.allCases.map(\.title) == [
            "Connecting",
            "Syncing",
            "Connected",
            "Stale",
            "Needs Attention"
        ])
    }

    @Test("Balance state maps retained crypto tracking statuses deterministically")
    func retainedCryptoTrackingStatusMapping() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            BalanceState.loading.publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: false
            ) == .connecting
        )
        #expect(
            BalanceState.loading.publicCryptoTrackingStatus(
                isRefreshing: true,
                hasRetainedValue: true
            ) == .syncing
        )
        #expect(
            BalanceState.loaded(balance: 1.25, isCached: false, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .connected
        )
        #expect(
            BalanceState.loaded(balance: 1.25, isCached: true, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .stale
        )
        #expect(
            BalanceState.error(message: "offline", cachedBalance: 1.25, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .needsAttention
        )
    }

    @Test("Needs attention copy preserves last successful value guidance")
    func needsAttentionCopyKeepsLastSuccessfulValueVisible() {
        let detail = BalanceState.error(
            message: "offline",
            cachedBalance: 0.42,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        ).publicTrackingStatusDetail(
            isRefreshing: false,
            hasRetainedValue: true
        )

        #expect(detail.contains("last successful"))
        #expect(detail.contains("visible"))
    }

    private static func tokenBalance(
        address: String,
        balance: String = "1",
        denominatedBalance: String = "1000000"
    ) -> TatumV4BalanceItem {
        TatumV4BalanceItem(
            chain: "ethereum-mainnet",
            address: "0xwallet",
            balance: balance,
            denominatedBalance: denominatedBalance,
            decimals: 6,
            type: "fungible",
            tokenAddress: address,
            tokenName: "Token",
            tokenSymbol: "TOKEN"
        )
    }
}
