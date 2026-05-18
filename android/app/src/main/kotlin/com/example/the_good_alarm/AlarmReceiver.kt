package com.andodevs.the_good_alarm

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import android.util.Log
import android.app.NotificationChannel
import android.app.Notification
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.min
import kotlin.math.roundToInt

object AlarmVolumeController {
    private var appContext: Context? = null
    private val handler = Handler(Looper.getMainLooper())
    private var tickRunnable: Runnable? = null
    private var tempEndRunnable: Runnable? = null

    private var isActive = false
    private var activeAlarmId: Int? = null
    private var originalVolume: Int? = null

    private var targetVolume: Int = 0
    private var rampStartVolume: Int = 0
    private var rampStartTimeMs: Long = 0L
    private var rampDurationMs: Long = 0L
    private var rampRunning: Boolean = false

    private var tempActive: Boolean = false
    private var tempReducedVolume: Int = 0

    fun startFromAlarmTrigger(
        context: Context,
        alarmId: Int,
        maxVolumePercent: Int,
        rampUpDurationSeconds: Int
    ) {
        val ctx = context.applicationContext
        appContext = ctx

        if (isActive && activeAlarmId != null && activeAlarmId != alarmId) {
            stop(ctx)
        }

        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (!isActive) {
            originalVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            isActive = true
            activeAlarmId = alarmId
        }

        val maxStreamVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        targetVolume = ((maxStreamVolume * maxVolumePercent) / 100).coerceIn(0, maxStreamVolume)

        if (rampUpDurationSeconds <= 0) {
            rampRunning = false
            handler.removeCallbacks(tickRunnable ?: Runnable {})
            tickRunnable = null
            applyEffectiveVolume(am, targetVolume)
            return
        }

        val initialVolume = 1.coerceIn(0, maxStreamVolume)
        am.setStreamVolume(AudioManager.STREAM_ALARM, initialVolume, 0)

        rampStartVolume = initialVolume
        rampStartTimeMs = SystemClock.elapsedRealtime()
        rampDurationMs = rampUpDurationSeconds * 1000L
        rampRunning = true

        ensureTickScheduled()
        tick()
    }

    fun ensureStarted(context: Context, maxVolumePercent: Int, rampUpDurationSeconds: Int) {
        val ctx = context.applicationContext
        appContext = ctx

        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (!isActive) {
            originalVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            isActive = true
        }

        val maxStreamVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        targetVolume = ((maxStreamVolume * maxVolumePercent) / 100).coerceIn(0, maxStreamVolume)

        if (!rampRunning && rampUpDurationSeconds > 0) {
            rampStartVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            rampStartTimeMs = SystemClock.elapsedRealtime()
            rampDurationMs = rampUpDurationSeconds * 1000L
            rampRunning = true
            ensureTickScheduled()
        } else if (!rampRunning && rampUpDurationSeconds <= 0) {
            applyEffectiveVolume(am, targetVolume)
            return
        }

        tick()
    }

    fun setTemporaryReduction(context: Context, reductionPercent: Int, durationSeconds: Int) {
        val ctx = context.applicationContext
        appContext = ctx

        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (!isActive) {
            originalVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            isActive = true
        }

        val maxStreamVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val absoluteReduced = ((maxStreamVolume * reductionPercent) / 100).coerceIn(0, maxStreamVolume)
        val currentVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        tempReducedVolume = min(currentVolume, absoluteReduced)
        tempActive = true

        handler.removeCallbacks(tempEndRunnable ?: Runnable {})
        tempEndRunnable = Runnable {
            tempActive = false
            tick()
        }
        handler.postDelayed(tempEndRunnable!!, durationSeconds * 1000L)

        applyEffectiveVolume(am, tempReducedVolume)
        tick()
    }

    fun cancelTemporaryReduction(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx

        handler.removeCallbacks(tempEndRunnable ?: Runnable {})
        tempEndRunnable = null
        tempActive = false
        tick()
    }

    fun stop(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx

        handler.removeCallbacks(tickRunnable ?: Runnable {})
        handler.removeCallbacks(tempEndRunnable ?: Runnable {})
        tickRunnable = null
        tempEndRunnable = null

        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        originalVolume?.let { volume ->
            am.setStreamVolume(AudioManager.STREAM_ALARM, volume, 0)
        }

        isActive = false
        activeAlarmId = null
        originalVolume = null
        targetVolume = 0
        rampStartVolume = 0
        rampStartTimeMs = 0L
        rampDurationMs = 0L
        rampRunning = false
        tempActive = false
        tempReducedVolume = 0
    }

    private fun ensureTickScheduled() {
        if (tickRunnable == null) {
            tickRunnable = Runnable { tick() }
        }
        handler.removeCallbacks(tickRunnable!!)
        handler.post(tickRunnable!!)
    }

    private fun tick() {
        if (!isActive) return
        val ctx = appContext ?: return
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxStreamVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)

        val baseVolume = computeBaseVolume(am, maxStreamVolume)
        val effectiveVolume = if (tempActive) min(baseVolume, tempReducedVolume) else baseVolume
        applyEffectiveVolume(am, effectiveVolume)

        if (rampRunning) {
            handler.removeCallbacks(tickRunnable!!)
            handler.postDelayed(tickRunnable!!, 250L)
        }
    }

    private fun computeBaseVolume(am: AudioManager, maxStreamVolume: Int): Int {
        if (!rampRunning) {
            return targetVolume.coerceIn(0, maxStreamVolume)
        }

        val now = SystemClock.elapsedRealtime()
        val elapsed = (now - rampStartTimeMs).coerceAtLeast(0L)
        if (rampDurationMs <= 0L || elapsed >= rampDurationMs) {
            rampRunning = false
            return targetVolume.coerceIn(0, maxStreamVolume)
        }

        val progress = elapsed.toDouble() / rampDurationMs.toDouble()
        val interpolated = (rampStartVolume + (targetVolume - rampStartVolume) * progress).roundToInt()
        return interpolated.coerceIn(0, maxStreamVolume)
    }

    private fun applyEffectiveVolume(am: AudioManager, volume: Int) {
        val maxStreamVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val clamped = volume.coerceIn(0, maxStreamVolume)
        val current = am.getStreamVolume(AudioManager.STREAM_ALARM)
        if (current != clamped) {
            am.setStreamVolume(AudioManager.STREAM_ALARM, clamped, 0)
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    
    companion object {
        var currentRingtone: Ringtone? = null
        var currentVibrator: Vibrator? = null
        const val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
        private const val ALARM_ACTION = "com.andodevs.the_good_alarm.ALARM_TRIGGERED"
        private const val STOP_ACTION = "com.andodevs.the_good_alarm.STOP_ALARM_ACTION"
        private const val SNOOZE_ACTION = "com.andodevs.the_good_alarm.SNOOZE_ALARM_ACTION"
        private const val SNOOZE_REQUEST_CODE_OFFSET = 1000000
        
        fun stopAlarmSound() {
            try {
                currentRingtone?.let { ringtone ->
                    if (ringtone.isPlaying) {
                        Log.d("AlarmReceiver", "Stopping alarm sound")
                        ringtone.stop()
                        Log.d("AlarmReceiver", "Alarm sound stopped")
                    } else {
                        Log.d("AlarmReceiver", "Alarm sound was not playing")
                    }
                }
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error stopping alarm sound", e)
            } finally {
                try {
                    currentRingtone = null
                    Log.d("AlarmReceiver", "Current ringtone set to null")
                } catch (e: Exception) {
                    Log.e("AlarmReceiver", "Error setting ringtone to null", e)
                }
            }
        }
        
        fun isVibrating(): Boolean {
            return currentVibrator != null
        }
        
        fun stopVibration(context: Context) {
            try {
                currentVibrator?.let { vibrator ->
                    Log.d("AlarmReceiver", "Stopping vibration")
                    vibrator.cancel()
                    Log.d("AlarmReceiver", "Vibration stopped")
                }
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error stopping vibration", e)
                // Fallback: try to get vibrator service and cancel
                try {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    vibrator?.cancel()
                    Log.d("AlarmReceiver", "Fallback vibration stop attempted")
                } catch (fallbackException: Exception) {
                    Log.e("AlarmReceiver", "Fallback vibration stop also failed", fallbackException)
                }
            } finally {
                try {
                    currentVibrator = null
                    Log.d("AlarmReceiver", "Current vibrator set to null")
                } catch (e: Exception) {
                    Log.e("AlarmReceiver", "Error setting vibrator to null", e)
                }
            }
        }
        
        fun cancelAllNotificationsForAlarm(context: Context, alarmId: Int) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                // Cancel the main notification
                notificationManager.cancel(alarmId)
                Log.d("AlarmReceiver", "Cancelled notification with ID: $alarmId")
                
                // Also try to cancel related notification IDs that might have been used
                val relatedIds = listOf(
                    alarmId + 1000,  // Launch intent ID
                    alarmId + 2000,  // Stop intent ID
                    alarmId + 3000   // Snooze intent ID
                )
                
                relatedIds.forEach { id ->
                    try {
                        notificationManager.cancel(id)
                        Log.d("AlarmReceiver", "Cancelled related notification with ID: $id")
                    } catch (e: Exception) {
                        Log.w("AlarmReceiver", "Could not cancel notification with ID: $id", e)
                    }
                }
                
                Log.d("AlarmReceiver", "All notifications cancelled for alarm ID: $alarmId")
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error cancelling notifications for alarm ID: $alarmId", e)
            }
        }

        fun pushAlarmEvent(context: Context, type: String, alarmId: Int, newTimeInMillis: Long?) {
            try {
                val prefs = context.getSharedPreferences("alarm_events", Context.MODE_PRIVATE)
                val current = prefs.getString("events", "[]") ?: "[]"
                val array = JSONArray(current)
                val obj = JSONObject()
                obj.put("type", type)
                obj.put("alarmId", alarmId)
                obj.put("timestamp", System.currentTimeMillis())
                if (newTimeInMillis != null) {
                    obj.put("newTimeInMillis", newTimeInMillis)
                }
                array.put(obj)
                prefs.edit().putString("events", array.toString()).apply()
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error pushing alarm event", e)
            }
        }

        fun cancelSnoozeAlarm(context: Context, alarmId: Int) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, AlarmReceiver::class.java).apply { action = ALARM_ACTION }
                val pending = PendingIntent.getBroadcast(
                    context,
                    alarmId + SNOOZE_REQUEST_CODE_OFFSET,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pending)
                pending.cancel()
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error canceling snooze alarm", e)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "onReceive called with action: ${intent.action}")
        
        when (intent.action) {
            STOP_ACTION -> {
                Log.d("AlarmReceiver", "Stop action received")
                val alarmId = intent.getIntExtra("alarmId", -1)
                Log.d("AlarmReceiver", "Stopping alarm with ID: $alarmId")
                
                stopAlarmSound()
                stopVibration(context)
                AlarmVolumeController.stop(context)
                cancelAllNotificationsForAlarm(context, alarmId)
                cancelSnoozeAlarm(context, alarmId)
                val alarmScreenKey = "alarm_screen_shown_$alarmId"
                context.getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                pushAlarmEvent(context, type = "stopped", alarmId = alarmId, newTimeInMillis = null)
                
                Log.d("AlarmReceiver", "Alarm stopped completely")
            }
            SNOOZE_ACTION -> {
                Log.d("AlarmReceiver", "Snooze action received")
                val alarmId = intent.getIntExtra("alarmId", -1)
                val maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
                val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
                val title = intent.getStringExtra("title") ?: "Alarma Pospuesta"
                val message = intent.getStringExtra("message") ?: "¡Es hora de despertar!"
                val maxVolumePercent = intent.getIntExtra("maxVolumePercent", 100)
                val volumeRampUpDurationSeconds = intent.getIntExtra("volumeRampUpDurationSeconds", 30)
                val tempVolumeReductionPercent = intent.getIntExtra("tempVolumeReductionPercent", 50)
                val tempVolumeReductionDurationSeconds = intent.getIntExtra("tempVolumeReductionDurationSeconds", 60)
                
                Log.d("AlarmReceiver", "Snoozing alarm ID: $alarmId, maxSnoozes: $maxSnoozes, duration: $snoozeDurationMinutes")
                
                stopAlarmSound()
                stopVibration(context)
                AlarmVolumeController.stop(context)
                cancelAllNotificationsForAlarm(context, alarmId)
                cancelSnoozeAlarm(context, alarmId)

                val alarmScreenKey = "alarm_screen_shown_$alarmId"
                context.getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()

                val now = Calendar.getInstance()
                now.add(Calendar.MINUTE, snoozeDurationMinutes)
                val newTimeInMillis = now.timeInMillis

                try {
                    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
                        action = ALARM_ACTION
                        putExtra("alarmId", alarmId)
                        putExtra("title", title)
                        putExtra("message", message)
                        putExtra("screenRoute", "/alarm")
                        putExtra("repeatDays", intArrayOf())
                        putExtra("isDaily", false)
                        putExtra("isWeekly", false)
                        putExtra("isWeekend", false)
                        putExtra("maxSnoozes", maxSnoozes)
                        putExtra("snoozeDurationMinutes", snoozeDurationMinutes)
                        putExtra("hour", -1)
                        putExtra("minute", -1)
                        putExtra("isSnooze", true)
                        putExtra("maxVolumePercent", maxVolumePercent)
                        putExtra("volumeRampUpDurationSeconds", volumeRampUpDurationSeconds)
                        putExtra("tempVolumeReductionPercent", tempVolumeReductionPercent)
                        putExtra("tempVolumeReductionDurationSeconds", tempVolumeReductionDurationSeconds)
                    }
                    val pending = PendingIntent.getBroadcast(
                        context,
                        alarmId + SNOOZE_REQUEST_CODE_OFFSET,
                        snoozeIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, newTimeInMillis, pending)
                    } else {
                        alarmManager.setExact(AlarmManager.RTC_WAKEUP, newTimeInMillis, pending)
                    }
                } catch (e: Exception) {
                    Log.e("AlarmReceiver", "Error scheduling snooze alarm", e)
                }

                pushAlarmEvent(context, type = "snoozed", alarmId = alarmId, newTimeInMillis = newTimeInMillis)
                Log.d("AlarmReceiver", "Alarm snoozed")
            }
            else -> {
                Log.d("AlarmReceiver", "Default alarm trigger action")
                handleAlarmTrigger(context, intent)
            }
        }
    }

    private fun calculateNextRepeatingTimeMillis(hour: Int, minute: Int, repeatDays: List<Int>): Long? {
        if (hour !in 0..23 || minute !in 0..59) return null
        if (repeatDays.isEmpty()) return null

        val calendar = Calendar.getInstance()
        val now = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, hour)
        calendar.set(Calendar.MINUTE, minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        val calendarDays = repeatDays.map { day ->
            when (day) {
                1 -> Calendar.MONDAY
                2 -> Calendar.TUESDAY
                3 -> Calendar.WEDNESDAY
                4 -> Calendar.THURSDAY
                5 -> Calendar.FRIDAY
                6 -> Calendar.SATURDAY
                7 -> Calendar.SUNDAY
                else -> Calendar.MONDAY
            }
        }.toSet()

        val currentDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
        if (calendarDays.contains(currentDayOfWeek) && calendar.after(now)) {
            return calendar.timeInMillis
        }

        for (daysToAdd in 1..7) {
            calendar.add(Calendar.DAY_OF_MONTH, 1)
            if (calendarDays.contains(calendar.get(Calendar.DAY_OF_WEEK))) {
                return calendar.timeInMillis
            }
        }
        return null
    }

    private fun rescheduleNextIfRepeating(context: Context, intent: Intent, alarmId: Int) {
        val isSnooze = intent.getBooleanExtra("isSnooze", false)
        if (isSnooze) return

        fun calendarDayToRepeatDay(dayOfWeek: Int): Int {
            return when (dayOfWeek) {
                Calendar.MONDAY -> 1
                Calendar.TUESDAY -> 2
                Calendar.WEDNESDAY -> 3
                Calendar.THURSDAY -> 4
                Calendar.FRIDAY -> 5
                Calendar.SATURDAY -> 6
                Calendar.SUNDAY -> 7
                else -> 1
            }
        }

        val rawRepeatDays = intent.getIntArrayExtra("repeatDays")?.toList() ?: emptyList()
        val repeatDays = when {
            rawRepeatDays.isNotEmpty() -> rawRepeatDays
            intent.getBooleanExtra("isDaily", false) -> listOf(1, 2, 3, 4, 5, 6, 7)
            intent.getBooleanExtra("isWeekend", false) -> listOf(6, 7)
            intent.getBooleanExtra("isWeekly", false) -> listOf(
                calendarDayToRepeatDay(Calendar.getInstance().get(Calendar.DAY_OF_WEEK))
            )
            else -> emptyList()
        }
        val hour = intent.getIntExtra("hour", -1)
        val minute = intent.getIntExtra("minute", -1)
        val nextTime = calculateNextRepeatingTimeMillis(hour, minute, repeatDays) ?: return

        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val rescheduleIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION
                if (intent.extras != null) {
                    putExtras(intent.extras!!)
                }
                putExtra("isSnooze", false)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                alarmId,
                rescheduleIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextTime, pending)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, nextTime, pending)
            }
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Error rescheduling repeating alarm", e)
        }
    }

    private fun handleAlarmTrigger(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "handleAlarmTrigger called")
        
        try {
            val alarmId = intent.getIntExtra("alarmId", -1)
            val title = intent.getStringExtra("title") ?: "Alarma"
            val message = intent.getStringExtra("message") ?: "Es hora de despertar"
            val maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
            val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
            val maxVolumePercent = intent.getIntExtra("maxVolumePercent", 100)
            val volumeRampUpDurationSeconds = intent.getIntExtra("volumeRampUpDurationSeconds", 30)
            val tempVolumeReductionPercent = intent.getIntExtra("tempVolumeReductionPercent", 50)
            val tempVolumeReductionDurationSeconds = intent.getIntExtra("tempVolumeReductionDurationSeconds", 60)
            val repeatDays = intent.getIntArrayExtra("repeatDays")?.toList() ?: emptyList()
            val hour = intent.getIntExtra("hour", -1)
            val minute = intent.getIntExtra("minute", -1)
            
            Log.d("AlarmReceiver", "Alarm details - ID: $alarmId, Title: $title, Message: $message")
            Log.d("AlarmReceiver", "Snooze settings - Max: $maxSnoozes, Duration: $snoozeDurationMinutes minutes")
            Log.d("AlarmReceiver", "Volume settings - Max: $maxVolumePercent%, RampUp: ${volumeRampUpDurationSeconds}s, TempReduction: $tempVolumeReductionPercent% for ${tempVolumeReductionDurationSeconds}s")
            Log.d("AlarmReceiver", "Repeat settings - Days: $repeatDays, Hour: $hour, Minute: $minute")

            rescheduleNextIfRepeating(context, intent, alarmId)

            // Adquirir WakeLock para mantener el dispositivo despierto
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "AlarmApp:AlarmWakeLock"
            )
            wakeLock.acquire(10 * 60 * 1000L) // 10 minutos máximo
            Log.d("AlarmReceiver", "WakeLock acquired")

            try {
                Log.d("AlarmReceiver", "Starting volume control: maxVolume=$maxVolumePercent%, rampUp=${volumeRampUpDurationSeconds}s")
                AlarmVolumeController.startFromAlarmTrigger(
                    context = context,
                    alarmId = alarmId,
                    maxVolumePercent = maxVolumePercent,
                    rampUpDurationSeconds = volumeRampUpDurationSeconds
                )
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error starting volume control: ${e.message}")
            }

            // Reproducir sonido de alarma con control de volumen
            try {
                Log.d("AlarmReceiver", "Setting up alarm sound with volume control")
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                
                Log.d("AlarmReceiver", "Alarm URI: $alarmUri")
                
                currentRingtone = RingtoneManager.getRingtone(context, alarmUri)
                currentRingtone?.let { ringtone ->
                    // Configurar el ringtone para usar el stream de alarma
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        ringtone.audioAttributes = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    } else {
                        @Suppress("DEPRECATION")
                        ringtone.streamType = android.media.AudioManager.STREAM_ALARM
                    }
                    
                    if (!ringtone.isPlaying) {
                        Log.d("AlarmReceiver", "Starting alarm sound with ALARM stream")
                        ringtone.play()
                        Log.d("AlarmReceiver", "Alarm sound started")
                    } else {
                        Log.d("AlarmReceiver", "Alarm sound was already playing")
                    }
                } ?: Log.e("AlarmReceiver", "Could not get ringtone")
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error playing alarm sound", e)
            }

            // Configurar vibración continua
            try {
                Log.d("AlarmReceiver", "Setting up vibration")
                
                // Verificar configuraciones del sistema que pueden afectar la vibración
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                val ringerMode = audioManager?.ringerMode
                Log.d("AlarmReceiver", "Current ringer mode: $ringerMode (NORMAL=2, VIBRATE=1, SILENT=0)")
                
                // Verificar Do Not Disturb
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    val dndFilter = notificationManager?.currentInterruptionFilter
                    Log.d("AlarmReceiver", "Do Not Disturb filter: $dndFilter (ALL=1, PRIORITY=2, NONE=3, ALARMS=4)")
                }
                
                // Verificar optimización de batería
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnoringOptimizations = powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
                    Log.d("AlarmReceiver", "Ignoring battery optimizations: $isIgnoringOptimizations")
                }
                
                // Verificar si el dispositivo tiene vibrador
                val hasVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    val hasVib = vibratorManager?.defaultVibrator?.hasVibrator() == true
                    Log.d("AlarmReceiver", "VibratorManager hasVibrator: $hasVib")
                    hasVib
                } else {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    val hasVib = vibrator?.hasVibrator() == true
                    Log.d("AlarmReceiver", "Vibrator hasVibrator: $hasVib")
                    hasVib
                }
                
                if (!hasVibrator) {
                    Log.w("AlarmReceiver", "Device does not have vibrator capability")
                } else {
                    Log.d("AlarmReceiver", "Device has vibrator, proceeding with vibration setup")
                    
                    currentVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                        vibratorManager.defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    }
                    
                    Log.d("AlarmReceiver", "Current vibrator obtained: ${currentVibrator != null}")
                    
                    // Patrón de vibración más intenso y continuo: vibrar 1 segundo, pausa 0.5 segundos, repetir
                    val vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000, 500)
                    Log.d("AlarmReceiver", "Vibration pattern: ${vibrationPattern.contentToString()}")
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        // Crear efecto de vibración con repetición infinita (índice 1)
                        val effect = VibrationEffect.createWaveform(vibrationPattern, 1)
                        Log.d("AlarmReceiver", "VibrationEffect created, starting vibration...")
                        
                        // Crear AudioAttributes para alarmas (necesario para Android 10+)
                        val audioAttributes = AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .build()
                        
                        Log.d("AlarmReceiver", "AudioAttributes created: ContentType=${audioAttributes.contentType}, Usage=${audioAttributes.usage}")
                        
                        try {
                            currentVibrator?.vibrate(effect, audioAttributes)
                            Log.d("AlarmReceiver", "Vibration started with VibrationEffect and AudioAttributes (API 26+)")
                            
                            // Verificar inmediatamente si la vibración está activa
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                                val isVibrating = vibratorManager?.defaultVibrator?.let { vibrator ->
                                    try {
                                        // Intentar obtener información del estado del vibrador
                                        vibrator.hasVibrator() && vibrator.hasAmplitudeControl()
                                    } catch (e: Exception) {
                                        Log.w("AlarmReceiver", "Could not check vibrator state: ${e.message}")
                                        false
                                    }
                                } ?: false
                                Log.d("AlarmReceiver", "Vibrator state check (API 31+): isCapable=$isVibrating")
                            }
                            
                        } catch (e: SecurityException) {
                            Log.e("AlarmReceiver", "SecurityException during vibration: ${e.message}")
                            Log.e("AlarmReceiver", "This may indicate missing VIBRATE permission or system restrictions")
                            throw e
                        } catch (e: Exception) {
                            Log.e("AlarmReceiver", "Exception during vibration: ${e.message}")
                            Log.e("AlarmReceiver", "Attempting retry with simpler vibration pattern...")
                            
                            // Intento de re-intento con patrón más simple
                            try {
                                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                    try {
                                        val simpleEffect = VibrationEffect.createOneShot(1000, VibrationEffect.DEFAULT_AMPLITUDE)
                                        currentVibrator?.vibrate(simpleEffect, audioAttributes)
                                        Log.d("AlarmReceiver", "Retry vibration with simple pattern succeeded")
                                        
                                        // Si el simple funciona, intentar el patrón completo nuevamente
                                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                            try {
                                                val retryEffect = VibrationEffect.createWaveform(vibrationPattern, 1)
                                                currentVibrator?.vibrate(retryEffect, audioAttributes)
                                                Log.d("AlarmReceiver", "Retry vibration with full pattern succeeded")
                                            } catch (retryException: Exception) {
                                                Log.e("AlarmReceiver", "Retry with full pattern failed: ${retryException.message}")
                                            }
                                        }, 500)
                                        
                                    } catch (retryException: Exception) {
                                        Log.e("AlarmReceiver", "Simple retry vibration failed: ${retryException.message}")
                                    }
                                }, 1000)
                            } catch (retrySetupException: Exception) {
                                Log.e("AlarmReceiver", "Could not setup retry vibration: ${retrySetupException.message}")
                            }
                            throw e
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        // Para versiones anteriores, usar el método deprecated con repetición (índice 1)
                        Log.d("AlarmReceiver", "Using deprecated vibration method, starting vibration...")
                        try {
                            currentVibrator?.vibrate(vibrationPattern, 1)
                            Log.d("AlarmReceiver", "Vibration started with deprecated method (API < 26)")
                        } catch (e: Exception) {
                            Log.e("AlarmReceiver", "Exception during deprecated vibration: ${e.message}")
                            throw e
                        }
                    }
                    
                    // Verificar si la vibración realmente comenzó
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Log.d("AlarmReceiver", "Vibrator amplitude control: ${currentVibrator?.hasAmplitudeControl()}")
                    }
                    
                    // Verificar estado después de iniciar
                    Log.d("AlarmReceiver", "Vibration setup completed. Current vibrator: ${currentVibrator != null}")
                    
                    // Verificación periódica más robusta de la vibración
                    val vibrationChecker = object : Runnable {
                        private var checkCount = 0
                        private val maxChecks = 10
                        
                        override fun run() {
                            checkCount++
                            Log.d("AlarmReceiver", "Vibration check #$checkCount after ${checkCount} seconds...")
                            
                            if (currentVibrator != null) {
                                Log.d("AlarmReceiver", "Current vibrator still active: true")
                                
                                // Verificaciones adicionales del estado del vibrador
                                try {
                                    val hasVibrator = currentVibrator?.hasVibrator() ?: false
                                    Log.d("AlarmReceiver", "Vibrator hasVibrator(): $hasVibrator")
                                    
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        val hasAmplitudeControl = currentVibrator?.hasAmplitudeControl() ?: false
                                        Log.d("AlarmReceiver", "Vibrator hasAmplitudeControl(): $hasAmplitudeControl")
                                    }
                                    
                                    // Verificar configuración del sistema
                                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                                    val ringerMode = audioManager?.ringerMode
                                    Log.d("AlarmReceiver", "System ringer mode: $ringerMode (NORMAL=2, VIBRATE=1, SILENT=0)")
                                    
                                    // Verificar configuración de vibración del sistema
                                    val settings = context.contentResolver
                                    try {
                                        val hapticFeedback = android.provider.Settings.System.getInt(settings, android.provider.Settings.System.HAPTIC_FEEDBACK_ENABLED, 0)
                                        Log.d("AlarmReceiver", "System haptic feedback enabled: $hapticFeedback")
                                    } catch (e: Exception) {
                                        Log.w("AlarmReceiver", "Could not read haptic feedback setting: ${e.message}")
                                    }
                                    
                                } catch (e: Exception) {
                                    Log.e("AlarmReceiver", "Error during vibration state check: ${e.message}")
                                }
                                
                                // Continuar verificando si no hemos alcanzado el máximo
                                if (checkCount < maxChecks) {
                                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(this, 1000)
                                } else {
                                    Log.d("AlarmReceiver", "Vibration monitoring completed after $maxChecks checks")
                                }
                            } else {
                                Log.w("AlarmReceiver", "Vibration was cancelled or lost at check #$checkCount")
                            }
                        }
                    }
                    
                    // Iniciar la primera verificación después de 1 segundo
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(vibrationChecker, 1000)
                }
                
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error starting vibration: ${e.message}", e)
                // Intentar vibración simple como fallback
                try {
                    Log.d("AlarmReceiver", "Attempting fallback vibration...")
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    if (vibrator?.hasVibrator() == true) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            // Usar AudioAttributes también en el fallback para API 26+
                            val audioAttributes = AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .build()
                            val fallbackEffect = VibrationEffect.createWaveform(longArrayOf(0, 1000, 500, 1000, 500), 1)
                            vibrator.vibrate(fallbackEffect, audioAttributes)
                            Log.d("AlarmReceiver", "Fallback vibration started with VibrationEffect and AudioAttributes")
                        } else {
                            vibrator.vibrate(longArrayOf(0, 1000, 500, 1000, 500), 1) // Repetir infinitamente
                            Log.d("AlarmReceiver", "Fallback vibration started with pattern (API < 26)")
                        }
                    } else {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val audioAttributes = AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .build()
                            val simpleEffect = VibrationEffect.createOneShot(2000, VibrationEffect.DEFAULT_AMPLITUDE)
                            vibrator?.vibrate(simpleEffect, audioAttributes)
                            Log.d("AlarmReceiver", "Fallback simple vibration started with AudioAttributes")
                        } else {
                            vibrator?.vibrate(2000) // Vibrar por 2 segundos como último recurso
                            Log.d("AlarmReceiver", "Fallback simple vibration started (API < 26)")
                        }
                    }
                } catch (fallbackException: Exception) {
                    Log.e("AlarmReceiver", "Fallback vibration also failed: ${fallbackException.message}")
                }
            }

            // Intent para abrir MainActivity
            Log.d("AlarmReceiver", "Creating launch intent for MainActivity")
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("alarmId", alarmId)
                putExtra("title", title)
                putExtra("message", message)
                putExtra("screenRoute", "/alarm")
                putExtra("autoShowAlarm", true)
                putExtra("maxSnoozes", maxSnoozes)
                putExtra("snoozeDurationMinutes", snoozeDurationMinutes)
                putExtra("snoozeCount", 0)
                putExtra("maxVolumePercent", maxVolumePercent)
                putExtra("volumeRampUpDurationSeconds", volumeRampUpDurationSeconds)
                putExtra("tempVolumeReductionPercent", tempVolumeReductionPercent)
                putExtra("tempVolumeReductionDurationSeconds", tempVolumeReductionDurationSeconds)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            
            // AGREGAR LOG DETALLADO
            Log.d("AlarmReceiver", "Launch intent extras: alarmId=$alarmId, maxSnoozes=$maxSnoozes, snoozeDuration=$snoozeDurationMinutes, title=$title")
            
            val pendingLaunchIntent = PendingIntent.getActivity(
                context, alarmId + 1000, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Acción para detener la alarma
            Log.d("AlarmReceiver", "Creating stop intent for notification action")
            val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = STOP_ACTION
                putExtra("alarmId", alarmId)
            }
            val pendingStopIntent = PendingIntent.getBroadcast(
                context, alarmId + 2000, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Acción para posponer la alarma
            Log.d("AlarmReceiver", "Creating snooze intent for notification action")
            val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = SNOOZE_ACTION
                putExtra("alarmId", alarmId)
                putExtra("maxSnoozes", maxSnoozes)
                putExtra("snoozeDurationMinutes", snoozeDurationMinutes)
                putExtra("title", title)
                putExtra("message", message)
                putExtra("repeatDays", repeatDays.toIntArray())
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("maxVolumePercent", maxVolumePercent)
                putExtra("volumeRampUpDurationSeconds", volumeRampUpDurationSeconds)
                putExtra("tempVolumeReductionPercent", tempVolumeReductionPercent)
                putExtra("tempVolumeReductionDurationSeconds", tempVolumeReductionDurationSeconds)
            }
            val pendingSnoozeIntent = PendingIntent.getBroadcast(
                context, alarmId + 3000, snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            Log.d("AlarmReceiver", "Got NotificationManager service")

            // Crear canal de notificación (sin sonido ni vibración para evitar duplicación)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Log.d("AlarmReceiver", "Creating notification channel")
                try {
                    val channel = NotificationChannel(
                        NOTIFICATION_CHANNEL_ID, 
                        "Alarm Notifications", 
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        this.description = "Channel for alarm notifications"
                        this.setBypassDnd(true)
                        this.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                        // Deshabilitar vibración y sonido del canal para evitar duplicación
                        // La vibración y sonido se manejan directamente en el código
                        this.enableVibration(false)
                        this.enableLights(true)
                        this.setSound(null, null)
                    }
                    notificationManager.createNotificationChannel(channel)
                    Log.d("AlarmReceiver", "Notification channel created successfully")
                } catch (e: Exception) {
                    Log.e("AlarmReceiver", "Error creating notification channel", e)
                }
            }

            Log.d("AlarmReceiver", "Building notification")
            val notificationBuilder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(pendingLaunchIntent, true)
                .setContentIntent(pendingLaunchIntent)
                .addAction(0, "Apagar", pendingStopIntent)
                .addAction(0, "Posponer", pendingSnoozeIntent)
                .setAutoCancel(false)
                .setOngoing(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setSound(null)
                .setVibrate(null)

            try {
                // Show notification using alarmId directly as notificationId
                val notification = notificationBuilder.build()
                Log.d("AlarmReceiver", "Showing notification with ID: $alarmId")
                notificationManager.notify(alarmId, notification)
                Log.d("AlarmReceiver", "Notification shown with ID: $alarmId")
                
                // Registrar los IDs de notificación relacionados para depuración
                Log.d("AlarmReceiver", "Related notification IDs that might be used:")
                Log.d("AlarmReceiver", "  - Main notification ID: $alarmId")
                Log.d("AlarmReceiver", "  - Launch intent ID: ${alarmId + 1000}")
                Log.d("AlarmReceiver", "  - Stop intent ID: ${alarmId + 2000}")
                Log.d("AlarmReceiver", "  - Snooze intent ID: ${alarmId + 3000}")
                
                Log.d("AlarmReceiver", "Also starting MainActivity directly as backup")
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error showing notification", e)
            }

        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Error in handleAlarmTrigger", e)
        }
    }
}
