package com.gymmane.app.personal

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

object WearBridge {
    @JvmStatic
    fun send(context: Context, command: String, sessionId: String): Boolean {
        if (command !in setOf("start", "pause", "resume", "stop", "state")) return false
        val issuedAt = System.currentTimeMillis()
        Wearable.getNodeClient(context).connectedNodes.addOnSuccessListener { nodes ->
            val bytes = sessionId.toByteArray(Charsets.UTF_8)
            nodes.forEach { node ->
                Wearable.getMessageClient(context)
                    .sendMessage(node.id, "/gymmane/command/v1/$command", bytes)
            }
        }
        val durable = PutDataMapRequest.create("/gymmane/control/v1/$issuedAt-$command").apply {
            dataMap.putString("command", command)
            dataMap.putString("payload", sessionId)
            dataMap.putLong("issuedAt", issuedAt)
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(context).putDataItem(durable)
        return true
    }
}
