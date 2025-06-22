package com.example.the_good_alarm

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
    private val CHANNEL = "com.example.the_good_alarm/alarm"
    private val ALARM_ACTION = "com.example.the_good_alarm.ALARM_TRIGGERED"
    private val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
    private lateinit var alarmManager: AlarmManager
    private lateinit var alarmReceiver: BroadcastReceiver
    private var methodChannel: MethodChannel? = null
    private var timeZoneReceiver: BroadcastReceiver? = null
    
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
        createNotificationChannel()
        checkDoNotDisturbPermission()
        checkOverlayPermission()
        requestBatteryOptimizationExemption()
        handleTimeZoneChange()
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "MethodChannel call: ${call.method}")
            when (call.method) {
                "setAlarm" -> {
                    val timeInMillis = call.argument<Long>("timeInMillis") ?: 0
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val title = call.argument<String>("title") ?: "Alarma"
                    val message = call.argument<String>("message") ?: "¡Es hora de despertar!"
                    val screenRoute = call.argument<String>("screenRoute") ?: "/alarm"
                    val repeatDays = call.argument<List<Int>>("repeatDays") ?: emptyList()
                    val isDaily = call.argument<Boolean>("isDaily") ?: false
                    val isWeekly = call.argument<Boolean>("isWeekly") ?: false
                    val isWeekend = call.argument<Boolean>("isWeekend") ?: false
                    val maxSnoozes = call.argument<Int>("maxSnoozes") ?: 3
                    val snoozeDurationMinutes = call.argument<Int>("snoozeDurationMinutes") ?: 5

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (alarmManager.canScheduleExactAlarms()) {
                                setAlarm(
                                    timeInMillis, alarmId, title, message, screenRoute,
                                    repeatDays, isDaily, isWeekly, isWeekend, maxSnoozes, snoozeDurationMinutes
                                )
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                startActivity(intent)
                                result.error("PERMISSION_DENIED", "Se requiere permiso para programar alarmas exactas", null)
                            }
                        } else {
                            setAlarm(
                                timeInMillis, alarmId, title, message, screenRoute,
                                repeatDays, isDaily, isWeekly, isWeekend, maxSnoozes, snoozeDurationMinutes
                            )
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.localizedMessage, null)
                    }
                }
                "cancelAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    cancelAlarm(alarmId)
                    result.success(true)
                }
                "stopAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    Log.d("MainActivity", "Stopping alarm: $alarmId")
                    AlarmReceiver.stopAlarmSound()
                    cancelAlarm(alarmId)
                    methodChannel?.invokeMethod("alarmManuallyStopped", mapOf("alarmId" to alarmId))
                    result.success(true)
                }
                "snoozeAlarm" -> {
                    Log.d("MainActivity", "=== SNOOZE ALARM METHOD START ===")
                    val alarmId = call.argument<Int>("alarmId")
                    val maxSnoozes = call.argument<Int>("maxSnoozes") ?: 3
                    val snoozeDurationMinutes = call.argument<Int>("snoozeDurationMinutes") ?: 5
                    
                    // AGREGAR LOGS DETALLADOS
                    Log.d("MainActivity", "Received snooze parameters:")
                    Log.d("MainActivity", "  - alarmId: $alarmId")
                    Log.d("MainActivity", "  - maxSnoozes: $maxSnoozes")
                    Log.d("MainActivity", "  - snoozeDurationMinutes: $snoozeDurationMinutes")
                    
                    Log.d("MainActivity", "Snoozing alarm ID: $alarmId for $snoozeDurationMinutes minutes, max: $maxSnoozes")
                    
                    if (alarmId != null) {
                        AlarmReceiver.stopAlarmSound()
                        cancelAlarm(alarmId)
                        
                        val calendar = Calendar.getInstance()
                        Log.d("MainActivity", "Current time before adding snooze: ${calendar.time}")
                        calendar.add(Calendar.MINUTE, snoozeDurationMinutes)
                        Log.d("MainActivity", "New snooze time after adding $snoozeDurationMinutes minutes: ${calendar.time}")
                        
                        setAlarm(
                            timeInMillis = calendar.timeInMillis,
                            alarmId = alarmId,
                            title = "Alarma Pospuesta",
                            message = "¡Es hora de despertar!",
                            screenRoute = "/alarm",
                            repeatDays = emptyList(),
                            isDaily = false,
                            isWeekly = false,
                            isWeekend = false,
                            maxSnoozes = maxSnoozes,
                            snoozeDurationMinutes = snoozeDurationMinutes
                        )
                        
                        Log.d("MainActivity", "Alarm rescheduled with correct parameters")
                        
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
                    vibrate(pattern)
                    result.success(true)
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
                    cancelAlarm(alarmIdFromIntent)
                    Log.d("MainActivity", "Invoking Flutter method: alarmManuallyStopped")
                    methodChannel?.invokeMethod("alarmManuallyStopped", mapOf("alarmId" to alarmIdFromIntent))
                    Log.d("MainActivity", "Invoking Flutter method: closeAlarmScreenIfOpen")
                    methodChannel?.invokeMethod("closeAlarmScreenIfOpen", mapOf("alarmId" to alarmIdFromIntent))
                }
            }
            "SNOOZE_ALARM_FROM_NOTIFICATION" -> {
                if (alarmIdFromIntent != -1) {
                    Log.d("MainActivity", "Snoozing alarm from notification: $alarmIdFromIntent")
                    AlarmReceiver.stopAlarmSound()
                    cancelAlarm(alarmIdFromIntent)
                    
                    val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
                    val calendar = Calendar.getInstance()
                    calendar.add(Calendar.MINUTE, snoozeDurationMinutes) // Usar la duración correcta
                    Log.d("MainActivity", "Setting new alarm for $snoozeDurationMinutes minutes later: ${calendar.time}")
                    setAlarm(
                        timeInMillis = calendar.timeInMillis,
                        alarmId = alarmIdFromIntent,
                        title = intent.getStringExtra("title") ?: "Alarma Pospuesta",
                        message = intent.getStringExtra("message") ?: "¡Es hora de despertar!",
                        screenRoute = "/alarm",
                        repeatDays = emptyList(),
                        isDaily = false,
                        isWeekly = false,
                        isWeekend = false,
                        maxSnoozes = intent.getIntExtra("maxSnoozes", 3),
                        snoozeDurationMinutes = snoozeDurationMinutes
                    )
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

                Log.d("MainActivity", "Checking if should show alarm screen - alarmId: $alarmIdFromIntent, screenRoute: $screenRoute, autoShow: $autoShow")
                Log.d("MainActivity", "Alarm parameters: maxSnoozes=$maxSnoozes, snoozeDuration=$snoozeDurationMinutes, snoozeCount=$snoozeCount")
                Log.d("MainActivity", "Intent extras: ${intent.extras?.keySet()?.joinToString()}") // AGREGAR ESTE LOG
                
                if (alarmIdFromIntent != -1 && screenRoute == "/alarm" && autoShow) {
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
                    
                    Log.d("MainActivity", "Scheduling delayed call to show alarm screen")
                    Handler(Looper.getMainLooper()).postDelayed({
                        Log.d("MainActivity", "Now showing alarm screen via Flutter")
                        Log.d("MainActivity", "Passing parameters: alarmId=$alarmIdFromIntent, maxSnoozes=$maxSnoozes, snoozeDuration=$snoozeDurationMinutes, snoozeCount=$snoozeCount") // AGREGAR ESTE LOG
                        methodChannel?.invokeMethod("showAlarmScreen", mapOf(
                            "alarmId" to alarmIdFromIntent,
                            "title" to title,
                            "message" to message,
                            "maxSnoozes" to maxSnoozes,
                            "snoozeDurationMinutes" to snoozeDurationMinutes,
                            "snoozeCount" to snoozeCount
                        ))
                    }, 500)
                    intent.removeExtra("autoShowAlarm") 
                }
            }
        }
    }
    
    private fun setAlarm(
        timeInMillis: Long,
        alarmId: Int,
        title: String,
        message: String,
        screenRoute: String,
        repeatDays: List<Int>,
        isDaily: Boolean,
        isWeekly: Boolean,
        isWeekend: Boolean,
        maxSnoozes: Int,
        snoozeDurationMinutes: Int
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
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
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

    private fun cancelAlarm(alarmId: Int) {
        try {
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION  // Agregar esta línea
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("MainActivity", "Alarm canceled successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error canceling alarm", e)
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
                            title = alarm.title,
                            message = alarm.message,
                            screenRoute = "/alarm",
                            repeatDays = alarm.repeatDays,
                            isDaily = alarm.isDaily,
                            isWeekly = alarm.isWeekly,
                            isWeekend = alarm.isWeekend,
                            maxSnoozes = alarm.maxSnoozes,
                            snoozeDurationMinutes = alarm.snoozeDurationMinutes
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
        
        calendar.set(Calendar.HOUR_OF_DAY, alarm.hour)
        calendar.set(Calendar.MINUTE, alarm.minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        
        if (alarm.isDaily) {
            if (calendar.before(now)) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            return calendar.timeInMillis
        }
        
        if (alarm.isWeekend) {
            val weekendDays = listOf(Calendar.SATURDAY, Calendar.SUNDAY)
            while (!weekendDays.contains(calendar.get(Calendar.DAY_OF_WEEK)) || calendar.before(now)) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            return calendar.timeInMillis
        }
        
        if (alarm.repeatDays.isNotEmpty()) {
            val calendarDays = alarm.repeatDays.map { day ->
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
            
            if (calendar.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR) && 
                calendar.before(now)) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            
            while (!calendarDays.contains(calendar.get(Calendar.DAY_OF_WEEK))) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            
            return calendar.timeInMillis
        }
        
        if (calendar.before(now)) {
            calendar.add(Calendar.DAY_OF_MONTH, 1)
        }
        
        return calendar.timeInMillis
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
            ringtone.play()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error playing sound", e)
        }
    }
    
    private fun vibrate(pattern: LongArray) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                val effect = VibrationEffect.createWaveform(pattern, 0)
                vibrator.vibrate(effect)
            } else {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, 0)
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, 0)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error vibrating", e)
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Alarm Notifications"
            val descriptionText = "Channel for alarm notifications"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(true)
                enableLights(true)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttributes)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
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
    }
}
