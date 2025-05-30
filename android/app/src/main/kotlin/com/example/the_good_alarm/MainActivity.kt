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
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.the_good_alarm/alarm"
    private val ALARM_ACTION = "com.example.the_good_alarm.ALARM_TRIGGERED"
    private val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
    private lateinit var alarmManager: AlarmManager
    private lateinit var alarmReceiver: BroadcastReceiver
    private var methodChannel: MethodChannel? = null
    
    private fun checkDoNotDisturbPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                startActivity(intent)
            }
        }
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
                    // Puedes mostrar un mensaje al usuario aquí si el permiso es crucial
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
        
        alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        createNotificationChannel() // Asegúrate que esto crea el canal con IMPORTANCE_HIGH
        checkDoNotDisturbPermission()
        checkOverlayPermission() // <-- Añade esta llamada
        // registerAlarmReceiver() // Esta función parece redundante si AlarmReceiver se declara en el Manifest
        
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
                    
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (alarmManager.canScheduleExactAlarms()) {
                                setAlarm(timeInMillis, alarmId, title, message, screenRoute)
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                startActivity(intent)
                                result.error("PERMISSION_DENIED", "Se requiere permiso para programar alarmas exactas", null)
                            }
                        } else {
                            setAlarm(timeInMillis, alarmId, title, message, screenRoute)
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
                    result.success(true)
                }
                "snoozeAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    Log.d("MainActivity", "Snoozing alarm: $alarmId")
                    AlarmReceiver.stopAlarmSound()
                    cancelAlarm(alarmId)
                    
                    val calendar = Calendar.getInstance()
                    calendar.add(Calendar.MINUTE, 1)
                    setAlarm(
                        timeInMillis = calendar.timeInMillis,
                        alarmId = alarmId,
                        title = "Alarma pospuesta",
                        message = "¡Es hora de despertar!",
                        screenRoute = "/alarm"
                    )
                    result.success(true)
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
                    val pattern = call.argument<LongArray>("pattern") ?: longArrayOf(0, 500, 500, 500)
                    vibrate(pattern)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Solicitar permiso de notificaciones en Android 13 (Tiramisu) y superiores
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 100)
                Log.d("MainActivity", "Requesting POST_NOTIFICATIONS permission")
            }
        }
        
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent called with action: ${intent.action}")
        setIntent(intent) // Es crucial actualizar el intent de la actividad
        handleAlarmIntent(intent) // Procesa el intent actual
    }

    private fun handleAlarmIntent(intent: Intent?) {
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
                    AlarmReceiver.stopAlarmSound() // Detiene sonido/vibración
                    cancelAlarm(alarmIdFromIntent) // Cancela la alarma en AlarmManager
                    // Informa a Flutter para actualizar la UI y posiblemente eliminar la alarma de la lista
                    Log.d("MainActivity", "Invoking Flutter method: alarmManuallyStopped")
                    methodChannel?.invokeMethod("alarmManuallyStopped", mapOf("alarmId" to alarmIdFromIntent))
                    // Cierra la pantalla de alarma si está abierta
                    Log.d("MainActivity", "Invoking Flutter method: closeAlarmScreenIfOpen")
                    methodChannel?.invokeMethod("closeAlarmScreenIfOpen", mapOf("alarmId" to alarmIdFromIntent))
                }
            }
            "SNOOZE_ALARM_FROM_NOTIFICATION" -> {
                if (alarmIdFromIntent != -1) {
                    Log.d("MainActivity", "Snoozing alarm from notification: $alarmIdFromIntent")
                    AlarmReceiver.stopAlarmSound()
                    cancelAlarm(alarmIdFromIntent) // Cancela la alarma actual
                    
                    val calendar = Calendar.getInstance()
                    calendar.add(Calendar.MINUTE, 1) // Posponer 1 minuto
                    Log.d("MainActivity", "Setting new alarm for 1 minute later: ${calendar.time}")
                    setAlarm(
                        timeInMillis = calendar.timeInMillis,
                        alarmId = alarmIdFromIntent, // Reutiliza el ID o genera uno nuevo si es necesario
                        title = intent.getStringExtra("title") ?: "Alarma Pospuesta",
                        message = intent.getStringExtra("message") ?: "¡Es hora de despertar!",
                        screenRoute = "/alarm"
                    )
                    // Informa a Flutter para actualizar la UI
                    Log.d("MainActivity", "Invoking Flutter method: alarmManuallySnoozed")
                    methodChannel?.invokeMethod("alarmManuallySnoozed", mapOf("alarmId" to alarmIdFromIntent, "newTimeInMillis" to calendar.timeInMillis))
                    Log.d("MainActivity", "Invoking Flutter method: closeAlarmScreenIfOpen")
                    methodChannel?.invokeMethod("closeAlarmScreenIfOpen", mapOf("alarmId" to alarmIdFromIntent))
                }
            }
            else -> {
                 // Lógica existente para mostrar la pantalla de alarma cuando la app se abre por la notificación
                val title = intent.getStringExtra("title")
                val message = intent.getStringExtra("message")
                val screenRoute = intent.getStringExtra("screenRoute")
                val autoShow = intent.getBooleanExtra("autoShowAlarm", false)

                Log.d("MainActivity", "Checking if should show alarm screen - alarmId: $alarmIdFromIntent, screenRoute: $screenRoute, autoShow: $autoShow")
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
                    android.os.Handler(Looper.getMainLooper()).postDelayed({
                        Log.d("MainActivity", "Now showing alarm screen via Flutter")
                        methodChannel?.invokeMethod(
                            "showAlarmScreen",
                            mapOf(
                                "alarmId" to alarmIdFromIntent,
                                "title" to (title ?: "Alarma"),
                                "message" to (message ?: "¡Es hora de despertar!")
                            )
                        )
                    }, 500)
                    // Limpia el extra para que no se vuelva a procesar si la actividad se recrea
                    intent.removeExtra("autoShowAlarm") 
                }
            }
        }
    }
    
    private fun setAlarm(timeInMillis: Long, alarmId: Int, title: String, message: String, screenRoute: String) {
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            action = ALARM_ACTION
            putExtra("alarmId", alarmId)
            putExtra("title", title)
            putExtra("message", message)
            putExtra("screenRoute", screenRoute)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        }
        
        val serviceIntent = Intent(this, AlarmService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }
    
    private fun cancelAlarm(alarmId: Int) {
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
    }
    
    private fun getSystemAlarmSounds(): List<Map<String, String>> {
        val soundsList = mutableListOf<Map<String, String>>()
        
        val ringtoneManager = RingtoneManager(this)
        ringtoneManager.setType(RingtoneManager.TYPE_ALARM)
        val cursor = ringtoneManager.cursor
        
        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = ringtoneManager.getRingtoneUri(cursor.position).toString()
            soundsList.add(mapOf("title" to title, "uri" to uri))
        }
        
        return soundsList
    }
    
    private fun playSound(soundUri: Uri) {
        val ringtone = RingtoneManager.getRingtone(applicationContext, soundUri)
        ringtone.play()
    }
    
    private fun vibrate(pattern: LongArray) {
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
    
    private fun registerAlarmReceiver() {
        alarmReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == ALARM_ACTION) {
                    val alarmId = intent.getIntExtra("alarmId", 0)
                    val title = intent.getStringExtra("title") ?: "Alarma"
                    val message = intent.getStringExtra("message") ?: "¡Es hora de despertar!"
                    
                    showNotification(alarmId, title, message)
                }
            }
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(alarmReceiver, IntentFilter(ALARM_ACTION), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(alarmReceiver, IntentFilter(ALARM_ACTION))
        }
    }
    
    private fun showNotification(alarmId: Int, title: String, message: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .setVibrate(longArrayOf(0, 500, 500, 500))
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(alarmId, builder.build())
    }
    
    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(alarmReceiver)
        } catch (e: Exception) {
            // El receptor puede no estar registrado
        }
    }
    
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 100) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d("MainActivity", "POST_NOTIFICATIONS permission granted")
                // Aquí puedes realizar acciones adicionales si el permiso fue concedido
            } else {
                Log.d("MainActivity", "POST_NOTIFICATIONS permission denied")
                // Aquí puedes manejar el caso en que el permiso fue denegado
            }
        }
    }
}
