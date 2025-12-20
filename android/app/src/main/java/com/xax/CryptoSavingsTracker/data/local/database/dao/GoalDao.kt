package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface GoalDao {

    @Query("SELECT * FROM goals ORDER BY deadline_epoch_day ASC")
    fun getAllGoals(): Flow<List<GoalEntity>>

    @Query("SELECT * FROM goals WHERE lifecycle_status = 'active' ORDER BY deadline_epoch_day ASC")
    fun getActiveGoals(): Flow<List<GoalEntity>>

    @Query("SELECT * FROM goals WHERE lifecycle_status = :status ORDER BY deadline_epoch_day ASC")
    fun getGoalsByStatus(status: String): Flow<List<GoalEntity>>

    @Query("SELECT * FROM goals WHERE id = :id")
    fun getGoalById(id: String): Flow<GoalEntity?>

    @Query("SELECT * FROM goals WHERE id = :id")
    suspend fun getGoalByIdOnce(id: String): GoalEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(goal: GoalEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(goals: List<GoalEntity>)

    @Update
    suspend fun update(goal: GoalEntity)

    @Delete
    suspend fun delete(goal: GoalEntity)

    @Query("DELETE FROM goals WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE goals SET lifecycle_status = :status, lifecycle_status_changed_at_utc_millis = :changedAt, last_modified_at_utc_millis = :modifiedAt WHERE id = :id")
    suspend fun updateLifecycleStatus(id: String, status: String, changedAt: Long, modifiedAt: Long)

    @Query("SELECT COUNT(*) FROM goals")
    suspend fun getGoalCount(): Int

    @Query("SELECT COUNT(*) FROM goals WHERE lifecycle_status = 'active'")
    suspend fun getActiveGoalCount(): Int
}
