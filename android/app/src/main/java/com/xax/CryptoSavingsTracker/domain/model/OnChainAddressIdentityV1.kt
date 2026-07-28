package com.xax.CryptoSavingsTracker.domain.model

import java.math.BigInteger
import java.security.MessageDigest

/**
 * Versioned persistence identity for wallet addresses.
 *
 * This contract is shared by migration, add/update, balance caches, and transaction import.
 * Do not change V1 rules after release; introduce a new version and migration instead.
 */
internal object OnChainAddressIdentityV1 {
    private const val BITCOIN_CASH_MAINNET_PREFIX = "bitcoincash"
    private const val BITCOIN_CASH_P2PKH_TYPE = 0
    private const val BITCOIN_CASH_P2SH_TYPE = 1
    private const val BITCOIN_CASH_P2PKH_LEGACY_VERSION = 0
    private const val BITCOIN_CASH_P2SH_LEGACY_VERSION = 5
    private const val LITECOIN_P2PKH_VERSION = 48
    private const val LITECOIN_LEGACY_P2SH_VERSION = 5
    private const val LITECOIN_CURRENT_P2SH_VERSION = 50
    private const val BASE58_CHECKSUM_SIZE = 4
    private const val CASHADDR_CHECKSUM_SIZE = 8
    private const val CASHADDR_RESERVED_BIT = 0x80
    private val base58Radix = BigInteger.valueOf(58L)
    private const val base58Alphabet =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private const val cashAddressAlphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private val cashAddressHashSizes = intArrayOf(20, 24, 28, 32, 40, 48, 56, 64)
    private val cashAddressGenerators = longArrayOf(
        0x98f2bc8e61L,
        0x79b76d99e2L,
        0xf33e5fb3c4L,
        0xae2eabe2a8L,
        0x1e4f43e470L
    )

    private data class ScriptPayload(
        val type: Int,
        val hash: ByteArray
    )

    fun canonicalize(chainId: String?, address: String): String {
        val trimmed = address.trim()
        val canonicalChainId = chainId
            ?.trim()
            ?.lowercase()
            .orEmpty()

        return when (canonicalChainId) {
            "eth", "ethereum",
            "matic", "pol", "polygon",
            "bnb", "bsc", "binance-smart-chain",
            "arb", "arbitrum", "arbitrum-one",
            "op", "optimism",
            "base",
            "avax", "avalanche", "avalanche-c" -> trimmed.lowercase()
            "btc", "bitcoin" -> trimmed.normalizeOneCaseBech32(prefix = "bc1")
            "ltc", "litecoin" -> normalizeLitecoinAddress(trimmed)
            "bch", "bcash", "bitcoin-cash" -> normalizeBitcoinCashAddress(trimmed)
            else -> trimmed
        }
    }

    private fun String.normalizeOneCaseBech32(prefix: String): String {
        if (!startsWith(prefix, ignoreCase = true) || !usesOneLetterCase()) return this
        return lowercase()
    }

    private fun normalizeLitecoinAddress(address: String): String {
        if (address.startsWith("ltc1", ignoreCase = true)) {
            return address.normalizeOneCaseBech32(prefix = "ltc1")
        }
        if (address.firstOrNull() !in setOf('3', 'L', 'M')) return address

        val decoded = decodeBase58Check(address, "Litecoin")
        require(decoded.size == 21) {
            "Litecoin address has an invalid payload length"
        }
        val version = decoded.first().toInt() and 0xff
        val canonicalVersion = when (version) {
            LITECOIN_P2PKH_VERSION -> LITECOIN_P2PKH_VERSION
            LITECOIN_LEGACY_P2SH_VERSION,
            LITECOIN_CURRENT_P2SH_VERSION -> LITECOIN_CURRENT_P2SH_VERSION
            else -> throw IllegalArgumentException(
                "Litecoin address uses an unsupported network or script version"
            )
        }
        return encodeBase58Check(
            version = canonicalVersion,
            payload = decoded.copyOfRange(1, decoded.size)
        )
    }

    private fun normalizeBitcoinCashAddress(address: String): String {
        val scriptPayload = when {
            ':' in address || address.firstOrNull()?.lowercaseChar() in setOf('q', 'p') ->
                decodeCashAddress(address)
            address.firstOrNull() in setOf('1', '3') -> {
                val decoded = decodeBase58Check(address, "Bitcoin Cash")
                require(decoded.size == 21) {
                    "Bitcoin Cash legacy address has an invalid payload length"
                }
                val type = when (decoded.first().toInt() and 0xff) {
                    BITCOIN_CASH_P2PKH_LEGACY_VERSION -> BITCOIN_CASH_P2PKH_TYPE
                    BITCOIN_CASH_P2SH_LEGACY_VERSION -> BITCOIN_CASH_P2SH_TYPE
                    else -> throw IllegalArgumentException(
                        "Bitcoin Cash legacy address uses an unsupported network or script version"
                    )
                }
                ScriptPayload(
                    type = type,
                    hash = decoded.copyOfRange(1, decoded.size)
                )
            }
            else -> return address
        }
        return encodeCashAddress(scriptPayload)
    }

    private fun decodeBase58Check(address: String, description: String): ByteArray {
        require(address.isNotEmpty()) { "$description address is empty" }
        var number = BigInteger.ZERO
        address.forEach { character ->
            val digit = base58Alphabet.indexOf(character)
            require(digit >= 0) { "$description address contains an invalid Base58 character" }
            number = number.multiply(base58Radix).add(BigInteger.valueOf(digit.toLong()))
        }

        val significantBytes = if (number == BigInteger.ZERO) {
            ByteArray(0)
        } else {
            number.toByteArray().let { bytes ->
                if (bytes.firstOrNull() == 0.toByte()) {
                    bytes.copyOfRange(1, bytes.size)
                } else {
                    bytes
                }
            }
        }
        val leadingZeros = address.takeWhile { it == base58Alphabet.first() }.length
        val decoded = ByteArray(leadingZeros + significantBytes.size)
        significantBytes.copyInto(decoded, destinationOffset = leadingZeros)
        require(decoded.size > BASE58_CHECKSUM_SIZE) {
            "$description address has an invalid Base58Check length"
        }

        val payload = decoded.copyOfRange(0, decoded.size - BASE58_CHECKSUM_SIZE)
        val checksum = decoded.copyOfRange(decoded.size - BASE58_CHECKSUM_SIZE, decoded.size)
        val expectedChecksum = doubleSha256(payload).copyOf(BASE58_CHECKSUM_SIZE)
        require(checksum.contentEquals(expectedChecksum)) {
            "$description address has an invalid checksum"
        }
        return payload
    }

    private fun encodeBase58Check(version: Int, payload: ByteArray): String {
        val versionedPayload = byteArrayOf(version.toByte()) + payload
        val encodedBytes = versionedPayload + doubleSha256(versionedPayload)
            .copyOf(BASE58_CHECKSUM_SIZE)
        var number = BigInteger(1, encodedBytes)
        val encoded = StringBuilder()
        while (number > BigInteger.ZERO) {
            val (quotient, remainder) = number.divideAndRemainder(base58Radix)
            encoded.append(base58Alphabet[remainder.toInt()])
            number = quotient
        }
        encodedBytes.takeWhile { it == 0.toByte() }.forEach {
            encoded.append(base58Alphabet.first())
        }
        return encoded.reverse().toString()
    }

    private fun decodeCashAddress(address: String): ScriptPayload {
        require(address.usesOneLetterCase()) {
            "Bitcoin Cash address mixes letter case"
        }
        val normalized = address.lowercase()
        val separatorIndex = normalized.indexOf(':')
        val prefix = if (separatorIndex >= 0) {
            normalized.substring(0, separatorIndex)
        } else {
            BITCOIN_CASH_MAINNET_PREFIX
        }
        require(prefix == BITCOIN_CASH_MAINNET_PREFIX) {
            "Bitcoin Cash address uses an unsupported network prefix"
        }
        val encodedPayload = if (separatorIndex >= 0) {
            normalized.substring(separatorIndex + 1)
        } else {
            normalized
        }
        require(encodedPayload.length > CASHADDR_CHECKSUM_SIZE) {
            "Bitcoin Cash address has an invalid CashAddr length"
        }
        val values = encodedPayload.map { character ->
            cashAddressAlphabet.indexOf(character).also { value ->
                require(value >= 0) {
                    "Bitcoin Cash address contains an invalid CashAddr character"
                }
            }
        }
        require(
            cashAddressPolymod(
                cashAddressPrefixExpand(prefix) + values
            ) == 0L
        ) {
            "Bitcoin Cash address has an invalid checksum"
        }

        val payloadValues = values.dropLast(CASHADDR_CHECKSUM_SIZE)
        val decoded = convertBits(
            values = payloadValues,
            fromBits = 5,
            toBits = 8,
            pad = false
        )
        require(decoded.isNotEmpty()) {
            "Bitcoin Cash address has an empty payload"
        }
        val version = decoded.first()
        require(version and CASHADDR_RESERVED_BIT == 0) {
            "Bitcoin Cash address uses a reserved version"
        }
        val type = version ushr 3
        require(type == BITCOIN_CASH_P2PKH_TYPE || type == BITCOIN_CASH_P2SH_TYPE) {
            "Bitcoin Cash address uses an unsupported script type"
        }
        val hash = decoded.drop(1).map(Int::toByte).toByteArray()
        val expectedHashSize = cashAddressHashSizes[version and 0x07]
        require(hash.size == expectedHashSize) {
            "Bitcoin Cash address payload size does not match its version"
        }
        return ScriptPayload(type = type, hash = hash)
    }

    private fun encodeCashAddress(scriptPayload: ScriptPayload): String {
        val sizeIndex = cashAddressHashSizes.indexOf(scriptPayload.hash.size)
        require(sizeIndex >= 0) {
            "Bitcoin Cash script payload has an unsupported hash size"
        }
        val version = (scriptPayload.type shl 3) or sizeIndex
        val payload = convertBits(
            values = listOf(version) + scriptPayload.hash.map { it.toInt() and 0xff },
            fromBits = 8,
            toBits = 5,
            pad = true
        )
        val checksumTemplate = cashAddressPrefixExpand(BITCOIN_CASH_MAINNET_PREFIX) +
            payload +
            List(CASHADDR_CHECKSUM_SIZE) { 0 }
        val polymod = cashAddressPolymod(checksumTemplate)
        val checksum = (0 until CASHADDR_CHECKSUM_SIZE).map { index ->
            ((polymod ushr (5 * (CASHADDR_CHECKSUM_SIZE - 1 - index))) and 31L).toInt()
        }
        val encodedPayload = (payload + checksum)
            .joinToString(separator = "") { cashAddressAlphabet[it].toString() }
        return "$BITCOIN_CASH_MAINNET_PREFIX:$encodedPayload"
    }

    private fun cashAddressPrefixExpand(prefix: String): List<Int> =
        prefix.map { it.code and 31 } + 0

    private fun cashAddressPolymod(values: List<Int>): Long {
        var checksum = 1L
        values.forEach { value ->
            val highBits = checksum ushr 35
            checksum = ((checksum and 0x07ffffffffL) shl 5) xor value.toLong()
            cashAddressGenerators.indices.forEach { index ->
                if ((highBits ushr index) and 1L != 0L) {
                    checksum = checksum xor cashAddressGenerators[index]
                }
            }
        }
        return checksum xor 1L
    }

    private fun convertBits(
        values: List<Int>,
        fromBits: Int,
        toBits: Int,
        pad: Boolean
    ): List<Int> {
        var accumulator = 0L
        var bitCount = 0
        val result = mutableListOf<Int>()
        val outputMask = (1 shl toBits) - 1
        val accumulatorMask = (1L shl (fromBits + toBits - 1)) - 1L

        values.forEach { value ->
            require(value >= 0 && value ushr fromBits == 0) {
                "Address payload has a value outside its bit group"
            }
            accumulator = ((accumulator shl fromBits) or value.toLong()) and accumulatorMask
            bitCount += fromBits
            while (bitCount >= toBits) {
                bitCount -= toBits
                result += ((accumulator ushr bitCount) and outputMask.toLong()).toInt()
            }
        }
        if (pad) {
            if (bitCount > 0) {
                result += ((accumulator shl (toBits - bitCount)) and outputMask.toLong()).toInt()
            }
        } else {
            require(
                bitCount < fromBits &&
                    ((accumulator shl (toBits - bitCount)) and outputMask.toLong()) == 0L
            ) {
                "Address payload has invalid padding"
            }
        }
        return result
    }

    private fun doubleSha256(value: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(digest.digest(value))
    }

    private fun String.usesOneLetterCase(): Boolean {
        val letters = filter(Char::isLetter)
        return letters.all(Char::isLowerCase) || letters.all(Char::isUpperCase)
    }
}
