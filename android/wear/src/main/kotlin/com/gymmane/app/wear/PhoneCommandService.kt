package com.gymmane.app.wear

import android.content.Intent
import androidx.core.content.ContextCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import java.io.File

class PhoneCommandService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path.startsWith(ACK_PATH)) {
            val parts = event.path.removePrefix(ACK_PATH).split('/')
            if (parts.size == 2) {
                File(filesDir, "telemetry/${parts[0]}/${parts[1]}.json").delete()
            }
            return
        }
        if (!event.path.startsWith(COMMAND_PATH)) return
        val command = event.path.substringAfterLast('/')
        val capture = Intent(this, WatchCaptureService::class.java).apply {
            action = when (command) {
                "start" -> WatchCaptureService.ACTION_START
                "pause" -> WatchCaptureService.ACTION_PAUSE
                "resume" -> WatchCaptureService.ACTION_RESUME
                "stop" -> WatchCaptureService.ACTION_STOP
                else -> return
            }
            if (command == "start") {
                putExtra(WatchCaptureService.EXTRA_SESSION_ID, String(event.data, Charsets.UTF_8))
            }
        }
        ContextCompat.startForegroundService(this, capture)
    }

    companion object {
        private const val COMMAND_PATH = "/gymmane/command/v1/"
        private const val ACK_PATH = "/gymmane/ack/v1/"
    }
}
