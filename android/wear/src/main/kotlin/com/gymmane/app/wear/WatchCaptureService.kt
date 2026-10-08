package com.gymmane.app.wear

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.endExercise
import androidx.health.services.client.getCapabilities
import androidx.health.services.client.pauseExercise
import androidx.health.services.client.resumeExercise
import androidx.health.services.client.startExercise
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.io.File
import kotlin.math.sqrt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class WatchCaptureService : Service(), SensorEventListener {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val exerciseClient by lazy { HealthServices.getClient(this).exerciseClient }
    private val sensorManager by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }
    private var sessionId = ""
    private var sequence = 0L
    private var running = false
    private var paused = false
    private var heartRate: Double? = null
    private var totalCalories: Double? = null
    private var heartRateTotal = 0.0
    private var heartRateCount = 0L
    private var heartRateMax: Double? = null
    private var accelEnergy = 0.0
    private var accelSquareEnergy = 0.0
    private var gyroEnergy = 0.0
    private var accelCount = 0
    private var gyroCount = 0
    private var startedElapsed = 0L
    private var samplingJob: Job? = null
    private val batch = JSONArray()

    private val exerciseCallback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            readHealthMetrics(update.latestMetrics)
        }

        override fun onLapSummaryReceived(summary: ExerciseLapSummary) = Unit
        override fun onRegistered() = Unit
        override fun onRegistrationFailed(throwable: Throwable) {
            writeStatus("health_error", throwable.message ?: "registration_failed")
            updateUi(WearMode.DEGRADED, throwable.message ?: "No se pudo iniciar el sensor")
        }

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
            writeStatus("availability", "$dataType:$availability")
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        exerciseClient.setUpdateCallback(exerciseCallback)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startCapture(intent.getStringExtra(EXTRA_SESSION_ID).orEmpty())
            ACTION_PAUSE -> pauseCapture()
            ACTION_RESUME -> resumeCapture()
            ACTION_STOP -> stopCapture()
        }
        return START_STICKY
    }

    private fun startCapture(requestedSessionId: String) {
        if (running) return
        sessionId = requestedSessionId.ifBlank { java.util.UUID.randomUUID().toString() }
        sequence = 0
        startedElapsed = SystemClock.elapsedRealtime()
        val startedWall = System.currentTimeMillis()
        running = true
        paused = false
        heartRate = null
        totalCalories = null
        heartRateTotal = 0.0
        heartRateCount = 0L
        heartRateMax = null
        val previousUi = WearUiStateStore.read(this)
        WearUiStateStore.write(
            this,
            previousUi.copy(
                mode = WearMode.STARTING,
                running = true,
                sessionId = sessionId,
                startedAt = startedWall,
                completedAt = 0L
            )
        )
        postNotification("Capturando entrenamiento")
        registerMotionSensors()
        scope.launch {
            try {
                val capabilities = exerciseClient.getCapabilities()
                val workout = capabilities.getExerciseTypeCapabilities(ExerciseType.WORKOUT)
                val requested = setOf(DataType.HEART_RATE_BPM, DataType.CALORIES_TOTAL)
                    .intersect(workout.supportedDataTypes)
                exerciseClient.startExercise(
                    ExerciseConfig(
                        exerciseType = ExerciseType.WORKOUT,
                        dataTypes = requested,
                        isAutoPauseAndResumeEnabled = false,
                        isGpsEnabled = false
                    )
                )
                writeStatus("started", "ok")
                updateUi(WearMode.ACTIVE)
            } catch (error: Throwable) {
                writeStatus("health_error", error.message ?: error.javaClass.simpleName)
                updateUi(WearMode.DEGRADED, error.message ?: "Sensor de salud no disponible")
            }
        }
        samplingJob = scope.launch {
            while (running) {
                delay(1000)
                if (!paused) captureSecond()
            }
        }
    }

    private fun pauseCapture() {
        if (!running || paused) return
        paused = true
        updateUi(WearMode.PAUSED)
        scope.launch {
            runCatching { exerciseClient.pauseExercise() }
            flushBatch("pause")
        }
    }

    private fun resumeCapture() {
        if (!running || !paused) return
        paused = false
        updateUi(WearMode.ACTIVE)
        scope.launch { runCatching { exerciseClient.resumeExercise() } }
    }

    private fun stopCapture() {
        if (!running) {
            val previous = WearUiStateStore.read(this)
            if (previous.running) {
                sessionId = previous.sessionId
                WearUiStateStore.write(
                    this,
                    previous.copy(mode = WearMode.SUMMARY, running = false, completedAt = System.currentTimeMillis())
                )
                scope.launch { runCatching { exerciseClient.endExercise() } }
            }
            stopSelf()
            return
        }
        running = false
        samplingJob?.cancel()
        sensorManager.unregisterListener(this)
        updateUi(WearMode.SUMMARY)
        scope.launch {
            runCatching { exerciseClient.endExercise() }
            flushBatch("final")
            ServiceCompat.stopForeground(this@WatchCaptureService, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun registerMotionSensors() {
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        val magnitude = sqrt(event.values.sumOf { (it * it).toDouble() })
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelEnergy += magnitude
                accelSquareEnergy += magnitude * magnitude
                accelCount++
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyroEnergy += magnitude
                gyroCount++
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun captureSecond() {
        val accelMean = if (accelCount == 0) null else accelEnergy / accelCount
        val accelVariance = if (accelCount == 0 || accelMean == null) null else
            (accelSquareEnergy / accelCount - accelMean * accelMean).coerceAtLeast(0.0)
        val sample = JSONObject()
            .put("t", System.currentTimeMillis())
            .put("elapsedMs", SystemClock.elapsedRealtime() - startedElapsed)
            .put("hr", heartRate ?: JSONObject.NULL)
            .put("caloriesTotal", totalCalories ?: JSONObject.NULL)
            .put("accelMean", accelMean ?: JSONObject.NULL)
            .put("accelVariance", accelVariance ?: JSONObject.NULL)
            .put("gyroMean", if (gyroCount == 0) JSONObject.NULL else gyroEnergy / gyroCount)
            .put("accelSamples", accelCount)
            .put("gyroSamples", gyroCount)
        synchronized(batch) { batch.put(sample) }
        updateUi(if (paused) WearMode.PAUSED else WearMode.ACTIVE)
        accelEnergy = 0.0
        accelSquareEnergy = 0.0
        gyroEnergy = 0.0
        accelCount = 0
        gyroCount = 0
        if (batch.length() >= 10) scope.launch { flushBatch("periodic") }
    }

    private fun readHealthMetrics(metrics: DataPointContainer) {
        metrics.getData(DataType.HEART_RATE_BPM).lastOrNull()?.value?.let { latest ->
            heartRate = latest
            heartRateTotal += latest
            heartRateCount++
            heartRateMax = maxOf(heartRateMax ?: latest, latest)
        }
        totalCalories = metrics.getData(DataType.CALORIES_TOTAL)?.total ?: totalCalories
    }

    private fun updateUi(mode: WearMode, message: String = "") {
        val previous = WearUiStateStore.read(this)
        WearUiStateStore.write(
            this,
            previous.copy(
                mode = mode,
                running = running,
                completedAt = if (mode == WearMode.SUMMARY) System.currentTimeMillis() else previous.completedAt,
                sessionId = sessionId.ifBlank { previous.sessionId },
                heartRate = heartRate,
                heartRateAverage = if (heartRateCount == 0L) previous.heartRateAverage else heartRateTotal / heartRateCount,
                heartRateMax = heartRateMax ?: previous.heartRateMax,
                calories = totalCalories,
                sampleCount = sequence,
                message = message
            )
        )
    }

    private fun flushBatch(reason: String) {
        val samples = synchronized(batch) {
            if (batch.length() == 0) return
            val copy = JSONArray(batch.toString())
            while (batch.length() > 0) batch.remove(0)
            copy
        }
        val payload = JSONObject()
            .put("protocol", 1)
            .put("sessionId", sessionId)
            .put("sequence", sequence)
            .put("reason", reason)
            .put("samples", samples)
            .toString()
        persistLocalBatch(sequence, payload)
        val request = PutDataMapRequest.create("/gymmane/telemetry/v1/$sessionId/$sequence").apply {
            dataMap.putString("payload", payload)
            dataMap.putLong("createdAt", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(request)
        sequence++
    }

    private fun persistLocalBatch(number: Long, payload: String) {
        val directory = File(filesDir, "telemetry/$sessionId").apply { mkdirs() }
        File(directory, "$number.json").writeText(payload)
    }

    private fun writeStatus(type: String, message: String) {
        val payload = JSONObject()
            .put("protocol", 1)
            .put("sessionId", sessionId)
            .put("type", type)
            .put("message", message)
            .put("at", System.currentTimeMillis())
            .toString()
        val request = PutDataMapRequest.create("/gymmane/status/v1/$sessionId/$type").apply {
            dataMap.putString("payload", payload)
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(request)
    }

    private fun postNotification(text: String) {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, WearMainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(com.gymmane.app.R.drawable.ic_launcher)
            .setContentTitle("GymMane Sensor")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        )
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Captura de entrenamiento", NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onDestroy() {
        sensorManager.unregisterListener(this)
        exerciseClient.clearUpdateCallbackAsync(exerciseCallback)
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.gymmane.app.wear.START"
        const val ACTION_PAUSE = "com.gymmane.app.wear.PAUSE"
        const val ACTION_RESUME = "com.gymmane.app.wear.RESUME"
        const val ACTION_STOP = "com.gymmane.app.wear.STOP"
        const val EXTRA_SESSION_ID = "sessionId"
        private const val CHANNEL_ID = "gymmane_capture"
        private const val NOTIFICATION_ID = 4101
    }
}
