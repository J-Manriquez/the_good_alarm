package com.andodevs.the_good_alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.util.Log

class MedicationReceiver : BroadcastReceiver() {
    companion object {
        const val MEDICATION_ACTION = "com.andodevs.the_good_alarm.MEDICATION_TRIGGERED"
        const val MEDICATION_CONFIRM_ACTION = "com.andodevs.the_good_alarm.MEDICATION_CONFIRMATION"
        const val MEDICATION_NOTIFICATION_CHANNEL_ID = "medication_notification_channel_v2"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != MEDICATION_ACTION && action != MEDICATION_CONFIRM_ACTION) return

        val medicationId = intent.getStringExtra("medicationId") ?: return
        val occurrenceKey = intent.getStringExtra("occurrenceKey") ?: return
        val title = intent.getStringExtra("title") ?: "Medicamento"
        val message = intent.getStringExtra("message") ?: ""
        val dosageAmount = intent.getStringExtra("dosageAmount") ?: ""
        val dosageUnit = intent.getStringExtra("dosageUnit") ?: ""
        val scheduledAtLocalMillis = intent.getLongExtra("scheduledAtLocalMillis", System.currentTimeMillis())
        val isConfirmation = action == MEDICATION_CONFIRM_ACTION

        val notificationId = stableNotificationId(if (isConfirmation) "confirm|$occurrenceKey" else occurrenceKey)
        val screenRoute = if (isConfirmation) "/medication_confirm" else "/medication"

        createChannelIfNeeded(context)

        // Adquirir WakeLock para encender la pantalla inmediatamente
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "TheGoodAlarm:MedicationWakeLock"
        )
        wakeLock.acquire(3 * 60 * 1000L) // 3 minutos máximo
        Log.d("MedicationReceiver", "WakeLock acquired isConfirmation=$isConfirmation")

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("screenRoute", screenRoute)
            putExtra("autoShowAlarm", true)
            putExtra("medicationId", medicationId)
            putExtra("occurrenceKey", occurrenceKey)
            putExtra("scheduledAtLocalMillis", scheduledAtLocalMillis)
            putExtra("title", title)
            putExtra("message", message)
            putExtra("dosageAmount", dosageAmount)
            putExtra("dosageUnit", dosageUnit)
            putExtra("isConfirmation", isConfirmation)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationTitle = if (isConfirmation) "Confirmación: $title" else title
        val notificationText = if (isConfirmation) "¿Ya tomaste $title?" else
            if (dosageAmount.isNotEmpty()) "$dosageAmount $dosageUnit - $message" else message

        val notification = NotificationCompat.Builder(context, MEDICATION_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setColor(ContextCompat.getColor(context, android.R.color.holo_green_light))
            .setContentTitle(notificationTitle)
            .setContentText(notificationText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(notificationText))
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(notificationId, notification)

        // Lanzar la Activity directamente (igual que AlarmReceiver) para garantizar
        // apertura inmediata sin requerir que el usuario toque la notificación.
        // setFullScreenIntent es el mecanismo estándar pero en Android 12+ muchos
        // fabricantes lo suprimen sin audio; startActivity desde un receiver con
        // USE_FULL_SCREEN_INTENT + SCHEDULE_EXACT_ALARM sí funciona de forma directa.
        try {
            context.startActivity(launchIntent)
            Log.d("MedicationReceiver", "startActivity directo lanzado isConfirmation=$isConfirmation")
        } catch (e: Exception) {
            Log.e("MedicationReceiver", "startActivity directo falló, se usará fullScreenIntent: ${e.message}")
        }

        Log.d("MedicationReceiver", "action=$action medicationId=$medicationId occurrenceKey=$occurrenceKey isConfirmation=$isConfirmation")
    }

    private fun createChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = notificationManager.getNotificationChannel(MEDICATION_NOTIFICATION_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            MEDICATION_NOTIFICATION_CHANNEL_ID,
            "Medicamentos",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null)
            enableVibration(false)
            description = "Avisos de medicamentos"
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun stableNotificationId(key: String): Int {
        val h = key.hashCode().toLong()
        val abs = kotlin.math.abs(h)
        return (abs % 2147483647L).toInt()
    }
}
