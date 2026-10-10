package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumEvmJsonRpcReceiptResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumEvmJsonRpcRequest
import com.xax.CryptoSavingsTracker.data.remote.api.TatumEvmTransactionReceipt
import com.xax.CryptoSavingsTracker.data.remote.api.TatumScriptPubKey
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOCoin
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOInput
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOOutput
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOTransaction
import com.xax.CryptoSavingsTracker.data.remote.api.TatumTransactionDto
import com.xax.CryptoSavingsTracker.data.remote.api.TatumV4TransactionResponse
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceUnavailableException
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.confirmVerified
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Named
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource

class OnChainTransactionRepositoryImplTest {
    @ParameterizedTest(name = "{0}")
    @MethodSource("officialEvmV4Chains")
    fun `transaction refresh sends the official V4 chain identifier`(
        @Suppress("UNUSED_PARAMETER") description: String,
        internalChain: String,
        officialChain: String,
        nativeCurrency: String
    ) = runTest {
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }
        val repository = repository(api)

        val result = repository.refresh(
            asset = Asset(
                id = "asset-1",
                currency = nativeCurrency,
                address = "0xwallet",
                chainId = internalChain,
                createdAt = 1L,
                updatedAt = 1L
            ),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = officialChain,
                addresses = "0xwallet",
                transactionTypes = "native",
                tokenAddress = null,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
        confirmVerified(api)
    }

    @Test
    fun `transaction refresh routes persisted legacy chain alias through canonical chain`() = runTest {
        val cacheReads = mutableListOf<String>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }

        val result = repository(
            api = api,
            cacheReads = cacheReads
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ETH", address = "0xlegacywallet"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(cacheReads).containsExactly(
            "transactions_v3:asset-1:ethereum:0xlegacywallet:USDC"
        )
        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xlegacywallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
    }

    @Test
    fun `transaction refresh clamps caller limit to the supported V4 page size`() = runTest {
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }

        repository(api).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            limit = 0,
            forceRefresh = true
        ).getOrThrow()
        repository(api).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            limit = 500,
            forceRefresh = true
        ).getOrThrow()

        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 1,
                offset = 0
            )
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 50,
                offset = 0
            )
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("unsupportedTransactionChains")
    fun `unsupported transaction chain fails before any Tatum request`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val api = mockk<TatumApi>()
        val result = repository(
            api = api,
            cachedEntry = """{"fetchedAtMillis":${System.currentTimeMillis()}}""",
            apiKey = ""
        ).refresh(
            asset = Asset(
                id = "asset-1",
                currency = currency,
                address = "wallet",
                chainId = chainId,
                createdAt = 1L,
                updatedAt = 1L
            ),
            forceRefresh = false
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains(chainId)
        confirmVerified(api)
    }

    @Test
    fun `legacy fresh cache entry cannot suppress first filtered refresh`() = runTest {
        val cacheReads = mutableListOf<String>()
        val legacyCacheKey = "ethereum:0xwallet:USDC"
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }

        val result = repository(
            api = api,
            cachedEntries = mapOf(
                legacyCacheKey to """{"fetchedAtMillis":${System.currentTimeMillis()}}"""
            ),
            cacheReads = cacheReads
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = false
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(cacheReads).containsExactly("transactions_v3:asset-1:$legacyCacheKey")
        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
    }

    @Test
    fun `future cache timestamp after device clock rollback cannot suppress refresh`() = runTest {
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }
        val futureTimestamp = System.currentTimeMillis() + 86_400_000L

        val result = repository(
            api = api,
            cachedEntry = """{"fetchedAtMillis":$futureTimestamp}"""
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = false
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
    }

    @Test
    fun `fresh cache from deleted asset cannot suppress re-added asset refresh`() = runTest {
        val cacheStore = linkedMapOf<String, String>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse()
        }
        val repository = repository(
            api = api,
            cacheStore = cacheStore
        )

        repository.refresh(
            asset = asset(
                id = "deleted-asset",
                currency = "USDC",
                chainId = "ethereum"
            ),
            forceRefresh = true
        ).getOrThrow()
        repository.refresh(
            asset = asset(
                id = "re-added-asset",
                currency = "USDC",
                chainId = "ethereum"
            ),
            forceRefresh = false
        ).getOrThrow()

        coVerify(exactly = 2) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
        assertThat(cacheStore).hasSize(2)
    }

    @Test
    fun `fungible refresh requests and imports only the canonical token contract`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val transactionRepository = transactionRepository(inserted)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "canonical",
                        transactionType = "fungible",
                        amount = "12.5",
                        tokenAddress = USDC_ETHEREUM_CONTRACT
                    ),
                    evmTransaction(
                        hash = "counterfeit",
                        transactionType = "fungible",
                        amount = "9000",
                        tokenAddress = COUNTERFEIT_USDC_CONTRACT
                    ),
                    evmTransaction(
                        hash = "native",
                        transactionType = "native",
                        amount = "4",
                        tokenAddress = null
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted).hasSize(1)
        assertThat(inserted.single().amount).isEqualTo(12.5)
        coVerify(exactly = 1) {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
        }
    }

    @Test
    fun `same hash token events without provider indices fail closed`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "shared-hash",
                        transactionType = "fungible",
                        amount = "1.25",
                        tokenAddress = USDC_ETHEREUM_CONTRACT,
                        counterAddress = "0xsender-a"
                    ),
                    evmTransaction(
                        hash = "shared-hash",
                        transactionType = "fungible",
                        amount = "2.50",
                        tokenAddress = USDC_ETHEREUM_CONTRACT,
                        counterAddress = "0xsender-b"
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("indistinguishable movements without stable event indices")
        assertThat(inserted).isEmpty()
    }

    @Test
    fun `indistinguishable same hash movements fail without partial import`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val repeatedMovement = evmTransaction(
            hash = "repeated-hash",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xsender"
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(repeatedMovement, repeatedMovement)
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(inserted).isEmpty()
    }

    @Test
    fun `same hash movements use API indices and remain stable when response order changes`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val transactionRepository = statefulTransactionRepository(storedByExternalId)
        val movementAtIndexSeven = evmTransaction(
            hash = "indexed-hash",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xsender"
        ).copy(transactionIndex = 7, logIndex = 70)
        val movementAtIndexEight = movementAtIndexSeven.copy(
            transactionIndex = 8,
            logIndex = 80
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(
                    result = listOf(movementAtIndexSeven, movementAtIndexEight)
                ),
                TatumV4TransactionResponse(
                    result = listOf(movementAtIndexEight, movementAtIndexSeven)
                )
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = transactionRepository
        )

        val firstRefresh = repository.refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )
        val firstExternalIds = storedByExternalId.keys.toSet()
        val secondRefresh = repository.refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(firstRefresh.getOrThrow()).isEqualTo(2)
        assertThat(secondRefresh.getOrThrow()).isEqualTo(0)
        assertThat(storedByExternalId).hasSize(2)
        assertThat(storedByExternalId.keys).containsExactlyElementsIn(firstExternalIds)
    }

    @Test
    fun `provider correction across refresh updates one canonical row without duplicating value`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val original = evmTransaction(
            hash = "provider-correction",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xoriginal"
        ).copy(transactionIndex = 4, logIndex = 9, timestamp = 1_000L)
        val corrected = original.copy(
            amount = "2.50",
            counterAddress = "0xcorrected",
            timestamp = 2_000L
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(original)),
                TatumV4TransactionResponse(result = listOf(corrected))
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        assertThat(
            repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        ).isEqualTo(1)
        val originalRowId = storedByExternalId.values.single().id
        assertThat(
            repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        ).isEqualTo(0)

        assertThat(storedByExternalId.values.map { it.id }.distinct())
            .containsExactly(originalRowId)
        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.values.single().amount).isEqualTo(2.5)
        assertThat(storedByExternalId.values.single().dateMillis).isEqualTo(2_000_000L)
        assertThat(storedByExternalId.values.single().counterparty).isEqualTo("0xcorrected")
    }

    @Test
    fun `latest refresh wins when an older provider correction completes last`() = runTest {
        val olderSnapshot = evmTransaction(
            hash = "reverse-completion-correction",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xolder"
        ).copy(transactionIndex = 4, logIndex = 9, timestamp = 1_000L)
        val newerSnapshot = olderSnapshot.copy(
            amount = "2.50",
            counterAddress = "0xnewer",
            timestamp = 2_000L
        )
        val olderRequestStarted = CompletableDeferred<Unit>()
        val allowOlderResponse = CompletableDeferred<Unit>()
        var requestCount = 0
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } coAnswers {
                requestCount += 1
                if (requestCount == 1) {
                    olderRequestStarted.complete(Unit)
                    allowOlderResponse.await()
                    TatumV4TransactionResponse(result = listOf(olderSnapshot))
                } else {
                    TatumV4TransactionResponse(result = listOf(newerSnapshot))
                }
            }
        }
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId),
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        val olderRefresh = async {
            repository.refresh(trackedAsset, forceRefresh = true)
        }
        olderRequestStarted.await()
        val newerRefresh = async {
            repository.refresh(trackedAsset, forceRefresh = true)
        }

        assertThat(newerRefresh.await().getOrThrow()).isEqualTo(1)
        assertThat(storedByExternalId.values.single().amount).isEqualTo(2.5)
        assertThat(storedByExternalId.values.single().dateMillis).isEqualTo(2_000_000L)
        assertThat(cacheWrites).hasSize(1)
        val newestCacheWrite = cacheWrites.single()

        allowOlderResponse.complete(Unit)
        assertThat(olderRefresh.await().getOrThrow()).isEqualTo(0)

        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.values.single().amount).isEqualTo(2.5)
        assertThat(storedByExternalId.values.single().dateMillis).isEqualTo(2_000_000L)
        assertThat(storedByExternalId.values.single().counterparty).isEqualTo("0xnewer")
        assertThat(cacheWrites).containsExactly(newestCacheWrite)
    }

    @Test
    fun `older refresh cannot publish a stale balance after newer correction commits`() = runTest {
        val originalDeposit = evmTransaction(
            hash = "stale-preflight-balance",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 4, logIndex = 9, timestamp = 1_000L)
        val olderPositiveCorrection = originalDeposit.copy(amount = "2", timestamp = 2_000L)
        val newerWithdrawalCorrection = originalDeposit.copy(
            amount = "-2",
            transactionSubtype = "outgoing",
            timestamp = 3_000L
        )
        var transactionRequestCount = 0
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } coAnswers {
                transactionRequestCount += 1
                TatumV4TransactionResponse(
                    result = listOf(
                        if (transactionRequestCount == 1) {
                            olderPositiveCorrection
                        } else {
                            newerWithdrawalCorrection
                        }
                    )
                )
            }
        }
        var allocation = Allocation(
            id = "stale-preflight-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 6.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf(
            AllocationHistory(
                id = "stale-preflight-history",
                assetId = "asset-1",
                goalId = "goal-1",
                amount = 6.0,
                monthLabel = "1970-01",
                timestamp = 1_000_000L,
                createdAt = 1L
            )
        )
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val olderBalanceStarted = CompletableDeferred<Unit>()
        val allowOlderBalanceResponse = CompletableDeferred<Unit>()
        var publishedBalance = OnChainBalance(
            assetId = "asset-1",
            chainId = "ethereum",
            address = "0xwallet",
            currency = "USDC",
            balance = 7.0,
            fetchedAtMillis = 1L,
            isStale = false
        )
        val onChainBalanceRepository = object : OnChainBalanceRepository {
            var publishingCalls = 0

            override suspend fun getBalance(
                asset: Asset,
                forceRefresh: Boolean
            ): Result<OnChainBalance> {
                publishingCalls += 1
                publishedBalance = providerSnapshot(asset)
                return Result.success(publishedBalance)
            }

            override suspend fun getFreshBalanceForPreflight(
                asset: Asset
            ): Result<OnChainBalance> {
                olderBalanceStarted.complete(Unit)
                allowOlderBalanceResponse.await()
                return Result.success(providerSnapshot(asset))
            }

            override suspend fun clearCache() = Unit

            private fun providerSnapshot(asset: Asset) = OnChainBalance(
                assetId = asset.id,
                chainId = checkNotNull(asset.chainId),
                address = checkNotNull(asset.address),
                currency = asset.currency,
                balance = 6.0,
                fetchedAtMillis = System.currentTimeMillis(),
                isStale = false
            )
        }
        val originalExternalId = canonicalExternalIdFor(originalDeposit)
        val storedByExternalId = linkedMapOf(
            originalExternalId to Transaction(
                id = "stale-preflight-transaction",
                assetId = "asset-1",
                amount = 1.0,
                dateMillis = 1_000_000L,
                source = TransactionSource.ON_CHAIN,
                externalId = originalExternalId,
                counterparty = null,
                comment = "On-chain",
                createdAt = 1L
            )
        )
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        val olderRefresh = async {
            repository.refresh(trackedAsset, forceRefresh = true)
        }
        olderBalanceStarted.await()
        val newerRefresh = async {
            repository.refresh(trackedAsset, forceRefresh = true)
        }

        assertThat(newerRefresh.await().getOrThrow()).isEqualTo(0)
        assertThat(storedByExternalId.values.single().amount).isEqualTo(-2.0)
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(publishedBalance.balance).isEqualTo(7.0)

        allowOlderBalanceResponse.complete(Unit)
        assertThat(olderRefresh.await().getOrThrow()).isEqualTo(0)

        assertThat(storedByExternalId.values.single().amount).isEqualTo(-2.0)
        assertThat(storedByExternalId.values.single().dateMillis).isEqualTo(3_000_000L)
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(histories.single().amount).isEqualTo(5.0)
        assertThat(publishedBalance.balance).isEqualTo(7.0)
        assertThat(onChainBalanceRepository.publishingCalls).isEqualTo(0)
    }

    @Test
    fun `provider index enrichment upgrades the unique installed row`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val original = evmTransaction(
            hash = "provider-enrichment",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val enriched = original.copy(transactionIndex = 3, logIndex = 8)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(original)),
                TatumV4TransactionResponse(result = listOf(enriched))
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        val originalRowId = storedByExternalId.values.single().id
        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()

        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.values.single().id).isEqualTo(originalRowId)
        assertThat(storedByExternalId.keys.single()).isEqualTo(canonicalExternalIdFor(enriched))
    }

    @Test
    fun `partial provider index enrichment upgrades the unique installed row`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val partial = evmTransaction(
            hash = "partial-provider-enrichment",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 3, logIndex = null)
        val enriched = partial.copy(logIndex = 8)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(partial)),
                TatumV4TransactionResponse(result = listOf(enriched))
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        val originalRowId = storedByExternalId.values.single().id
        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()

        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.values.single().id).isEqualTo(originalRowId)
        assertThat(storedByExternalId.keys.single()).isEqualTo(canonicalExternalIdFor(enriched))
    }

    @Test
    fun `same provider batch collapses one weak event into its unique enrichment`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val weak = evmTransaction(
            hash = "same-batch-enrichment",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val enriched = weak.copy(transactionIndex = 3, logIndex = 8)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(weak, enriched))
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.keys.single()).isEqualTo(canonicalExternalIdFor(enriched))
    }

    @Test
    fun `same provider batch fails when one weak event maps to multiple enrichments`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val weak = evmTransaction(
            hash = "same-batch-ambiguous-enrichment",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val enrichedA = weak.copy(transactionIndex = 3, logIndex = 8)
        val enrichedB = weak.copy(
            amount = "2.50",
            counterAddress = "0xother",
            transactionIndex = 3,
            logIndex = 9
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(weak, enrichedA, enrichedB)
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("same-batch event-index enrichment maps ambiguously")
        assertThat(inserted).isEmpty()
    }

    @Test
    fun `provider index enrichment fails when one weak row maps to multiple events`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val original = evmTransaction(
            hash = "ambiguous-enrichment",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val enrichedA = original.copy(transactionIndex = 3, logIndex = 8)
        val enrichedB = original.copy(
            amount = "2.50",
            counterAddress = "0xother",
            transactionIndex = 3,
            logIndex = 9
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(original)),
                TatumV4TransactionResponse(result = listOf(enrichedA, enrichedB))
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        val installedBeforeEnrichment = storedByExternalId.toMap()
        val result = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("event-index enrichment maps ambiguously")
        assertThat(storedByExternalId).containsExactlyEntriesIn(installedBeforeEnrichment)
    }

    @Test
    fun `installed mutable provider id migrates in place on correction`() = runTest {
        val original = evmTransaction(
            hash = "installed-mutable-id",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xold"
        ).copy(transactionIndex = 3, logIndex = 8, timestamp = 1_000L)
        val corrected = original.copy(
            amount = "2.50",
            counterAddress = "0xnew",
            timestamp = 2_000L
        )
        val oldExternalId = legacyMutableExternalIdFor(original)
        val installed = Transaction(
            id = "installed-row",
            assetId = "asset-1",
            amount = 1.25,
            dateMillis = 1_000_000L,
            source = TransactionSource.ON_CHAIN,
            externalId = oldExternalId,
            counterparty = "0xold",
            comment = "Preserve comment",
            createdAt = 777L
        )
        val storedByExternalId = linkedMapOf(oldExternalId to installed)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(corrected))
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(storedByExternalId.values).hasSize(1)
        with(storedByExternalId.values.single()) {
            assertThat(id).isEqualTo("installed-row")
            assertThat(externalId).isEqualTo(canonicalExternalIdFor(corrected))
            assertThat(amount).isEqualTo(2.5)
            assertThat(dateMillis).isEqualTo(2_000_000L)
            assertThat(counterparty).isEqualTo("0xnew")
            assertThat(comment).isEqualTo("Preserve comment")
            assertThat(createdAt).isEqualTo(777L)
        }
    }

    @Test
    fun `ambiguous installed mutable provider rows fail before correction writes`() = runTest {
        val first = evmTransaction(
            hash = "ambiguous-installed-provider",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 3, logIndex = 8)
        val second = first.copy(amount = "2.50")
        val firstId = legacyMutableExternalIdFor(first)
        val secondId = legacyMutableExternalIdFor(second)
        val storedByExternalId = linkedMapOf(
            firstId to legacyTransaction("installed-a", firstId),
            secondId to legacyTransaction("installed-b", secondId)
        )
        val originalRows = storedByExternalId.toMap()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(second.copy(amount = "3.0")))
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("Installed provider transaction identity is ambiguous")
        assertThat(storedByExternalId).containsExactlyEntriesIn(originalRows)
    }

    @Test
    fun `refresh aborts atomically when provider asset identity changes during network suspension`() = runTest {
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        var persistedAsset = trackedAsset
        val assetRepository = mockk<AssetRepository> {
            coEvery { getAssetById(trackedAsset.id) } answers { persistedAsset }
        }
        val requestStarted = CompletableDeferred<Unit>()
        val allowResponse = CompletableDeferred<Unit>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } coAnswers {
                requestStarted.complete(Unit)
                allowResponse.await()
                TatumV4TransactionResponse(
                    result = listOf(
                        evmTransaction(
                            hash = "identity-race",
                            transactionType = "fungible",
                            amount = "1.25",
                            tokenAddress = USDC_ETHEREUM_CONTRACT
                        ).copy(transactionIndex = 1, logIndex = 2)
                    )
                )
            }
        }
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val refresh = async {
            repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                assetProviderIdentityVerifier =
                    OnChainAssetProviderIdentityVerifier(assetRepository),
                cacheWrites = cacheWrites
            ).refresh(
                asset = trackedAsset,
                forceRefresh = true
            )
        }

        requestStarted.await()
        persistedAsset = trackedAsset.copy(address = "0xdifferent-wallet")
        allowResponse.complete(Unit)
        val result = refresh.await()

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity changed")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `refresh imports every new movement across more than one history page`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val firstPage = (0 until 20).map { index ->
            evmTransaction(
                hash = "page-one-$index",
                transactionType = "fungible",
                amount = "1",
                tokenAddress = USDC_ETHEREUM_CONTRACT
            )
        }
        val secondPage = (0 until 5).map { index ->
            evmTransaction(
                hash = "page-two-$index",
                transactionType = "fungible",
                amount = "1",
                tokenAddress = USDC_ETHEREUM_CONTRACT
            )
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(
                    chain = "ethereum-mainnet",
                    addresses = "0xwallet",
                    transactionTypes = "fungible",
                    tokenAddress = USDC_ETHEREUM_CONTRACT,
                    sort = "ASC",
                    pageSize = 20,
                    offset = 0
                )
            } returns TatumV4TransactionResponse(result = firstPage)
            coEvery {
                getTransactionHistoryV4(
                    chain = "ethereum-mainnet",
                    addresses = "0xwallet",
                    transactionTypes = "fungible",
                    tokenAddress = USDC_ETHEREUM_CONTRACT,
                    sort = "ASC",
                    pageSize = 20,
                    offset = 20
                )
            } returns TatumV4TransactionResponse(result = secondPage)
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(25)
        assertThat(inserted).hasSize(25)
        coVerify {
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 0
            )
            api.getTransactionHistoryV4(
                chain = "ethereum-mainnet",
                addresses = "0xwallet",
                transactionTypes = "fungible",
                tokenAddress = USDC_ETHEREUM_CONTRACT,
                sort = "ASC",
                pageSize = 20,
                offset = 20
            )
        }
    }

    @Test
    fun `history pagination safety cap fails before partially importing a truncated history`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val requestedOffsets = mutableListOf<Int>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(
                    chain = any(),
                    addresses = any(),
                    transactionTypes = any(),
                    tokenAddress = any(),
                    sort = any(),
                    pageSize = 20,
                    offset = capture(requestedOffsets)
                )
            } answers {
                val currentPage = requestedOffsets.last() / 20
                TatumV4TransactionResponse(
                    result = (0 until 20).map { index ->
                        evmTransaction(
                            hash = "page-$currentPage-$index",
                            transactionType = "fungible",
                            amount = "1",
                            tokenAddress = USDC_ETHEREUM_CONTRACT
                        )
                    }
                )
            }
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(inserted).isEmpty()
        assertThat(requestedOffsets.size).isAtLeast(2)
        assertThat(requestedOffsets.size).isAtMost(100)
        assertThat(requestedOffsets.distinct()).hasSize(requestedOffsets.size)
        assertThat(requestedOffsets.first()).isEqualTo(0)
        requestedOffsets.zipWithNext().forEach { (previous, next) ->
            assertThat(next - previous).isEqualTo(20)
        }
    }

    @Test
    fun `ambiguous same hash legacy mapping fails before writes or cache update`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val legacy = Transaction(
            id = "legacy-row",
            assetId = "asset-1",
            amount = 9.0,
            dateMillis = 123L,
            source = TransactionSource.ON_CHAIN,
            externalId = "ambiguous-hash",
            counterparty = "0xlegacy",
            comment = "Preserve legacy",
            createdAt = 777L
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionByExternalId(any()) } answers {
                if (firstArg<String>() == "ambiguous-hash") legacy else null
            }
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == "ambiguous-hash") listOf(legacy) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "ambiguous-hash",
                        transactionType = "fungible",
                        amount = "1",
                        tokenAddress = USDC_ETHEREUM_CONTRACT,
                        counterAddress = "0xsender-a"
                    ),
                    evmTransaction(
                        hash = "ambiguous-hash",
                        transactionType = "fungible",
                        amount = "2",
                        tokenAddress = USDC_ETHEREUM_CONTRACT,
                        counterAddress = "0xsender-b"
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(updated).isEmpty()
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(legacy.externalId).isEqualTo("ambiguous-hash")
        assertThat(legacy.amount).isEqualTo(9.0)
    }

    @Test
    fun `legacy hash identity in the same asset is upgraded in place`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val existing = Transaction(
            id = "database-row-42",
            assetId = "asset-1",
            amount = 999.0,
            dateMillis = 123L,
            source = TransactionSource.ON_CHAIN,
            externalId = "legacy-hash",
            counterparty = "0xold-counterparty",
            comment = "Preserve me",
            createdAt = 777L
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionByExternalId(any()) } answers {
                if (firstArg<String>() == "legacy-hash") existing else null
            }
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == "legacy-hash") listOf(existing) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "legacy-hash",
                        transactionType = "fungible",
                        amount = "2.5",
                        tokenAddress = USDC_ETHEREUM_CONTRACT,
                        counterAddress = "0xfresh-counterparty"
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(inserted).isEmpty()
        assertThat(updated).hasSize(1)
        with(updated.single()) {
            assertThat(id).isEqualTo("database-row-42")
            assertThat(createdAt).isEqualTo(777L)
            assertThat(assetId).isEqualTo("asset-1")
            assertThat(source).isEqualTo(TransactionSource.ON_CHAIN)
            assertThat(comment).isEqualTo("Preserve me")
            assertThat(amount).isEqualTo(2.5)
            assertThat(dateMillis).isEqualTo(1_000_000L)
            assertThat(counterparty).isEqualTo("0xold-counterparty")
            assertThat(externalId).isNotEqualTo("legacy-hash")
            assertThat(externalId).contains("legacy-hash")
        }
    }

    @Test
    fun `EVM legacy hash reconciliation is case normalized and asset scoped`() = runTest {
        val updated = mutableListOf<Transaction>()
        val currentAssetLegacy = legacyTransaction(
            id = "current-uppercase-row",
            externalId = "0xABCD"
        )
        val otherAssetLegacy = legacyTransaction(
            id = "other-lowercase-row",
            externalId = "0xabcd"
        ).copy(assetId = "other-asset")
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByAssetIdOnce("asset-1") } returns
                listOf(currentAssetLegacy)
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == "0xabcd") listOf(otherAssetLegacy) else emptyList()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val movement = evmTransaction(
            hash = "0xabcd",
            transactionType = "fungible",
            amount = "2.5",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(updated).hasSize(1)
        with(updated.single()) {
            assertThat(id).isEqualTo(currentAssetLegacy.id)
            assertThat(assetId).isEqualTo("asset-1")
            assertThat(externalId).isEqualTo(canonicalExternalIdFor(movement))
            assertThat(amount).isEqualTo(2.5)
        }
        assertThat(otherAssetLegacy.externalId).isEqualTo("0xabcd")
        coVerify(exactly = 0) { transactionRepository.insertTransactions(any()) }
    }

    @Test
    fun `multiple legacy rows with one canonical movement fail without writes`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val legacyRows = listOf(
            legacyTransaction(id = "legacy-a", externalId = "duplicate-legacy-hash"),
            legacyTransaction(id = "legacy-b", externalId = "duplicate-legacy-hash")
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionByExternalId(any()) } returns null
            coEvery { getTransactionsByExternalId("duplicate-legacy-hash") } returns legacyRows
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "duplicate-legacy-hash",
                        transactionType = "fungible",
                        amount = "3",
                        tokenAddress = USDC_ETHEREUM_CONTRACT
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(updated).isEmpty()
        assertThat(inserted).isEmpty()
        assertThat(legacyRows.map { it.externalId }).containsExactly(
            "duplicate-legacy-hash",
            "duplicate-legacy-hash"
        )
    }

    @Test
    fun `global legacy hash identity from another asset does not block canonical import`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val otherAssetLegacy = Transaction(
            id = "other-database-row",
            assetId = "other-asset",
            amount = 8.0,
            dateMillis = 123L,
            source = TransactionSource.ON_CHAIN,
            externalId = "shared-legacy-hash",
            counterparty = "0xold-counterparty",
            comment = "Other asset",
            createdAt = 777L
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionByExternalId(any()) } answers {
                if (firstArg<String>() == "shared-legacy-hash") otherAssetLegacy else null
            }
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == "shared-legacy-hash") {
                    listOf(otherAssetLegacy)
                } else {
                    emptyList()
                }
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(
                    evmTransaction(
                        hash = "shared-legacy-hash",
                        transactionType = "fungible",
                        amount = "3",
                        tokenAddress = USDC_ETHEREUM_CONTRACT
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(updated).isEmpty()
        assertThat(inserted).hasSize(1)
        assertThat(inserted.single().assetId).isEqualTo("asset-1")
        assertThat(inserted.single().externalId).contains("shared-legacy-hash")
        assertThat(cacheWrites).hasSize(1)
        assertThat(otherAssetLegacy.externalId).isEqualTo("shared-legacy-hash")
        assertThat(otherAssetLegacy.amount).isEqualTo(8.0)
    }

    @Test
    fun `exact legacy and existing canonical duplicate merge into preserved legacy row`() = runTest {
        val movement = evmTransaction(
            hash = "merge-hash",
            transactionType = "fungible",
            amount = "3",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val canonicalExternalId = canonicalExternalIdFor(movement)
        val legacy = legacyTransaction(id = "preserved-legacy-row", externalId = movement.hash)
        val canonical = Transaction(
            id = "duplicate-canonical-row",
            assetId = "asset-1",
            amount = 3.0,
            dateMillis = 1_000_000L,
            source = TransactionSource.ON_CHAIN,
            externalId = canonicalExternalId,
            counterparty = "0xsender",
            comment = "Canonical duplicate",
            createdAt = 999L
        )
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val deleted = mutableListOf<String>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByExternalId(any()) } answers {
                when (firstArg<String>()) {
                    movement.hash -> listOf(legacy)
                    canonicalExternalId -> listOf(canonical)
                    else -> emptyList()
                }
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
            coEvery { deleteTransaction(any<String>()) } answers {
                deleted += firstArg<String>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(inserted).isEmpty()
        assertThat(deleted).containsExactly("duplicate-canonical-row")
        assertThat(updated).hasSize(1)
        with(updated.single()) {
            assertThat(id).isEqualTo("preserved-legacy-row")
            assertThat(createdAt).isEqualTo(legacy.createdAt)
            assertThat(comment).isEqualTo(legacy.comment)
            assertThat(externalId).isEqualTo(canonicalExternalId)
            assertThat(amount).isEqualTo(3.0)
        }
    }

    @Test
    fun `existing canonical sibling plus global legacy hash remains ambiguous and fails atomically`() = runTest {
        val movementA = evmTransaction(
            hash = "sibling-hash",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT,
            counterAddress = "0xsender-a"
        )
        val movementB = movementA.copy(amount = "2", counterAddress = "0xsender-b")
        val existingCanonical = Transaction(
            id = "existing-canonical-sibling",
            assetId = "asset-1",
            amount = 1.0,
            dateMillis = 1_000_000L,
            source = TransactionSource.ON_CHAIN,
            externalId = canonicalExternalIdFor(movementA),
            counterparty = movementA.counterAddress,
            comment = "Existing canonical",
            createdAt = 1L
        )
        val globalLegacy = legacyTransaction(id = "global-legacy", externalId = movementA.hash)
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val deleted = mutableListOf<String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByExternalId(any()) } answers {
                when (firstArg<String>()) {
                    movementA.hash -> listOf(globalLegacy)
                    existingCanonical.externalId -> listOf(existingCanonical)
                    else -> emptyList()
                }
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
            coEvery { deleteTransaction(any<String>()) } answers {
                deleted += firstArg<String>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movementA, movementB))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(inserted).isEmpty()
        assertThat(updated).isEmpty()
        assertThat(deleted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `dedicated deposit forces provider-coherent balance before auto allocation`() = runTest {
        val movement = evmTransaction(
            hash = "provider-coherent-auto-allocation",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                histories += firstArg<AllocationHistory>()
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getBalance(any(), forceRefresh = false) } returns Result.success(
                OnChainBalance(
                    assetId = "asset-1",
                    chainId = "ethereum",
                    address = "0xwallet",
                    currency = "USDC",
                    balance = 5.0,
                    fetchedAtMillis = 1L,
                    isStale = false
                )
            )
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                OnChainBalance(
                    assetId = "asset-1",
                    chainId = "ethereum",
                    address = "0xwallet",
                    currency = "USDC",
                    balance = 6.0,
                    fetchedAtMillis = 2L,
                    isStale = false
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(6.0)
        coVerify(exactly = 1) {
            onChainBalanceRepository.getFreshBalanceForPreflight(any())
        }
        coVerify(exactly = 0) { onChainBalanceRepository.getBalance(any(), any()) }
    }

    @Test
    fun `newly discovered old provider deposit remains unallocated behind newer history`() = runTest {
        val oldDeposit = evmTransaction(
            hash = "backdated-provider-deposit",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(timestamp = 1_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(oldDeposit))
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "chronology-protected-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 2_000_000L
        )
        val laterHistory = AllocationHistory(
            id = "later-allocation-evidence",
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            monthLabel = "1970-01",
            timestamp = 2_000_000L,
            createdAt = 2_000_001L
        )
        val insertedHistories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers {
                listOf(allocation)
            }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } returns flowOf(listOf(laterHistory))
            coEvery { insert(any()) } answers {
                insertedHistories += firstArg<AllocationHistory>()
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                onChainBalance(
                    balance = 6.0,
                    fetchedAtMillis = 3_000_000L
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(storedTransactions.values).hasSize(1)
        assertThat(storedTransactions.values.single().dateMillis).isEqualTo(1_000_000L)
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(insertedHistories).isEmpty()
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
    }

    @Test
    fun `provider correction reconciles dedicated allocation and history without duplication`() = runTest {
        val original = evmTransaction(
            hash = "dedicated-provider-correction",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 4, logIndex = 9, timestamp = 1_000L)
        val corrected = original.copy(amount = "2", timestamp = 2_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(original)),
                TatumV4TransactionResponse(result = listOf(corrected))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "corrected-dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { getByAssetGoalMonth(any(), any(), any()) } answers {
                val assetId = firstArg<String>()
                val goalId = secondArg<String>()
                val monthLabel = thirdArg<String>()
                histories.singleOrNull {
                    it.assetId == assetId &&
                        it.goalId == goalId &&
                        it.monthLabel == monthLabel
                }
            }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(
                    OnChainBalance(
                        assetId = "asset-1",
                        chainId = "ethereum",
                        address = "0xwallet",
                        currency = "USDC",
                        balance = 6.0,
                        fetchedAtMillis = 1L,
                        isStale = false
                    )
                ),
                Result.success(
                    OnChainBalance(
                        assetId = "asset-1",
                        chainId = "ethereum",
                        address = "0xwallet",
                        currency = "USDC",
                        balance = 7.0,
                        fetchedAtMillis = 2L,
                        isStale = false
                    )
                )
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        val originalHistoryId = histories.single().id

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)

        assertThat(storedTransactions.values.single().amount).isEqualTo(2.0)
        assertThat(storedTransactions.values.single().dateMillis).isEqualTo(2_000_000L)
        assertThat(allocation.amount).isEqualTo(7.0)
        assertThat(histories).hasSize(1)
        with(histories.single()) {
            assertThat(id).isEqualTo(originalHistoryId)
            assertThat(amount).isEqualTo(7.0)
            assertThat(timestamp).isEqualTo(2_000_000L)
            assertThat(monthLabel).isEqualTo("1970-01")
        }
    }

    @Test
    fun `provider correction selects exact auto allocation evidence among same month deposits`() = runTest {
        val firstDeposit = evmTransaction(
            hash = "same-month-first-deposit",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val secondDeposit = evmTransaction(
            hash = "same-month-corrected-deposit",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 2_000L)
        val correctedSecondDeposit = secondDeposit.copy(amount = "3", timestamp = 3_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(firstDeposit, secondDeposit)),
                TatumV4TransactionResponse(result = listOf(correctedSecondDeposit))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "same-month-dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { getByAssetGoalMonth(any(), any(), any()) } answers {
                val assetId = firstArg<String>()
                val goalId = secondArg<String>()
                val monthLabel = thirdArg<String>()
                histories.singleOrNull {
                    it.assetId == assetId &&
                        it.goalId == goalId &&
                        it.monthLabel == monthLabel
                }
            }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(
                    OnChainBalance(
                        assetId = "asset-1",
                        chainId = "ethereum",
                        address = "0xwallet",
                        currency = "USDC",
                        balance = 8.0,
                        fetchedAtMillis = 1L,
                        isStale = false
                    )
                ),
                Result.success(
                    OnChainBalance(
                        assetId = "asset-1",
                        chainId = "ethereum",
                        address = "0xwallet",
                        currency = "USDC",
                        balance = 9.0,
                        fetchedAtMillis = 2L,
                        isStale = false
                    )
                )
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(2)
        assertThat(allocation.amount).isEqualTo(8.0)
        assertThat(histories).hasSize(2)
        val originalSecondHistoryId = histories.single { it.timestamp == 2_000_000L }.id

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)

        assertThat(storedTransactions.values.single { it.amount == 3.0 }.dateMillis)
            .isEqualTo(3_000_000L)
        assertThat(allocation.amount).isEqualTo(9.0)
        assertThat(histories).hasSize(2)
        assertThat(histories.single { it.id == originalSecondHistoryId }.amount).isEqualTo(9.0)
        assertThat(histories.single { it.id == originalSecondHistoryId }.timestamp)
            .isEqualTo(3_000_000L)
        assertThat(histories.single { it.id != originalSecondHistoryId }.amount).isEqualTo(6.0)
    }

    @Test
    fun `provider correction of non-latest auto allocation evidence rolls back every write`() = runTest {
        val firstDeposit = evmTransaction(
            hash = "non-latest-first-deposit",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val secondDeposit = evmTransaction(
            hash = "non-latest-second-deposit",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 2_000L)
        val correctedFirstDeposit = firstDeposit.copy(amount = "2", timestamp = 1_500L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(firstDeposit, secondDeposit)),
                TatumV4TransactionResponse(result = listOf(correctedFirstDeposit))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "non-latest-dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(
                    onChainBalance(
                        balance = 8.0,
                        fetchedAtMillis = 1L
                    )
                ),
                Result.success(
                    onChainBalance(
                        balance = 9.0,
                        fetchedAtMillis = 2L
                    )
                )
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(2)
        val transactionSnapshot = storedTransactions.toMap()
        val allocationSnapshot = allocation
        val historySnapshot = histories.toList()
        val cacheSnapshot = cacheWrites.toList()

        val correction = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(correction.isFailure).isTrue()
        assertThat(correction.exceptionOrNull()).hasMessageThat().contains("latest")
        assertThat(storedTransactions).containsExactlyEntriesIn(transactionSnapshot)
        assertThat(allocation).isEqualTo(allocationSnapshot)
        assertThat(histories).containsExactlyElementsIn(historySnapshot).inOrder()
        assertThat(cacheWrites).containsExactlyElementsIn(cacheSnapshot).inOrder()
    }

    @Test
    fun `provider correction moving latest evidence behind another history rolls back every write`() = runTest {
        val firstDeposit = evmTransaction(
            hash = "chronology-first-deposit",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val secondDeposit = evmTransaction(
            hash = "chronology-second-deposit",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 2_000L)
        val correctedSecondDeposit = secondDeposit.copy(amount = "3", timestamp = 500L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(firstDeposit, secondDeposit)),
                TatumV4TransactionResponse(result = listOf(correctedSecondDeposit))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "chronology-dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(
                    onChainBalance(
                        balance = 8.0,
                        fetchedAtMillis = 1L
                    )
                ),
                Result.success(
                    onChainBalance(
                        balance = 9.0,
                        fetchedAtMillis = 2L
                    )
                )
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(2)
        val transactionSnapshot = storedTransactions.toMap()
        val allocationSnapshot = allocation
        val historySnapshot = histories.toList()
        val cacheSnapshot = cacheWrites.toList()

        val correction = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(correction.isFailure).isTrue()
        assertThat(correction.exceptionOrNull()).hasMessageThat().contains("chronology")
        assertThat(storedTransactions).containsExactlyEntriesIn(transactionSnapshot)
        assertThat(allocation).isEqualTo(allocationSnapshot)
        assertThat(histories).containsExactlyElementsIn(historySnapshot).inOrder()
        assertThat(cacheWrites).containsExactlyElementsIn(cacheSnapshot).inOrder()
    }

    @Test
    fun `provider correction from deposit to withdrawal removes dedicated delta`() = runTest {
        assertProviderCorrectionAcrossDepositBoundary(
            name = "incoming-to-outgoing",
            originalSubtype = "incoming",
            correctedSubtype = "outgoing",
            originalProviderBalance = 6.0,
            correctedProviderBalance = 5.0,
            expectedInitialAllocation = 6.0,
            expectedInitialHistoryCount = 1,
            expectedCorrectedAllocation = 5.0
        )
    }

    @Test
    fun `provider correction from withdrawal to deposit applies dedicated delta`() = runTest {
        assertProviderCorrectionAcrossDepositBoundary(
            name = "outgoing-to-incoming",
            originalSubtype = "outgoing",
            correctedSubtype = "incoming",
            originalProviderBalance = 5.0,
            correctedProviderBalance = 7.0,
            expectedInitialAllocation = 5.0,
            expectedInitialHistoryCount = 0,
            expectedCorrectedAllocation = 7.0
        )
    }

    private suspend fun assertProviderCorrectionAcrossDepositBoundary(
        name: String,
        originalSubtype: String,
        correctedSubtype: String,
        originalProviderBalance: Double,
        correctedProviderBalance: Double,
        expectedInitialAllocation: Double,
        expectedInitialHistoryCount: Int,
        expectedCorrectedAllocation: Double
    ) {
        val original = evmTransaction(
            hash = "deposit-boundary-$name",
            transactionType = "fungible",
            amount = if (originalSubtype == "outgoing") "-1" else "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(
            transactionSubtype = originalSubtype,
            transactionIndex = 4,
            logIndex = 9,
            timestamp = 1_000L
        )
        val corrected = original.copy(
            amount = if (correctedSubtype == "outgoing") "-2" else "2",
            transactionSubtype = correctedSubtype,
            timestamp = 2_000L
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(original)),
                TatumV4TransactionResponse(result = listOf(corrected))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "boundary-allocation-$name",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { getByAssetGoalMonth(any(), any(), any()) } answers {
                val assetId = firstArg<String>()
                val goalId = secondArg<String>()
                val monthLabel = thirdArg<String>()
                histories.singleOrNull {
                    it.assetId == assetId &&
                        it.goalId == goalId &&
                        it.monthLabel == monthLabel
                }
            }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                OnChainBalance(
                    assetId = "asset-1",
                    chainId = "ethereum",
                    address = "0xwallet",
                    currency = "USDC",
                    balance = if (originalSubtype == "incoming") {
                        originalProviderBalance
                    } else {
                        correctedProviderBalance
                    },
                    fetchedAtMillis = 2L,
                    isStale = false
                )
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()
        assertThat(allocation.amount).isEqualTo(expectedInitialAllocation)
        assertThat(histories).hasSize(expectedInitialHistoryCount)

        repository.refresh(trackedAsset, forceRefresh = true).getOrThrow()

        assertThat(allocation.amount).isEqualTo(expectedCorrectedAllocation)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(expectedCorrectedAllocation)
        assertThat(histories.single().timestamp).isEqualTo(2_000_000L)
        coVerify(exactly = 1) {
            onChainBalanceRepository.getFreshBalanceForPreflight(any())
        }
    }

    @Test
    fun `auto allocation failure rolls back imported transaction and retry applies it exactly once`() = runTest {
        val movement = evmTransaction(
            hash = "atomic-auto-allocation",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        val transactionRepository = statefulTransactionRepository(storedTransactions)
        var allocation = Allocation(
            id = "dedicated-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        var historyFailuresRemaining = 1
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                if (historyFailuresRemaining > 0) {
                    historyFailuresRemaining -= 1
                    throw IllegalStateException("history write failed")
                }
                histories += firstArg<AllocationHistory>()
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                OnChainBalance(
                    assetId = "asset-1",
                    chainId = "ethereum",
                    address = "0xwallet",
                    currency = "USDC",
                    balance = 6.0,
                    fetchedAtMillis = 1L,
                    isStale = false
                )
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")

        val firstRefresh = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(firstRefresh.isFailure).isTrue()
        assertThat(firstRefresh.exceptionOrNull()).hasMessageThat().contains("history write failed")
        assertThat(storedTransactions).isEmpty()
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(histories).isEmpty()
        assertThat(cacheWrites).isEmpty()

        val retry = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(retry.getOrThrow()).isEqualTo(1)
        assertThat(storedTransactions).hasSize(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(6.0)
        assertThat(cacheWrites).hasSize(1)
        coVerify(exactly = 2) {
            onChainBalanceRepository.getFreshBalanceForPreflight(any())
        }
    }

    @Test
    fun `dedicated deposit balance failure aborts before transaction or cache writes`() = runTest {
        val movement = evmTransaction(
            hash = "balance-preflight-failure",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } returns listOf(
                Allocation(
                    id = "dedicated-allocation",
                    assetId = "asset-1",
                    goalId = "goal-1",
                    amount = 5.0,
                    createdAt = 1L,
                    lastModifiedAt = 1L
                )
            )
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.failure(
                IllegalStateException("balance unavailable")
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            allocationRepository = allocationRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(AssetBalanceUnavailableException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("unavailable")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        coVerify(exactly = 1) {
            onChainBalanceRepository.getFreshBalanceForPreflight(any())
        }
    }

    @Test
    fun `dedicated deposit stale balance aborts before transaction or allocation writes`() = runTest {
        val movement = evmTransaction(
            hash = "stale-balance-preflight",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } returns listOf(
                Allocation(
                    id = "dedicated-allocation",
                    assetId = "asset-1",
                    goalId = "goal-1",
                    amount = 5.0,
                    createdAt = 1L,
                    lastModifiedAt = 1L
                )
            )
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                OnChainBalance(
                    assetId = "asset-1",
                    chainId = "ethereum",
                    address = "0xwallet",
                    currency = "USDC",
                    balance = 6.0,
                    fetchedAtMillis = System.currentTimeMillis(),
                    isStale = true
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            allocationRepository = allocationRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("stale")
        assertThat(inserted).isEmpty()
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
        assertThat(cacheWrites).isEmpty()
        coVerify(exactly = 1) {
            onChainBalanceRepository.getFreshBalanceForPreflight(any())
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("utxoChains")
    fun `UTXO refresh imports all pages with numeric offsets`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val inserted = mutableListOf<Transaction>()
        val requestedOffsets = mutableListOf<Int>()
        val firstPage = (0 until 20).map { index ->
            utxoTransaction(hash = "$chainId-page-one-$index", trackedAddress = "wallet")
        }
        val secondPage = (0 until 5).map { index ->
            utxoTransaction(hash = "$chainId-page-two-$index", trackedAddress = "wallet")
        }
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                when (offset) {
                    0 -> firstPage
                    20 -> secondPage
                    else -> error("Unexpected offset $offset")
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(25)
        assertThat(inserted).hasSize(25)
        assertThat(requestedOffsets).containsExactly(0, 20).inOrder()
        verifyUtxoRequests(api = api, chainId = chainId, expectedCalls = 2)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("utxoChains")
    fun `identical UTXO page overlap is imported once`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val inserted = mutableListOf<Transaction>()
        val requestedOffsets = mutableListOf<Int>()
        val firstPage = (0 until 20).map { index ->
            utxoTransaction(hash = "$chainId-overlap-$index", trackedAddress = "wallet")
        }
        val secondPage = listOf(firstPage.last()) + (20 until 24).map { index ->
            utxoTransaction(hash = "$chainId-overlap-$index", trackedAddress = "wallet")
        }
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                when (offset) {
                    0 -> firstPage
                    20 -> secondPage
                    else -> error("Unexpected offset $offset")
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(24)
        assertThat(inserted).hasSize(24)
        assertThat(inserted.mapNotNull { it.externalId }.distinct()).hasSize(24)
        assertThat(requestedOffsets).containsExactly(0, 20).inOrder()
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("utxoChains")
    fun `conflicting UTXO page overlap fails before writes or cache update`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val requestedOffsets = mutableListOf<Int>()
        val firstPage = (0 until 20).map { index ->
            utxoTransaction(hash = "$chainId-conflict-$index", trackedAddress = "wallet")
        }
        val conflictingDuplicate = firstPage.last().copy(
            outputs = listOf(
                TatumUTXOOutput(
                    valueNumber = 200_000_000.0,
                    address = "wallet"
                )
            )
        )
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                when (offset) {
                    0 -> firstPage
                    20 -> listOf(conflictingDuplicate)
                    else -> error("Unexpected offset $offset")
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("changed between pages")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(requestedOffsets).containsExactly(0, 20).inOrder()
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("utxoChains")
    fun `UTXO pagination cap fails before writes or cache update`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String
    ) = runTest {
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val requestedOffsets = mutableListOf<Int>()
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                (0 until 20).map { index ->
                    utxoTransaction(hash = "$chainId-$offset-$index", trackedAddress = "wallet")
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(requestedOffsets)
            .containsExactlyElementsIn((0 until 20).map { pageIndex -> pageIndex * 20 })
            .inOrder()
        verifyUtxoRequests(api = api, chainId = chainId, expectedCalls = 20)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("rawUtxoChains")
    fun `raw outgoing transaction on a later page resolves unique prevouts and imports exact net once`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String,
        tatumChain: String
    ) = runTest {
        val parentHash = "$chainId-parent"
        val rawHash = "$chainId-raw-outgoing"
        val rawOutgoing = rawOutgoingTransaction(
            chainId = chainId,
            hash = rawHash,
            parentHashes = listOf(parentHash, parentHash)
        )
        val lookupRequests = mutableListOf<Pair<String, String>>()
        val requestedOffsets = mutableListOf<Int>()
        val inserted = mutableListOf<Transaction>()
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                when (offset) {
                    0 -> (0 until 20).map { index ->
                        utxoTransaction("$chainId-enriched-$index", "wallet")
                    }
                    20 -> listOf(rawOutgoing)
                    else -> error("Unexpected offset $offset")
                }
            },
            lookupRequests = lookupRequests,
            previousTransactionForLookup = { requestedChain, requestedHash ->
                assertThat(requestedChain).isEqualTo(tatumChain)
                assertThat(requestedHash).isEqualTo(parentHash)
                previousTransaction(
                    chainId = chainId,
                    hash = requestedHash,
                    outputs = listOf(0.4 to "wallet", 0.6 to "wallet")
                )
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(21)
        assertThat(requestedOffsets).containsExactly(0, 20).inOrder()
        assertThat(lookupRequests).containsExactly(tatumChain to parentHash)
        val importedRaw = inserted.single { it.externalId?.contains(rawHash) == true }
        assertThat(importedRaw.amount).isWithin(0.000000001).of(-0.7)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("rawUtxoChains")
    fun `prevout lookup failure after a valid page fails before transaction or cache writes`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String,
        tatumChain: String
    ) = runTest {
        val parentHash = "$chainId-unavailable-parent"
        val lookupRequests = mutableListOf<Pair<String, String>>()
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                when (offset) {
                    0 -> (0 until 20).map { index ->
                        utxoTransaction("$chainId-before-failure-$index", "wallet")
                    }
                    20 -> listOf(
                        rawOutgoingTransaction(
                            chainId = chainId,
                            hash = "$chainId-lookup-failure",
                            parentHashes = listOf(parentHash)
                        )
                    )
                    else -> error("Unexpected offset $offset")
                }
            },
            lookupRequests = lookupRequests,
            previousTransactionForLookup = { _, _ ->
                throw IllegalStateException("Previous transaction unavailable")
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("Previous transaction unavailable")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(lookupRequests).containsExactly(tatumChain to parentHash)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("rawUtxoChains")
    fun `prevout lookup cap fails before transaction or cache writes`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String,
        tatumChain: String
    ) = runTest {
        val parentHashes = (0..MAX_UTXO_PREVOUT_LOOKUPS).map { index ->
            "$chainId-parent-$index"
        }
        val lookupRequests = mutableListOf<Pair<String, String>>()
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                when (offset) {
                    0 -> (0 until 20).map { index ->
                        utxoTransaction("$chainId-before-cap-$index", "wallet")
                    }
                    20 -> listOf(
                        rawOutgoingTransaction(
                            chainId = chainId,
                            hash = "$chainId-over-cap",
                            parentHashes = parentHashes
                        )
                    )
                    else -> error("Unexpected offset $offset")
                }
            },
            lookupRequests = lookupRequests,
            previousTransactionForLookup = { _, requestedHash ->
                previousTransaction(
                    chainId = chainId,
                    hash = requestedHash,
                    outputs = listOf(1.0 to "wallet")
                )
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("prevout lookup limit")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(lookupRequests).hasSize(MAX_UTXO_PREVOUT_LOOKUPS)
        assertThat(lookupRequests.map { it.first }.distinct()).containsExactly(tatumChain)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("rawUtxoChains")
    fun `raw coinbase input imports its output without a prevout lookup`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String,
        @Suppress("UNUSED_PARAMETER") tatumChain: String
    ) = runTest {
        val lookupRequests = mutableListOf<Pair<String, String>>()
        val inserted = mutableListOf<Transaction>()
        val coinbase = rawCoinbaseTransaction(
            chainId = chainId,
            hash = "$chainId-coinbase",
            trackedAddress = "wallet",
            amount = 6.25
        )
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset -> if (offset == 0) listOf(coinbase) else emptyList() },
            lookupRequests = lookupRequests,
            previousTransactionForLookup = { _, _ ->
                error("Coinbase must not resolve a previous transaction")
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "asset-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted.single().amount).isWithin(0.000000001).of(6.25)
        assertThat(lookupRequests).isEmpty()
    }

    @Test
    fun `normalized coinbase flag imports its Bitcoin output without a prevout lookup`() = runTest {
        val lookupRequests = mutableListOf<Pair<String, String>>()
        val inserted = mutableListOf<Transaction>()
        val coinbase = TatumUTXOTransaction(
            hash = "bitcoin-normalized-coinbase",
            time = 1_000L,
            inputs = listOf(
                TatumUTXOInput(
                    coin = TatumUTXOCoin(coinbase = true)
                )
            ),
            outputs = listOf(
                TatumUTXOOutput(
                    valueNumber = 625_000_000.0,
                    address = "wallet"
                )
            )
        )
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset -> if (offset == 0) listOf(coinbase) else emptyList() },
            lookupRequests = lookupRequests,
            previousTransactionForLookup = { _, _ ->
                error("Coinbase must not resolve a previous transaction")
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "asset-bitcoin",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted.single().amount).isWithin(0.000000001).of(6.25)
        assertThat(lookupRequests).isEmpty()
    }

    @Test
    fun `same UTXO hash for two tracked assets persists two scoped movements and retries deterministically`() = runTest {
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val transactionRepository = statefulTransactionRepository(storedByExternalId)
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions(any(), pageSize = 20, offset = 0)
            } answers {
                listOf(
                    utxoTransaction(
                        hash = "shared-utxo-hash",
                        trackedAddress = firstArg()
                    )
                )
            }
        }
        val repository = repository(api = api, transactionRepository = transactionRepository)
        val firstAsset = asset(
            id = "btc-wallet-a",
            currency = "BTC",
            address = "wallet-a",
            chainId = "bitcoin"
        )
        val secondAsset = asset(
            id = "btc-wallet-b",
            currency = "BTC",
            address = "wallet-b",
            chainId = "bitcoin"
        )

        val firstImport = repository.refresh(firstAsset, limit = 20, forceRefresh = true)
        val secondImport = repository.refresh(secondAsset, limit = 20, forceRefresh = true)
        val firstRetry = repository.refresh(firstAsset, limit = 20, forceRefresh = true)
        val secondRetry = repository.refresh(secondAsset, limit = 20, forceRefresh = true)

        assertThat(firstImport.getOrThrow()).isEqualTo(1)
        assertThat(secondImport.getOrThrow()).isEqualTo(1)
        assertThat(firstRetry.getOrThrow()).isEqualTo(0)
        assertThat(secondRetry.getOrThrow()).isEqualTo(0)
        assertThat(storedByExternalId.values.map { it.assetId })
            .containsExactly("btc-wallet-a", "btc-wallet-b")
        assertThat(storedByExternalId.keys).hasSize(2)
        assertThat(storedByExternalId.keys.all { it.contains("shared-utxo-hash") }).isTrue()
    }

    @Test
    fun `raw UTXO legacy hash from another asset does not block scoped import`() = runTest {
        val rawHash = "shared-raw-utxo-hash"
        val otherAssetLegacy = legacyTransaction(
            id = "other-utxo-row",
            externalId = rawHash
        ).copy(assetId = "other-asset")
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == rawHash) listOf(otherAssetLegacy) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                if (offset == 0) {
                    listOf(utxoTransaction(hash = rawHash, trackedAddress = "wallet"))
                } else {
                    emptyList()
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(
                id = "current-asset",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(updated).isEmpty()
        assertThat(inserted).hasSize(1)
        assertThat(inserted.single().assetId).isEqualTo("current-asset")
        assertThat(inserted.single().externalId)
            .isEqualTo("utxo:current-asset:$rawHash")
        assertThat(otherAssetLegacy.externalId).isEqualTo(rawHash)
        assertThat(otherAssetLegacy.assetId).isEqualTo("other-asset")
    }

    @Test
    fun `UTXO provider correction updates amount and time on the scoped row`() = runTest {
        val trackedAsset = asset(
            id = "btc-correction",
            currency = "BTC",
            address = "wallet",
            chainId = "bitcoin"
        )
        val original = utxoTransaction("utxo-correction", trackedAsset.address!!)
        val corrected = original.copy(
            time = 2_000L,
            outputs = listOf(
                TatumUTXOOutput(
                    valueNumber = 200_000_000.0,
                    address = trackedAsset.address
                )
            )
        )
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions(trackedAsset.address, pageSize = 20, offset = 0)
            } returnsMany listOf(listOf(original), listOf(corrected))
        }
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        val originalRowId = storedByExternalId.values.single().id
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)

        assertThat(storedByExternalId.values).hasSize(1)
        with(storedByExternalId.values.single()) {
            assertThat(id).isEqualTo(originalRowId)
            assertThat(amount).isEqualTo(2.0)
            assertThat(dateMillis).isEqualTo(2_000_000L)
        }
    }

    @Test
    fun `Bitcoin Base58 address comparison preserves case`() = runTest {
        val trackedAddress = "1AbCWallet"
        val externalAddress = "1aBcWallet"
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions(trackedAddress, pageSize = 20, offset = 0)
            } returns listOf(
                TatumUTXOTransaction(
                    hash = "base58-case-hash",
                    time = 1_000L,
                    inputs = listOf(
                        TatumUTXOInput(
                            coin = TatumUTXOCoin(
                                valueNumber = 100_000_000.0,
                                address = externalAddress
                            )
                        )
                    ),
                    outputs = listOf(
                        TatumUTXOOutput(
                            valueNumber = 100_000_000.0,
                            address = trackedAddress
                        )
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "case-sensitive-btc",
                currency = "BTC",
                address = trackedAddress,
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted.single().amount).isEqualTo(1.0)
        assertThat(inserted.single().counterparty).isEqualTo(externalAddress)
    }

    @Test
    fun `Bitcoin Bech32 comparison accepts equivalent all-uppercase and all-lowercase forms`() = runTest {
        val trackedAddress = "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"
        val providerAddress = trackedAddress.lowercase()
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions(trackedAddress, pageSize = 20, offset = 0)
            } returns listOf(
                TatumUTXOTransaction(
                    hash = "bech32-case-hash",
                    time = 1_000L,
                    inputs = listOf(
                        TatumUTXOInput(
                            coin = TatumUTXOCoin(
                                valueNumber = 100_000_000.0,
                                address = "1ExternalWallet"
                            )
                        )
                    ),
                    outputs = listOf(
                        TatumUTXOOutput(
                            valueNumber = 100_000_000.0,
                            address = providerAddress
                        )
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "bech32-case-btc",
                currency = "BTC",
                address = trackedAddress,
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted.single().amount).isEqualTo(1.0)
    }

    @Test
    fun `Bitcoin Cash comparison accepts an omitted mainnet CashAddr prefix`() = runTest {
        val trackedAddress = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        val providerAddress = "bitcoincash:$trackedAddress"
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinCashTransactions(trackedAddress, pageSize = 20, offset = 0)
            } returns listOf(
                TatumUTXOTransaction(
                    hash = "cashaddr-prefix-hash",
                    time = 1_000L,
                    inputs = listOf(
                        TatumUTXOInput(
                            coin = TatumUTXOCoin(
                                valueNumber = 1.25,
                                address = "qqs3kax2g6r0s8ha54jpwelusnh3dkh7pvu23rzrru"
                            )
                        )
                    ),
                    outputs = listOf(
                        TatumUTXOOutput(
                            valueNumber = 1.25,
                            address = providerAddress
                        )
                    )
                )
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "cashaddr-prefix-bch",
                currency = "BCH",
                address = trackedAddress,
                chainId = "bitcoin-cash"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted.single().amount).isEqualTo(1.25)
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("officialUtxoV3Fixtures")
    fun `official UTXO V3 payload decodes its nested shape and imports the signed movement`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        currency: String,
        payload: String,
        expectedHash: String,
        expectedAmount: Double,
        usesLegacyVinVout: Boolean
    ) = runTest {
        val decoded = Json { ignoreUnknownKeys = true }
            .decodeFromString<TatumUTXOTransaction>(payload)

        assertThat(decoded.resolvedHash).isEqualTo(expectedHash)
        assertThat(decoded.resolvedOutputs).hasSize(1)
        if (usesLegacyVinVout) {
            assertThat(decoded.vin).isNotEmpty()
            assertThat(decoded.vout).isNotEmpty()
        } else {
            assertThat(decoded.inputs?.single()?.coin).isNotNull()
            assertThat(decoded.outputs).isNotEmpty()
        }

        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                if (offset == 0) listOf(decoded) else emptyList()
            },
            previousTransactionForLookup = { _, requestedHash ->
                val referencedIndex = decoded.vin?.single()?.vout ?: 0
                previousTransaction(
                    chainId = chainId,
                    hash = requestedHash,
                    outputs = (0..referencedIndex).map { index ->
                        1.0 to if (index == referencedIndex) "external-sender" else "other"
                    }
                )
            }
        )
        val inserted = mutableListOf<Transaction>()

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "fixture-$chainId",
                currency = currency,
                address = "wallet",
                chainId = chainId
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(1)
        assertThat(inserted).hasSize(1)
        assertThat(inserted.single().amount).isWithin(0.000000001).of(expectedAmount)
        assertThat(inserted.single().externalId).contains(expectedHash)
    }

    @Test
    fun `Bitcoin Cash txid is used for exact legacy lookup and metadata upgrade`() = runTest {
        val rawHash = "bch-legacy-hash"
        val existing = legacyTransaction(id = "legacy-database-row", externalId = rawHash)
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val lookups = mutableListOf<String>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByExternalId(any()) } answers {
                firstArg<String>().also(lookups::add)
                if (firstArg<String>() == rawHash) listOf(existing) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<TatumUTXOTransaction>(
            """
                {
                  "txid": "$rawHash",
                  "time": 1000,
                  "vin": [{"txid": "previous-hash", "vout": 0}],
                  "vout": [
                    {
                      "value": "1.25",
                      "scriptPubKey": {"addresses": ["secondary", "wallet"]}
                    }
                  ]
                }
            """.trimIndent()
        )
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset -> if (offset == 0) listOf(decoded) else emptyList() },
            previousTransactionForLookup = { _, requestedHash ->
                previousTransaction(
                    chainId = "bitcoin-cash",
                    hash = requestedHash,
                    outputs = listOf(0.5 to "external-sender")
                )
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(
                currency = "BCH",
                chainId = "bitcoin-cash",
                address = "wallet"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(inserted).isEmpty()
        assertThat(updated).hasSize(1)
        assertThat(updated.single().id).isEqualTo("legacy-database-row")
        assertThat(updated.single().externalId).contains(rawHash)
        assertThat(updated.single().amount).isWithin(0.000000001).of(1.25)
        assertThat(lookups).contains(rawHash)
    }

    @Test
    fun `UTXO witness hash legacy row migrates to canonical txid without duplication`() = runTest {
        val witnessHash = "legacy-witness-hash"
        val transactionId = "canonical-txid"
        val existing = legacyTransaction(id = "legacy-database-row", externalId = witnessHash)
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val lookups = mutableListOf<String>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByExternalId(any()) } answers {
                firstArg<String>().also(lookups::add)
                if (firstArg<String>() == witnessHash) listOf(existing) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
        }
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<TatumUTXOTransaction>(
            """
                {
                  "hash": "$witnessHash",
                  "txid": "$transactionId",
                  "time": 1000,
                  "vin": [{"txid": "previous-hash", "vout": 0}],
                  "vout": [
                    {
                      "value": "1.25",
                      "scriptPubKey": {"addresses": ["secondary", "wallet"]}
                    }
                  ]
                }
            """.trimIndent()
        )
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset -> if (offset == 0) listOf(decoded) else emptyList() },
            previousTransactionForLookup = { _, requestedHash ->
                previousTransaction(
                    chainId = "bitcoin-cash",
                    hash = requestedHash,
                    outputs = listOf(0.5 to "external-sender")
                )
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository
        ).refresh(
            asset = asset(
                currency = "BCH",
                chainId = "bitcoin-cash",
                address = "wallet"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(inserted).isEmpty()
        assertThat(updated).hasSize(1)
        assertThat(updated.single().id).isEqualTo("legacy-database-row")
        assertThat(updated.single().externalId).contains(transactionId)
        assertThat(updated.single().externalId).contains(witnessHash)
        assertThat(updated.single().amount).isWithin(0.000000001).of(1.25)
        assertThat(lookups).contains(witnessHash)
    }

    @Test
    fun `UTXO durable aliases prevent weak response from duplicating an enriched txid`() = runTest {
        val witnessHash = "durable-witness-hash"
        val transactionId = "durable-canonical-txid"
        val weak = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
        val enriched = weak.copy(txid = transactionId)
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returnsMany listOf(listOf(weak), listOf(enriched), listOf(weak))
        }
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(
            id = "durable-alias-asset",
            currency = "BTC",
            address = "wallet",
            chainId = "bitcoin"
        )

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        val originalRowId = storedByExternalId.values.single().id
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        val strengthenedExternalId = checkNotNull(storedByExternalId.values.single().externalId)
        assertThat(strengthenedExternalId).contains(transactionId)
        assertThat(strengthenedExternalId).contains(witnessHash)

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        assertThat(storedByExternalId.values).hasSize(1)
        assertThat(storedByExternalId.values.single().id).isEqualTo(originalRowId)
        assertThat(storedByExternalId.values.single().externalId)
            .isEqualTo(strengthenedExternalId)
    }

    @Test
    fun `UTXO shared alias cannot replace one durable canonical txid with another`() = runTest {
        val witnessHash = "cross-refresh-shared-witness"
        val firstCanonical = "first-canonical-txid"
        val conflictingCanonical = "second-canonical-txid"
        val first = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
            .copy(txid = firstCanonical)
        val conflicting = first.copy(txid = conflictingCanonical)
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returnsMany listOf(listOf(first), listOf(conflicting))
        }
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId),
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(
            id = "cross-refresh-alias-asset",
            currency = "BTC",
            address = "wallet",
            chainId = "bitcoin"
        )
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        val durableRow = storedByExternalId.values.single()
        cacheWrites.clear()

        val result = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("canonical txids")
        assertThat(storedByExternalId.values).containsExactly(durableRow)
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `UTXO page overlap collapses a weak hash into its enriched txid`() = runTest {
        val witnessHash = "overlap-witness-hash"
        val transactionId = "overlap-canonical-txid"
        val weak = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
        val enriched = weak.copy(txid = transactionId)
        val firstPage = (0 until 19).map { index ->
            utxoTransaction(hash = "unrelated-$index", trackedAddress = "wallet")
        } + weak
        val requestedOffsets = mutableListOf<Int>()
        val api = pagedUtxoApi(
            requestedOffsets = requestedOffsets,
            pageForOffset = { offset ->
                when (offset) {
                    0 -> firstPage
                    20 -> listOf(enriched)
                    else -> error("Unexpected offset $offset")
                }
            }
        )
        val inserted = mutableListOf<Transaction>()

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(
                id = "page-overlap-asset",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(20)
        assertThat(inserted).hasSize(20)
        val enrichedRow = inserted.single {
            it.externalId?.contains(transactionId) == true
        }
        assertThat(enrichedRow.externalId).contains(witnessHash)
        assertThat(requestedOffsets).containsExactly(0, 20).inOrder()
    }

    @Test
    fun `fresh UTXO batch with two canonical txids sharing one alias fails before writes`() = runTest {
        val sharedWitnessHash = "shared-witness-hash"
        val first = utxoTransaction(hash = sharedWitnessHash, trackedAddress = "wallet")
            .copy(txid = "canonical-txid-a")
        val second = first.copy(txid = "canonical-txid-b")
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                if (offset == 0) listOf(first, second) else emptyList()
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "shared-alias-asset",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            limit = 20,
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("alias")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `blank UTXO provider hashes fail before writes`() = runTest {
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                if (offset == 0) {
                    listOf(
                        utxoTransaction(hash = "   ", trackedAddress = "wallet")
                            .copy(txid = " ")
                    )
                } else {
                    emptyList()
                }
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "blank-hash-asset",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("without a hash")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `negative provider event indexes fail before writes`() = runTest {
        val invalidMovements = listOf(
            evmTransaction(
                hash = "negative-transaction-index",
                transactionType = "fungible",
                amount = "1",
                tokenAddress = USDC_ETHEREUM_CONTRACT
            ).copy(transactionIndex = -1),
            evmTransaction(
                hash = "negative-log-index",
                transactionType = "fungible",
                amount = "1",
                tokenAddress = USDC_ETHEREUM_CONTRACT
            ).copy(logIndex = -1)
        )

        invalidMovements.forEach { invalidMovement ->
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(invalidMovement))
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(currency = "USDC", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains("non-negative")
            assertThat(inserted).isEmpty()
            assertThat(cacheWrites).isEmpty()
        }
    }

    @Test
    fun `blank EVM provider hash fails before writes`() = runTest {
        val movement = evmTransaction(
            hash = " ",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("non-blank")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `EVM token batch preserves provider signs and ignores zero and unrelated rows`() = runTest {
        val incoming = evmTransaction(
            hash = "signed-token-incoming",
            transactionType = "fungible",
            amount = "1.25",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1)
        val outgoing = evmTransaction(
            hash = "signed-token-outgoing",
            transactionType = "fungible",
            amount = "-2.5",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(
            transactionSubtype = "outgoing",
            transactionIndex = 2,
            logIndex = 2,
            gasUsed = "not-applicable-to-token",
            gasPrice = "not-applicable-to-token"
        )
        val zeroTransfer = evmTransaction(
            hash = "ignored-token-zero-transfer",
            transactionType = "fungible",
            amount = "0",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(
            hash = " ",
            timestamp = null,
            transactionSubtype = "zero-transfer",
            transactionIndex = 3,
            logIndex = 3
        )
        val unrelated = evmTransaction(
            hash = " ",
            transactionType = "fungible",
            amount = "NaN",
            tokenAddress = "0x0000000000000000000000000000000000000001"
        ).copy(timestamp = null)
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(
                result = listOf(incoming, outgoing, zeroTransfer, unrelated)
            )
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(2)
        assertThat(inserted.map { it.amount }).containsExactly(1.25, -2.5)
    }

    @Test
    fun `EVM subtype sign mismatch fails the whole routed batch before writes`() = runTest {
        val valid = evmTransaction(
            hash = "sign-consistent-incoming",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val invalid = evmTransaction(
            hash = "sign-inconsistent-outgoing",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionSubtype = "outgoing")
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(valid, invalid))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("outgoing")
        assertThat(inserted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `official native history shape is enriched once per hash and charges receipt gas once`() =
        runTest {
        val history = Json.decodeFromString<TatumV4TransactionResponse>(
            """
            {
              "result": [
                {
                  "hash": "native-incoming-no-gas-charge",
                  "chain": "ethereum-mainnet",
                  "address": "0xwallet",
                  "transactionType": "native",
                  "transactionSubtype": "incoming",
                  "amount": "1",
                  "timestamp": 1000,
                  "transactionIndex": 1,
                  "counterAddress": "0xsender"
                },
                {
                  "hash": "same-native-sender-hash",
                  "chain": "ethereum-mainnet",
                  "address": "0xwallet",
                  "transactionType": "native",
                  "transactionSubtype": "outgoing",
                  "amount": "-2",
                  "timestamp": 1000,
                  "transactionIndex": 2,
                  "counterAddress": "0xrecipient"
                },
                {
                  "hash": "same-native-sender-hash",
                  "chain": "ethereum-mainnet",
                  "address": "0xwallet",
                  "transactionType": "native",
                  "transactionSubtype": "zero-transfer",
                  "amount": "0",
                  "timestamp": 1000,
                  "transactionIndex": 3,
                  "counterAddress": "0xcontract"
                }
              ]
            }
            """.trimIndent()
        )
        val inserted = mutableListOf<Transaction>()
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns history
            coEvery {
                getEvmTransactionReceipt(any(), any())
            } returns successfulEvmDetail(hash = "same-native-sender-hash")
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted)
        ).refresh(
            asset = asset(currency = "ETH", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(3)
        assertThat(inserted.single { it.externalId?.contains("native-incoming") == true }.amount)
            .isEqualTo(1.0)
        assertThat(
            inserted
                .filter { it.externalId?.contains("same-native-sender-hash") == true }
                .sumOf(Transaction::amount)
        )
            .isWithin(1e-12)
            .of(-2.00042)
        assertThat(
            inserted.single {
                it.externalId?.contains("same-native-sender-hash") == true &&
                    it.externalId?.endsWith(":2:no-log-index") == true
            }.amount
        ).isEqualTo(-2.0)
        assertThat(
            inserted.single {
                it.externalId?.contains("same-native-sender-hash") == true &&
                    it.externalId?.endsWith(":3:no-log-index") == true
            }.amount
        ).isWithin(1e-12).of(-0.00042)
        coVerify(exactly = 1) {
            api.getEvmTransactionReceipt(
                chain = "ethereum-mainnet",
                request = TatumEvmJsonRpcRequest(
                    params = listOf("same-native-sender-hash")
                )
            )
        }
    }

    @Test
    fun `EVM receipt accepts documented success and integer quantity wire shapes`() = runTest {
        val outgoing = evmTransaction(
            hash = "documented-receipt-shape",
            transactionType = "native",
            amount = "-1",
            tokenAddress = null
        ).copy(
            transactionSubtype = "outgoing",
            from = null
        )
        val detailFixtures = listOf(
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "documented-receipt-shape",
                "from": "0xwallet",
                "status": true,
                "gasUsed": 21000,
                "effectiveGasPrice": "20000000000"
              }
            }
            """,
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "documented-receipt-shape",
                "from": "0xwallet",
                "status": 1,
                "gasUsed": "0x5208",
                "effectiveGasPrice": "0x4a817c800"
              }
            }
            """,
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "documented-receipt-shape",
                "from": "0xwallet",
                "status": "1",
                "gasUsed": "21000",
                "effectiveGasPrice": 20000000000
              }
            }
            """,
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "documented-receipt-shape",
                "from": "0xwallet",
                "status": "0x1",
                "gasUsed": "0x5208",
                "effectiveGasPrice": "0x4a817c800"
              }
            }
            """
        )

        detailFixtures.forEach { fixture ->
            val inserted = mutableListOf<Transaction>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(outgoing))
                coEvery {
                    getEvmTransactionReceipt(any(), any())
                } returns Json.decodeFromString<TatumEvmJsonRpcReceiptResponse>(
                    fixture.trimIndent()
                )
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted)
            ).refresh(
                asset = asset(currency = "ETH", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.getOrThrow()).isEqualTo(1)
            assertThat(inserted.single().amount).isWithin(1e-12).of(-1.00042)
        }
    }

    @Test
    fun `failed zero transfer receipt persists sender gas exactly once`() = runTest {
        val failedZeroTransfer = evmTransaction(
            hash = "failed-zero-transfer",
            transactionType = "native",
            amount = "0",
            tokenAddress = null
        ).copy(
            transactionSubtype = "zero-transfer",
            transactionIndex = 7,
            from = null
        )
        val failedReceiptFixtures = listOf(
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "failed-zero-transfer",
                "from": "0xwallet",
                "status": "0x0",
                "gasUsed": "0x5208",
                "effectiveGasPrice": "0x4a817c800"
              }
            }
            """ to 0.00042,
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "failed-zero-transfer",
                "from": "0xwallet",
                "status": false,
                "gasUsed": 21000,
                "effectiveGasPrice": 20000000000
              }
            }
            """ to 0.00042,
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "transactionHash": "failed-zero-transfer",
                "from": "0xwallet",
                "status": "0x0",
                "gasUsed": "0x1",
                "effectiveGasPrice": "0x1"
              }
            }
            """ to 0.000000000000000001
        )

        failedReceiptFixtures.forEach { (fixture, expectedFee) ->
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(failedZeroTransfer))
                coEvery {
                    getEvmTransactionReceipt(any(), any())
                } returns Json.decodeFromString<TatumEvmJsonRpcReceiptResponse>(
                    fixture.trimIndent()
                )
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(currency = "ETH", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.getOrThrow()).isEqualTo(1)
            assertThat(inserted.single().amount).isWithin(1e-24).of(-expectedFee)
            assertThat(cacheWrites).isNotEmpty()
            coVerify(exactly = 1) {
                api.getEvmTransactionReceipt(
                    chain = "ethereum-mainnet",
                    request = TatumEvmJsonRpcRequest(
                        params = listOf("failed-zero-transfer")
                    )
                )
            }
        }
    }

    @Test
    fun `malformed or mismatched native receipt fails atomically`() = runTest {
        val valid = evmTransaction(
            hash = "native-valid-incoming-before-gas-failure",
            transactionType = "native",
            amount = "1",
            tokenAddress = null
        )
        val invalid = evmTransaction(
            hash = "native-invalid-gas",
            transactionType = "native",
            amount = "-1",
            tokenAddress = null
        ).copy(
            transactionSubtype = "outgoing",
            from = null
        )
        val invalidDetails = listOf(
            "hash" to successfulEvmDetail(hash = "different-hash"),
            "envelope" to successfulEvmDetail(hash = "native-invalid-gas").copy(id = 2),
            "sender" to successfulEvmDetail(
                hash = "native-invalid-gas",
                from = "0xdifferent"
            ),
            "Failed" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = JsonPrimitive("0x0")
            ),
            "Failed" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = JsonPrimitive(false)
            ),
            "Failed" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = JsonPrimitive(0)
            ),
            "Failed" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = JsonPrimitive("0")
            ),
            "status" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = null
            ),
            "status" to successfulEvmDetail(
                hash = "native-invalid-gas",
                status = JsonPrimitive("pending")
            ),
            "gas" to successfulEvmDetail(
                hash = "native-invalid-gas",
                effectiveGasPrice = JsonPrimitive("not-a-number")
            )
        )

        invalidDetails.forEach { (expectedMessage, detail) ->
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(valid, invalid))
                coEvery {
                    getEvmTransactionReceipt(any(), any())
                } returns detail
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(currency = "ETH", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains(expectedMessage)
            assertThat(inserted).isEmpty()
            assertThat(cacheWrites).isEmpty()
        }
    }

    @Test
    fun `missing or unknown routed EVM subtype fails before writes and cache`() = runTest {
        listOf(null, "provider-added-subtype").forEach { invalidSubtype ->
            val invalid = evmTransaction(
                hash = "invalid-subtype",
                transactionType = "fungible",
                amount = "1",
                tokenAddress = USDC_ETHEREUM_CONTRACT
            ).copy(transactionSubtype = invalidSubtype)
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(invalid))
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(currency = "USDC", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains("subtype")
            assertThat(inserted).isEmpty()
            assertThat(cacheWrites).isEmpty()
        }
    }

    @Test
    fun `missing invalid or nonfinite EVM authoritative fields fail before writes`() = runTest {
        val valid = evmTransaction(
            hash = "invalid-authoritative-field",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        )
        val invalidMovements = listOf(
            valid.copy(timestamp = null),
            valid.copy(timestamp = 0L),
            valid.copy(timestamp = -1L),
            valid.copy(timestamp = Long.MAX_VALUE),
            valid.copy(amount = "NaN"),
            valid.copy(amount = "Infinity"),
            valid.copy(amount = "0"),
            valid.copy(amount = "-1")
        )

        invalidMovements.forEach { invalidMovement ->
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = mockk<TatumApi> {
                coEvery {
                    getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
                } returns TatumV4TransactionResponse(result = listOf(invalidMovement))
            }

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(currency = "USDC", chainId = "ethereum"),
                forceRefresh = true
            )

            assertThat(result.isFailure).isTrue()
            assertThat(inserted).isEmpty()
            assertThat(cacheWrites).isEmpty()
        }
    }

    @Test
    fun `future EVM timestamp fails before transaction allocation or cache publication`() = runTest {
        val movement = evmTransaction(
            hash = "future-evm-timestamp",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(timestamp = System.currentTimeMillis() + 86_400_000L)
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(movement))
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            allocationRepository = allocationRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(currency = "USDC", chainId = "ethereum"),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("future")
        assertThat(inserted).isEmpty()
        coVerify(exactly = 0) {
            allocationRepository.getAllocationsForAsset(any())
        }
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `UTXO aggregate overflow fails before transaction or auto allocation persistence`() = runTest {
        val trackedAsset = asset(
            id = "overflow-ltc-asset",
            currency = "LTC",
            address = "wallet",
            chainId = "litecoin"
        )
        val movement = TatumUTXOTransaction(
            hash = "finite-components-overflow",
            time = 1_000L,
            inputs = listOf(
                TatumUTXOInput(
                    coin = TatumUTXOCoin(
                        valueNumber = 1.0,
                        address = "external-sender"
                    )
                )
            ),
            outputs = listOf(
                TatumUTXOOutput(
                    valueNumber = Double.MAX_VALUE,
                    address = trackedAsset.address
                ),
                TatumUTXOOutput(
                    valueNumber = Double.MAX_VALUE,
                    address = trackedAsset.address
                )
            )
        )
        val api = mockk<TatumApi> {
            coEvery {
                getLitecoinTransactions("wallet", pageSize = 20, offset = 0)
            } returns listOf(movement)
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "dedicated-overflow-allocation",
            assetId = trackedAsset.id,
            goalId = "goal-1",
            amount = 0.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset(trackedAsset.id) } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                histories += firstArg<AllocationHistory>()
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(trackedAsset) } returns Result.success(
                OnChainBalance(
                    assetId = trackedAsset.id,
                    chainId = "litecoin",
                    address = "wallet",
                    currency = "LTC",
                    balance = Double.MAX_VALUE,
                    fetchedAtMillis = 1L,
                    isStale = false
                )
            )
        }
        val cacheWrites = mutableListOf<Pair<String, String>>()

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = trackedAsset,
            forceRefresh = true
        )

        assertThat(histories).isEmpty()
        assertThat(allocation.amount).isEqualTo(0.0)
        assertThat(storedTransactions).isEmpty()
        assertThat(cacheWrites).isEmpty()
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("finite aggregate")
    }

    @Test
    fun `missing invalid or out of range UTXO timestamp fails before writes`() = runTest {
        val valid = utxoTransaction(hash = "invalid-utxo-time", trackedAddress = "wallet")
        val invalidMovements = listOf(
            valid.copy(time = null, ts = null),
            valid.copy(time = 0L),
            valid.copy(time = -1L),
            valid.copy(time = Long.MAX_VALUE)
        )

        invalidMovements.forEach { invalidMovement ->
            val inserted = mutableListOf<Transaction>()
            val cacheWrites = mutableListOf<Pair<String, String>>()
            val api = pagedUtxoApi(
                requestedOffsets = mutableListOf(),
                pageForOffset = { offset ->
                    if (offset == 0) listOf(invalidMovement) else emptyList()
                }
            )

            val result = repository(
                api = api,
                transactionRepository = transactionRepository(inserted),
                cacheWrites = cacheWrites
            ).refresh(
                asset = asset(
                    id = "invalid-utxo-time-asset",
                    currency = "BTC",
                    address = "wallet",
                    chainId = "bitcoin"
                ),
                forceRefresh = true
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains("timestamp")
            assertThat(inserted).isEmpty()
            assertThat(cacheWrites).isEmpty()
        }
    }

    @Test
    fun `future UTXO timestamp fails before transaction allocation or cache publication`() = runTest {
        val movement = utxoTransaction(
            hash = "future-utxo-timestamp",
            trackedAddress = "wallet"
        ).copy(time = System.currentTimeMillis() + 86_400_000L)
        val inserted = mutableListOf<Transaction>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val api = pagedUtxoApi(
            requestedOffsets = mutableListOf(),
            pageForOffset = { offset ->
                if (offset == 0) listOf(movement) else emptyList()
            }
        )

        val result = repository(
            api = api,
            transactionRepository = transactionRepository(inserted),
            allocationRepository = allocationRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                id = "future-utxo-time-asset",
                currency = "BTC",
                address = "wallet",
                chainId = "bitcoin"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("future")
        assertThat(inserted).isEmpty()
        coVerify(exactly = 0) {
            allocationRepository.getAllocationsForAsset(any())
        }
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `enriched UTXO response collapses compatible scoped witness and txid rows`() = runTest {
        val witnessHash = "scoped-legacy-witness"
        val transactionId = "scoped-legacy-canonical"
        val refreshed = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
            .copy(txid = transactionId)
        val canonicalExternalId = "utxo:asset-1:$transactionId"
        val witnessExternalId = "utxo:asset-1:$witnessHash"
        val canonical = Transaction(
            id = "canonical-row",
            assetId = "asset-1",
            amount = 1.0,
            dateMillis = 1_000_000L,
            source = TransactionSource.ON_CHAIN,
            externalId = canonicalExternalId,
            counterparty = "external-sender",
            comment = "On-chain",
            createdAt = 2L
        )
        val witness = canonical.copy(
            id = "witness-row",
            externalId = witnessExternalId,
            comment = "Preserve sole user note",
            createdAt = 1L
        )
        val storedByExternalId = linkedMapOf(
            canonicalExternalId to canonical,
            witnessExternalId to witness
        )
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returns listOf(refreshed)
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        ).refresh(
            asset = asset(
                currency = "BTC",
                chainId = "bitcoin",
                address = "wallet"
            ),
            forceRefresh = true
        )

        assertThat(result.getOrThrow()).isEqualTo(0)
        assertThat(storedByExternalId.values).hasSize(1)
        with(storedByExternalId.values.single()) {
            assertThat(id).isEqualTo(canonical.id)
            assertThat(externalId).contains(transactionId)
            assertThat(externalId).contains(witnessHash)
            assertThat(comment).isEqualTo("Preserve sole user note")
        }
    }

    @Test
    fun `enriched UTXO response leaves conflicting scoped rows unchanged`() = runTest {
        val witnessHash = "conflicting-scoped-witness"
        val transactionId = "conflicting-scoped-canonical"
        val refreshed = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
            .copy(txid = transactionId)
        val canonicalExternalId = "utxo:asset-1:$transactionId"
        val witnessExternalId = "utxo:asset-1:$witnessHash"
        val canonical = Transaction(
            id = "conflicting-canonical-row",
            assetId = "asset-1",
            amount = 1.0,
            dateMillis = 1_000_000L,
            source = TransactionSource.ON_CHAIN,
            externalId = canonicalExternalId,
            counterparty = "Canonical counterparty",
            comment = "Canonical user note",
            createdAt = 2L
        )
        val witness = canonical.copy(
            id = "conflicting-witness-row",
            externalId = witnessExternalId,
            counterparty = "Witness counterparty",
            comment = "Witness user note",
            createdAt = 1L
        )
        val storedByExternalId = linkedMapOf(
            canonicalExternalId to canonical,
            witnessExternalId to witness
        )
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returns listOf(refreshed)
        }

        val result = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId),
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                currency = "BTC",
                chainId = "bitcoin",
                address = "wallet"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("metadata")
        assertThat(storedByExternalId.values).containsExactly(canonical, witness)
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `duplicate UTXO alias rows fail before mutation or cache publication`() = runTest {
        val witnessHash = "ambiguous-duplicate-witness"
        val transactionId = "ambiguous-duplicate-canonical"
        val refreshed = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
            .copy(txid = transactionId)
        val first = legacyTransaction(
            id = "ambiguous-witness-a",
            externalId = witnessHash
        )
        val second = first.copy(id = "ambiguous-witness-b")
        val inserted = mutableListOf<Transaction>()
        val updated = mutableListOf<Transaction>()
        val deleted = mutableListOf<String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val transactionRepository = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByAssetIdOnce("asset-1") } returns listOf(first, second)
            coEvery { getTransactionsByExternalId(any()) } answers {
                if (firstArg<String>() == witnessHash) listOf(first, second) else emptyList()
            }
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
            coEvery { updateTransaction(any()) } answers {
                updated += firstArg<Transaction>()
            }
            coEvery { deleteTransaction(any<String>()) } answers {
                deleted += firstArg<String>()
            }
        }
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returns listOf(refreshed)
        }

        val result = repository(
            api = api,
            transactionRepository = transactionRepository,
            cacheWrites = cacheWrites
        ).refresh(
            asset = asset(
                currency = "BTC",
                chainId = "bitcoin",
                address = "wallet"
            ),
            forceRefresh = true
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("duplicate installed rows")
        assertThat(inserted).isEmpty()
        assertThat(updated).isEmpty()
        assertThat(deleted).isEmpty()
        assertThat(cacheWrites).isEmpty()
    }

    @Test
    fun `canonical and legacy UTXO metadata conflict fails without deleting either row`() = runTest {
        val witnessHash = "metadata-witness-hash"
        val transactionId = "metadata-canonical-txid"
        val refreshed = utxoTransaction(hash = witnessHash, trackedAddress = "wallet")
            .copy(txid = transactionId)
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returns listOf(refreshed)
        }
        val storedByExternalId = linkedMapOf<String, Transaction>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedByExternalId)
        )
        val trackedAsset = asset(
            currency = "BTC",
            chainId = "bitcoin",
            address = "wallet"
        )
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        val canonicalExternalId = storedByExternalId.keys.single()
        val canonical = storedByExternalId.getValue(canonicalExternalId).copy(
            counterparty = "Canonical counterparty",
            comment = "Canonical user note"
        )
        storedByExternalId[canonicalExternalId] = canonical
        val legacy = legacyTransaction(
            id = "metadata-legacy-row",
            externalId = witnessHash
        ).copy(
            counterparty = "Legacy counterparty",
            comment = "Legacy user note"
        )
        storedByExternalId[witnessHash] = legacy

        val result = repository.refresh(trackedAsset, forceRefresh = true)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("metadata")
        assertThat(storedByExternalId.values).hasSize(2)
        assertThat(storedByExternalId.getValue(canonicalExternalId)).isEqualTo(canonical)
        assertThat(storedByExternalId.getValue(witnessHash)).isEqualTo(legacy)
    }

    @Test
    fun `same-batch deposits at one timestamp create one cumulative allocation history`() = runTest {
        val first = evmTransaction(
            hash = "same-timestamp-batch-first",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val second = evmTransaction(
            hash = "same-timestamp-batch-second",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 1_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returns TatumV4TransactionResponse(result = listOf(first, second))
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "same-timestamp-batch-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                onChainBalance(balance = 8.0, fetchedAtMillis = 1L)
            )
        }
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )

        assertThat(
            repository.refresh(
                asset = asset(currency = "USDC", chainId = "ethereum"),
                forceRefresh = true
            ).getOrThrow()
        ).isEqualTo(2)
        assertThat(storedTransactions).hasSize(2)
        assertThat(allocation.amount).isEqualTo(8.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(8.0)
        assertThat(histories.single().timestamp).isEqualTo(1_000_000L)
    }

    @Test
    fun `same-timestamp unallocated sibling makes later removal fail closed`() = runTest {
        val first = evmTransaction(
            hash = "same-timestamp-cross-refresh-first",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val second = evmTransaction(
            hash = "same-timestamp-cross-refresh-second",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 1_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(first)),
                TatumV4TransactionResponse(result = listOf(first, second)),
                TatumV4TransactionResponse(result = listOf(first)),
                TatumV4TransactionResponse(result = listOf(first))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "same-timestamp-cross-refresh-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(onChainBalance(balance = 6.0, fetchedAtMillis = 1L)),
                Result.success(onChainBalance(balance = 7.0, fetchedAtMillis = 2L))
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheStore = linkedMapOf<String, String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheStore = cacheStore,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        val originalHistory = histories.single()

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(storedTransactions).hasSize(2)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).containsExactly(originalHistory)

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        val transactionSnapshot = storedTransactions.toMap()
        val cacheWriteSnapshot = cacheWrites.toList()

        val confirmedRemoval = repository.refresh(trackedAsset)

        assertThat(confirmedRemoval.isFailure).isTrue()
        assertThat(confirmedRemoval.exceptionOrNull()).hasMessageThat()
            .contains("same-timestamp provenance")
        assertThat(storedTransactions).containsExactlyEntriesIn(transactionSnapshot)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).containsExactly(originalHistory)
        assertThat(cacheWrites).containsExactlyElementsIn(cacheWriteSnapshot).inOrder()
        assertThat(cacheStore).doesNotContainKey(cacheKey)
        assertThat(cacheStore).containsKey(pendingAbsenceKey)
    }

    @Test
    fun `removing both autoallocated and unallocated same-timestamp rows fails closed`() = runTest {
        val autoAllocated = evmTransaction(
            hash = "same-timestamp-both-missing-autoallocated",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val unallocated = evmTransaction(
            hash = "same-timestamp-both-missing-unallocated",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 1_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(autoAllocated)),
                TatumV4TransactionResponse(result = listOf(autoAllocated, unallocated)),
                TatumV4TransactionResponse(),
                TatumV4TransactionResponse()
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "same-timestamp-both-missing-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returnsMany listOf(
                Result.success(onChainBalance(balance = 6.0, fetchedAtMillis = 1L)),
                Result.success(onChainBalance(balance = 7.0, fetchedAtMillis = 2L))
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheStore = linkedMapOf<String, String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheStore = cacheStore,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        val transactionSnapshot = storedTransactions.toMap()
        val historySnapshot = histories.toList()
        val cacheWriteSnapshot = cacheWrites.toList()

        val confirmedRemoval = repository.refresh(trackedAsset)

        assertThat(confirmedRemoval.isFailure).isTrue()
        assertThat(confirmedRemoval.exceptionOrNull()).hasMessageThat()
            .contains("same-timestamp provenance")
        assertThat(storedTransactions).containsExactlyEntriesIn(transactionSnapshot)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).containsExactlyElementsIn(historySnapshot).inOrder()
        assertThat(cacheWrites).containsExactlyElementsIn(cacheWriteSnapshot).inOrder()
        assertThat(cacheStore).doesNotContainKey(cacheKey)
        assertThat(cacheStore).containsKey(pendingAbsenceKey)
    }

    @Test
    fun `provider absence requires two exhaustive refreshes before reversing dedicated deposit`() = runTest {
        val movement = evmTransaction(
            hash = "confirmed-provider-removal",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(
            transactionIndex = 3,
            logIndex = 7,
            timestamp = 1_000L
        )
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(movement)),
                TatumV4TransactionResponse(),
                TatumV4TransactionResponse()
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "confirmed-removal-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                onChainBalance(balance = 6.0, fetchedAtMillis = 1L)
            )
        }
        val cacheStore = linkedMapOf<String, String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            cacheStore = cacheStore,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(storedTransactions).hasSize(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(6.0)
        assertThat(cacheStore).containsKey(cacheKey)

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        assertThat(storedTransactions).hasSize(1)
        assertThat(allocation.amount).isEqualTo(6.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(6.0)
        assertThat(cacheStore).doesNotContainKey(cacheKey)
        assertThat(cacheStore).containsKey(pendingAbsenceKey)
        assertThat(cacheWrites.count { it.first == cacheKey }).isEqualTo(1)

        assertThat(repository.refresh(trackedAsset).getOrThrow()).isEqualTo(0)
        assertThat(storedTransactions).isEmpty()
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(5.0)
        assertThat(histories.single().timestamp).isEqualTo(1_000_000L)
        assertThat(cacheStore).containsKey(cacheKey)
        assertThat(cacheStore).doesNotContainKey(pendingAbsenceKey)
        assertThat(cacheWrites.count { it.first == cacheKey }).isEqualTo(2)
        coVerify(exactly = 3) {
            api.getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
        }
    }

    @Test
    fun `changed provider absence set resets confirmation and reappearance clears it`() = runTest {
        val first = evmTransaction(
            hash = "absence-set-first",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val second = evmTransaction(
            hash = "absence-set-second",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 2_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(first, second)),
                TatumV4TransactionResponse(result = listOf(second)),
                TatumV4TransactionResponse(result = listOf(first)),
                TatumV4TransactionResponse(result = listOf(first, second))
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        val cacheStore = linkedMapOf<String, String>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            cacheStore = cacheStore
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(2)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        val firstPendingEvidence = cacheStore.getValue(pendingAbsenceKey)
        assertThat(storedTransactions).hasSize(2)

        assertThat(repository.refresh(trackedAsset).getOrThrow()).isEqualTo(0)
        assertThat(storedTransactions).hasSize(2)
        assertThat(cacheStore.getValue(pendingAbsenceKey)).isNotEqualTo(firstPendingEvidence)
        assertThat(cacheStore).doesNotContainKey(cacheKey)

        assertThat(repository.refresh(trackedAsset).getOrThrow()).isEqualTo(0)
        assertThat(storedTransactions).hasSize(2)
        assertThat(cacheStore).containsKey(cacheKey)
        assertThat(cacheStore).doesNotContainKey(pendingAbsenceKey)
    }

    @Test
    fun `confirmed multi-deposit removal reverses the proven history suffix atomically`() = runTest {
        val first = evmTransaction(
            hash = "ambiguous-removal-first",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 1, logIndex = 1, timestamp = 1_000L)
        val second = evmTransaction(
            hash = "ambiguous-removal-second",
            transactionType = "fungible",
            amount = "2",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 2, logIndex = 2, timestamp = 2_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(first, second)),
                TatumV4TransactionResponse(),
                TatumV4TransactionResponse()
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        var allocation = Allocation(
            id = "ambiguous-removal-allocation",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 5.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { listOf(allocation) }
            coEvery { upsertAllocation(any()) } answers {
                allocation = firstArg()
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { deleteById(any()) } answers {
                val historyId = firstArg<String>()
                histories.removeAll { it.id == historyId }
            }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                onChainBalance(balance = 8.0, fetchedAtMillis = 1L)
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocation
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocation = allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheStore = linkedMapOf<String, String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheStore = cacheStore,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(2)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)

        assertThat(repository.refresh(trackedAsset).getOrThrow()).isEqualTo(0)

        assertThat(storedTransactions).isEmpty()
        assertThat(allocation.amount).isEqualTo(5.0)
        assertThat(histories).hasSize(1)
        assertThat(histories.single().amount).isEqualTo(5.0)
        assertThat(histories.single().timestamp).isEqualTo(2_000_000L)
        assertThat(cacheStore).containsKey(cacheKey)
        assertThat(cacheStore).doesNotContainKey(pendingAbsenceKey)
        assertThat(cacheWrites.count { it.first == cacheKey }).isEqualTo(2)
    }

    @Test
    fun `confirmed removal rolls back when dedicated allocation ownership changed`() = runTest {
        val movement = evmTransaction(
            hash = "changed-allocation-removal",
            transactionType = "fungible",
            amount = "1",
            tokenAddress = USDC_ETHEREUM_CONTRACT
        ).copy(transactionIndex = 4, logIndex = 8, timestamp = 1_000L)
        val api = mockk<TatumApi> {
            coEvery {
                getTransactionHistoryV4(any(), any(), any(), any(), any(), any(), any())
            } returnsMany listOf(
                TatumV4TransactionResponse(result = listOf(movement)),
                TatumV4TransactionResponse(),
                TatumV4TransactionResponse()
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        val allocations = mutableListOf(
            Allocation(
                id = "original-dedicated-allocation",
                assetId = "asset-1",
                goalId = "goal-1",
                amount = 5.0,
                createdAt = 1L,
                lastModifiedAt = 1L
            )
        )
        val histories = mutableListOf<AllocationHistory>()
        val allocationRepository = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers { allocations.toList() }
            coEvery { upsertAllocation(any()) } answers {
                val updated = firstArg<Allocation>()
                allocations.removeAll { it.id == updated.id }
                allocations += updated
            }
        }
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } answers { flowOf(histories.toList()) }
            coEvery { insert(any()) } answers {
                val history = firstArg<AllocationHistory>()
                histories.removeAll { it.id == history.id }
                histories += history
            }
        }
        val onChainBalanceRepository = mockk<OnChainBalanceRepository> {
            coEvery { getFreshBalanceForPreflight(any()) } returns Result.success(
                onChainBalance(balance = 6.0, fetchedAtMillis = 1L)
            )
        }
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T {
                val transactionSnapshot = storedTransactions.toMap()
                val allocationSnapshot = allocations.toList()
                val historySnapshot = histories.toList()
                return try {
                    block()
                } catch (error: Throwable) {
                    storedTransactions.clear()
                    storedTransactions.putAll(transactionSnapshot)
                    allocations.clear()
                    allocations += allocationSnapshot
                    histories.clear()
                    histories += historySnapshot
                    throw error
                }
            }
        }
        val cacheStore = linkedMapOf<String, String>()
        val cacheWrites = mutableListOf<Pair<String, String>>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = transactionRunner,
            cacheStore = cacheStore,
            cacheWrites = cacheWrites
        )
        val trackedAsset = asset(currency = "USDC", chainId = "ethereum")
        val cacheKey = "transactions_v3:asset-1:ethereum:0xwallet:USDC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        allocations[0] = allocations.single().copy(
            amount = 5.0,
            lastModifiedAt = 2L
        )
        allocations += Allocation(
            id = "new-shared-allocation",
            assetId = "asset-1",
            goalId = "goal-2",
            amount = 1.0,
            createdAt = 2L,
            lastModifiedAt = 2L
        )
        val transactionSnapshot = storedTransactions.toMap()
        val allocationSnapshot = allocations.toList()
        val historySnapshot = histories.toList()
        val cacheSnapshot = cacheStore.toMap()
        val cacheWriteSnapshot = cacheWrites.toList()

        val confirmedRemoval = repository.refresh(trackedAsset)

        assertThat(confirmedRemoval.isFailure).isTrue()
        assertThat(confirmedRemoval.exceptionOrNull()).hasMessageThat().contains("ownership")
        assertThat(storedTransactions).containsExactlyEntriesIn(transactionSnapshot)
        assertThat(allocations).containsExactlyElementsIn(allocationSnapshot).inOrder()
        assertThat(histories).containsExactlyElementsIn(historySnapshot).inOrder()
        assertThat(cacheStore).containsExactlyEntriesIn(cacheSnapshot)
        assertThat(cacheWrites).containsExactlyElementsIn(cacheWriteSnapshot).inOrder()
        assertThat(cacheStore).doesNotContainKey(cacheKey)
        assertThat(cacheStore).containsKey(pendingAbsenceKey)
    }

    @Test
    fun `UTXO canonical row uses the same two-phase absence confirmation`() = runTest {
        val movement = utxoTransaction(
            hash = "utxo-confirmed-provider-removal",
            trackedAddress = "wallet"
        )
        val api = mockk<TatumApi> {
            coEvery {
                getBitcoinTransactions("wallet", pageSize = 20, offset = 0)
            } returnsMany listOf(
                listOf(movement),
                emptyList(),
                emptyList()
            )
        }
        val storedTransactions = linkedMapOf<String, Transaction>()
        val cacheStore = linkedMapOf<String, String>()
        val repository = repository(
            api = api,
            transactionRepository = statefulTransactionRepository(storedTransactions),
            cacheStore = cacheStore
        )
        val trackedAsset = asset(
            currency = "BTC",
            chainId = "bitcoin",
            address = "wallet"
        )
        val cacheKey = "transactions_v3:asset-1:bitcoin:wallet:BTC"
        val pendingAbsenceKey = "provider_absence_v1:$cacheKey"

        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(1)
        assertThat(repository.refresh(trackedAsset, forceRefresh = true).getOrThrow())
            .isEqualTo(0)
        assertThat(storedTransactions).hasSize(1)
        assertThat(cacheStore).doesNotContainKey(cacheKey)
        assertThat(cacheStore).containsKey(pendingAbsenceKey)

        assertThat(repository.refresh(trackedAsset).getOrThrow()).isEqualTo(0)
        assertThat(storedTransactions).isEmpty()
        assertThat(cacheStore).containsKey(cacheKey)
        assertThat(cacheStore).doesNotContainKey(pendingAbsenceKey)
    }

    private fun repository(
        api: TatumApi,
        cachedEntry: String? = null,
        cachedEntries: Map<String, String> = emptyMap(),
        cacheReads: MutableList<String>? = null,
        apiKey: String = "test-api-key",
        transactionRepository: TransactionRepository = mockk(relaxed = true),
        allocationRepository: AllocationRepository = mockk(relaxed = true),
        allocationHistoryRepository: AllocationHistoryRepository = mockk(relaxed = true) {
            every { getByAssetId(any()) } returns flowOf(emptyList())
        },
        onChainBalanceRepository: OnChainBalanceRepository = mockk(relaxed = true),
        assetProviderIdentityVerifier: OnChainAssetProviderIdentityVerifier = mockk(relaxed = true),
        transactionRunner: ExecutionTransitionTransactionRunner = DirectTransactionRunner,
        cacheStore: MutableMap<String, String>? = null,
        cacheWrites: MutableList<Pair<String, String>>? = null
    ): OnChainTransactionRepositoryImpl {
        val context = mockk<Context>()
        val prefs = mockk<SharedPreferences>()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val apiKeyStore = mockk<ApiKeyStore>()

        every {
            context.getSharedPreferences(any(), Context.MODE_PRIVATE)
        } returns prefs
        every { prefs.getString(any(), null) } answers {
            val key = firstArg<String>()
            cacheReads?.add(key)
            cacheStore?.get(key) ?: cachedEntries[key] ?: cachedEntry
        }
        every { prefs.edit() } returns editor
        every { editor.putString(any(), any()) } answers {
            val key = firstArg<String>()
            val value = secondArg<String>()
            cacheStore?.set(key, value)
            cacheWrites?.add(key to value)
            editor
        }
        every { editor.remove(any()) } answers {
            cacheStore?.remove(firstArg())
            editor
        }
        every { apiKeyStore.getTatumApiKey() } returns apiKey

        return OnChainTransactionRepositoryImpl(
            tatumApi = api,
            rateLimiter = TokenBucketRateLimiter(
                maxTokens = 100.0,
                refillTokensPerSecond = 100.0
            ),
            apiKeyStore = apiKeyStore,
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            assetProviderIdentityVerifier = assetProviderIdentityVerifier,
            transactionRunner = transactionRunner,
            context = context
        )
    }

    private fun transactionRepository(inserted: MutableList<Transaction>) =
        mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionsByAssetIdOnce(any()) } returns emptyList()
            coEvery { getTransactionByExternalId(any()) } returns null
            coEvery { getTransactionsByExternalId(any()) } returns emptyList()
            coEvery { insertTransactions(any()) } answers {
                inserted += firstArg<List<Transaction>>()
            }
        }

    private fun statefulTransactionRepository(
        storedByExternalId: MutableMap<String, Transaction>
    ) = mockk<TransactionRepository>(relaxed = true) {
        coEvery { getTransactionsByAssetIdOnce(any()) } answers {
            val assetId = firstArg<String>()
            storedByExternalId.values
                .distinctBy { it.id }
                .filter { it.assetId == assetId }
        }
        coEvery { getTransactionByExternalId(any()) } answers {
            storedByExternalId[firstArg<String>()]
        }
        coEvery { getTransactionsByExternalId(any()) } answers {
            storedByExternalId[firstArg<String>()]?.let(::listOf).orEmpty()
        }
        coEvery { insertTransactions(any()) } answers {
            firstArg<List<Transaction>>().forEach { transaction ->
                storedByExternalId[checkNotNull(transaction.externalId)] = transaction
            }
        }
        coEvery { updateTransaction(any()) } answers {
            val transaction = firstArg<Transaction>()
            storedByExternalId.entries.removeAll { (_, existing) ->
                existing.id == transaction.id
            }
            transaction.externalId?.let { storedByExternalId[it] = transaction }
        }
        coEvery { deleteTransaction(any<String>()) } answers {
            val id = firstArg<String>()
            storedByExternalId.entries.removeAll { (_, existing) -> existing.id == id }
        }
    }

    private fun legacyTransaction(id: String, externalId: String) = Transaction(
        id = id,
        assetId = "asset-1",
        amount = 9.0,
        dateMillis = 123L,
        source = TransactionSource.ON_CHAIN,
        externalId = externalId,
        counterparty = "0xlegacy",
        comment = "Preserve legacy",
        createdAt = 777L
    )

    private fun asset(
        currency: String,
        chainId: String,
        id: String = "asset-1",
        address: String = "0xwallet"
    ) = Asset(
        id = id,
        currency = currency,
        address = address,
        chainId = chainId,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun pagedUtxoApi(
        requestedOffsets: MutableList<Int>,
        pageForOffset: (Int) -> List<TatumUTXOTransaction>,
        lookupRequests: MutableList<Pair<String, String>> = mutableListOf(),
        previousTransactionForLookup: (String, String) -> TatumUTXOTransaction = { chain, hash ->
            error("Unexpected prevout lookup for $chain:$hash")
        }
    ) = mockk<TatumApi> {
        coEvery { getBitcoinTransactions(any(), pageSize = 20, offset = capture(requestedOffsets)) } answers {
            pageForOffset(thirdArg())
        }
        coEvery { getLitecoinTransactions(any(), pageSize = 20, offset = capture(requestedOffsets)) } answers {
            pageForOffset(thirdArg())
        }
        coEvery { getBitcoinCashTransactions(any(), pageSize = 20, offset = capture(requestedOffsets)) } answers {
            pageForOffset(thirdArg())
        }
        coEvery { getDogecoinTransactions(any(), pageSize = 20, offset = capture(requestedOffsets)) } answers {
            pageForOffset(thirdArg())
        }
        coEvery { getBlockchainTransaction(any(), any()) } answers {
            val request = firstArg<String>() to secondArg<String>()
            lookupRequests += request
            previousTransactionForLookup(request.first, request.second)
        }
    }

    private fun verifyUtxoRequests(api: TatumApi, chainId: String, expectedCalls: Int) {
        when (chainId) {
            "bitcoin" -> coVerify(exactly = expectedCalls) {
                api.getBitcoinTransactions(any(), pageSize = 20, offset = any())
            }
            "litecoin" -> coVerify(exactly = expectedCalls) {
                api.getLitecoinTransactions(any(), pageSize = 20, offset = any())
            }
            "bitcoin-cash" -> coVerify(exactly = expectedCalls) {
                api.getBitcoinCashTransactions(any(), pageSize = 20, offset = any())
            }
            "dogecoin" -> coVerify(exactly = expectedCalls) {
                api.getDogecoinTransactions(any(), pageSize = 20, offset = any())
            }
            else -> error("Unsupported test chain $chainId")
        }
    }

    private fun utxoTransaction(
        hash: String,
        trackedAddress: String
    ) = TatumUTXOTransaction(
        hash = hash,
        time = 1_000L,
        inputs = listOf(
            TatumUTXOInput(
                coin = TatumUTXOCoin(
                    valueNumber = 1.0,
                    address = "external-sender"
                )
            )
        ),
        outputs = listOf(
            TatumUTXOOutput(
                valueNumber = 100_000_000.0,
                address = trackedAddress
            )
        )
    )

    private fun rawOutgoingTransaction(
        chainId: String,
        hash: String,
        parentHashes: List<String>
    ): TatumUTXOTransaction {
        val nextIndexByParent = mutableMapOf<String, Int>()
        return TatumUTXOTransaction(
            hash = if (chainId == "bitcoin-cash") "" else hash,
            txid = hash.takeIf { chainId == "bitcoin-cash" },
            time = 1_000L,
            vin = parentHashes.map { parentHash ->
                val outputIndex = nextIndexByParent.getOrDefault(parentHash, 0)
                nextIndexByParent[parentHash] = outputIndex + 1
                TatumUTXOInput(txid = parentHash, vout = outputIndex)
            },
            vout = listOf(
                TatumUTXOOutput(
                    valueNumber = 0.6,
                    n = 0,
                    scriptPubKey = TatumScriptPubKey(addresses = listOf("recipient"))
                ),
                TatumUTXOOutput(
                    valueNumber = 0.3,
                    n = 1,
                    scriptPubKey = TatumScriptPubKey(addresses = listOf("wallet"))
                )
            )
        )
    }

    private fun rawCoinbaseTransaction(
        chainId: String,
        hash: String,
        trackedAddress: String,
        amount: Double
    ) = TatumUTXOTransaction(
        hash = if (chainId == "bitcoin-cash") "" else hash,
        txid = hash.takeIf { chainId == "bitcoin-cash" },
        time = 1_000L,
        vin = listOf(TatumUTXOInput(coinbase = "03abcdef")),
        vout = listOf(
            TatumUTXOOutput(
                valueNumber = amount,
                n = 0,
                scriptPubKey = TatumScriptPubKey(addresses = listOf(trackedAddress))
            )
        )
    )

    private fun previousTransaction(
        chainId: String,
        hash: String,
        outputs: List<Pair<Double, String>>
    ): TatumUTXOTransaction {
        return if (chainId == "bitcoin-cash") {
            TatumUTXOTransaction(
                txid = hash,
                vout = outputs.mapIndexed { index, (value, address) ->
                    TatumUTXOOutput(
                        valueNumber = value,
                        n = index,
                        scriptPubKey = TatumScriptPubKey(addresses = listOf(address))
                    )
                }
            )
        } else {
            TatumUTXOTransaction(
                hash = hash,
                outputs = outputs.map { (value, address) ->
                    TatumUTXOOutput(
                        valueNumber = value * 100_000_000.0,
                        address = address
                    )
                }
            )
        }
    }

    private fun evmTransaction(
        hash: String,
        transactionType: String,
        amount: String,
        tokenAddress: String?,
        counterAddress: String = "0xsender"
    ) = TatumTransactionDto(
        hash = hash,
        chain = "ethereum-mainnet",
        address = "0xwallet",
        transactionType = transactionType,
        transactionSubtype = "incoming",
        amount = amount,
        tokenAddress = tokenAddress,
        counterAddress = counterAddress,
        timestamp = 1_000L
    )

    private fun successfulEvmDetail(
        hash: String,
        from: String = "0xwallet",
        status: JsonPrimitive? = JsonPrimitive("0x1"),
        gasUsed: JsonPrimitive = JsonPrimitive("0x5208"),
        effectiveGasPrice: JsonPrimitive = JsonPrimitive("0x4a817c800")
    ) = TatumEvmJsonRpcReceiptResponse(
        jsonrpc = "2.0",
        id = 1,
        result = TatumEvmTransactionReceipt(
            transactionHash = hash,
            from = from,
            status = status,
            gasUsed = gasUsed,
            effectiveGasPrice = effectiveGasPrice
        )
    )

    private fun canonicalExternalIdFor(transaction: TatumTransactionDto): String {
        return listOf(
            "evm-record-v1",
            transaction.chain.orEmpty(),
            transaction.hash,
            transaction.transactionType.orEmpty(),
            transaction.tokenAddress ?: "native",
            transaction.address.orEmpty(),
            transaction.tokenId ?: "no-token-id",
            transaction.transactionIndex?.toString() ?: "no-transaction-index",
            transaction.logIndex?.toString() ?: "no-log-index"
        ).joinToString(separator = ":") { it.trim().lowercase() }
    }

    private fun legacyMutableExternalIdFor(transaction: TatumTransactionDto): String {
        val normalizedAmount = transaction.amount
            ?.toBigDecimalOrNull()
            ?.stripTrailingZeros()
            ?.toPlainString()
            ?: "0"
        return listOf(
            transaction.chain.orEmpty(),
            transaction.hash,
            transaction.transactionType.orEmpty(),
            transaction.tokenAddress ?: "native",
            transaction.address.orEmpty(),
            transaction.transactionSubtype.orEmpty(),
            transaction.counterAddress.orEmpty(),
            normalizedAmount,
            transaction.tokenId ?: "no-token-id",
            transaction.transactionIndex?.toString() ?: "no-transaction-index",
            transaction.logIndex?.toString() ?: "no-log-index"
        ).joinToString(separator = ":") { it.trim().lowercase() }
    }

    private fun onChainBalance(
        balance: Double,
        fetchedAtMillis: Long
    ) = OnChainBalance(
        assetId = "asset-1",
        chainId = "ethereum",
        address = "0xwallet",
        currency = "USDC",
        balance = balance,
        fetchedAtMillis = fetchedAtMillis,
        isStale = false
    )

    private object DirectTransactionRunner : ExecutionTransitionTransactionRunner {
        override suspend fun <T> run(block: suspend () -> T): T = block()
    }

    private companion object {
        const val USDC_ETHEREUM_CONTRACT = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        const val COUNTERFEIT_USDC_CONTRACT = "0x0000000000000000000000000000000000000001"

        @JvmStatic
        fun officialEvmV4Chains() = listOf(
            Arguments.of(Named.of("Ethereum", "ethereum"), "ethereum", "ethereum-mainnet", "ETH"),
            Arguments.of(Named.of("Polygon", "polygon"), "polygon", "polygon-mainnet", "POL"),
            Arguments.of(Named.of("BNB Smart Chain", "bsc"), "bsc", "bsc-mainnet", "BNB"),
            Arguments.of(Named.of("Arbitrum One", "arbitrum"), "arbitrum", "arb-one-mainnet", "ETH"),
            Arguments.of(Named.of("Optimism", "optimism"), "optimism", "optimism-mainnet", "ETH"),
            Arguments.of(Named.of("Base", "base"), "base", "base-mainnet", "ETH"),
            Arguments.of(Named.of("Avalanche", "avax"), "avax", "avax-mainnet", "AVAX")
        )

        @JvmStatic
        fun unsupportedTransactionChains() = listOf(
            Arguments.of(Named.of("Fantom", "ftm"), "ftm", "FTM"),
            Arguments.of(Named.of("Unknown chain", "mystery"), "mystery", "ETH"),
            Arguments.of(Named.of("Unknown Ethereum token", "ethereum-fake"), "ethereum", "FAKE"),
            Arguments.of(Named.of("Token on UTXO chain", "bitcoin-usdc"), "bitcoin", "USDC")
        )

        @JvmStatic
        fun utxoChains() = listOf(
            Arguments.of(Named.of("Bitcoin", "bitcoin"), "bitcoin", "BTC"),
            Arguments.of(Named.of("Litecoin", "litecoin"), "litecoin", "LTC"),
            Arguments.of(Named.of("Bitcoin Cash", "bitcoin-cash"), "bitcoin-cash", "BCH"),
            Arguments.of(Named.of("Dogecoin", "dogecoin"), "dogecoin", "DOGE")
        )

        @JvmStatic
        fun rawUtxoChains() = listOf(
            Arguments.of(
                Named.of("Bitcoin Cash raw vin/vout", "bitcoin-cash-raw"),
                "bitcoin-cash",
                "BCH",
                "bch-mainnet"
            ),
            Arguments.of(
                Named.of("Dogecoin raw vin/vout", "dogecoin-raw"),
                "dogecoin",
                "DOGE",
                "doge-mainnet"
            )
        )

        @JvmStatic
        fun officialUtxoV3Fixtures() = listOf(
            Arguments.of(
                Named.of("Bitcoin enriched inputs/outputs", "bitcoin-enriched"),
                "bitcoin",
                "BTC",
                """
                    {
                      "hash": "btc-fixture-hash",
                      "time": 1700000000,
                      "inputs": [
                        {
                          "coin": {
                            "value": 125000000,
                            "address": "sender"
                          }
                        }
                      ],
                      "outputs": [
                        {
                          "value": 100000000,
                          "address": "wallet"
                        }
                      ]
                    }
                """.trimIndent(),
                "btc-fixture-hash",
                1.0,
                false
            ),
            Arguments.of(
                Named.of("Litecoin enriched string amounts", "litecoin-enriched"),
                "litecoin",
                "LTC",
                """
                    {
                      "hash": "ltc-fixture-hash",
                      "time": 1700000000,
                      "inputs": [
                        {
                          "coin": {
                            "value": "1.25",
                            "address": "wallet"
                          }
                        }
                      ],
                      "outputs": [
                        {
                          "value": "1.0",
                          "address": "recipient"
                        }
                      ]
                    }
                """.trimIndent(),
                "ltc-fixture-hash",
                -1.25,
                false
            ),
            Arguments.of(
                Named.of("Bitcoin Cash txid/vin/vout", "bitcoin-cash-legacy"),
                "bitcoin-cash",
                "BCH",
                """
                    {
                      "txid": "bch-fixture-hash",
                      "time": 1700000000,
                      "vin": [
                        {
                          "txid": "previous-bch-hash",
                          "vout": 0
                        }
                      ],
                      "vout": [
                        {
                          "value": "1.25",
                          "scriptPubKey": {
                            "addresses": ["wallet"]
                          }
                        }
                      ]
                    }
                """.trimIndent(),
                "bch-fixture-hash",
                1.25,
                true
            ),
            Arguments.of(
                Named.of("Dogecoin vin/vout", "dogecoin-legacy"),
                "dogecoin",
                "DOGE",
                """
                    {
                      "hash": "doge-fixture-hash",
                      "time": 1700000000,
                      "vin": [
                        {
                          "txid": "previous-doge-hash",
                          "vout": 1
                        }
                      ],
                      "vout": [
                        {
                          "value": 12.5,
                          "scriptPubKey": {
                            "addresses": ["wallet"]
                          }
                        }
                      ]
                    }
                """.trimIndent(),
                "doge-fixture-hash",
                12.5,
                true
            )
        )
    }
}
