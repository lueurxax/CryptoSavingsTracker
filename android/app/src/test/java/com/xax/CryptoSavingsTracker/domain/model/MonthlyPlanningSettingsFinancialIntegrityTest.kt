package com.xax.CryptoSavingsTracker.domain.model

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.jupiter.api.Test

class MonthlyPlanningSettingsFinancialIntegrityTest {
    @Test
    fun `monthly budget rejects values that overflow persisted float`() {
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val prefs = mockk<SharedPreferences> {
            every { edit() } returns editor
        }
        val settings = settings(prefs)

        val failure = runCatching {
            settings.monthlyBudget = Double.MAX_VALUE
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        verify(exactly = 0) { editor.putFloat(any(), any()) }
    }

    @Test
    fun `monthly budget fails closed for corrupted non-finite persisted float`() {
        val prefs = mockk<SharedPreferences> {
            every { contains("MonthlyPlanning.FixedBudget.MonthlyBudget") } returns true
            every {
                getFloat("MonthlyPlanning.FixedBudget.MonthlyBudget", 0f)
            } returns Float.POSITIVE_INFINITY
        }

        assertThat(settings(prefs).monthlyBudget).isNull()
    }

    private fun settings(prefs: SharedPreferences): MonthlyPlanningSettings {
        val context = mockk<Context> {
            every {
                getSharedPreferences("monthly_planning_settings", Context.MODE_PRIVATE)
            } returns prefs
        }
        return MonthlyPlanningSettings(context)
    }
}
