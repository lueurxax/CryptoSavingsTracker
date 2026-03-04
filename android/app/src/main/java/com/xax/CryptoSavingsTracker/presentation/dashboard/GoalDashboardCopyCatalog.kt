package com.xax.CryptoSavingsTracker.presentation.dashboard

object GoalDashboardCopyCatalog {
    const val hardErrorUserMessage: String =
        "We could not refresh goal data. Retry now or review diagnostics."

    private val values: Map<String, String> = mapOf(
        "dashboard.nextAction.hardError.reason" to "Data sync failed. Retry now or inspect diagnostics.",
        "dashboard.nextAction.hardError.nextStep" to "Retry sync first. If it still fails, verify connection and currency rates.",
        "dashboard.nextAction.finished.reason" to "This goal is closed. Review history or create a new goal.",
        "dashboard.nextAction.paused.reason" to "This goal is paused. Resume tracking to continue progress.",
        "dashboard.nextAction.overAllocated.reason" to "Allocated amounts exceed available balance on at least one asset.",
        "dashboard.nextAction.noAssets.reason" to "No assets are linked to this goal yet.",
        "dashboard.nextAction.noContributions.reason" to "No contributions were recorded this month.",
        "dashboard.nextAction.stale.reason" to "Dashboard data is stale. Refresh before making decisions.",
        "dashboard.nextAction.behind.reason" to "Current pace is below target. Plan this month now.",
        "dashboard.nextAction.onTrack.reason" to "Goal is on track. Log your next contribution.",
        "dashboard.forecast.empty" to "Forecast needs more activity data."
    )

    fun text(key: String): String = values[key] ?: key

    // DASH-COPY-ERR-001: diagnostics copy quality checklist.
    fun diagnosticsChecklistViolations(): List<String> {
        val violations = mutableListOf<String>()
        val reason = text("dashboard.nextAction.hardError.reason")
        val nextStep = text("dashboard.nextAction.hardError.nextStep")
        val userMessage = hardErrorUserMessage

        if (containsInternalJargon(reason) || containsInternalJargon(nextStep) || containsInternalJargon(userMessage)) {
            violations.add("copy contains internal jargon")
        }
        if (reason.substringBefore(".").isBlank()) {
            violations.add("reason copy is missing a concise user-facing sentence")
        }
        if (!startsWithVerb(nextStep)) {
            violations.add("next-step guidance must start with a verb")
        }
        if (containsVagueError(reason) && !startsWithVerb(nextStep)) {
            violations.add("vague error copy must be followed by actionable next step")
        }
        return violations
    }

    private fun containsInternalJargon(text: String): Boolean {
        val lowered = text.lowercase()
        val forbidden = listOf("viewmodel", "service", "repository", "stacktrace", "exception", "nserror")
        return forbidden.any { lowered.contains(it) }
    }

    private fun containsVagueError(text: String): Boolean {
        val lowered = text.lowercase()
        return lowered.contains("unknown error") || lowered.contains("unexpected issue")
    }

    private fun startsWithVerb(text: String): Boolean {
        val verbs = setOf("retry", "verify", "check", "open", "refresh", "reconnect", "inspect")
        val firstWord = text.trim().split(Regex("\\s+")).firstOrNull()?.lowercase() ?: return false
        return verbs.contains(firstWord)
    }
}
