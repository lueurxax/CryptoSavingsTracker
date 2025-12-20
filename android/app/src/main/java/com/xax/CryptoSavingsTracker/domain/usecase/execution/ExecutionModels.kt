package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot

data class ExecutionGoalProgress(
    val snapshot: ExecutionSnapshot,
    val baselineFunded: Double,
    val currentFunded: Double,
    val deltaSinceStart: Double
)

data class ExecutionSession(
    val record: ExecutionRecord,
    val goals: List<ExecutionGoalProgress>
)
