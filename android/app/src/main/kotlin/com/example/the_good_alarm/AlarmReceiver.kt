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
    
    companion object {
        var currentRingtone: Ringtone? = null
        var currentVibrator: Vibrator? = null
        const val NOTIFICATION_CHANNEL_ID = "alarm_notification_channel"
        private const val STOP_ACTION = "com.example.the_good_alarm.STOP_ALARM_ACTION"
        private const val SNOOZE_ACTION = "com.example.the_good_alarm.SNOOZE_ALARM_ACTION"

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

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "onReceive called with action: ${intent.action}")
        
        val alarmId = intent.getIntExtra("alarmId", -1)
        Log.d("AlarmReceiver", "Alarm ID: $alarmId")

        when (intent.action) {
            "com.example.the_good_alarm.ALARM_TRIGGERED" -> {
                Log.d("AlarmReceiver", "Handling alarm trigger for alarmId: $alarmId")
                handleAlarmTrigger(context, intent)
            }
            STOP_ACTION -> {
                Log.d("AlarmReceiver", "Stop action received for alarmId: $alarmId")
                stopAlarmSound()
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(alarmId) 
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
                val mainActivityIntent = Intent(context, MainActivity::class.java).apply {
                    action = "SNOOZE_ALARM_FROM_NOTIFICATION"
                    putExtra("alarmId", alarmId)
                    // AGREGAR PARÁMETROS DE POSPOSICIÓN
                    putExtra("maxSnoozes", intent.getIntExtra("maxSnoozes", 3))
                    putExtra("snoozeDurationMinutes", intent.getIntExtra("snoozeDurationMinutes", 5))
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
        val maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
        val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
    
        Log.d("AlarmReceiver", "Alarm triggered - ID: $alarmId, Title: $title, MaxSnoozes: $maxSnoozes, SnoozeDuration: $snoozeDurationMinutes")
        
        try {
            Log.d("AlarmReceiver", "handleAlarmTrigger: Starting alarm handling process")
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "TheGoodAlarm::AlarmWakeLock"
            )
            wakeLock.acquire(60 * 1000L)
            Log.d("AlarmReceiver", "WakeLock acquired for 60 seconds")

            Log.d("AlarmReceiver", "Alarm details - ID: $alarmId, Title: $title, Message: $message")

            // Play sound and vibrate
            try {
                Log.d("AlarmReceiver", "Setting up ringtone")
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
            }
            val pendingSnoozeIntent = PendingIntent.getBroadcast(
                context, alarmId + 3000, snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            Log.d("AlarmReceiver", "Got NotificationManager service")

            // Crear canal de notificación
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
                Log.d("AlarmReceiver", "Showing notification with ID: $alarmId")
                notificationManager.notify(alarmId, notificationBuilder.build())
                Log.d("AlarmReceiver", "Notification should be visible now")
                
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