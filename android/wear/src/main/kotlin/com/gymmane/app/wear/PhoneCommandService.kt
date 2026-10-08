package com.gymmane.app.wear

import android.content.Intent
import androidx.core.content.ContextCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import java.io.File
import org.json.JSONObject

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
        if (command == "state") {
            updateWorkoutState(String(event.data, Charsets.UTF_8))
            return
        }
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

    private fun updateWorkoutState(payload: String) {
        runCatching {
            val json = JSONObject(payload)
            val previous = WearUiStateStore.read(this)
            val incomingSession = json.optString("sessionId")
            if (previous.sessionId.isNotBlank() && incomingSession.isNotBlank() && previous.sessionId != incomingSession) {
                return
            }
            WearUiStateStore.write(
                this,
                previous.copy(
                    sessionId = incomingSession.ifBlank { previous.sessionId },
                    phase = json.optString("phase", "idle"),
                    exerciseName = json.optString("exerciseName"),
                    setIndex = json.optInt("setIndex"),
                    setCount = json.optInt("setCount"),
                    phaseStartedAt = json.optLong("phaseStartedAt"),
                    restEndsAt = json.optLong("restEndsAt")
                )
            )
        }
    }

    companion object {
        private const val COMMAND_PATH = "/gymmane/command/v1/"
        private const val ACK_PATH = "/gymmane/ack/v1/"
    }
}
