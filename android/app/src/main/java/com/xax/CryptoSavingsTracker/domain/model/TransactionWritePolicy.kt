package com.xax.CryptoSavingsTracker.domain.model

/**
 * Financial invariants for transaction writes.
 *
 * Manual transaction dates selected in the UI are date-only values, while persistence uses
 * instants. A small forward-clock tolerance prevents a device clock tick between layers from
 * rejecting today's transaction; accepted future instants are normalized back to the commit
 * time so they never inflate the current balance.
 */
internal object TransactionWritePolicy {
    private const val MANUAL_CLOCK_TOLERANCE_MILLIS = 60_000L

    fun normalizeForPersistence(
        transaction: Transaction,
        nowMillis: Long = System.currentTimeMillis()
    ): Transaction {
        require(transaction.amount.isFinite()) {
            "Transaction amount must be finite"
        }
        require(transaction.amount != 0.0) {
            "Transaction amount must be non-zero"
        }

        if (transaction.source != TransactionSource.MANUAL) {
            return transaction
        }

        require(transaction.dateMillis <= nowMillis + MANUAL_CLOCK_TOLERANCE_MILLIS) {
            "Manual transaction date cannot be in the future"
        }
        return if (transaction.dateMillis > nowMillis) {
            transaction.copy(dateMillis = nowMillis)
        } else {
            transaction
        }
    }

    fun requireMetadataOnlyUpdate(
        original: Transaction,
        candidate: Transaction
    ) {
        check(original.source == TransactionSource.MANUAL) {
            "Only manual transaction metadata can be edited"
        }
        check(candidate.id == original.id) {
            "Transaction identity cannot be changed"
        }
        check(candidate.assetId == original.assetId) {
            "Transaction asset cannot be changed"
        }
        check(candidate.amount.toBits() == original.amount.toBits()) {
            "Transaction amount cannot be changed because automatic allocation provenance is unavailable"
        }
        check(candidate.dateMillis == original.dateMillis) {
            "Transaction date cannot be changed because automatic allocation provenance is unavailable"
        }
        check(candidate.source == original.source) {
            "Transaction source cannot be changed"
        }
        check(candidate.externalId == original.externalId) {
            "Transaction external identity cannot be changed"
        }
        check(candidate.createdAt == original.createdAt) {
            "Transaction creation time cannot be changed"
        }
    }

    fun requireDeletionAllowed(transaction: Transaction) {
        check(transaction.source != TransactionSource.MANUAL) {
            "Manual transaction cannot be deleted because automatic allocation provenance is unavailable"
        }
    }
}
