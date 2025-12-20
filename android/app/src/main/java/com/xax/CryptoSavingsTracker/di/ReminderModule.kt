package com.xax.CryptoSavingsTracker.di

import com.xax.CryptoSavingsTracker.data.local.reminders.GoalReminderSchedulerImpl
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class ReminderModule {

    @Binds
    @Singleton
    abstract fun bindGoalReminderScheduler(
        impl: GoalReminderSchedulerImpl
    ): GoalReminderScheduler
}

