package com.example.the_good_alarm

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.AudioAttributes
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
                cancelAllNotificationsForAlarm(context, alarmId)
                
                Log.d("AlarmReceiver", "Alarm stopped completely")
            }
            SNOOZE_ACTION -> {
                Log.d("AlarmReceiver", "Snooze action received")
                val alarmId = intent.getIntExtra("alarmId", -1)
                val maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
                val snoozeDurationMinutes = intent.getIntExtra("snoozeDurationMinutes", 5)
                
                Log.d("AlarmReceiver", "Snoozing alarm ID: $alarmId, maxSnoozes: $maxSnoozes, duration: $snoozeDurationMinutes")
                
                stopAlarmSound()
                stopVibration(context)
                cancelAllNotificationsForAlarm(context, alarmId)
                
                // TODO: Implement snooze logic here
                Log.d("AlarmReceiver", "Alarm snoozed")
            }
            else -> {
                Log.d("AlarmReceiver", "Default alarm trigger action")
                handleAlarmTrigger(context, intent)
            }
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
            
            Log.d("AlarmReceiver", "Alarm details - ID: $alarmId, Title: $title, Message: $message")
            Log.d("AlarmReceiver", "Snooze settings - Max: $maxSnoozes, Duration: $snoozeDurationMinutes minutes")

            // Adquirir WakeLock para mantener el dispositivo despierto
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "AlarmApp:AlarmWakeLock"
            )
            wakeLock.acquire(10 * 60 * 1000L) // 10 minutos máximo
            Log.d("AlarmReceiver", "WakeLock acquired")

            // Reproducir sonido de alarma
            try {
                Log.d("AlarmReceiver", "Setting up alarm sound")
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                
                Log.d("AlarmReceiver", "Alarm URI: $alarmUri")
                
                currentRingtone = RingtoneManager.getRingtone(context, alarmUri)
                currentRingtone?.let { ringtone ->
                    if (!ringtone.isPlaying) {
                        Log.d("AlarmReceiver", "Starting alarm sound")
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