package com.xax.CryptoSavingsTracker.presentation.assets

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumAdaBalanceResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumAdaCurrency
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumSolBalanceResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumTronAccountResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOBalance
import com.xax.CryptoSavingsTracker.data.remote.api.TatumV4BalanceItem
import com.xax.CryptoSavingsTracker.data.remote.api.TatumV4NativeBalanceResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumV4PortfolioResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumXrpBalanceResponse
import com.xax.CryptoSavingsTracker.data.repository.OnChainAssetProviderIdentityVerifier
import com.xax.CryptoSavingsTracker.data.repository.OnChainBalanceRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.confirmVerified
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Named
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource

@OptIn(ExperimentalCoroutinesApi::class)
class AssetBalanceCalculatorTest {
    private val tatumJson = Json { ignoreUnknownKeys = true }

    @Test
    fun totalBalance_includesOnChainBalance_whenHasOnChain() {
        val total = AssetBalanceCalculator.totalBalance(
            manualBalance = 0.0,
            onChainBalance = 0.004106,
            hasOnChain = true
        )

        assertThat(total).isWithin(0.0000001).of(0.004106)
    }

    @Test
    fun totalBalance_ignoresOnChainBalance_whenNoOnChain() {
        val total = AssetBalanceCalculator.totalBalance(
            manualBalance = 1.25,
            onChainBalance = 999.0,
            hasOnChain = false
        )

        assertThat(total).isWithin(0.0000001).of(1.25)
    }

    @Test
    fun `preflight balance fetch does not publish to persistent cache`() = runTest {
        val api = mockk<TatumApi>()
        coEvery { api.getBitcoinBalance("bc1qwallet") } returnsMany listOf(
            TatumUTXOBalance(incoming = "7", outgoing = "0"),
            TatumUTXOBalance(incoming = "6", outgoing = "0")
        )
        val cacheEntries = mutableMapOf<String, String>()
        val repository = repository(api = api, cacheEntries = cacheEntries)
        val trackedAsset = asset(
            currency = "BTC",
            chainId = "bitcoin",
            address = "bc1qwallet"
        )

        assertThat(
            repository.getBalance(trackedAsset, forceRefresh = true).getOrThrow().balance
        ).isEqualTo(7.0)
        assertThat(
            repository.getFreshBalanceForPreflight(trackedAsset).getOrThrow().balance
        ).isEqualTo(6.0)

        val cached = repository.getBalance(trackedAsset, forceRefresh = false).getOrThrow()
        assertThat(cached.balance).isEqualTo(7.0)
        assertThat(repository.observeBalanceInvalidations().first()).isEqualTo(1L)
        coVerify(exactly = 2) { api.getBitcoinBalance("bc1qwallet") }
    }

    @Test
    fun `slower earlier provider completion cannot roll persistent cache back`() = runTest {
        val api = mockk<TatumApi>()
        val calls = AtomicInteger(0)
        val firstStarted = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()
        val firstResponse = CompletableDeferred<TatumUTXOBalance>()
        val secondResponse = CompletableDeferred<TatumUTXOBalance>()
        coEvery { api.getBitcoinBalance("bc1qwallet") } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> {
                    firstStarted.complete(Unit)
                    firstResponse.await()
                }
                2 -> {
                    secondStarted.complete(Unit)
                    secondResponse.await()
                }
                else -> error("Unexpected provider request")
            }
        }
        val cacheEntries = mutableMapOf<String, String>()
        val repository = repository(api = api, cacheEntries = cacheEntries)
        val trackedAsset = asset(
            currency = "BTC",
            chainId = "bitcoin",
            address = "bc1qwallet"
        )

        val earlier = async {
            repository.getBalance(trackedAsset, forceRefresh = true).getOrThrow()
        }
        firstStarted.await()
        val later = async {
            repository.getBalance(trackedAsset, forceRefresh = true).getOrThrow()
        }
        secondStarted.await()

        secondResponse.complete(TatumUTXOBalance(incoming = "20", outgoing = "0"))
        assertThat(later.await().balance).isEqualTo(20.0)
        firstResponse.complete(TatumUTXOBalance(incoming = "10", outgoing = "0"))
        assertThat(earlier.await().balance).isEqualTo(10.0)

        val cached = repository.getBalance(trackedAsset, forceRefresh = false).getOrThrow()
        assertThat(cached.balance).isEqualTo(20.0)
        assertThat(calls.get()).isEqualTo(2)
        assertThat(repository.observeBalanceInvalidations().first()).isEqualTo(1L)
    }

    @Test
    fun `cache clear fences an older balance before it registers its request generation`() = runTest {
        val api = mockk<TatumApi>()
        val calls = AtomicInteger(0)
        coEvery { api.getBitcoinBalance("bc1qwallet") } coAnswers {
            if (calls.incrementAndGet() == 1) {
                TatumUTXOBalance(incoming = "10", outgoing = "0")
            } else {
                TatumUTXOBalance(incoming = "20", outgoing = "0")
            }
        }
        val cacheEntries = mutableMapOf<String, String>()
        val repository = repository(api = api, cacheEntries = cacheEntries)
        val trackedAsset = asset(
            currency = "BTC",
            chainId = "bitcoin",
            address = "bc1qwallet"
        )
        val repositoryMutex = repository.privateMutex()

        repositoryMutex.lock()
        val preClear = async {
            repository.getBalance(trackedAsset, forceRefresh = true).getOrThrow()
        }
        runCurrent()
        val clear = async { repository.clearCache() }
        runCurrent()
        repositoryMutex.unlock()

        clear.await()
        assertThat(preClear.await().balance).isEqualTo(10.0)

        val postClear = repository.getBalance(trackedAsset, forceRefresh = false).getOrThrow()
        assertThat(postClear.balance).isEqualTo(20.0)
        assertThat(calls.get()).isEqualTo(2)
    }

    @Test
    fun evmTokenBalance_selectsCanonicalContractBeforeCounterfeitWithSameSymbol() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                tokenTypes = any()
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "99000000",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = COUNTERFEIT_USDC_ETHEREUM_CONTRACT
                ),
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "12500000",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xwallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(12.5)
    }

    @Test
    fun evmTokenBalance_routesPersistedLegacyChainAliasThroughCanonicalChain() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xlegacywallet",
                tokenTypes = any()
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "2500000",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ETH", address = "0xlegacywallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.chainId).isEqualTo("ethereum")
        assertThat(balance.balance).isWithin(0.0000001).of(2.5)
        coVerify(exactly = 1) {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xlegacywallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 0
            )
        }
    }

    @Test
    fun nonEvmBalanceCache_preservesCaseSensitiveSolanaAddresses() = runTest {
        val firstAddress = "So11111111111111111111111111111111111111112"
        val secondAddress = "so11111111111111111111111111111111111111112"
        val cacheEntries = mutableMapOf<String, String>()
        val api = apiReturningV4NativeBalance(42.0)
        coEvery { api.getSolanaBalance(firstAddress) } returns
            TatumSolBalanceResponse(balance = "1000000000")
        coEvery { api.getSolanaBalance(secondAddress) } returns
            TatumSolBalanceResponse(balance = "2000000000")
        val repository = repository(api = api, cacheEntries = cacheEntries)

        val first = repository.getBalance(
            asset = asset(currency = "SOL", chainId = "solana", address = firstAddress),
            forceRefresh = true
        ).getOrThrow()
        val second = repository.getBalance(
            asset = asset(currency = "SOL", chainId = "solana", address = secondAddress),
            forceRefresh = false
        ).getOrThrow()

        assertThat(first.balance).isWithin(0.0000001).of(1.0)
        assertThat(second.balance).isWithin(0.0000001).of(2.0)
        assertThat(cacheEntries).hasSize(2)
        coVerify(exactly = 1) {
            api.getSolanaBalance(firstAddress)
            api.getSolanaBalance(secondAddress)
        }
    }

    @Test
    fun evmTokenBalance_usesCurrentQuickContractWhenLegacyAndCurrentBalancesBothExist() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "polygon-mainnet",
                addresses = "0xquickwallet",
                tokenTypes = any()
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "3",
                    decimals = 0,
                    tokenSymbol = "QUICK",
                    tokenAddress = LEGACY_QUICK_POLYGON_CONTRACT
                ),
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "7",
                    decimals = 0,
                    tokenSymbol = "QUICK",
                    tokenAddress = CURRENT_QUICK_POLYGON_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "QUICK", chainId = "polygon", address = "0xquickwallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(7.0)
    }

    @Test
    fun evmTokenBalance_followsPortfolioPagesUntilCanonicalContractIsFound() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xpagedwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 0
            )
        } returns TatumV4PortfolioResponse(
            result = List(50) { index ->
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "1",
                    decimals = 0,
                    tokenAddress = "0x${index.toString(16).padStart(40, '0')}"
                )
            }
        )
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xpagedwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 50
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "7500000",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xpagedwallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(7.5)
        io.mockk.coVerifySequence {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xpagedwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 0
            )
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xpagedwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 50
            )
        }
    }

    @Test
    fun evmTokenBalance_returnsZeroWhenExhaustedPortfolioIsEmpty() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xemptywallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 0
            )
        } returns TatumV4PortfolioResponse(result = emptyList())

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xemptywallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isEqualTo(0.0)
    }

    @Test
    fun networkBalanceFailsWithoutCachingWhenPersistedProviderIdentityChanged() = runTest {
        val original = asset(
            currency = "ETH",
            chainId = "ethereum",
            address = "0xwallet-a"
        )
        val identityVerifier = mockk<OnChainAssetProviderIdentityVerifier>()
        val cacheEntries = mutableMapOf<String, String>()
        coEvery {
            identityVerifier.assertUnchanged(original)
        } throws IllegalStateException(
            "Asset provider identity changed while on-chain balance was loading"
        )

        val result = repository(
            api = apiReturningV4NativeBalance(42.0),
            cacheEntries = cacheEntries,
            identityVerifier = identityVerifier
        ).getBalance(original, forceRefresh = true)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity changed")
        assertThat(cacheEntries).isEmpty()
        coVerify(exactly = 1) {
            identityVerifier.assertUnchanged(original)
        }
    }

    @Test
    fun evmTokenBalance_returnsZeroWhenLastPartialPageHasNoCanonicalContract() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xpartialwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = 0
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "99000000",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = COUNTERFEIT_USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xpartialwallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isEqualTo(0.0)
    }

    @Test
    fun evmTokenBalance_failsUnavailableWhenPortfolioPaginationSafetyCapIsExhausted() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        val requestedOffsets = mutableListOf<Int>()
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xspamwallet",
                tokenTypes = "fungible",
                pageSize = 50,
                offset = capture(requestedOffsets)
            )
        } returns TatumV4PortfolioResponse(
            result = List(50) { index ->
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "1",
                    decimals = 0,
                    tokenAddress = "0x${index.toString(16).padStart(40, '0')}"
                )
            }
        )

        val result = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xspamwallet"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(requestedOffsets.size).isAtLeast(2)
        assertThat(requestedOffsets.size).isAtMost(100)
        assertThat(requestedOffsets.distinct()).hasSize(requestedOffsets.size)
        assertThat(requestedOffsets.first()).isEqualTo(0)
        requestedOffsets.zipWithNext().forEach { (previous, next) ->
            assertThat(next - previous).isEqualTo(50)
        }
    }

    @Test
    fun evmTokenBalance_scalesAtomicBalanceAtOrBelowOneThousand() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xsmallwallet",
                tokenTypes = any()
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "500",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDC", chainId = "ethereum", address = "0xsmallwallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000000001).of(0.0005)
    }

    @Test
    fun xrpBalance_usesXrpEndpointAndConvertsDrops() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery { api.getXrpBalance("rWallet") } returns TatumXrpBalanceResponse(
            balance = "2000000"
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "XRP", chainId = "xrp", address = "rWallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(2.0)
    }

    @Test
    fun tronTokenBalance_decodesRealPayloadAndNormalizesAtomicUnits() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery { api.getTronAccount("TWallet") } returns
            tatumJson.decodeFromString<TatumTronAccountResponse>(TRON_ACCOUNT_RESPONSE_JSON)

        val balance = repository(api).getBalance(
            asset = asset(currency = "USDT", chainId = "tron", address = "TWallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(12.345678)
    }

    @Test
    fun tronTokenBalance_acceptsCanonicalContractAddress() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery { api.getTronAccount("TWallet") } returns
            tatumJson.decodeFromString<TatumTronAccountResponse>(TRON_ACCOUNT_RESPONSE_JSON)

        val balance = repository(api).getBalance(
            asset = asset(
                currency = TRON_USDT_CONTRACT,
                chainId = "tron",
                address = "TWallet"
            ),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(12.345678)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("unsupportedNativeOnlyPairs")
    fun nativeOnlyChain_rejectsTokenCurrency(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        nativeCurrency: String
    ) = runTest {
        val result = repository(apiReturningNativeBalances()).getBalance(
            asset = asset(currency = "USDC", chainId = chainId, address = "wallet"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("USDC")
        assertThat(result.exceptionOrNull()).hasMessageThat().contains(nativeCurrency)
    }

    @Test
    fun nativeOnlyChain_rejectsTokenCurrencyBeforeReturningLegacyMislabelledCache() = runTest {
        val cachedEntry = """
            {
              "balance": 42.0,
              "fetchedAtMillis": ${System.currentTimeMillis()}
            }
        """.trimIndent()

        val result = repository(
            api = apiReturningNativeBalances(),
            cachedEntry = cachedEntry
        ).getBalance(
            asset = asset(currency = "USDC", chainId = "solana", address = "wallet"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun cardano_rejectsNonAdaBeforeReturningCachedBalance() = runTest {
        val cachedEntry = """
            {
              "balance": 42.0,
              "fetchedAtMillis": ${System.currentTimeMillis()}
            }
        """.trimIndent()

        val result = repository(
            api = apiReturningNativeBalances(),
            cachedEntry = cachedEntry
        ).getBalance(
            asset = asset(currency = "USDC", chainId = "cardano", address = "addr1wallet"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("ADA")
    }

    @Test
    fun evmTokenBalance_rejectsUnsupportedTokenChainPairBeforeReturningCachedBalance() = runTest {
        val cachedEntry = """
            {
              "balance": 42.0,
              "fetchedAtMillis": ${System.currentTimeMillis()}
            }
        """.trimIndent()

        val result = repository(
            api = apiReturningNativeBalances(),
            cachedEntry = cachedEntry
        ).getBalance(
            asset = asset(currency = "USDC", chainId = "bsc", address = "0xwallet"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("USDC")
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("bsc")
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("officialEvmV4Chains")
    fun evmNativeBalance_usesOfficialV4ChainAndPreservesHumanReadableAmount(
        @Suppress("UNUSED_PARAMETER") description: String,
        internalChainId: String,
        nativeCurrency: String,
        officialTatumChain: String
    ) = runTest {
        val api = mockk<TatumApi>()
        coEvery {
            api.getNativeBalance(
                chain = officialTatumChain,
                address = "0xwallet"
            )
        } returns TatumV4NativeBalanceResponse(balance = "0.502")

        val balance = repository(api).getBalance(
            asset = asset(
                currency = nativeCurrency,
                chainId = internalChainId,
                address = "0xwallet"
            ),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(0.502)
    }

    @Test
    fun malformedNativeBalance_failsWithoutCachingAuthoritativeZero() = runTest {
        val cacheEntries = mutableMapOf<String, String>()
        val api = mockk<TatumApi>()
        coEvery {
            api.getNativeBalance(
                chain = "ethereum-mainnet",
                address = "0xwallet"
            )
        } returns TatumV4NativeBalanceResponse(balance = "not-a-balance")

        val result = repository(
            api = api,
            cacheEntries = cacheEntries
        ).getBalance(
            asset = asset(
                currency = "ETH",
                chainId = "ethereum",
                address = "0xwallet"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(cacheEntries).isEmpty()
    }

    @Test
    fun futureDatedBalanceCache_isRejectedAndRefreshedFromNetwork() = runTest {
        val futureCachedEntry = """
            {
              "balance": 42.0,
              "fetchedAtMillis": ${System.currentTimeMillis() + 86_400_000L}
            }
        """.trimIndent()
        val api = apiReturningV4NativeBalance(7.0)

        val balance = repository(
            api = api,
            cachedEntry = futureCachedEntry
        ).getBalance(
            asset = asset(
                currency = "ETH",
                chainId = "ethereum",
                address = "0xwallet"
            ),
            forceRefresh = false
        ).getOrThrow()

        assertThat(balance.balance).isEqualTo(7.0)
        assertThat(balance.fetchedAtMillis).isLessThan(System.currentTimeMillis() + 5_000L)
        coVerify(exactly = 1) {
            api.getNativeBalance("ethereum-mainnet", "0xwallet")
        }
    }

    @Test
    fun nonFiniteCanonicalTokenBalance_failsWithoutCachingIt() = runTest {
        val cacheEntries = mutableMapOf<String, String>()
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                tokenTypes = "fungible"
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "NaN",
                    decimals = 6,
                    tokenSymbol = "USDC",
                    tokenAddress = USDC_ETHEREUM_CONTRACT
                )
            )
        )

        val result = repository(
            api = api,
            cacheEntries = cacheEntries
        ).getBalance(
            asset = asset(
                currency = "USDC",
                chainId = "ethereum",
                address = "0xwallet"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(cacheEntries).isEmpty()
    }

    @Test
    fun legacyRoutingCache_isIgnoredWhenFreshNetworkBalanceIsAvailable() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery {
            api.getWalletPortfolio(
                chain = "ethereum-mainnet",
                addresses = "address",
                tokenTypes = any()
            )
        } returns TatumV4PortfolioResponse(
            result = listOf(
                TatumV4BalanceItem(
                    type = "fungible",
                    denominatedBalance = "7500000",
                    decimals = 6,
                    tokenSymbol = "USDT",
                    tokenAddress = USDT_ETHEREUM_CONTRACT
                )
            )
        )

        val balance = repository(
            api = api,
            legacyCachedEntry = freshCacheEntry(balance = 42.0)
        ).getBalance(
            asset = asset(currency = "USDT", chainId = "ethereum", address = "address"),
            forceRefresh = false
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(7.5)
        assertThat(balance.isStale).isFalse()
    }

    @Test
    fun legacyRoutingCache_isIgnoredForOfflineFallback() = runTest {
        val result = repository(
            api = apiReturningV4NativeBalance(42.0),
            legacyCachedEntry = freshCacheEntry(balance = 42.0),
            apiKey = ""
        ).getBalance(
            asset = asset(currency = "USDT", chainId = "ethereum", address = "address"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("Tatum API key")
    }

    @Test
    fun previousV2ScalingCache_isIgnoredForOfflineFallback() = runTest {
        val result = repository(
            api = apiReturningV4NativeBalance(42.0),
            previousCachedEntry = freshCacheEntry(balance = 42.0),
            apiKey = ""
        ).getBalance(
            asset = asset(currency = "ETH", chainId = "ethereum", address = "address"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("Tatum API key")
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("unsupportedEvmChains")
    fun unsupportedChain_rejectsCurrentCacheWithoutCallingTatum(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val api = mockk<TatumApi>()
        val result = repository(
            api = api,
            cachedEntry = freshCacheEntry(balance = 42.0)
        ).getBalance(
            asset = asset(currency = currency, chainId = chainId, address = "0xwallet"),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains(chainId)
        confirmVerified(api)
    }

    @Test
    fun cardanoBalance_usesCardanoEndpointAndSelectsAda() = runTest {
        val api = apiReturningV4NativeBalance(42.0)
        coEvery { api.getCardanoAccount("addr1wallet") } returns listOf(
            TatumAdaBalanceResponse(
                value = "4000000",
                currency = TatumAdaCurrency(symbol = "ADA")
            )
        )

        val balance = repository(api).getBalance(
            asset = asset(currency = "ADA", chainId = "cardano", address = "addr1wallet"),
            forceRefresh = true
        ).getOrThrow()

        assertThat(balance.balance).isWithin(0.0000001).of(4.0)
    }

    private fun apiReturningV4NativeBalance(balance: Double): TatumApi {
        return mockk<TatumApi>().also { api ->
            coEvery {
                api.getNativeBalance(any(), any())
            } returns TatumV4NativeBalanceResponse(balance = balance.toString())
        }
    }

    private fun apiReturningNativeBalances(): TatumApi {
        return apiReturningV4NativeBalance(42.0).also { api ->
            coEvery { api.getBitcoinBalance(any()) } returns TatumUTXOBalance("0", "0")
            coEvery { api.getLitecoinBalance(any()) } returns TatumUTXOBalance("0", "0")
            coEvery { api.getBitcoinCashBalance(any()) } returns TatumUTXOBalance("0", "0")
            coEvery { api.getDogecoinBalance(any()) } returns TatumUTXOBalance("0", "0")
            coEvery { api.getSolanaBalance(any()) } returns TatumSolBalanceResponse("0")
            coEvery { api.getXrpBalance(any()) } returns TatumXrpBalanceResponse("0")
        }
    }

    private fun repository(
        api: TatumApi,
        cachedEntry: String? = null,
        legacyCachedEntry: String? = null,
        previousCachedEntry: String? = null,
        apiKey: String = "test-api-key",
        cacheEntries: MutableMap<String, String>? = null,
        identityVerifier: OnChainAssetProviderIdentityVerifier =
            currentIdentityVerifier()
    ): OnChainBalanceRepositoryImpl {
        val context = mockk<Context>()
        val prefs = mockk<SharedPreferences>()
        val legacyPrefs = mockk<SharedPreferences>()
        val previousPrefs = mockk<SharedPreferences>()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val apiKeyStore = mockk<ApiKeyStore>()

        every {
            context.getSharedPreferences(any(), Context.MODE_PRIVATE)
        } answers {
            when (firstArg<String>()) {
                LEGACY_CACHE_NAMESPACE -> legacyPrefs
                PREVIOUS_CACHE_NAMESPACE -> previousPrefs
                else -> prefs
            }
        }
        every { prefs.getString(any(), null) } answers {
            cacheEntries?.get(firstArg()) ?: cachedEntry
        }
        every { legacyPrefs.getString(any(), null) } returns legacyCachedEntry
        every { previousPrefs.getString(any(), null) } returns previousCachedEntry
        every { prefs.edit() } returns editor
        every { editor.putString(any(), any()) } answers {
            cacheEntries?.set(firstArg(), secondArg())
            editor
        }
        every { apiKeyStore.getTatumApiKey() } returns apiKey

        return OnChainBalanceRepositoryImpl(
            tatumApi = api,
            rateLimiter = TokenBucketRateLimiter(
                maxTokens = 100.0,
                refillTokensPerSecond = 100.0
            ),
            apiKeyStore = apiKeyStore,
            context = context,
            assetProviderIdentityVerifier = identityVerifier
        )
    }

    private fun OnChainBalanceRepositoryImpl.privateMutex(): Mutex {
        return javaClass.getDeclaredField("mutex")
            .apply { isAccessible = true }
            .get(this) as Mutex
    }

    private fun currentIdentityVerifier(): OnChainAssetProviderIdentityVerifier {
        return mockk<OnChainAssetProviderIdentityVerifier>().also { verifier ->
            coEvery { verifier.assertUnchanged(any()) } returns Unit
        }
    }

    private fun asset(
        currency: String,
        chainId: String,
        address: String
    ) = Asset(
        id = "$chainId-$currency",
        currency = currency,
        address = address,
        chainId = chainId,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun freshCacheEntry(balance: Double): String {
        return """
            {
              "balance": $balance,
              "fetchedAtMillis": ${System.currentTimeMillis()}
            }
        """.trimIndent()
    }

    private companion object {
        const val LEGACY_CACHE_NAMESPACE = "onchain_balance_cache"
        const val PREVIOUS_CACHE_NAMESPACE = "onchain_balance_cache_v2"
        const val USDT_ETHEREUM_CONTRACT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        const val USDC_ETHEREUM_CONTRACT = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        const val COUNTERFEIT_USDC_ETHEREUM_CONTRACT = "0x0000000000000000000000000000000000000001"
        const val CURRENT_QUICK_POLYGON_CONTRACT = "0xB5C064F955D8e7F38fE0460C556a72987494eE17"
        const val LEGACY_QUICK_POLYGON_CONTRACT = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13"
        const val TRON_USDT_CONTRACT = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

        const val TRON_ACCOUNT_RESPONSE_JSON = """
            {
              "balance": 3000000,
              "createTime": 1668192183000,
              "trc10": [],
              "trc20": [
                {
                  "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t": "12345678"
                }
              ],
              "freeNetLimit": 600,
              "bandwidth": 600
            }
        """

        @JvmStatic
        fun unsupportedNativeOnlyPairs() = listOf(
            Arguments.of(Named.of("Bitcoin rejects USDC", "bitcoin"), "bitcoin", "BTC"),
            Arguments.of(Named.of("Litecoin rejects USDC", "litecoin"), "litecoin", "LTC"),
            Arguments.of(Named.of("Bitcoin Cash rejects USDC", "bitcoin-cash"), "bitcoin-cash", "BCH"),
            Arguments.of(Named.of("Dogecoin rejects USDC", "dogecoin"), "dogecoin", "DOGE"),
            Arguments.of(Named.of("Solana rejects USDC", "solana"), "solana", "SOL"),
            Arguments.of(Named.of("XRP Ledger rejects USDC", "xrp"), "xrp", "XRP"),
            Arguments.of(Named.of("Cardano rejects USDC", "cardano"), "cardano", "ADA")
        )

        @JvmStatic
        fun officialEvmV4Chains() = listOf(
            Arguments.of(
                Named.of("Ethereum", "ethereum"),
                "ethereum",
                "ETH",
                "ethereum-mainnet"
            ),
            Arguments.of(
                Named.of("Polygon", "polygon"),
                "polygon",
                "POL",
                "polygon-mainnet"
            ),
            Arguments.of(
                Named.of("BNB Smart Chain", "bsc"),
                "bsc",
                "BNB",
                "bsc-mainnet"
            ),
            Arguments.of(
                Named.of("Arbitrum", "arbitrum"),
                "arbitrum",
                "ETH",
                "arb-one-mainnet"
            ),
            Arguments.of(
                Named.of("Optimism", "optimism"),
                "optimism",
                "ETH",
                "optimism-mainnet"
            ),
            Arguments.of(
                Named.of("Base", "base"),
                "base",
                "ETH",
                "base-mainnet"
            ),
            Arguments.of(
                Named.of("Avalanche", "avax"),
                "avax",
                "AVAX",
                "avax-mainnet"
            )
        )

        @JvmStatic
        fun unsupportedEvmChains() = listOf(
            Arguments.of(Named.of("Fantom", "ftm"), "ftm", "FTM"),
            Arguments.of(Named.of("Unknown chain", "mystery"), "mystery", "ETH"),
            Arguments.of(
                Named.of(
                    "Quarantined immutable-rate conflict",
                    "legacy-rate-conflict:ethereum:rate-contract"
                ),
                "legacy-rate-conflict:ethereum:rate-contract",
                "USDC"
            )
        )
    }
}
