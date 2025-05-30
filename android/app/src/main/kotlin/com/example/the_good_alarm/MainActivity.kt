package com.example.the_good_alarm

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.the_good_alarm/alarm"
    private val ALARM_ACTION = "com.example.the_good_alarm.ALARM_TRIGGERED"
    private val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
    private lateinit var alarmManager: AlarmManager
    private lateinit var alarmReceiver: BroadcastReceiver
    
    // Añadir este método en MainActivity.kt
    private fun checkDoNotDisturbPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                startActivity(intent)
            }
        }
    }
    
    // Llamar a este método en configureFlutterEngine después de createNotificationChannel()
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
        
        // Inicializar el AlarmManager
        alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // Crear canal de notificación para Android 8.0+
        createNotificationChannel()
        
        // Verificar permiso de No molestar
        checkDoNotDisturbPermission()
        
        // Registrar el BroadcastReceiver para las alarmas
        registerAlarmReceiver()
        
        // Configurar el MethodChannel para comunicarse con Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
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
                "stopSound" -> {
                    stopSound()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
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
        
        // Configurar la alarma para que se active en el tiempo especificado
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
        }
        
        // Iniciar el servicio en primer plano para mantener la aplicación activa
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
        
        // Obtener sonidos de alarma del sistema
        val alarmSoundsUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
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
    
    private fun stopSound() {
        // Implementación para detener el sonido actual
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
                setBypassDnd(true)  // Permitir que las notificaciones pasen el modo No molestar
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                
                // Configurar atributos de audio para el canal
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
                    val screenRoute = intent.getStringExtra("screenRoute") ?: "/alarm"
                    
                    // Mostrar notificación
                    showNotification(alarmId, title, message)
                    
                    // Iniciar la actividad Flutter con la ruta específica
                    val launchIntent = Intent(context, MainActivity::class.java).apply {
                        action = Intent.ACTION_MAIN
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra("screenRoute", screenRoute)
                        putExtra("alarmId", alarmId)
                    }
                    context.startActivity(launchIntent)
                }
            }
        }
        
        // Modificar esta línea para incluir la flag RECEIVER_NOT_EXPORTED en Android 14+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // Android 14 (API 34)
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
}
