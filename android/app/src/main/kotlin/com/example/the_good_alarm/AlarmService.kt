package com.example.the_good_alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log

class AlarmService : Service() {
    private val NOTIFICATION_CHANNEL_ID = "alarm_service_channel"
    private val NOTIFICATION_ID = 1
    
    override fun onCreate() {
        super.onCreate()
        Log.d("AlarmService", "onCreate called")
        createNotificationChannel()
        startForeground()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AlarmService", "onStartCommand called")
        
        // Optional: Clean up orphaned notifications
        cleanupOrphanedNotifications()
        
        // Asegurar que el servicio se reinicie si es terminado
        return START_STICKY
    }
    
    private fun cleanupOrphanedNotifications() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // On Android M+, check for active alarm notifications
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val activeNotifications = notificationManager.activeNotifications
                activeNotifications.forEach { notification ->
                    // Log active alarm notifications (IDs that might be alarm-related)
                    if (notification.id != NOTIFICATION_ID) {
                        Log.d("AlarmService", "Found active alarm notification with ID: ${notification.id}")
                        // Note: We're only logging here. Full cleanup logic could be implemented
                        // if we had a way to determine which notifications are truly orphaned
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("AlarmService", "Error during notification cleanup: ${e.message}")
        }
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Reiniciar servicio si la tarea es removida
        val restartServiceIntent = Intent(applicationContext, AlarmService::class.java)
        startForegroundService(restartServiceIntent)
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        Log.d("AlarmService", "onBind called")
        return null
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Alarm Service"
            val descriptionText = "Keeps the alarm service running"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun startForeground() {
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Alarma Activa")
            .setContentText("La aplicación de alarma está ejecutándose en segundo plano")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        
        startForeground(NOTIFICATION_ID, notification)
    }
}