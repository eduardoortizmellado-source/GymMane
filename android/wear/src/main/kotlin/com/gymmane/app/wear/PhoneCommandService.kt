package com.gymmane.app.wear

import android.content.Intent
import androidx.core.content.ContextCompat
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
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
        handleCommand(command, String(event.data, Charsets.UTF_8), System.currentTimeMillis())
    }

    override fun onDataChanged(events: DataEventBuffer) {
        val commands = events
            .filter { it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path?.startsWith(CONTROL_PATH) == true }
            .map { event ->
                val map = DataMapItem.fromDataItem(event.dataItem).dataMap
                DurableCommand(
                    command = map.getString("command").orEmpty(),
                    payload = map.getString("payload").orEmpty(),
                    issuedAt = map.getLong("issuedAt"),
                    uri = event.dataItem.uri
                )
            }
            .sortedBy { it.issuedAt }
        commands.forEach { item ->
            handleCommand(item.command, item.payload, item.issuedAt)
            Wearable.getDataClient(this).deleteDataItems(item.uri)
        }
    }

    private fun handleCommand(command: String, payload: String, issuedAt: Long) {
        val previous = WearUiStateStore.read(this)
        if (issuedAt < previous.lastControlAt) return
        if (command == "state") {
            updateWorkoutState(payload, issuedAt)
            return
        }
        WearUiStateStore.write(this, previous.copy(lastControlAt = issuedAt))
        val capture = Intent(this, WatchCaptureService::class.java).apply {
            action = when (command) {
                "start" -> WatchCaptureService.ACTION_START
                "pause" -> WatchCaptureService.ACTION_PAUSE
                "resume" -> WatchCaptureService.ACTION_RESUME
                "stop" -> WatchCaptureService.ACTION_STOP
                else -> return
            }
            putExtra(WatchCaptureService.EXTRA_SESSION_ID, payload)
        }
        ContextCompat.startForegroundService(this, capture)
    }

    private fun updateWorkoutState(payload: String, issuedAt: Long) {
        runCatching {
            val json = JSONObject(payload)
            val previous = WearUiStateStore.read(this)
            val incomingSession = json.optString("sessionId")
            if (previous.sessionId.isNotBlank() && incomingSession.isNotBlank() && previous.sessionId != incomingSession) {
                return
            }
            val nextPhase = json.optString("phase", "idle")
            when {
                nextPhase == "set" && previous.phase != "set" -> WearHaptics.setStarted(this)
                nextPhase == "rest" && previous.phase != "rest" -> WearHaptics.restStarted(this)
                nextPhase == "idle" && previous.phase == "rest" -> WearHaptics.restFinished(this)
            }
            WearUiStateStore.write(
                this,
                previous.copy(
                    sessionId = incomingSession.ifBlank { previous.sessionId },
                    phase = nextPhase,
                    exerciseName = json.optString("exerciseName"),
                    setIndex = json.optInt("setIndex"),
                    setCount = json.optInt("setCount"),
                    phaseStartedAt = json.optLong("phaseStartedAt"),
                    restEndsAt = json.optLong("restEndsAt"),
                    lastControlAt = issuedAt
                )
            )
        }
    }

    companion object {
        private const val COMMAND_PATH = "/gymmane/command/v1/"
        private const val ACK_PATH = "/gymmane/ack/v1/"
        private const val CONTROL_PATH = "/gymmane/control/v1/"
    }

    private data class DurableCommand(
        val command: String,
        val payload: String,
        val issuedAt: Long,
        val uri: android.net.Uri
    )
}
