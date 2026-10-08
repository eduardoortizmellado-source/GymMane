package com.gymmane.app.wear

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.UUID

class WearMainActivity : Activity() {
    private lateinit var watchView: GymManeWatchView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        watchView = GymManeWatchView(this).apply {
            onPrimaryAction = { handlePrimaryAction() }
            onSecondaryAction = { finishCapture() }
            onRunningChanged = { running ->
                val attributes = window.attributes
                if (running) {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    attributes.screenBrightness = ACTIVE_SCREEN_BRIGHTNESS
                } else {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    attributes.screenBrightness = android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                }
                window.attributes = attributes
            }
        }
        setContentView(watchView)
        requestHealthPermissions()
    }

    override fun onResume() {
        super.onResume()
        watchView.startRefreshing()
    }

    override fun onPause() {
        watchView.stopRefreshing()
        super.onPause()
    }

    private fun requestHealthPermissions() {
        val permissions = buildList {
            add(Manifest.permission.ACTIVITY_RECOGNITION)
            if (Build.VERSION.SDK_INT >= 36) {
                add("android.permission.health.READ_HEART_RATE")
            } else {
                add(Manifest.permission.BODY_SENSORS)
            }
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (permissions.isNotEmpty()) ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 41)
    }

    private fun handlePrimaryAction() {
        val state = WearUiStateStore.read(this)
        if (state.mode == WearMode.DEGRADED && state.running) {
            WearUiStateStore.write(this, state.copy(mode = WearMode.ACTIVE))
            watchView.refreshNow()
            return
        }
        val intent = Intent(this, WatchCaptureService::class.java)
        when {
            state.mode == WearMode.PAUSED -> intent.action = WatchCaptureService.ACTION_RESUME
            state.running -> intent.action = WatchCaptureService.ACTION_PAUSE
            else -> {
                intent.action = WatchCaptureService.ACTION_START
                intent.putExtra(WatchCaptureService.EXTRA_SESSION_ID, UUID.randomUUID().toString())
            }
        }
        ContextCompat.startForegroundService(this, intent)
        watchView.refreshNow()
    }

    private fun finishCapture() {
        val state = WearUiStateStore.read(this)
        if (!state.running) return
        ContextCompat.startForegroundService(
            this,
            Intent(this, WatchCaptureService::class.java).apply { action = WatchCaptureService.ACTION_STOP }
        )
        watchView.refreshNow()
    }

    companion object {
        private const val ACTIVE_SCREEN_BRIGHTNESS = 0.22f
    }
}
