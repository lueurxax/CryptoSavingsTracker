package com.xax.CryptoSavingsTracker.presentation.common

import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

open class DeadlineTimeSource @Inject constructor() {
    open fun nowMillis(): Long = System.currentTimeMillis()
}

/**
 * Emits immediately and again at each persisted deadline. Repository state
 * does not need to change for consumers to revoke an expired action.
 */
internal fun deadlineInvalidationFlow(
    deadlinesMillis: Collection<Long>,
    timeSource: DeadlineTimeSource
): Flow<Long> = flow {
    val deadlines = deadlinesMillis
        .filter { it > 0L }
        .distinct()
        .sorted()
    var now = timeSource.nowMillis()
    emit(now)

    while (true) {
        val nextDeadline = deadlines.firstOrNull { deadline -> deadline > now } ?: return@flow
        delay(nextDeadline - now)
        now = timeSource.nowMillis()
        emit(now)
    }
}
