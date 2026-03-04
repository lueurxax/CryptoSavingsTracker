package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.CycleConflictReason
import com.xax.CryptoSavingsTracker.domain.model.PlanningSource
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonthlyCycleActionGateTest {

    @Test
    fun planning_finish_isBlockedWithNoExecutingCopy() {
        val state = UiCycleState.Planning(monthLabel = "2026-03", source = PlanningSource.CURRENT_MONTH)

        val decision = MonthlyCycleActionGate.evaluate(state, MonthlyCycleAction.FINISH_MONTH)

        assertFalse(decision.allowed)
        assertEquals(MonthlyCycleBlockedCopyKey.FINISH_BLOCKED_NO_EXECUTING, decision.blockedCopyKey)
    }

    @Test
    fun executing_start_isBlockedWithAlreadyExecutingCopy() {
        val state = UiCycleState.Executing(
            monthLabel = "2026-03",
            canFinish = true,
            canUndoStart = true
        )

        val decision = MonthlyCycleActionGate.evaluate(state, MonthlyCycleAction.START_TRACKING)

        assertFalse(decision.allowed)
        assertEquals(MonthlyCycleBlockedCopyKey.START_BLOCKED_ALREADY_EXECUTING, decision.blockedCopyKey)
    }

    @Test
    fun executing_undoStart_respectsUndoWindow() {
        val undoAllowedState = UiCycleState.Executing(
            monthLabel = "2026-03",
            canFinish = true,
            canUndoStart = true
        )
        val undoExpiredState = UiCycleState.Executing(
            monthLabel = "2026-03",
            canFinish = true,
            canUndoStart = false
        )

        val allowedDecision = MonthlyCycleActionGate.evaluate(undoAllowedState, MonthlyCycleAction.UNDO_START)
        val blockedDecision = MonthlyCycleActionGate.evaluate(undoExpiredState, MonthlyCycleAction.UNDO_START)

        assertTrue(allowedDecision.allowed)
        assertFalse(blockedDecision.allowed)
        assertEquals(MonthlyCycleBlockedCopyKey.UNDO_START_EXPIRED, blockedDecision.blockedCopyKey)
    }

    @Test
    fun closed_undoCompletion_respectsUndoWindow() {
        val undoAllowedState = UiCycleState.Closed(monthLabel = "2026-03", canUndoCompletion = true)
        val undoExpiredState = UiCycleState.Closed(monthLabel = "2026-03", canUndoCompletion = false)

        val allowedDecision = MonthlyCycleActionGate.evaluate(undoAllowedState, MonthlyCycleAction.UNDO_COMPLETION)
        val blockedDecision = MonthlyCycleActionGate.evaluate(undoExpiredState, MonthlyCycleAction.UNDO_COMPLETION)

        assertTrue(allowedDecision.allowed)
        assertFalse(blockedDecision.allowed)
        assertEquals(MonthlyCycleBlockedCopyKey.UNDO_COMPLETION_EXPIRED, blockedDecision.blockedCopyKey)
    }

    @Test
    fun conflict_blocksAnyAction() {
        val state = UiCycleState.Conflict(
            monthLabel = "2026-03",
            reason = CycleConflictReason.DUPLICATE_ACTIVE_RECORDS
        )

        val decision = MonthlyCycleActionGate.evaluate(state, MonthlyCycleAction.START_TRACKING)

        assertFalse(decision.allowed)
        assertEquals(MonthlyCycleBlockedCopyKey.RECORD_CONFLICT, decision.blockedCopyKey)
    }
}
