package com.xax.CryptoSavingsTracker.domain.model

/**
 * Execution record lifecycle.
 */
enum class ExecutionStatus(val rawValue: String) {
    DRAFT("draft"),
    EXECUTING("executing"),
    CLOSED("closed");

    companion object {
        fun fromString(value: String): ExecutionStatus {
            return entries.find { it.rawValue.equals(value, ignoreCase = true) } ?: DRAFT
        }
    }
}

