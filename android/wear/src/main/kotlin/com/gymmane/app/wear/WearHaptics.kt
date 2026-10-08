package com.gymmane.app.wear

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object WearHaptics {
    fun captureStarted(context: Context) = pulse(context, longArrayOf(0, 90), intArrayOf(0, 190))
    fun setStarted(context: Context) = pulse(context, longArrayOf(0, 65), intArrayOf(0, 210))
    fun restStarted(context: Context) = pulse(context, longArrayOf(0, 45, 70, 45), intArrayOf(0, 150, 0, 150))
    fun restFinished(context: Context) = pulse(context, longArrayOf(0, 160, 100, 240), intArrayOf(0, 255, 0, 255))
    fun paused(context: Context) = pulse(context, longArrayOf(0, 70, 60, 70), intArrayOf(0, 170, 0, 170))
    fun resumed(context: Context) = pulse(context, longArrayOf(0, 110), intArrayOf(0, 190))
    fun completed(context: Context) = pulse(
        context,
        longArrayOf(0, 70, 55, 70, 55, 180),
        intArrayOf(0, 170, 0, 190, 0, 230)
    )
    fun error(context: Context) = pulse(context, longArrayOf(0, 230, 110, 230), intArrayOf(0, 230, 0, 230))

    private fun pulse(context: Context, timings: LongArray, amplitudes: IntArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }
}
