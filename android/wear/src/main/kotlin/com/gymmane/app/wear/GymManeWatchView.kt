package com.gymmane.app.wear

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

class GymManeWatchView(context: Context) : View(context) {
    var onPrimaryAction: (() -> Unit)? = null
    var onSecondaryAction: (() -> Unit)? = null
    var onRunningChanged: ((Boolean) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    private val clock = SimpleDateFormat("HH:mm", Locale.getDefault())
    private val condensed = Typeface.create("sans-serif-condensed", Typeface.BOLD)
    private val regular = Typeface.create("sans-serif", Typeface.NORMAL)
    private val bronze = Color.rgb(217, 161, 132)
    private val sage = Color.rgb(143, 163, 119)
    private val warning = Color.rgb(224, 177, 90)
    private val danger = Color.rgb(229, 103, 76)
    private val muted = Color.rgb(153, 153, 153)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var state = WearUiStateStore.read(context)
    private var lastKeepAwake: Boolean? = null
    private var pressed = false
    private var pressedAt = 0L

    private val ticker = object : Runnable {
        override fun run() {
            refreshNow()
            handler.postDelayed(this, 1000L)
        }
    }

    fun startRefreshing() {
        handler.removeCallbacks(ticker)
        ticker.run()
    }

    fun stopRefreshing() = handler.removeCallbacks(ticker)

    fun refreshNow() {
        state = WearUiStateStore.read(context)
        val keepAwake = state.running && System.currentTimeMillis() - state.updatedAt < 15_000L
        if (lastKeepAwake != keepAwake) {
            lastKeepAwake = keepAwake
            onRunningChanged?.invoke(keepAwake)
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Color.rgb(10, 10, 10))
        val scale = (minOf(width, height) / 192f).coerceAtLeast(.8f)
        canvas.save()
        canvas.translate((width - 192f * scale) / 2f, (height - 192f * scale) / 2f)
        canvas.scale(scale, scale)
        val cx = 96f
        val top = 0f
        drawFrame(canvas, cx, top)
        when (state.mode) {
            WearMode.READY -> drawReady(canvas, cx, top)
            WearMode.STARTING -> drawStarting(canvas, cx, top)
            WearMode.ACTIVE -> if (state.phase == "rest") drawRest(canvas, cx, top) else drawActive(canvas, cx, top)
            WearMode.PAUSED -> drawPaused(canvas, cx, top)
            WearMode.DEGRADED -> drawDegraded(canvas, cx, top)
            WearMode.SUMMARY -> drawSummary(canvas, cx, top)
        }
        canvas.restore()
    }

    private fun drawFrame(canvas: Canvas, cx: Float, top: Float) {
        text(canvas, clock.format(Date()), cx, top + 14, 8f, muted)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1f
        paint.color = Color.rgb(38, 38, 38)
        canvas.drawCircle(cx, top + 96, 91f, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawReady(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "● CONECTADO", sage)
        text(canvas, "GYMMANE", cx, top + 53, 13f, bronze, condensed)
        text(canvas, "RELOJ LISTO", cx, top + 72, 9f, Color.WHITE, condensed)
        text(canvas, "El teléfono iniciará la captura", cx, top + 88, 7f, muted)
        iconCircle(canvas, cx, top + 112, sage)
        button(canvas, cx, top + 153, "INICIAR PRUEBA", bronze)
        text(canvas, "FC · MOVIMIENTO · CALORÍAS", cx, top + 181, 5.5f, muted)
    }

    private fun drawStarting(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "CONECTANDO", warning)
        text(canvas, "PREPARANDO SENSORES", cx, top + 66, 10f, Color.WHITE, condensed)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = bronze
        canvas.drawArc(RectF(cx - 24, top + 80, cx + 24, top + 128), -80f, 245f, false, paint)
        paint.style = Paint.Style.FILL
        text(canvas, "Mantén el reloj ajustado", cx, top + 146, 7f, muted)
    }

    private fun drawActive(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "● CAPTURANDO", sage)
        text(canvas, if (state.phase == "set") "SERIE ACTIVA" else "CAPTURA ACTIVA", cx, top + 48, 8f, bronze, condensed)
        text(canvas, state.exerciseName.ifBlank { "ENTRENAMIENTO" }.uppercase().take(24), cx, top + 67, 12f, Color.WHITE, condensed)
        if (state.setIndex > 0 && state.setCount > 0) {
            text(canvas, "Serie ${state.setIndex} de ${state.setCount}", cx, top + 78, 6f, muted)
        }
        text(canvas, elapsed(), cx, top + 98, 20f, Color.WHITE, condensed)
        val hr = state.heartRate?.roundToInt()?.toString() ?: "--"
        text(canvas, "♥ $hr bpm", cx - 28, top + 118, 7f, Color.WHITE)
        text(canvas, signalLabel(), cx + 35, top + 118, 6f, sage, condensed)
        button(canvas, cx, top + 145, "Ⅱ  PAUSAR", Color.WHITE, outlined = true)
        val kcal = state.calories?.let { String.format(Locale.US, "%.1f KCAL", it) } ?: "CALCULANDO KCAL"
        text(canvas, kcal, cx, top + 177, 5.5f, muted)
        text(canvas, "MANTÉN PARA FINALIZAR", cx, top + 185, 4.5f, muted)
    }

    private fun drawRest(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "● CAPTURANDO", sage)
        text(canvas, "DESCANSO", cx, top + 51, 9f, bronze, condensed)
        text(canvas, restLabel(), cx, top + 91, 28f, Color.WHITE, condensed)
        val hr = state.heartRate?.roundToInt()?.toString() ?: "--"
        text(canvas, "♥ $hr bpm", cx, top + 113, 7f, Color.WHITE)
        text(canvas, "RECUPERANDO", cx + 38, top + 113, 5.5f, sage, condensed)
        text(canvas, nextSetLabel(), cx, top + 139, 7f, muted)
        button(canvas, cx, top + 160, "Ⅱ  PAUSAR", Color.WHITE, outlined = true)
        text(canvas, "MANTÉN PARA FINALIZAR", cx, top + 184, 4.5f, muted)
    }

    private fun restLabel(): String {
        val seconds = max(0L, (state.restEndsAt - System.currentTimeMillis() + 999L) / 1000L)
        return String.format(Locale.US, "%02d:%02d", seconds / 60, seconds % 60)
    }

    private fun nextSetLabel(): String {
        val next = if (state.setIndex <= 0) 1 else (state.setIndex + 1).coerceAtMost(state.setCount)
        return if (state.setCount > 0) "SIGUE · SERIE $next DE ${state.setCount}" else "PREPÁRATE PARA LA SIGUIENTE SERIE"
    }

    private fun drawPaused(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "EN PAUSA", warning)
        text(canvas, "ENTRENAMIENTO", cx, top + 54, 8f, muted, condensed)
        text(canvas, "PAUSADO", cx, top + 75, 14f, Color.WHITE, condensed)
        text(canvas, elapsed(), cx, top + 102, 18f, Color.WHITE, condensed)
        button(canvas, cx, top + 143, "▶  REANUDAR", bronze)
        text(canvas, "La captura está en espera", cx, top + 174, 6f, muted)
    }

    private fun drawDegraded(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 27, "ATENCIÓN", danger)
        text(canvas, "CAPTURA LIMITADA", cx, top + 58, 12f, Color.WHITE, condensed)
        text(canvas, degradedTitle(), cx, top + 81, 8f, warning, condensed)
        multiline(canvas, state.message.ifBlank { "Revisa el teléfono o cierra otra\napp de entrenamiento." }, cx, top + 101, 6.5f, muted)
        button(canvas, cx, top + 151, if (state.running) "CONTINUAR SIN FC" else "REINTENTAR", danger, outlined = true)
        text(canvas, "Tus series siguen guardándose", cx, top + 178, 5.5f, muted)
    }

    private fun drawSummary(canvas: Canvas, cx: Float, top: Float) {
        pill(canvas, cx, top + 25, "SINCRONIZADO", sage)
        text(canvas, "ENTRENAMIENTO LISTO", cx, top + 47, 10f, bronze, condensed)
        text(canvas, elapsed(), cx, top + 72, 18f, Color.WHITE, condensed)
        metric(canvas, cx - 45, top + 101, "FC MEDIA", state.heartRateAverage?.roundToInt()?.toString() ?: "--", "bpm")
        metric(canvas, cx, top + 101, "FC MÁX", state.heartRateMax?.roundToInt()?.toString() ?: "--", "bpm")
        metric(canvas, cx + 45, top + 101, "RELOJ", state.calories?.roundToInt()?.toString() ?: "--", "kcal")
        button(canvas, cx, top + 153, "NUEVA CAPTURA", bronze, outlined = true)
        text(canvas, "Datos enviados al teléfono", cx, top + 180, 5.5f, muted)
    }

    private fun metric(canvas: Canvas, x: Float, y: Float, label: String, value: String, unit: String) {
        text(canvas, label, x, y, 5f, muted)
        text(canvas, value, x, y + 15, 13f, Color.WHITE, condensed)
        text(canvas, unit, x, y + 24, 5f, muted)
    }

    private fun signalLabel(): String {
        val age = System.currentTimeMillis() - state.updatedAt
        return when {
            state.heartRate == null -> "BUSCANDO FC"
            age > 10_000 -> "SEÑAL DÉBIL"
            else -> "SEÑAL BUENA"
        }
    }

    private fun degradedTitle(): String = when {
        state.message.contains("exercise", ignoreCase = true) || state.message.contains("ongoing", ignoreCase = true) ->
            "OTRA APP ESTÁ MIDIENDO"
        else -> "SENSOR NO DISPONIBLE"
    }

    private fun elapsed(): String {
        val started = if (state.phase == "set" && state.phaseStartedAt > 0) state.phaseStartedAt else state.startedAt
        if (started <= 0) return "00:00"
        val end = if (state.mode == WearMode.SUMMARY && state.completedAt > 0) state.completedAt else System.currentTimeMillis()
        val seconds = max(0L, (end - started) / 1000L)
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%02d:%02d", m, s)
    }

    private fun pill(canvas: Canvas, cx: Float, y: Float, label: String, color: Int) {
        paint.typeface = condensed
        paint.textSize = 5.5f
        val w = paint.measureText(label) + 16f
        paint.color = Color.argb(40, Color.red(color), Color.green(color), Color.blue(color))
        canvas.drawRoundRect(cx - w / 2, y - 8, cx + w / 2, y + 3, 6f, 6f, paint)
        text(canvas, label, cx, y, 5.5f, color, condensed)
    }

    private fun iconCircle(canvas: Canvas, cx: Float, y: Float, color: Int) {
        paint.color = Color.argb(35, Color.red(color), Color.green(color), Color.blue(color))
        canvas.drawCircle(cx, y, 18f, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        paint.color = color
        canvas.drawCircle(cx, y, 8f, paint)
        canvas.drawLine(cx - 4, y, cx - 1, y + 3, paint)
        canvas.drawLine(cx - 1, y + 3, cx + 5, y - 4, paint)
        paint.style = Paint.Style.FILL
    }

    private fun button(canvas: Canvas, cx: Float, y: Float, label: String, color: Int, outlined: Boolean = false) {
        val w = 104f
        val alpha = if (pressed) 150 else 255
        paint.style = if (outlined) Paint.Style.STROKE else Paint.Style.FILL
        paint.strokeWidth = 1f
        paint.color = if (outlined) color else Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
        canvas.drawRoundRect(cx - w / 2, y - 13, cx + w / 2, y + 10, 12f, 12f, paint)
        paint.style = Paint.Style.FILL
        text(canvas, label, cx, y + 1, 7f, if (outlined) color else Color.rgb(20, 20, 20), condensed)
    }

    private fun multiline(canvas: Canvas, value: String, x: Float, y: Float, size: Float, color: Int) {
        value.lines().take(3).forEachIndexed { index, line -> text(canvas, line, x, y + index * (size + 3), size, color) }
    }

    private fun text(canvas: Canvas, value: String, x: Float, baseline: Float, size: Float, color: Int, face: Typeface = regular) {
        paint.style = Paint.Style.FILL
        paint.typeface = face
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = size
        paint.color = color
        canvas.drawText(value, x, baseline, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { pressed = true; pressedAt = System.currentTimeMillis(); invalidate(); return true }
            MotionEvent.ACTION_UP -> {
                val longPress = System.currentTimeMillis() - pressedAt >= 850L
                pressed = false
                invalidate()
                if (longPress && state.running) onSecondaryAction?.invoke() else performClick()
                return true
            }
            MotionEvent.ACTION_CANCEL -> { pressed = false; invalidate() }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        onPrimaryAction?.invoke()
        return true
    }
}
