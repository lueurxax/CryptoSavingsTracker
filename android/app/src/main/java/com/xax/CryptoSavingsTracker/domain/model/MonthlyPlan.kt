package com.xax.CryptoSavingsTracker.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MonthlyPlanStatus {
    @SerialName("draft")
    DRAFT,

    @SerialName("executing")
    EXECUTING,

    @SerialName("closed")
    CLOSED;

    companion object {
        fun fromString(value: String?): MonthlyPlanStatus = when (value?.lowercase()) {
            "executing" -> EXECUTING
            "closed" -> CLOSED
            else -> DRAFT
        }
    }
}

@Serializable
data class MonthlyPlanGoalSettings(
    val isProtected: Boolean = false,
    val isSkipped: Boolean = false,
    val customAmount: Double? = null
)

@Serializable
data class MonthlyPlanSettings(
    val perGoal: Map<String, MonthlyPlanGoalSettings> = emptyMap()
)

data class MonthlyPlan(
    val id: String,
    val monthLabel: String,
    val status: MonthlyPlanStatus,
    val flexPercentage: Double,
    val totalRequired: Double,
    val settings: MonthlyPlanSettings,
    val createdAtUtcMillis: Long,
    val lastModifiedAtUtcMillis: Long
)

