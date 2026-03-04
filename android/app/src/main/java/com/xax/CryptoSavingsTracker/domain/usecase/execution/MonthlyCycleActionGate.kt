package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.UiCycleState

enum class MonthlyCycleAction {
    START_TRACKING,
    FINISH_MONTH,
    UNDO_START,
    UNDO_COMPLETION
}

enum class MonthlyCycleBlockedCopyKey {
    START_BLOCKED_ALREADY_EXECUTING,
    START_BLOCKED_CLOSED_MONTH,
    FINISH_BLOCKED_NO_EXECUTING,
    UNDO_START_EXPIRED,
    UNDO_COMPLETION_EXPIRED,
    RECORD_CONFLICT
}

data class MonthlyCycleActionDecision(
    val allowed: Boolean,
    val blockedCopyKey: MonthlyCycleBlockedCopyKey? = null,
    val blockedMessage: String? = null
)

object MonthlyCycleActionGate {
    fun evaluate(state: UiCycleState, action: MonthlyCycleAction): MonthlyCycleActionDecision {
        return when (state) {
            is UiCycleState.Planning -> {
                val month = state.monthLabel
                when (action) {
                    MonthlyCycleAction.START_TRACKING -> MonthlyCycleActionDecision(allowed = true)
                    MonthlyCycleAction.FINISH_MONTH -> blocked(
                        MonthlyCycleBlockedCopyKey.FINISH_BLOCKED_NO_EXECUTING,
                        ExecutionActionCopyCatalog.finishBlockedNoExecuting()
                    )
                    MonthlyCycleAction.UNDO_START -> blocked(
                        MonthlyCycleBlockedCopyKey.UNDO_START_EXPIRED,
                        ExecutionActionCopyCatalog.undoStartExpired(month)
                    )
                    MonthlyCycleAction.UNDO_COMPLETION -> blocked(
                        MonthlyCycleBlockedCopyKey.UNDO_COMPLETION_EXPIRED,
                        ExecutionActionCopyCatalog.undoCompletionExpired(month)
                    )
                }
            }

            is UiCycleState.Executing -> {
                val month = state.monthLabel
                when (action) {
                    MonthlyCycleAction.START_TRACKING -> blocked(
                        MonthlyCycleBlockedCopyKey.START_BLOCKED_ALREADY_EXECUTING,
                        ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(month)
                    )
                    MonthlyCycleAction.FINISH_MONTH -> MonthlyCycleActionDecision(allowed = true)
                    MonthlyCycleAction.UNDO_START -> {
                        if (state.canUndoStart) {
                            MonthlyCycleActionDecision(allowed = true)
                        } else {
                            blocked(
                                MonthlyCycleBlockedCopyKey.UNDO_START_EXPIRED,
                                ExecutionActionCopyCatalog.undoStartExpired(month)
                            )
                        }
                    }
                    MonthlyCycleAction.UNDO_COMPLETION -> blocked(
                        MonthlyCycleBlockedCopyKey.UNDO_COMPLETION_EXPIRED,
                        ExecutionActionCopyCatalog.undoCompletionExpired(month)
                    )
                }
            }

            is UiCycleState.Closed -> {
                val month = state.monthLabel
                when (action) {
                    MonthlyCycleAction.START_TRACKING -> blocked(
                        MonthlyCycleBlockedCopyKey.START_BLOCKED_CLOSED_MONTH,
                        ExecutionActionCopyCatalog.startBlockedClosedMonth()
                    )
                    MonthlyCycleAction.FINISH_MONTH -> blocked(
                        MonthlyCycleBlockedCopyKey.FINISH_BLOCKED_NO_EXECUTING,
                        ExecutionActionCopyCatalog.finishBlockedNoExecuting()
                    )
                    MonthlyCycleAction.UNDO_START -> blocked(
                        MonthlyCycleBlockedCopyKey.UNDO_START_EXPIRED,
                        ExecutionActionCopyCatalog.undoStartExpired(month)
                    )
                    MonthlyCycleAction.UNDO_COMPLETION -> {
                        if (state.canUndoCompletion) {
                            MonthlyCycleActionDecision(allowed = true)
                        } else {
                            blocked(
                                MonthlyCycleBlockedCopyKey.UNDO_COMPLETION_EXPIRED,
                                ExecutionActionCopyCatalog.undoCompletionExpired(month)
                            )
                        }
                    }
                }
            }

            is UiCycleState.Conflict -> blocked(
                MonthlyCycleBlockedCopyKey.RECORD_CONFLICT,
                ExecutionActionCopyCatalog.recordConflict()
            )
        }
    }

    private fun blocked(
        key: MonthlyCycleBlockedCopyKey,
        message: String
    ): MonthlyCycleActionDecision {
        return MonthlyCycleActionDecision(
            allowed = false,
            blockedCopyKey = key,
            blockedMessage = message
        )
    }
}
