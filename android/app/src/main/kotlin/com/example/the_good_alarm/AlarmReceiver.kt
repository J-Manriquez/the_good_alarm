package com.example.the_good_alarm

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import android.util.Log
import android.app.NotificationChannel
import android.app.Notification

class AlarmReceiver : BroadcastReceiver() {
    
    private val STOP_ACTION = "com.example.the_good_alarm.STOP_ALARM_ACTION"
    private val SNOOZE_ACTION = "com.example.the_good_alarm.SNOOZE_ALARM_ACTION"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "onReceive called with action: ${intent.action}")
        
        val alarmId = intent.getIntExtra("alarmId", -1)
        Log.d("AlarmReceiver", "Alarm ID: $alarmId")
        // Asegúrate de que el alarmId se propague correctamente para las acciones

        when (intent.action) {
            "com.example.the_good_alarm.ALARM_TRIGGERED" -> {
                Log.d("AlarmReceiver", "Handling alarm trigger for alarmId: $alarmId")
                handleAlarmTrigger(context, intent)
            }
            STOP_ACTION -> {
                Log.d("AlarmReceiver", "Stop action received for alarmId: $alarmId")
                stopAlarmSound()
                // También cancela la notificación
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(alarmId) 
                // Llama a MainActivity para cancelar la alarma en AlarmManager y actualizar Flutter
                val mainActivityIntent = Intent(context, MainActivity::class.java).apply {
                    action = "STOP_ALARM_FROM_NOTIFICATION"
                    putExtra("alarmId", alarmId)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                Log.d("AlarmReceiver", "Starting MainActivity with STOP_ALARM_FROM_NOTIFICATION action")
                context.startActivity(mainActivityIntent)
            }
            SNOOZE_ACTION -> {
                Log.d("AlarmReceiver", "Snooze action received for alarmId: $alarmId")
                stopAlarmSound()
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(alarmId)
                // Llama a MainActivity para posponer la alarma
                val mainActivityIntent = Intent(context, MainActivity::class.java).apply {
                    action = "SNOOZE_ALARM_FROM_NOTIFICATION"
                    putExtra("alarmId", alarmId)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                Log.d("AlarmReceiver", "Starting MainActivity with SNOOZE_ALARM_FROM_NOTIFICATION action")
                context.startActivity(mainActivityIntent)
            }
        }
    }
    
    private fun handleAlarmTrigger(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "=== ALARM TRIGGER START ===")
        val alarmId = intent.getIntExtra("alarmId", -1)
        val title = intent.getStringExtra("title") ?: "Alarma"
        val message = intent.getStringExtra("message") ?: "¡Es hora de despertar!"
        
        Log.d("AlarmReceiver", "Alarm triggered - ID: $alarmId, Title: $title")
        
        try {
            // Crear canal de notificación con IMPORTANCE_HIGH para mantener visible
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Log.d("AlarmReceiver", "Creating HIGH importance notification channel")
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID, 
                    "Alarm Notifications", 
                    NotificationManager.IMPORTANCE_HIGH  // CAMBIO: HIGH en lugar de LOW
                ).apply {
                    this.description = "Channel for alarm notifications"
                    this.setBypassDnd(true)
                    this.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    this.enableVibration(false)  // Sin vibración en canal
                    this.enableLights(true)
                    this.setSound(null, null)  // Sin sonido en canal
                }
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
                Log.d("AlarmReceiver", "Notification channel created with HIGH importance")
            }
            
            Log.d("AlarmReceiver", "handleAlarmTrigger: Starting alarm handling process")
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "TheGoodAlarm::AlarmWakeLock"
            )
            wakeLock.acquire(60 * 1000L) // Adquirir por 60 segundos
            Log.d("AlarmReceiver", "WakeLock acquired for 60 seconds")

            val alarmId = intent.getIntExtra("alarmId", 0)
            val title = intent.getStringExtra("title") ?: "Alarma"
            val message = intent.getStringExtra("message") ?: "¡Es hora de despertar!"
            Log.d("AlarmReceiver", "Alarm details - ID: $alarmId, Title: $title, Message: $message")

            // Play sound and vibrate
            try {
                Log.d("AlarmReceiver", "Setting up ringtone")
                // Verificar si ya hay un sonido reproduciéndose
                if (currentRingtone == null || !currentRingtone!!.isPlaying) {
                    currentRingtone = RingtoneManager.getRingtone(
                        context, 
                        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    )
                    currentRingtone?.play()
                    Log.d("AlarmReceiver", "Ringtone started playing")
                } else {
                    Log.d("AlarmReceiver", "Ringtone already playing, skipping")
                }
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error playing ringtone", e)
            }

            try {
                Log.d("AlarmReceiver", "Setting up vibration")
                currentVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                    vibratorManager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                
                val vibrationPattern = longArrayOf(0, 500, 500, 500)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(vibrationPattern, 0)
                    currentVibrator?.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    currentVibrator?.vibrate(vibrationPattern, 0)
                }
                Log.d("AlarmReceiver", "Vibration started")
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error starting vibration", e)
            }

            // Intent para abrir MainActivity cuando se presiona la notificación
            Log.d("AlarmReceiver", "Creating launch intent for MainActivity")
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("alarmId", alarmId)
                putExtra("title", title)
                putExtra("message", message)
                putExtra("screenRoute", "/alarm")
                putExtra("autoShowAlarm", true) // Importante para que MainActivity sepa que debe mostrar la pantalla
            }
            val pendingLaunchIntent = PendingIntent.getActivity(
                context, alarmId + 1000, launchIntent, // requestCode debe ser único
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Acción para detener la alarma desde la notificación
            Log.d("AlarmReceiver", "Creating stop intent for notification action")
            val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = STOP_ACTION
                putExtra("alarmId", alarmId)
            }
            val pendingStopIntent = PendingIntent.getBroadcast(
                context, alarmId + 2000, stopIntent, // requestCode debe ser único
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Acción para posponer la alarma desde la notificación
            Log.d("AlarmReceiver", "Creating snooze intent for notification action")
            val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = SNOOZE_ACTION
                putExtra("alarmId", alarmId)
            }
            val pendingSnoozeIntent = PendingIntent.getBroadcast(
                context, alarmId + 3000, snoozeIntent, // requestCode debe ser único
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            Log.d("AlarmReceiver", "Got NotificationManager service")

            // Asegúrate de que el canal de notificación exista
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Log.d("AlarmReceiver", "Creating notification channel")
                try {
                    val channel = NotificationChannel(
                        NOTIFICATION_CHANNEL_ID, 
                        "Alarm Notifications", 
                        NotificationManager.IMPORTANCE_LOW  // Cambiar de IMPORTANCE_HIGH a IMPORTANCE_LOW
                    ).apply {
                        this.description = "Channel for alarm notifications"
                        this.setBypassDnd(true)
                        this.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                        this.enableVibration(false)  // Desactivar vibración del canal
                        this.enableLights(true)
                        this.setSound(null, null)  // Desactivar sonido del canal
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
                .setPriority(NotificationCompat.PRIORITY_MAX) // Cambiado a MAX para mayor visibilidad
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(pendingLaunchIntent, true)
                .setContentIntent(pendingLaunchIntent)
                .addAction(0, "Apagar", pendingStopIntent)
                .addAction(0, "Posponer 1 min", pendingSnoozeIntent)
                .setAutoCancel(false)
                .setOngoing(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // Asegura que sea visible en la pantalla de bloqueo
                .setSound(null) // Asegurarse de que la notificación no reproduzca sonido
                .setVibrate(null) // Asegurarse de que la notificación no vibre

            try {
                Log.d("AlarmReceiver", "Showing notification with ID: $alarmId")
                notificationManager.notify(alarmId, notificationBuilder.build())
                Log.d("AlarmReceiver", "Notification should be visible now")
                
                // También intentamos iniciar la actividad directamente como respaldo
                Log.d("AlarmReceiver", "Also starting MainActivity directly as backup")
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error showing notification", e)
            }

        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Error in handleAlarmTrigger", e)
        }
    }
    
    companion object {
        var currentRingtone: Ringtone? = null
        var currentVibrator: Vibrator? = null
        const val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"

        fun stopAlarmSound() {
            try {
                Log.d("AlarmReceiver", "Stopping alarm sound and vibration")
                currentRingtone?.stop()
                currentRingtone = null
                currentVibrator?.cancel()
                currentVibrator = null
                Log.d("AlarmReceiver", "Alarm sound and vibration stopped")
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Error stopping alarm sound", e)
            }
        }
    }
}