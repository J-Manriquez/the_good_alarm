package com.example.the_good_alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.util.Log

class HabitReceiver : BroadcastReceiver() {
    companion object {
        const val HABIT_ACTION = "com.example.the_good_alarm.HABIT_TRIGGERED"
        const val HABIT_NOTIFICATION_CHANNEL_ID = "habit_notification_channel"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != HABIT_ACTION) return

        val habitId = intent.getStringExtra("habitId") ?: return
        val occurrenceKey = intent.getStringExtra("occurrenceKey") ?: return
        val title = intent.getStringExtra("title") ?: "Hábito"
        val message = intent.getStringExtra("message") ?: ""
        val scheduledAtLocalMillis = intent.getLongExtra("scheduledAtLocalMillis", System.currentTimeMillis())

        val notificationId = stableNotificationId(occurrenceKey)

        createChannelIfNeeded(context)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("screenRoute", "/habit")
            putExtra("autoShowAlarm", true)
            putExtra("habitId", habitId)
            putExtra("occurrenceKey", occurrenceKey)
            putExtra("scheduledAtLocalMillis", scheduledAtLocalMillis)
            putExtra("title", title)
            putExtra("message", message)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, HABIT_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setColor(ContextCompat.getColor(context, android.R.color.holo_blue_light))
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(notificationId, notification)

        Log.d("HabitReceiver", "Habit triggered: habitId=$habitId occurrenceKey=$occurrenceKey")
    }

    private fun createChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = notificationManager.getNotificationChannel(HABIT_NOTIFICATION_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            HABIT_NOTIFICATION_CHANNEL_ID,
            "Hábitos",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null)
            enableVibration(false)
            description = "Avisos de hábitos"
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun stableNotificationId(key: String): Int {
        val h = key.hashCode().toLong()
        val abs = kotlin.math.abs(h)
        return (abs % 2147483647L).toInt()
    }
}
