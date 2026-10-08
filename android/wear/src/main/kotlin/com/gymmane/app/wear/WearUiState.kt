package com.gymmane.app.wear

import android.content.Context

enum class WearMode { READY, STARTING, ACTIVE, PAUSED, DEGRADED, SUMMARY }

data class WearUiState(
    val mode: WearMode = WearMode.READY,
    val running: Boolean = false,
    val sessionId: String = "",
    val phase: String = "idle",
    val exerciseName: String = "",
    val setIndex: Int = 0,
    val setCount: Int = 0,
    val phaseStartedAt: Long = 0L,
    val restEndsAt: Long = 0L,
    val startedAt: Long = 0L,
    val completedAt: Long = 0L,
    val heartRate: Double? = null,
    val heartRateAverage: Double? = null,
    val heartRateMax: Double? = null,
    val calories: Double? = null,
    val sampleCount: Long = 0,
    val message: String = "",
    val updatedAt: Long = 0L
)

object WearUiStateStore {
    private const val FILE = "wear_ui_state"

    fun read(context: Context): WearUiState {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        return WearUiState(
            mode = runCatching { WearMode.valueOf(p.getString("mode", WearMode.READY.name)!!) }
                .getOrDefault(WearMode.READY),
            running = p.getBoolean("running", false),
            sessionId = p.getString("sessionId", "").orEmpty(),
            phase = p.getString("phase", "idle").orEmpty(),
            exerciseName = p.getString("exerciseName", "").orEmpty(),
            setIndex = p.getInt("setIndex", 0),
            setCount = p.getInt("setCount", 0),
            phaseStartedAt = p.getLong("phaseStartedAt", 0L),
            restEndsAt = p.getLong("restEndsAt", 0L),
            startedAt = p.getLong("startedAt", 0L),
            completedAt = p.getLong("completedAt", 0L),
            heartRate = p.readOptionalDouble("heartRate"),
            heartRateAverage = p.readOptionalDouble("heartRateAverage"),
            heartRateMax = p.readOptionalDouble("heartRateMax"),
            calories = p.readOptionalDouble("calories"),
            sampleCount = p.getLong("sampleCount", 0L),
            message = p.getString("message", "").orEmpty(),
            updatedAt = p.getLong("updatedAt", 0L)
        )
    }

    fun write(context: Context, state: WearUiState) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().apply {
            putString("mode", state.mode.name)
            putBoolean("running", state.running)
            putString("sessionId", state.sessionId)
            putString("phase", state.phase)
            putString("exerciseName", state.exerciseName)
            putInt("setIndex", state.setIndex)
            putInt("setCount", state.setCount)
            putLong("phaseStartedAt", state.phaseStartedAt)
            putLong("restEndsAt", state.restEndsAt)
            putLong("startedAt", state.startedAt)
            putLong("completedAt", state.completedAt)
            putOptionalDouble("heartRate", state.heartRate)
            putOptionalDouble("heartRateAverage", state.heartRateAverage)
            putOptionalDouble("heartRateMax", state.heartRateMax)
            putOptionalDouble("calories", state.calories)
            putLong("sampleCount", state.sampleCount)
            putString("message", state.message)
            putLong("updatedAt", System.currentTimeMillis())
        }.apply()
    }

    private fun android.content.SharedPreferences.readOptionalDouble(key: String): Double? =
        if (contains(key)) java.lang.Double.longBitsToDouble(getLong(key, 0L)) else null

    private fun android.content.SharedPreferences.Editor.putOptionalDouble(key: String, value: Double?) {
        if (value == null) remove(key) else putLong(key, java.lang.Double.doubleToRawLongBits(value))
    }
}
