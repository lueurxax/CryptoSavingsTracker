package com.xax.CryptoSavingsTracker.data.local.database

import android.content.Context
import androidx.room.Room

object TestDatabaseFactory {
    fun create(context: Context): AppDatabase {
        return Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }
}

