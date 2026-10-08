package com.gymmane.app.personal

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.io.File
import org.json.JSONObject

class WearTelemetryService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        events.forEach { event ->
            if (event.type != DataEvent.TYPE_CHANGED) return@forEach
            val path = event.dataItem.uri.path.orEmpty()
            if (!path.startsWith("/gymmane/telemetry/v1/")) return@forEach
            val payload = DataMapItem.fromDataItem(event.dataItem).dataMap.getString("payload")
                ?: return@forEach
            if (storePayload(payload)) {
                val decoded = JSONObject(payload)
                val sessionId = decoded.getString("sessionId")
                val sequence = decoded.getLong("sequence")
                event.dataItem.uri.host?.let { nodeId ->
                    Wearable.getMessageClient(this).sendMessage(
                        nodeId,
                        "/gymmane/ack/v1/$sessionId/$sequence",
                        ByteArray(0),
                    )
                }
                Wearable.getDataClient(this).deleteDataItems(event.dataItem.uri)
            }
        }
    }

    private fun storePayload(raw: String): Boolean = runCatching {
        val payload = JSONObject(raw)
        if (payload.optInt("protocol") != 1) return false
        val sessionId = payload.getString("sessionId")
        val dbFile = File(applicationInfo.dataDir, "databases/gymmane_health_v1.db")
        if (!dbFile.exists()) return false
        val db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
        db.beginTransaction()
        try {
            val samples = payload.getJSONArray("samples")
            for (index in 0 until samples.length()) {
                val sample = samples.getJSONObject(index)
                val values = ContentValues().apply {
                    put("session_id", sessionId)
                    put("at", sample.getLong("t"))
                    putNullableDouble("heart_rate", sample, "hr")
                    putNullableDouble("calories_total", sample, "caloriesTotal")
                    putNullableDouble("accel_rms", sample, "accelMean")
                    putNullableDouble("accel_variance", sample, "accelVariance")
                    putNullableDouble("gyro_rms", sample, "gyroMean")
                }
                db.insertWithOnConflict(
                    "sensor_sample",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE,
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
            db.close()
        }
        true
    }.getOrDefault(false)

    private fun ContentValues.putNullableDouble(column: String, json: JSONObject, key: String) {
        if (json.isNull(key)) putNull(column) else put(column, json.optDouble(key))
    }
}
