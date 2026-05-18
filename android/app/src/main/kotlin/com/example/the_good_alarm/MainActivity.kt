package com.andodevs.the_good_alarm

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.os.Looper
import android.view.WindowManager
import android.os.PowerManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import java.util.*
import org.json.JSONArray
import org.json.JSONObject
import android.os.Handler
// import android.os.Looper

data class AlarmData(
    val id: Int,
    val title: String,
    val message: String,
    val isActive: Boolean,
    val repeatDays: List<Int>,
    val isDaily: Boolean,
    val isWeekly: Boolean,
    val isWeekend: Boolean,
    val maxSnoozes: Int,
    val snoozeDurationMinutes: Int,
    val hour: Int,
    val minute: Int
)

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.andodevs.the_good_alarm/alarm"
    private val ALARM_ACTION = "com.andodevs.the_good_alarm.ALARM_TRIGGERED"
    private val HABIT_ACTION = "com.andodevs.the_good_alarm.HABIT_TRIGGERED"
    private val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
    private val SNOOZE_REQUEST_CODE_OFFSET = 1000000
    private lateinit var alarmManager: AlarmManager
    private lateinit var alarmReceiver: BroadcastReceiver
    private var methodChannel: MethodChannel? = null
    private var timeZoneReceiver: BroadcastReceiver? = null
    
    // Volume control variables
    private lateinit var audioManager: AudioManager
    
    private fun checkDndPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                startActivity(intent)
                return false
            }
        }
        return true
    }
    
    private val REQUEST_CODE_OVERLAY_PERMISSION = 123

    private fun checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, REQUEST_CODE_OVERLAY_PERMISSION)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_OVERLAY_PERMISSION) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Settings.canDrawOverlays(this)) {
                    Log.d("MainActivity", "Overlay permission granted")
                } else {
                    Log.w("MainActivity", "Overlay permission not granted")
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
        
        alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        checkDoNotDisturbPermission()
        checkOverlayPermission()
        requestBatteryOptimizationExemption()
        handleTimeZoneChange()
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Setup volume control channel
        val volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alarm_volume_control")
        volumeChannel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "VolumeChannel call: ${call.method}")
            when (call.method) {
                "startVolumeControl" -> {
                    val maxVolumePercent = call.argument<Int>("maxVolumePercent") ?: 100
                    val rampUpDurationSeconds = call.argument<Int>("rampUpDurationSeconds") ?: 0
                    Log.d("MainActivity", "Starting volume control: maxVolume=$maxVolumePercent%, rampUp=${rampUpDurationSeconds}s")
                    startVolumeControl(maxVolumePercent, rampUpDurationSeconds)
                    result.success(true)
                }
                "stopVolumeControl" -> {
                    Log.d("MainActivity", "Stopping volume control")
                    stopVolumeControl()
                    result.success(true)
                }
                "setTemporaryVolumeReduction" -> {
                    val reductionPercent = call.argument<Int>("reductionPercent") ?: 50
                    val durationSeconds = call.argument<Int>("durationSeconds") ?: 30
                    Log.d("MainActivity", "Setting temporary volume reduction: $reductionPercent% for ${durationSeconds}s")
                    setTemporaryVolumeReduction(reductionPercent, durationSeconds)
                    result.success(true)
                }
                "getCurrentVolume" -> {
                    val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                    val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    val volumePercent = (currentVolume * 100) / maxVolume
                    Log.d("MainActivity", "Current volume: $currentVolume/$maxVolume ($volumePercent%)")
                    result.success(volumePercent)
                }
                "cancelTemporaryVolumeReduction" -> {
                    Log.d("MainActivity", "Cancelling temporary volume reduction")
                    cancelTemporaryVolumeReduction()
                    result.success(true)
                }
                "setVolume" -> {
                    val volumePercent = call.argument<Int>("volumePercent")
                        ?: call.argument<Int>("percent")
                        ?: call.argument<Double>("volume")?.let { (it * 100.0).toInt() }
                        ?: 100
                    val clamped = volumePercent.coerceIn(0, 100)
                    Log.d("MainActivity", "Setting volume to $clamped%")
                    setVolume(clamped)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "MethodChannel call: ${call.method}")
            when (call.method) {
                "setAlarm" -> {
                    val id = call.argument<Int>("id") ?: return@setMethodCallHandler
                    val hour = call.argument<Int>("hour") ?: return@setMethodCallHandler
                    val minute = call.argument<Int>("minute") ?: return@setMethodCallHandler
                    val title = call.argument<String>("title") ?: "Alarma"
                    val message = call.argument<String>("message") ?: "¡Es hora de despertar!"
                    val repeatDays = call.argument<List<Int>>("repeatDays") ?: emptyList()
                    val isDaily = call.argument<Boolean>("isDaily") ?: false
                    val isWeekly = call.argument<Boolean>("isWeekly") ?: false
                    val isWeekend = call.argument<Boolean>("isWeekend") ?: false
                    val maxSnoozes = call.argument<Int>("maxSnoozes") ?: 3
                    val snoozeDurationMinutes = call.argument<Int>("snoozeDurationMinutes") ?: 5
                    val maxVolumePercent = call.argument<Int>("maxVolumePercent") ?: 100
                    val volumeRampUpDurationSeconds = call.argument<Int>("volumeRampUpDurationSeconds") ?: 30
                    val tempVolumeReductionPercent = call.argument<Int>("tempVolumeReductionPercent") ?: 50
                    val tempVolumeReductionDurationSeconds = call.argument<Int>("tempVolumeReductionDurationSeconds") ?: 60
                    
                    // Crear un objeto AlarmData con la hora y minuto recibidos
                    val alarm = AlarmData(
                        id = id,
                        title = title,
                        message = message,
                        isActive = true,
                        repeatDays = repeatDays,
                        isDaily = isDaily,
                        isWeekly = isWeekly,
                        isWeekend = isWeekend,
                        maxSnoozes = maxSnoozes,
                        snoozeDurationMinutes = snoozeDurationMinutes,
                        hour = hour,
                        minute = minute
                    )
                    
                    // Calcular el próximo tiempo de alarma
                    val nextTime = calculateNextAlarmTime(alarm)
                    
                    // Establecer la alarma solo si el tiempo calculado está en el futuro
                    if (nextTime > System.currentTimeMillis()) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                if (alarmManager.canScheduleExactAlarms()) {
                                    setAlarm(
                                        timeInMillis = nextTime,
                                        alarmId = id,
                                        requestCode = id,
                                        title = title,
                                        message = message,
                                        screenRoute = "/alarm",
                                        repeatDays = repeatDays,
                                        isDaily = isDaily,
                                        isWeekly = isWeekly,
                                        isWeekend = isWeekend,
                                        maxSnoozes = maxSnoozes,
                                        snoozeDurationMinutes = snoozeDurationMinutes,
                                        hour = hour,
                                        minute = minute,
                                        isSnooze = false,
                                        maxVolumePercent = maxVolumePercent,
                                        volumeRampUpDurationSeconds = volumeRampUpDurationSeconds,
                                        tempVolumeReductionPercent = tempVolumeReductionPercent,
                                        tempVolumeReductionDurationSeconds = tempVolumeReductionDurationSeconds
                                    )
                                    Log.d("MainActivity", "Alarm set for: ${Date(nextTime)}")
                                    result.success(true)
                                } else {
                                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                    intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                    startActivity(intent)
                                    result.error("PERMISSION_DENIED", "Se requiere permiso para programar alarmas exactas", null)
                                }
                            } else {
                                setAlarm(
                                    timeInMillis = nextTime,
                                    alarmId = id,
                                    requestCode = id,
                                    title = title,
                                    message = message,
                                    screenRoute = "/alarm",
                                    repeatDays = repeatDays,
                                    isDaily = isDaily,
                                    isWeekly = isWeekly,
                                    isWeekend = isWeekend,
                                    maxSnoozes = maxSnoozes,
                                    snoozeDurationMinutes = snoozeDurationMinutes,
                                    hour = hour,
                                    minute = minute,
                                    isSnooze = false,
                                    maxVolumePercent = maxVolumePercent,
                                    volumeRampUpDurationSeconds = volumeRampUpDurationSeconds,
                                    tempVolumeReductionPercent = tempVolumeReductionPercent,
                                    tempVolumeReductionDurationSeconds = tempVolumeReductionDurationSeconds
                                )
                                Log.d("MainActivity", "Alarm set for: ${Date(nextTime)}")
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("ALARM_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        Log.d("MainActivity", "Alarm time is in the past, not setting")
                        result.success(false)
                    }
                }
                "cancelAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    cancelAlarm(alarmId, cancelBase = true, cancelSnooze = true)
                    result.success(true)
                }
                "setHabit" -> {
                    val habitId = call.argument<String>("habitId") ?: return@setMethodCallHandler
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val timeInMillis = call.argument<Long>("timeInMillis") ?: return@setMethodCallHandler
                    val title = call.argument<String>("title") ?: "Hábito"
                    val message = call.argument<String>("message") ?: ""

                    if (timeInMillis <= System.currentTimeMillis()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (!alarmManager.canScheduleExactAlarms()) {
                                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                startActivity(intent)
                                result.error("PERMISSION_DENIED", "Se requiere permiso para programar alarmas exactas", null)
                                return@setMethodCallHandler
                            }
                        }
                        setHabitOccurrence(
                            timeInMillis = timeInMillis,
                            habitId = habitId,
                            occurrenceKey = occurrenceKey,
                            title = title,
                            message = message
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HABIT_ERROR", e.localizedMessage, null)
                    }
                }
                "setCalendarAlarm" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val timeInMillis = call.argument<Long>("timeInMillis") ?: return@setMethodCallHandler
                    val title = call.argument<String>("title") ?: "Calendario"
                    val message = call.argument<String>("message") ?: ""
                    val hour = call.argument<Int>("hour") ?: -1
                    val minute = call.argument<Int>("minute") ?: -1
                    val maxSnoozes = call.argument<Int>("maxSnoozes") ?: 3
                    val snoozeDurationMinutes = call.argument<Int>("snoozeDurationMinutes") ?: 5
                    val maxVolumePercent = call.argument<Int>("maxVolumePercent") ?: 100
                    val volumeRampUpDurationSeconds = call.argument<Int>("volumeRampUpDurationSeconds") ?: 30
                    val tempVolumeReductionPercent = call.argument<Int>("tempVolumeReductionPercent") ?: 30
                    val tempVolumeReductionDurationSeconds = call.argument<Int>("tempVolumeReductionDurationSeconds") ?: 60

                    if (timeInMillis <= System.currentTimeMillis()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (!alarmManager.canScheduleExactAlarms()) {
                                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                startActivity(intent)
                                result.error("PERMISSION_DENIED", "Se requiere permiso para programar alarmas exactas", null)
                                return@setMethodCallHandler
                            }
                        }

                        val alarmId = calendarAlarmId(occurrenceKey)
                        setAlarm(
                            timeInMillis = timeInMillis,
                            alarmId = alarmId,
                            requestCode = alarmId,
                            title = title,
                            message = message,
                            screenRoute = "/alarm",
                            repeatDays = emptyList(),
                            isDaily = false,
                            isWeekly = false,
                            isWeekend = false,
                            maxSnoozes = maxSnoozes,
                            snoozeDurationMinutes = snoozeDurationMinutes,
                            hour = hour,
                            minute = minute,
                            isSnooze = false,
                            maxVolumePercent = maxVolumePercent,
                            volumeRampUpDurationSeconds = volumeRampUpDurationSeconds,
                            tempVolumeReductionPercent = tempVolumeReductionPercent,
                            tempVolumeReductionDurationSeconds = tempVolumeReductionDurationSeconds
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALENDAR_ALARM_ERROR", e.localizedMessage, null)
                    }
                }
                "cancelCalendarAlarm" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val alarmId = calendarAlarmId(occurrenceKey)
                    cancelAlarm(alarmId, cancelBase = true, cancelSnooze = true)
                    result.success(true)
                }
                "cancelHabit" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    cancelHabitOccurrence(occurrenceKey)
                    result.success(true)
                }
                "clearHabitScreenFlag" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val key = "habit_screen_shown_$occurrenceKey"
                    getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(key).apply()
                    result.success(true)
                }
                "setMedication" -> {
                    val medicationId = call.argument<String>("medicationId") ?: return@setMethodCallHandler
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val timeInMillis = call.argument<Long>("timeInMillis") ?: return@setMethodCallHandler
                    val title = call.argument<String>("title") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val dosageAmount = call.argument<String>("dosageAmount") ?: ""
                    val dosageUnit = call.argument<String>("dosageUnit") ?: ""
                    setMedicationOccurrence(timeInMillis, medicationId, occurrenceKey, title, message, dosageAmount, dosageUnit)
                    result.success(true)
                }
                "cancelMedication" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    cancelMedicationOccurrence(occurrenceKey)
                    result.success(true)
                }
                "setMedicationConfirmation" -> {
                    val medicationId = call.argument<String>("medicationId") ?: return@setMethodCallHandler
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val timeInMillis = call.argument<Long>("timeInMillis") ?: return@setMethodCallHandler
                    val title = call.argument<String>("title") ?: ""
                    setMedicationConfirmationOccurrence(timeInMillis, medicationId, occurrenceKey, title)
                    result.success(true)
                }
                "cancelMedicationConfirmation" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    cancelMedicationConfirmationOccurrence(occurrenceKey)
                    result.success(true)
                }
                "clearMedicationScreenFlag" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val keyMain = "medication_screen_shown_$occurrenceKey"
                    val keyConfirm = "medication_confirm_screen_shown_$occurrenceKey"
                    val prefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                    prefs.edit().remove(keyMain).remove(keyConfirm).apply()
                    result.success(true)
                }
                "getPendingMedicationScreen" -> {
                    val prefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                    val pending = prefs.getString("pending_medication_screen", null)
                    prefs.edit().remove("pending_medication_screen").apply()
                    Log.d("MainActivity", "getPendingMedicationScreen: ${if (pending != null) "encontrado" else "vacío"}")
                    result.success(pending)
                }
                "dismissMedicationNotification" -> {
                    val occurrenceKey = call.argument<String>("occurrenceKey") ?: return@setMethodCallHandler
                    val isConfirmation = call.argument<Boolean>("isConfirmation") ?: false
                    val key = if (isConfirmation) "confirm|$occurrenceKey" else occurrenceKey
                    val h = key.hashCode().toLong()
                    val notifId = (Math.abs(h) % 2147483647L).toInt()
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(notifId)
                    Log.d("MainActivity", "dismissMedicationNotification key=$key notifId=$notifId")
                    result.success(true)
                }
                "setMusicStreamVolume" -> {
                    val volumePercent = call.argument<Int>("volumePercent") ?: 80
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val savedVol = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                    val targetVol = ((maxVol * volumePercent) / 100).coerceIn(0, maxVol)
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, 0)
                    Log.d("MainActivity", "setMusicStreamVolume: $volumePercent% -> $targetVol/$maxVol (saved=$savedVol)")
                    result.success(savedVol)
                }
                "restoreMusicStreamVolume" -> {
                    val savedVol = call.argument<Int>("savedVolume") ?: -1
                    if (savedVol >= 0) {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, savedVol.coerceIn(0, maxVol), 0)
                        Log.d("MainActivity", "restoreMusicStreamVolume: $savedVol")
                    }
                    result.success(true)
                }
                "stopAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    Log.d("MainActivity", "Stopping alarm: $alarmId")
                    AlarmReceiver.stopAlarmSound()
                    AlarmReceiver.stopVibration(this)
                    AlarmVolumeController.stop(this)
                    
                    cancelAlarm(alarmId, cancelBase = false, cancelSnooze = true)
                    cancelAllNotificationsForAlarm(alarmId)
                    
                    // Limpiar la marca de pantalla mostrada para permitir futuras activaciones
                    val alarmScreenKey = "alarm_screen_shown_$alarmId"
                    getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                    Log.d("MainActivity", "Cleared alarm screen flag for alarm $alarmId")
                    
                    pushAlarmEvent(type = "stopped", alarmId = alarmId, newTimeInMillis = null)
                    methodChannel?.invokeMethod("alarmManuallyStopped", mapOf("alarmId" to alarmId))
                    result.success(true)
                }
                "clearAlarmScreenFlag" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val alarmScreenKey = "alarm_screen_shown_$alarmId"
                    getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                    Log.d("MainActivity", "Manually cleared alarm screen flag for alarm $alarmId")
                    result.success(true)
                }
                "snoozeAlarm" -> {
                    Log.d("MainActivity", "=== SNOOZE ALARM METHOD START ===")
                    val alarmId = call.argument<Int>("alarmId")
                    val maxSnoozes = call.argument<Int>("maxSnoozes") ?: 3
                    val snoozeDurationMinutes = call.argument<Int>("snoozeDurationMinutes") ?: 5
                    
                    // Logs detallados
                    Log.d("MainActivity", "Received snooze parameters:")
                    Log.d("MainActivity", "  - alarmId: $alarmId")
                    Log.d("MainActivity", "  - maxSnoozes: $maxSnoozes")
                    Log.d("MainActivity", "  - snoozeDurationMinutes: $snoozeDurationMinutes")
                    
                    Log.d("MainActivity", "Snoozing alarm ID: $alarmId for $snoozeDurationMinutes minutes, max: $maxSnoozes")
                    
                    if (alarmId != null) {
                        AlarmReceiver.stopAlarmSound()
                        AlarmReceiver.stopVibration(this)
                        AlarmVolumeController.stop(this)
                        
                        cancelAlarm(alarmId, cancelBase = false, cancelSnooze = true)
                        cancelAllNotificationsForAlarm(alarmId)
                        
                        // Limpiar la marca de pantalla mostrada para permitir futuras activaciones
                        val alarmScreenKey = "alarm_screen_shown_$alarmId"
                        getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                        Log.d("MainActivity", "Cleared alarm screen flag for snoozed alarm $alarmId")
                        
                        val calendar = Calendar.getInstance()
                        Log.d("MainActivity", "Current time before adding snooze: ${calendar.time}")
                        calendar.add(Calendar.MINUTE, snoozeDurationMinutes)
                        Log.d("MainActivity", "New snooze time after adding $snoozeDurationMinutes minutes: ${calendar.time}")
                        
                        setAlarm(
                            timeInMillis = calendar.timeInMillis,
                            alarmId = alarmId,
                            requestCode = alarmId + SNOOZE_REQUEST_CODE_OFFSET,
                            title = "Alarma Pospuesta",
                            message = "¡Es hora de despertar!",
                            screenRoute = "/alarm",
                            repeatDays = emptyList(),
                            isDaily = false,
                            isWeekly = false,
                            isWeekend = false,
                            maxSnoozes = maxSnoozes,
                            snoozeDurationMinutes = snoozeDurationMinutes,
                            hour = -1,
                            minute = -1,
                            isSnooze = true,
                            maxVolumePercent = 100,
                            volumeRampUpDurationSeconds = 30,
                            tempVolumeReductionPercent = 50,
                            tempVolumeReductionDurationSeconds = 60
                        )
                        
                        Log.d("MainActivity", "Alarm rescheduled with correct parameters")
                        
                        pushAlarmEvent(type = "snoozed", alarmId = alarmId, newTimeInMillis = calendar.timeInMillis)
                        methodChannel?.invokeMethod("alarmManuallySnoozed", mapOf(
                            "alarmId" to alarmId, 
                            "newTimeInMillis" to calendar.timeInMillis
                        ))
                        
                        result.success("Alarm snoozed for $snoozeDurationMinutes minutes")
                        Log.d("MainActivity", "Alarm snoozed successfully")
                    } else {
                        Log.e("MainActivity", "Invalid alarm ID for snooze")
                        result.error("INVALID_ALARM_ID", "Alarm ID is required", null)
                    }
                    Log.d("MainActivity", "=== SNOOZE ALARM METHOD END ===")
                }
                "checkDoNotDisturbPermission" -> {
                    result.success(checkDoNotDisturbPermission())
                }
                "requestDoNotDisturbPermission" -> {
                    requestDoNotDisturbPermission()
                    result.success(true)
                }
                "notifyAlarmRinging" -> {
                    Log.d("MainActivity", "Alarm ringing notification received")
                    result.success(null)
                }
                "getAndClearAlarmEvents" -> {
                    result.success(getAndClearAlarmEvents())
                }
                "getSystemSounds" -> {
                    val sounds = getSystemAlarmSounds()
                    result.success(sounds)
                }
                "playSound" -> {
                    val soundUri = call.argument<String>("soundUri")
                    if (soundUri != null) {
                        playSound(Uri.parse(soundUri))
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Sound URI is required", null)
                    }
                }
                "vibrate" -> {
                    val pattern = call.argument<List<Long>>("pattern")?.toLongArray() 
                        ?: longArrayOf(0, 500, 500, 500)
                    Log.d("MainActivity", "Vibrate method called from Flutter with pattern: ${pattern.contentToString()}")
                    vibrate(pattern)
                    result.success(true)
                }
                "checkVibratorCapability" -> {
                    val hasVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                        vibratorManager?.defaultVibrator?.hasVibrator() == true
                    } else {
                        @Suppress("DEPRECATION")
                        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                        vibrator?.hasVibrator() == true
                    }
                    Log.d("MainActivity", "Device vibrator capability: $hasVibrator")
                    result.success(hasVibrator)
                }
                "restoreAlarmsAfterBoot" -> {
                    val alarmsJson = call.argument<String>("alarmsData")
                    if (alarmsJson != null) {
                        restoreAlarmsFromJson(alarmsJson)
                        result.success(true)
                    } else {
                        result.error("NO_DATA", "No alarm data provided", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 100)
                Log.d("MainActivity", "Requesting POST_NOTIFICATIONS permission")
            }
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                startActivity(intent)
                Log.d("MainActivity", "Redirecting to exact alarm permission settings")
            }
        }
        
        handleAlarmIntent()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent called with action: ${intent.action}")
        setIntent(intent)
        handleAlarmIntent()
    }

    private fun handleAlarmIntent() {
        if (intent == null) {
            Log.d("MainActivity", "handleAlarmIntent: intent is null")
            return
        }
        
        val alarmIdFromIntent = intent.getIntExtra("alarmId", -1)
        Log.d("MainActivity", "handleAlarmIntent: action=${intent.action}, alarmId=$alarmIdFromIntent")

        when (intent.action) {
            "STOP_ALARM_FROM_NOTIFICATION" -> {
                if (alarmIdFromIntent != -1) {
                    Log.d("MainActivity", "Stopping alarm from notification: $alarmIdFromIntent")
                    AlarmReceiver.stopAlarmSound()
                    AlarmReceiver.stopVibration(this)
                    
                    // Cancelar la alarma y todas las notificaciones asociadas
                    cancelAlarm(alarmIdFromIntent, cancelBase = false, cancelSnooze = true)
                    
                    // Cancel all notifications for this alarm
                    cancelAllNotificationsForAlarm(alarmIdFromIntent)
                    
                    // Limpiar la marca de pantalla mostrada
                    val alarmScreenKey = "alarm_screen_shown_$alarmIdFromIntent"
                    getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                    
                    Log.d("MainActivity", "Invoking Flutter method: alarmManuallyStopped")
                    methodChannel?.invokeMethod("alarmManuallyStopped", mapOf("alarmId" to alarmIdFromIntent))
                    Log.d("MainActivity", "Invoking Flutter method: closeAlarmScreenIfOpen")
                    methodChannel?.invokeMethod("closeAlarmScreenIfOpen", mapOf("alarmId" to alarmIdFromIntent))
                    pushAlarmEvent(type = "stopped", alarmId = alarmIdFromIntent, newTimeInMillis = null)
                }
            }
            "SNOOZE_ALARM_FROM_NOTIFICATION" -> {
                if (alarmIdFromIntent != -1) {
                    Log.d("MainActivity", "Snoozing alarm from notification: $alarmIdFromIntent")
                    AlarmReceiver.stopAlarmSound()
                    AlarmReceiver.stopVibration(this)
                    cancelAlarm(alarmIdFromIntent, cancelBase = false, cancelSnooze = true)
                    
                    // Cancel all notifications for this alarm
                    cancelAllNotificationsForAlarm(alarmIdFromIntent)
                    
                    // Limpiar la marca de pantalla mostrada
                    val alarmScreenKey = "alarm_screen_shown_$alarmIdFromIntent"
                    getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()
                    
                    val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
                    val calendar = Calendar.getInstance()
                    calendar.add(Calendar.MINUTE, snoozeDurationMinutes) // Usar la duración correcta
                    Log.d("MainActivity", "Setting new alarm for $snoozeDurationMinutes minutes later: ${calendar.time}")
                    setAlarm(
                        timeInMillis = calendar.timeInMillis,
                        alarmId = alarmIdFromIntent,
                        requestCode = alarmIdFromIntent + SNOOZE_REQUEST_CODE_OFFSET,
                        title = intent.getStringExtra("title") ?: "Alarma Pospuesta",
                        message = intent.getStringExtra("message") ?: "¡Es hora de despertar!",
                        screenRoute = "/alarm",
                        repeatDays = emptyList(),
                        isDaily = false,
                        isWeekly = false,
                        isWeekend = false,
                        maxSnoozes = intent.getIntExtra("maxSnoozes", 3),
                        snoozeDurationMinutes = snoozeDurationMinutes,
                        hour = -1,
                        minute = -1,
                        isSnooze = true,
                        maxVolumePercent = intent.getIntExtra("maxVolumePercent", 100),
                        volumeRampUpDurationSeconds = intent.getIntExtra("volumeRampUpDurationSeconds", 30),
                        tempVolumeReductionPercent = intent.getIntExtra("tempVolumeReductionPercent", 50),
                        tempVolumeReductionDurationSeconds = intent.getIntExtra("tempVolumeReductionDurationSeconds", 60)
                    )
                    pushAlarmEvent(type = "snoozed", alarmId = alarmIdFromIntent, newTimeInMillis = calendar.timeInMillis)
                    Log.d("MainActivity", "Invoking Flutter method: alarmManuallySnoozed")
                    methodChannel?.invokeMethod("alarmManuallySnoozed", mapOf("alarmId" to alarmIdFromIntent, "newTimeInMillis" to calendar.timeInMillis))
                    Log.d("MainActivity", "Invoking Flutter method: closeAlarmScreenIfOpen")
                    methodChannel?.invokeMethod("closeAlarmScreenIfOpen", mapOf("alarmId" to alarmIdFromIntent))
                }
            }
            else -> {
                val title = intent.getStringExtra("title")
                val message = intent.getStringExtra("message")
                val screenRoute = intent.getStringExtra("screenRoute")
                val autoShow = intent.getBooleanExtra("autoShowAlarm", false)
                val maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
                val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
                val snoozeCount = intent.getIntExtra("snoozeCount", 0)
                val maxVolumePercent = intent.getIntExtra("maxVolumePercent", 100)
                val volumeRampUpDurationSeconds = intent.getIntExtra("volumeRampUpDurationSeconds", 30)
                val tempVolumeReductionPercent = intent.getIntExtra("tempVolumeReductionPercent", 50)
                val tempVolumeReductionDurationSeconds = intent.getIntExtra("tempVolumeReductionDurationSeconds", 60)

                Log.d("MainActivity", "Checking if should show alarm screen - alarmId: $alarmIdFromIntent, screenRoute: $screenRoute, autoShow: $autoShow")
                Log.d("MainActivity", "Alarm parameters: maxSnoozes=$maxSnoozes, snoozeDuration=$snoozeDurationMinutes, snoozeCount=$snoozeCount")
                Log.d("MainActivity", "Volume parameters: maxVolume=$maxVolumePercent%, rampUp=${volumeRampUpDurationSeconds}s, tempReduction=$tempVolumeReductionPercent% for ${tempVolumeReductionDurationSeconds}s")
                Log.d("MainActivity", "Intent extras: ${intent.extras?.keySet()?.joinToString()}") // AGREGAR ESTE LOG
                
                if (alarmIdFromIntent != -1 && screenRoute == "/alarm" && autoShow) {
                    // Verificar si ya se mostró la pantalla para esta alarma
                    val alarmScreenKey = "alarm_screen_shown_$alarmIdFromIntent"
                    val prefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                    val alreadyShown = prefs.getBoolean(alarmScreenKey, false)
                    
                    if (!alreadyShown) {
                        Log.d("MainActivity", "Setting window flags to show over lock screen")
                        try {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                            Log.d("MainActivity", "Window flags set successfully")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error setting window flags", e)
                        }
                        
                        // Marcar que ya se mostró la pantalla
                        prefs.edit().putBoolean(alarmScreenKey, true).apply()
                        
                        Log.d("MainActivity", "Scheduling delayed call to show alarm screen")
                        Handler(Looper.getMainLooper()).postDelayed({
                            Log.d("MainActivity", "Now showing alarm screen via Flutter")
                            Log.d("MainActivity", "Passing parameters: alarmId=$alarmIdFromIntent, maxSnoozes=$maxSnoozes, snoozeDuration=$snoozeDurationMinutes, snoozeCount=$snoozeCount")
                            methodChannel?.invokeMethod("showAlarmScreen", mapOf(
                                "alarmId" to alarmIdFromIntent,
                                "title" to title,
                                "message" to message,
                                "maxSnoozes" to maxSnoozes,
                                "snoozeDurationMinutes" to snoozeDurationMinutes,
                                "snoozeCount" to snoozeCount,
                                "maxVolumePercent" to maxVolumePercent,
                                "volumeRampUpDurationSeconds" to volumeRampUpDurationSeconds,
                                "tempVolumeReductionPercent" to tempVolumeReductionPercent,
                                "tempVolumeReductionDurationSeconds" to tempVolumeReductionDurationSeconds
                            ))
                        }, 500)
                    } else {
                        Log.d("MainActivity", "Alarm screen already shown for alarm $alarmIdFromIntent, skipping")
                    }
                }

                val habitIdFromIntent = intent.getStringExtra("habitId")
                val occurrenceKeyFromIntent = intent.getStringExtra("occurrenceKey")
                val scheduledAtLocalMillis = intent.getLongExtra("scheduledAtLocalMillis", -1L)
                if (screenRoute == "/habit" && autoShow && !habitIdFromIntent.isNullOrBlank() && !occurrenceKeyFromIntent.isNullOrBlank()) {
                    val habitScreenKey = "habit_screen_shown_$occurrenceKeyFromIntent"
                    val prefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                    val alreadyShown = prefs.getBoolean(habitScreenKey, false)

                    if (!alreadyShown) {
                        try {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                        } catch (_: Exception) {}

                        prefs.edit().putBoolean(habitScreenKey, true).apply()

                        Handler(Looper.getMainLooper()).postDelayed({
                            methodChannel?.invokeMethod(
                                "showHabitScreen",
                                mapOf(
                                    "habitId" to habitIdFromIntent,
                                    "occurrenceKey" to occurrenceKeyFromIntent,
                                    "scheduledAtLocalMillis" to scheduledAtLocalMillis
                                )
                            )
                        }, 300)
                    }
                }

                val medicationIdFromIntent = intent.getStringExtra("medicationId")
                val medOccurrenceKeyFromIntent = intent.getStringExtra("occurrenceKey")
                val medScheduledAtLocalMillis = intent.getLongExtra("scheduledAtLocalMillis", -1L)
                val medTitle = intent.getStringExtra("title") ?: ""
                val medMessage = intent.getStringExtra("message") ?: ""
                val medDosageAmount = intent.getStringExtra("dosageAmount") ?: ""
                val medDosageUnit = intent.getStringExtra("dosageUnit") ?: ""
                val isConfirmation = intent.getBooleanExtra("isConfirmation", false)

                if ((screenRoute == "/medication" || screenRoute == "/medication_confirm") &&
                    autoShow &&
                    !medicationIdFromIntent.isNullOrBlank() &&
                    !medOccurrenceKeyFromIntent.isNullOrBlank()
                ) {
                    val medScreenKey = if (screenRoute == "/medication_confirm")
                        "medication_confirm_screen_shown_$medOccurrenceKeyFromIntent"
                    else
                        "medication_screen_shown_$medOccurrenceKeyFromIntent"
                    val prefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                    val alreadyShown = prefs.getBoolean(medScreenKey, false)

                    if (!alreadyShown) {
                        try {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                        } catch (_: Exception) {}

                        prefs.edit().putBoolean(medScreenKey, true).apply()

                        // Guardar como pending en prefs para cold start (Flutter no listo aún)
                        val pendingJson = JSONObject().apply {
                            put("medicationId", medicationIdFromIntent)
                            put("occurrenceKey", medOccurrenceKeyFromIntent)
                            put("scheduledAtLocalMillis", medScheduledAtLocalMillis)
                            put("title", medTitle)
                            put("message", medMessage)
                            put("dosageAmount", medDosageAmount)
                            put("dosageUnit", medDosageUnit)
                            put("isConfirmation", isConfirmation)
                            put("screenRoute", screenRoute)
                            put("timestamp", System.currentTimeMillis())
                        }
                        prefs.edit().putString("pending_medication_screen", pendingJson.toString()).apply()
                        Log.d("MainActivity", "Guardado pending_medication_screen en alarm_prefs")

                        val methodName = if (screenRoute == "/medication_confirm") "showMedicationConfirmScreen" else "showMedicationScreen"
                        Handler(Looper.getMainLooper()).postDelayed({
                            methodChannel?.invokeMethod(
                                methodName,
                                mapOf(
                                    "medicationId" to medicationIdFromIntent,
                                    "occurrenceKey" to medOccurrenceKeyFromIntent,
                                    "scheduledAtLocalMillis" to medScheduledAtLocalMillis,
                                    "title" to medTitle,
                                    "message" to medMessage,
                                    "dosageAmount" to medDosageAmount,
                                    "dosageUnit" to medDosageUnit,
                                    "isConfirmation" to isConfirmation
                                )
                            )
                        }, 300)
                    }
                }
            }
        }
    }
    
    private fun setAlarm(
        timeInMillis: Long,
        alarmId: Int,
        requestCode: Int,
        title: String,
        message: String,
        screenRoute: String,
        repeatDays: List<Int>,
        isDaily: Boolean,
        isWeekly: Boolean,
        isWeekend: Boolean,
        maxSnoozes: Int,
        snoozeDurationMinutes: Int,
        hour: Int,
        minute: Int,
        isSnooze: Boolean,
        maxVolumePercent: Int = 100,
        volumeRampUpDurationSeconds: Int = 30,
        tempVolumeReductionPercent: Int = 50,
        tempVolumeReductionDurationSeconds: Int = 60
    ) {
        try {
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION
                putExtra("alarmId", alarmId)
                putExtra("title", title)
                putExtra("message", message)
                putExtra("screenRoute", screenRoute)
                putExtra("repeatDays", repeatDays.toIntArray())
                putExtra("isDaily", isDaily)
                putExtra("isWeekly", isWeekly)
                putExtra("isWeekend", isWeekend)
                putExtra("maxSnoozes", maxSnoozes)
                putExtra("snoozeDurationMinutes", snoozeDurationMinutes)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("isSnooze", isSnooze)
                putExtra("maxVolumePercent", maxVolumePercent)
                putExtra("volumeRampUpDurationSeconds", volumeRampUpDurationSeconds)
                putExtra("tempVolumeReductionPercent", tempVolumeReductionPercent)
                putExtra("tempVolumeReductionDurationSeconds", tempVolumeReductionDurationSeconds)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
            }

            Log.d("MainActivity", "Alarm set for: ${Date(timeInMillis)}")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting alarm", e)
        }
    }

    private fun setHabitOccurrence(
        timeInMillis: Long,
        habitId: String,
        occurrenceKey: String,
        title: String,
        message: String
    ) {
        val intent = Intent(this, HabitReceiver::class.java).apply {
            action = HABIT_ACTION
            putExtra("habitId", habitId)
            putExtra("occurrenceKey", occurrenceKey)
            putExtra("title", title)
            putExtra("message", message)
            putExtra("scheduledAtLocalMillis", timeInMillis)
            putExtra("screenRoute", "/habit")
            putExtra("autoShowAlarm", true)
        }

        val requestCode = stableRequestCode(occurrenceKey)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timeInMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                timeInMillis,
                pendingIntent
            )
        }

        Log.d("MainActivity", "Habit occurrence set for: ${Date(timeInMillis)} key=$occurrenceKey")
    }

    private fun cancelHabitOccurrence(occurrenceKey: String) {
        val intent = Intent(this, HabitReceiver::class.java).apply {
            action = HABIT_ACTION
            putExtra("occurrenceKey", occurrenceKey)
        }
        val requestCode = stableRequestCode(occurrenceKey)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun stableRequestCode(key: String): Int {
        val h = key.hashCode().toLong()
        val abs = kotlin.math.abs(h)
        return (abs % 2147483647L).toInt()
    }

    // ─── MEDICATION ─────────────────────────────────────────────────────────────

    private fun setMedicationOccurrence(
        timeInMillis: Long,
        medicationId: String,
        occurrenceKey: String,
        title: String,
        message: String,
        dosageAmount: String,
        dosageUnit: String
    ) {
        val intent = Intent(this, MedicationReceiver::class.java).apply {
            action = MedicationReceiver.MEDICATION_ACTION
            putExtra("medicationId", medicationId)
            putExtra("occurrenceKey", occurrenceKey)
            putExtra("title", title)
            putExtra("message", message)
            putExtra("dosageAmount", dosageAmount)
            putExtra("dosageUnit", dosageUnit)
            putExtra("scheduledAtLocalMillis", timeInMillis)
        }
        val requestCode = stableRequestCode(occurrenceKey)
        val pendingIntent = PendingIntent.getBroadcast(
            this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        Log.d("MainActivity", "Medication occurrence set: key=$occurrenceKey time=${java.util.Date(timeInMillis)}")
    }

    private fun setMedicationConfirmationOccurrence(
        timeInMillis: Long,
        medicationId: String,
        occurrenceKey: String,
        title: String
    ) {
        val intent = Intent(this, MedicationReceiver::class.java).apply {
            action = MedicationReceiver.MEDICATION_CONFIRM_ACTION
            putExtra("medicationId", medicationId)
            putExtra("occurrenceKey", occurrenceKey)
            putExtra("title", title)
            putExtra("scheduledAtLocalMillis", timeInMillis)
            putExtra("isConfirmation", true)
        }
        val confirmationOffset = 2_000_000
        val requestCode = stableRequestCode(occurrenceKey) + confirmationOffset
        val pendingIntent = PendingIntent.getBroadcast(
            this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        Log.d("MainActivity", "Medication confirmation set: key=$occurrenceKey time=${java.util.Date(timeInMillis)}")
    }

    private fun cancelMedicationOccurrence(occurrenceKey: String) {
        val intent = Intent(this, MedicationReceiver::class.java).apply {
            action = MedicationReceiver.MEDICATION_ACTION
            putExtra("occurrenceKey", occurrenceKey)
        }
        val requestCode = stableRequestCode(occurrenceKey)
        val pendingIntent = PendingIntent.getBroadcast(
            this, requestCode, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun cancelMedicationConfirmationOccurrence(occurrenceKey: String) {
        val intent = Intent(this, MedicationReceiver::class.java).apply {
            action = MedicationReceiver.MEDICATION_CONFIRM_ACTION
            putExtra("occurrenceKey", occurrenceKey)
        }
        val confirmationOffset = 2_000_000
        val requestCode = stableRequestCode(occurrenceKey) + confirmationOffset
        val pendingIntent = PendingIntent.getBroadcast(
            this, requestCode, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun calendarAlarmId(occurrenceKey: String): Int {
        val base = stableRequestCode("calendar|$occurrenceKey")
        val mod = base % 1000000000
        return 1000000000 + mod
    }

    private fun checkDoNotDisturbPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return notificationManager.isNotificationPolicyAccessGranted
        }
        return true
    }

    private fun requestDoNotDisturbPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            startActivity(intent)
        }
    }

    private fun cancelAllNotificationsForAlarm(alarmId: Int) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Cancel notifications using direct and related IDs
            val notificationIds = listOf(
                alarmId,
                alarmId + 1000,
                alarmId + 2000,
                alarmId + 3000,
                alarmId + 10000,
                alarmId + 20000
            )
            
            notificationIds.forEach { notificationId ->
                try {
                    notificationManager.cancel(notificationId)
                    Log.d("MainActivity", "Cancelled notification with ID: $notificationId")
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error cancelling notification $notificationId: ${e.message}")
                }
            }
            
            // Check SharedPreferences for saved notification IDs
            val prefs = getSharedPreferences("alarm_notifications", Context.MODE_PRIVATE)
            val savedNotificationId = prefs.getInt("notification_$alarmId", -1)
            if (savedNotificationId != -1) {
                notificationManager.cancel(savedNotificationId)
                Log.d("MainActivity", "Cancelled saved notification with ID: $savedNotificationId")
                prefs.edit().remove("notification_$alarmId").apply()
            }
            
            // On Android M+, iterate through active notifications to cancel any matching the alarmId
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    val activeNotifications = notificationManager.activeNotifications
                    activeNotifications.forEach { notification ->
                        if (notification.id == alarmId || 
                            notification.id == alarmId + 1000 ||
                            notification.id == alarmId + 2000 ||
                            notification.id == alarmId + 3000 ||
                            notification.id == alarmId + 10000 ||
                            notification.id == alarmId + 20000) {
                            notificationManager.cancel(notification.id)
                            Log.d("MainActivity", "Cancelled active notification with ID: ${notification.id}")
                        }
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error checking active notifications: ${e.message}")
                }
            }
            
            Log.d("MainActivity", "All notifications canceled for alarmId: $alarmId")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error canceling notifications for alarmId: $alarmId", e)
        }
    }

    private fun cancelAlarm(alarmId: Int, cancelBase: Boolean, cancelSnooze: Boolean) {
        try {
            if (cancelBase) {
                val intent = Intent(this, AlarmReceiver::class.java).apply {
                    action = ALARM_ACTION
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
            if (cancelSnooze) {
                val snoozeIntent = Intent(this, AlarmReceiver::class.java).apply {
                    action = ALARM_ACTION
                }
                val pendingSnoozeIntent = PendingIntent.getBroadcast(
                    this,
                    alarmId + SNOOZE_REQUEST_CODE_OFFSET,
                    snoozeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingSnoozeIntent)
                pendingSnoozeIntent.cancel()
            }

            // Use the new centralized notification cancellation method
            cancelAllNotificationsForAlarm(alarmId)

            val alarmScreenKey = "alarm_screen_shown_$alarmId"
            getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE).edit().remove(alarmScreenKey).apply()

            Log.d("MainActivity", "Alarm and all related notifications canceled successfully for alarmId: $alarmId")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error canceling alarm for alarmId: $alarmId", e)
        }
    }

    // IMPLEMENTACIÓN CORREGIDA: requestBatteryOptimizationExemption
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val packageName = packageName
            
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    Log.d("MainActivity", "Requesting battery optimization exemption")
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error requesting battery optimization exemption", e)
                    // Fallback: abrir configuración general de batería
                    try {
                        val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(fallbackIntent)
                    } catch (e2: Exception) {
                        Log.e("MainActivity", "Error opening battery settings", e2)
                    }
                }
            } else {
                Log.d("MainActivity", "App already exempted from battery optimization")
            }
        }
    }

    // IMPLEMENTACIÓN CORREGIDA: handleTimeZoneChange
    private fun handleTimeZoneChange() {
        timeZoneReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_TIMEZONE_CHANGED -> {
                        Log.d("MainActivity", "Time zone changed, notifying Flutter")
                        methodChannel?.invokeMethod("timeZoneChanged", mapOf(
                            "newTimeZone" to TimeZone.getDefault().id,
                            "timestamp" to System.currentTimeMillis()
                        ))
                    }
                    Intent.ACTION_TIME_CHANGED -> {
                        Log.d("MainActivity", "System time changed, notifying Flutter")
                        methodChannel?.invokeMethod("systemTimeChanged", mapOf(
                            "timestamp" to System.currentTimeMillis()
                        ))
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
        }
        
        try {
            registerReceiver(timeZoneReceiver, filter)
            Log.d("MainActivity", "Time zone change receiver registered")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error registering time zone receiver", e)
        }
    }

    // FUNCIÓN CORREGIDA: restoreAlarmsFromJson usando JSONObject en lugar de Gson
    private fun restoreAlarmsFromJson(alarmsJson: String) {
        try {
            val jsonArray = JSONArray(alarmsJson)
            
            for (i in 0 until jsonArray.length()) {
                val alarmJson = jsonArray.getJSONObject(i)
                
                val alarm = AlarmData(
                    id = alarmJson.getInt("id"),
                    title = alarmJson.getString("title"),
                    message = alarmJson.getString("message"),
                    isActive = alarmJson.getBoolean("isActive"),
                    repeatDays = parseIntArray(alarmJson.optJSONArray("repeatDays")),
                    isDaily = alarmJson.optBoolean("isDaily", false),
                    isWeekly = alarmJson.optBoolean("isWeekly", false),
                    isWeekend = alarmJson.optBoolean("isWeekend", false),
                    maxSnoozes = alarmJson.optInt("maxSnoozes", 3),
                    snoozeDurationMinutes = alarmJson.optInt("snoozeDurationMinutes", 5),
                    hour = alarmJson.optInt("hour", 0),
                    minute = alarmJson.optInt("minute", 0)
                )
                
                if (alarm.isActive) {
                    val nextTime = calculateNextAlarmTime(alarm)
                    if (nextTime > System.currentTimeMillis()) {
                        setAlarm(
                            timeInMillis = nextTime,
                            alarmId = alarm.id,
                            requestCode = alarm.id,
                            title = alarm.title,
                            message = alarm.message,
                            screenRoute = "/alarm",
                            repeatDays = alarm.repeatDays,
                            isDaily = alarm.isDaily,
                            isWeekly = alarm.isWeekly,
                            isWeekend = alarm.isWeekend,
                            maxSnoozes = alarm.maxSnoozes,
                            snoozeDurationMinutes = alarm.snoozeDurationMinutes,
                            hour = alarm.hour,
                            minute = alarm.minute,
                            isSnooze = false
                        )
                        Log.d("MainActivity", "Restored alarm: ${alarm.title} for ${Date(nextTime)}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error restoring alarms from JSON", e)
        }
    }
    
    private fun parseIntArray(jsonArray: JSONArray?): List<Int> {
        if (jsonArray == null) return emptyList()
        val result = mutableListOf<Int>()
        for (i in 0 until jsonArray.length()) {
            result.add(jsonArray.getInt(i))
        }
        return result
    }

    private fun calculateNextAlarmTime(alarm: AlarmData): Long {
        val calendar = Calendar.getInstance()
        val now = Calendar.getInstance()

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

        val effectiveRepeatDays = when {
            alarm.repeatDays.isNotEmpty() -> alarm.repeatDays
            alarm.isDaily -> listOf(1, 2, 3, 4, 5, 6, 7)
            alarm.isWeekend -> listOf(6, 7)
            alarm.isWeekly -> listOf(calendarDayToRepeatDay(now.get(Calendar.DAY_OF_WEEK)))
            else -> emptyList()
        }
        
        // SIEMPRE usar la fecha actual como base
        calendar.set(Calendar.YEAR, now.get(Calendar.YEAR))
        calendar.set(Calendar.MONTH, now.get(Calendar.MONTH))
        calendar.set(Calendar.DAY_OF_MONTH, now.get(Calendar.DAY_OF_MONTH))
        calendar.set(Calendar.HOUR_OF_DAY, alarm.hour)
        calendar.set(Calendar.MINUTE, alarm.minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        
        Log.d("MainActivity", "Calculating alarm time - Current: ${now.time}, Target hour: ${alarm.hour}:${alarm.minute}")
        
        if (effectiveRepeatDays.isNotEmpty()) {
            val calendarDays = effectiveRepeatDays.map { day ->
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
            }
            
            val currentDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            
            // Si hoy está en los días de repetición y la hora no ha pasado
            if (calendarDays.contains(currentDayOfWeek) && calendar.after(now)) {
                Log.d("MainActivity", "Repeat alarm: scheduling for today")
                return calendar.timeInMillis
            }
            
            // Buscar el próximo día válido
            var daysToAdd = 1
            while (daysToAdd <= 7) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
                if (calendarDays.contains(calendar.get(Calendar.DAY_OF_WEEK))) {
                    Log.d("MainActivity", "Repeat alarm: scheduling for next occurrence in $daysToAdd days")
                    break
                }
                daysToAdd++
            }
            
            return calendar.timeInMillis
        }
        
        // Para alarmas no repetitivas (una sola vez)
        if (calendar.before(now) || calendar.equals(now)) {
            calendar.add(Calendar.DAY_OF_MONTH, 1)
            Log.d("MainActivity", "One-time alarm: time passed today, scheduling for tomorrow")
        } else {
            Log.d("MainActivity", "One-time alarm: scheduling for today")
        }
        
        Log.d("MainActivity", "Final calculated time: ${calendar.time}")
        return calendar.timeInMillis
    }

    private fun pushAlarmEvent(type: String, alarmId: Int, newTimeInMillis: Long?) {
        try {
            val prefs = getSharedPreferences("alarm_events", Context.MODE_PRIVATE)
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
            Log.e("MainActivity", "Error pushing alarm event", e)
        }
    }

    private fun getAndClearAlarmEvents(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val prefs = getSharedPreferences("alarm_events", Context.MODE_PRIVATE)
            val current = prefs.getString("events", "[]") ?: "[]"
            val array = JSONArray(current)
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val map = mutableMapOf<String, Any>()
                val type = obj.optString("type", "")
                val alarmId = obj.optInt("alarmId", -1)
                if (type.isBlank() || alarmId == -1) continue
                map["type"] = type
                map["alarmId"] = alarmId
                if (obj.has("newTimeInMillis")) {
                    map["newTimeInMillis"] = obj.optLong("newTimeInMillis")
                }
                result.add(map)
            }
            prefs.edit().putString("events", "[]").apply()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error reading alarm events", e)
        }
        return result
    }
    
    private fun getSystemAlarmSounds(): List<Map<String, String>> {
        val soundsList = mutableListOf<Map<String, String>>()
        
        try {
            val ringtoneManager = RingtoneManager(this)
            ringtoneManager.setType(RingtoneManager.TYPE_ALARM)
            val cursor = ringtoneManager.cursor
            
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = ringtoneManager.getRingtoneUri(cursor.position).toString()
                soundsList.add(mapOf("title" to title, "uri" to uri))
            }
            cursor.close()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting system alarm sounds", e)
        }
        
        return soundsList
    }
    
    private fun playSound(soundUri: Uri) {
        try {
            val ringtone = RingtoneManager.getRingtone(applicationContext, soundUri)
            // Configurar el ringtone para usar el stream de alarma
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                ringtone.streamType = AudioManager.STREAM_ALARM
            }
            ringtone.play()
            Log.d("MainActivity", "Sound playing with ALARM stream")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error playing sound", e)
        }
    }
    
    private fun vibrate(pattern: LongArray) {
        try {
            Log.d("MainActivity", "Starting vibration with pattern: ${pattern.contentToString()}")
            
            // Verificar si el dispositivo tiene vibrador
            val hasVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.hasVibrator() == true
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.hasVibrator() == true
            }
            
            if (!hasVibrator) {
                Log.w("MainActivity", "Device does not have vibrator capability")
                return
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                val effect = VibrationEffect.createWaveform(pattern, -1) // -1 = no repeat
                vibrator.vibrate(effect)
                Log.d("MainActivity", "Vibration started with VibratorManager (API 31+)")
            } else {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, -1) // -1 = no repeat
                    vibrator.vibrate(effect)
                    Log.d("MainActivity", "Vibration started with VibrationEffect (API 26+)")
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, -1) // -1 = no repeat
                    Log.d("MainActivity", "Vibration started with deprecated method (API < 26)")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error vibrating: ${e.message}", e)
            // Intentar vibración simple como fallback
            try {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.vibrate(1000) // Vibrar por 1 segundo como fallback
                Log.d("MainActivity", "Fallback vibration started")
            } catch (fallbackException: Exception) {
                Log.e("MainActivity", "Fallback vibration also failed: ${fallbackException.message}")
            }
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Alarm Notifications"
            val descriptionText = "Channel for alarm notifications"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                // Deshabilitar vibración y sonido del canal para evitar duplicación
                // La vibración y sonido se manejan directamente en AlarmReceiver
                enableVibration(false)
                enableLights(true)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(null, null)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    // Volume control methods
    private fun startVolumeControl(maxVolumePercent: Int, rampUpDurationSeconds: Int) {
        try {
            AlarmVolumeController.ensureStarted(this, maxVolumePercent, rampUpDurationSeconds)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error starting volume control", e)
        }
    }
    
    private fun stopVolumeControl() {
        try {
            AlarmVolumeController.stop(this)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error stopping volume control", e)
        }
    }
    
    private fun setTemporaryVolumeReduction(reductionPercent: Int, durationSeconds: Int) {
        try {
            AlarmVolumeController.setTemporaryReduction(this, reductionPercent, durationSeconds)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting temporary volume reduction", e)
        }
    }
    
    private fun cancelTemporaryVolumeReduction() {
        try {
            AlarmVolumeController.cancelTemporaryReduction(this)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error cancelling temporary volume reduction", e)
        }
    }
    
    private fun setVolume(volumePercent: Int) {
        try {
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val targetVolume = (maxVolume * volumePercent) / 100
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, targetVolume, 0)
            Log.d("MainActivity", "Volume set to $targetVolume/$maxVolume ($volumePercent%)")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting volume", e)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        try {
            timeZoneReceiver?.let { receiver ->
                unregisterReceiver(receiver)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering time zone receiver", e)
        }
        // Clean up volume control
        stopVolumeControl()
        Log.d("MainActivity", "MainActivity destroyed")
    }
}
