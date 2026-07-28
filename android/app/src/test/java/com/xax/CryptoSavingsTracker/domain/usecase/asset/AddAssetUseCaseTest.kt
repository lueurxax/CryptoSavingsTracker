package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class AddAssetUseCaseTest {
    @Test
    fun `addressed asset rejects unsupported currency and chain before persistence`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        coEvery { repository.getAssetByAddress(any()) } returns null
        val useCase = AddAssetUseCase(repository)

        val unsupportedPairs = listOf(
            "USDT" to "polygon",
            "BTC" to "xrp",
            "BTC" to "unknown"
        )

        unsupportedPairs.forEachIndexed { index, (currency, chainId) ->
            val result = useCase(
                currency = currency,
                address = "wallet-$index",
                chainId = chainId
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
            assertThat(result.exceptionOrNull()).hasMessageThat()
                .contains("automatic balance tracking")
        }
        coVerify(exactly = 0) { repository.insertAsset(any()) }
    }

    @Test
    fun `asset without address remains available for manual tracking`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)

        val result = AddAssetUseCase(repository)(
            currency = "USDT",
            address = null,
            chainId = "polygon"
        )

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) {
            repository.insertAsset(match { it.address == null && it.chainId == "polygon" })
        }
    }

    @Test
    fun `same EVM wallet can track multiple currencies but not duplicate one identity`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)

        val eth = useCase(
            currency = "eth",
            address = " 0xAbCd ",
            chainId = "ETHEREUM"
        )
        val usdc = useCase(
            currency = "usdc",
            address = "0xABCD",
            chainId = "ethereum"
        )
        val duplicateEth = useCase(
            currency = "ETH",
            address = "0xabcd",
            chainId = "ethereum"
        )

        assertThat(eth.isSuccess).isTrue()
        assertThat(usdc.isSuccess).isTrue()
        assertThat(duplicateEth.isFailure).isTrue()
        assertThat(repository.assets).hasSize(2)
        assertThat(repository.assets.map { it.currency }).containsExactly("ETH", "USDC")
        assertThat(repository.assets.map { it.address }.distinct()).containsExactly("0xabcd")
    }

    @Test
    fun `canonical reservation beside quarantined migration evidence blocks third identity`() =
        runTest {
            val repository = RecordingAssetRepository(
                initialAssets = listOf(
                    asset(
                        id = "canonical-reservation",
                        currency = "USDC",
                        address = "0xrate",
                        chainId = "ethereum"
                    ),
                    asset(
                        id = "quarantined-rate-evidence",
                        currency = "USDC",
                        address = "0xrate",
                        chainId = "legacy-rate-conflict:ethereum:quarantined-rate-evidence"
                    )
                )
            )

            val result = AddAssetUseCase(repository)(
                currency = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                address = "0xRaTe",
                chainId = "ETH"
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat()
                .contains("already tracked")
            assertThat(repository.assets).hasSize(2)
        }

    @Test
    fun `native and token aliases persist one canonical identity`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)
        val usdcContract = "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

        val polygonLegacy = useCase(
            currency = "MATIC",
            address = "0xPoLy",
            chainId = "MATIC"
        )
        val polygonCanonicalDuplicate = useCase(
            currency = "POL",
            address = "0xpoly",
            chainId = "polygon"
        )
        val usdcContractAsset = useCase(
            currency = usdcContract,
            address = "0xUsDc",
            chainId = "ETH"
        )
        val usdcSymbolDuplicate = useCase(
            currency = "USDC",
            address = "0xusdc",
            chainId = "ethereum"
        )

        assertThat(polygonLegacy.isSuccess).isTrue()
        assertThat(polygonLegacy.getOrThrow().currency).isEqualTo("POL")
        assertThat(polygonLegacy.getOrThrow().chainId).isEqualTo("polygon")
        assertThat(polygonCanonicalDuplicate.isFailure).isTrue()
        assertThat(usdcContractAsset.isSuccess).isTrue()
        assertThat(usdcContractAsset.getOrThrow().currency).isEqualTo("USDC")
        assertThat(usdcContractAsset.getOrThrow().chainId).isEqualTo("ethereum")
        assertThat(usdcSymbolDuplicate.isFailure).isTrue()
        assertThat(repository.assets).hasSize(2)
    }

    @Test
    fun `TRON canonical contract persists as USDT without changing address case`() = runTest {
        val repository = RecordingAssetRepository()

        val result = AddAssetUseCase(repository)(
            currency = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            address = "TCaseSensitiveWallet",
            chainId = "TRX"
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrThrow().currency).isEqualTo("USDT")
        assertThat(result.getOrThrow().chainId).isEqualTo("tron")
        assertThat(result.getOrThrow().address).isEqualTo("TCaseSensitiveWallet")
    }

    @Test
    fun `UTXO address aliases cannot create duplicate persistence identities`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)

        val bitcoin = useCase(
            currency = "BTC",
            address = "BC1QEXAMPLEADDRESS",
            chainId = "bitcoin"
        )
        val duplicateBitcoin = useCase(
            currency = "BTC",
            address = "bc1qexampleaddress",
            chainId = "BTC"
        )
        val bitcoinCash = useCase(
            currency = "BCH",
            address = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A",
            chainId = "bitcoin-cash"
        )
        val duplicateBitcoinCash = useCase(
            currency = "BCH",
            address = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            chainId = "BCH"
        )

        assertThat(bitcoin.isSuccess).isTrue()
        assertThat(bitcoin.getOrThrow().address).isEqualTo("bc1qexampleaddress")
        assertThat(duplicateBitcoin.isFailure).isTrue()
        assertThat(bitcoinCash.isSuccess).isTrue()
        assertThat(bitcoinCash.getOrThrow().address)
            .isEqualTo("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        assertThat(duplicateBitcoinCash.isFailure).isTrue()
        assertThat(repository.assets).hasSize(2)
    }

    @Test
    fun `cross encoding UTXO addresses reserve one persistence identity`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)

        val bitcoinCashLegacy = useCase(
            currency = "BCH",
            address = "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu",
            chainId = "bitcoin-cash"
        )
        val bitcoinCashCashAddr = useCase(
            currency = "BCH",
            address = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            chainId = "bitcoin-cash"
        )
        val litecoinLegacy = useCase(
            currency = "LTC",
            address = "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC",
            chainId = "litecoin"
        )
        val litecoinModern = useCase(
            currency = "LTC",
            address = "MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN",
            chainId = "litecoin"
        )

        assertThat(bitcoinCashLegacy.isSuccess).isTrue()
        assertThat(bitcoinCashLegacy.getOrThrow().address)
            .isEqualTo("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        assertThat(bitcoinCashCashAddr.isFailure).isTrue()
        assertThat(litecoinLegacy.isSuccess).isTrue()
        assertThat(litecoinLegacy.getOrThrow().address)
            .isEqualTo("MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN")
        assertThat(litecoinModern.isFailure).isTrue()
        assertThat(repository.assets).hasSize(2)
    }

    @Test
    fun `cross encoding UTXO addresses fail closed on invalid checksum`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)

        val invalidBitcoinCash = useCase(
            currency = "BCH",
            address = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6q",
            chainId = "bitcoin-cash"
        )
        val invalidLitecoin = useCase(
            currency = "LTC",
            address = "MWWunwFdsSzsi44wARi2zJJGju6VqMMGtP",
            chainId = "litecoin"
        )

        assertThat(invalidBitcoinCash.isFailure).isTrue()
        assertThat(invalidLitecoin.isFailure).isTrue()
        assertThat(repository.assets).isEmpty()
    }

    @Test
    fun `legacy QUICK contract fails closed while current contract persists as QUICK`() = runTest {
        val repository = RecordingAssetRepository()
        val useCase = AddAssetUseCase(repository)

        val legacy = useCase(
            currency = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13",
            address = "0xquick",
            chainId = "polygon"
        )
        val current = useCase(
            currency = "0xB5C064F955D8e7F38fE0460C556a72987494eE17",
            address = "0xquick",
            chainId = "polygon"
        )

        assertThat(legacy.isFailure).isTrue()
        assertThat(current.isSuccess).isTrue()
        assertThat(current.getOrThrow().currency).isEqualTo("QUICK")
        assertThat(repository.assets).hasSize(1)
    }
}

private class RecordingAssetRepository(
    initialAssets: List<Asset> = emptyList()
) : AssetRepository {
    val assets = initialAssets.toMutableList()

    override fun getAllAssets(): Flow<List<Asset>> = flowOf(assets.toList())

    override fun getAssetsByCurrency(currency: String): Flow<List<Asset>> =
        flowOf(assets.filter { it.currency == currency })

    override suspend fun getAssetById(id: String): Asset? = assets.firstOrNull { it.id == id }

    override fun getAssetByIdFlow(id: String): Flow<Asset?> = flowOf(assets.firstOrNull { it.id == id })

    override suspend fun getAssetByAddress(address: String): Asset? =
        assets.firstOrNull { it.address == address }

    override suspend fun getAssetByOnChainIdentity(
        address: String,
        chainId: String,
        currency: String
    ): Asset? = assets.firstOrNull {
        it.address == address && it.chainId == chainId && it.currency == currency
    }

    override suspend fun insertAsset(asset: Asset) {
        assets += asset
    }

    override suspend fun updateAsset(asset: Asset) = Unit

    override suspend fun deleteAsset(id: String) = Unit

    override suspend fun deleteAsset(asset: Asset) = Unit

    override suspend fun getAssetCount(): Int = assets.size
}

private fun asset(
    id: String,
    currency: String,
    address: String?,
    chainId: String?
) = Asset(
    id = id,
    currency = currency,
    address = address,
    chainId = chainId,
    createdAt = 1L,
    updatedAt = 1L
)
