package com.gymmane.app.wear

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.UUID

class WearMainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var action: Button
    private var running = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(24, 16, 24, 16)
            setBackgroundColor(Color.BLACK)
        }
        status = TextView(this).apply {
            text = "Sensor listo"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }
        action = Button(this).apply {
            text = "Iniciar prueba"
            setOnClickListener { toggleCapture() }
        }
        root.addView(status)
        root.addView(action)
        setContentView(root)
        requestHealthPermissions()
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

    private fun toggleCapture() {
        val intent = Intent(this, WatchCaptureService::class.java)
        if (!running) {
            intent.action = WatchCaptureService.ACTION_START
            intent.putExtra(WatchCaptureService.EXTRA_SESSION_ID, UUID.randomUUID().toString())
            ContextCompat.startForegroundService(this, intent)
            status.text = "Capturando FC y movimiento"
            action.text = "Finalizar"
        } else {
            intent.action = WatchCaptureService.ACTION_STOP
            startService(intent)
            status.text = "Datos guardados y pendientes de sincronizar"
            action.text = "Iniciar prueba"
        }
        running = !running
    }
}
