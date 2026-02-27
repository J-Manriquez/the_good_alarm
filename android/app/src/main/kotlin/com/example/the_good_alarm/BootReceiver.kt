package com.example.the_good_alarm // Asegúrate de que este sea tu paquete correcto

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import java.util.Calendar
import java.util.Date

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            
            Log.d("BootReceiver", "System boot completed, restoring alarms")
            
            // Iniciar el servicio de alarmas
            val serviceIntent = Intent(context, AlarmService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
            // Restaurar todas las alarmas desde SharedPreferences
            restoreAlarmsFromPreferences(context)
            restoreHabitsFromPreferences(context)
        }
    }
    
    private fun restoreAlarmsFromPreferences(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val alarmsJson = prefs.getString("flutter.alarms", null)
            
            if (alarmsJson.isNullOrBlank()) return

            val alarmsArray = JSONArray(alarmsJson)
            for (i in 0 until alarmsArray.length()) {
                val alarmJson = alarmsArray.optJSONObject(i) ?: continue

                val isActive = alarmJson.optBoolean("isActive", false)
                if (!isActive) continue

                val alarmId = alarmJson.optInt("id", -1)
                if (alarmId <= 0) continue

                val hour = alarmJson.optInt("hour", 0).coerceIn(0, 23)
                val minute = alarmJson.optInt("minute", 0).coerceIn(0, 59)

                val title = alarmJson.optString("title", "Alarma")
                val message = alarmJson.optString("message", "Es hora de despertar")

                val repeatDays = parseRepeatDays(alarmJson.optJSONArray("repeatDays"))
                val isDaily = alarmJson.optBoolean("isDaily", false)
                val isWeekly = alarmJson.optBoolean("isWeekly", false)
                val isWeekend = alarmJson.optBoolean("isWeekend", false)

                val maxSnoozes = alarmJson.optInt("maxSnoozes", 3)
                val snoozeDurationMinutes = alarmJson.optInt("snoozeDurationMinutes", 5)

                val maxVolumePercent = alarmJson.optInt("maxVolumePercent", 100)
                val volumeRampUpDurationSeconds = alarmJson.optInt("volumeRampUpDurationSeconds", 0)
                val tempVolumeReductionPercent = alarmJson.optInt("tempVolumeReductionPercent", 50)
                val tempVolumeReductionDurationSeconds = alarmJson.optInt("tempVolumeReductionDurationSeconds", 30)

                val nextTimeInMillis = calculateNextAlarmTime(
                    hour = hour,
                    minute = minute,
                    repeatDays = repeatDays,
                    isDaily = isDaily,
                    isWeekly = isWeekly,
                    isWeekend = isWeekend
                )

                if (nextTimeInMillis <= System.currentTimeMillis()) continue

                scheduleAlarm(
                    context = context,
                    timeInMillis = nextTimeInMillis,
                    alarmId = alarmId,
                    title = title,
                    message = message,
                    repeatDays = repeatDays,
                    isDaily = isDaily,
                    isWeekly = isWeekly,
                    isWeekend = isWeekend,
                    maxSnoozes = maxSnoozes,
                    snoozeDurationMinutes = snoozeDurationMinutes,
                    maxVolumePercent = maxVolumePercent,
                    volumeRampUpDurationSeconds = volumeRampUpDurationSeconds,
                    tempVolumeReductionPercent = tempVolumeReductionPercent,
                    tempVolumeReductionDurationSeconds = tempVolumeReductionDurationSeconds
                )

                Log.d("BootReceiver", "Restored alarmId=$alarmId for ${Date(nextTimeInMillis)}")
            }
        } catch (e: Exception) {
            Log.e("BootReceiver", "Error restoring alarms", e)
        }
    }

    private fun restoreHabitsFromPreferences(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val habitsJson = prefs.getString("flutter.habits", null)
            if (habitsJson.isNullOrBlank()) return

            val array = JSONArray(habitsJson)
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue

                val habitId = item.optString("habitId", "").trim()
                val occurrenceKey = item.optString("occurrenceKey", "").trim()
                val title = item.optString("title", "Hábito")
                val message = item.optString("message", "")
                val timeInMillis = item.optLong("timeInMillis", -1L)

                if (habitId.isEmpty() || occurrenceKey.isEmpty() || timeInMillis <= System.currentTimeMillis()) {
                    continue
                }

                scheduleHabit(
                    context = context,
                    timeInMillis = timeInMillis,
                    habitId = habitId,
                    occurrenceKey = occurrenceKey,
                    title = title,
                    message = message
                )

                Log.d("BootReceiver", "Restored habitId=$habitId occurrenceKey=$occurrenceKey for ${Date(timeInMillis)}")
            }
        } catch (e: Exception) {
            Log.e("BootReceiver", "Error restoring habits", e)
        }
    }

    private fun parseRepeatDays(jsonArray: JSONArray?): List<Int> {
        if (jsonArray == null) return emptyList()
        val result = mutableListOf<Int>()
        for (i in 0 until jsonArray.length()) {
            val day = jsonArray.optInt(i, -1)
            if (day in 1..7) result.add(day)
        }
        return result
    }

    private fun calculateNextAlarmTime(
        hour: Int,
        minute: Int,
        repeatDays: List<Int>,
        isDaily: Boolean,
        isWeekly: Boolean,
        isWeekend: Boolean
    ): Long {
        val calendar = Calendar.getInstance()
        val now = Calendar.getInstance()

        calendar.set(Calendar.YEAR, now.get(Calendar.YEAR))
        calendar.set(Calendar.MONTH, now.get(Calendar.MONTH))
        calendar.set(Calendar.DAY_OF_MONTH, now.get(Calendar.DAY_OF_MONTH))
        calendar.set(Calendar.HOUR_OF_DAY, hour)
        calendar.set(Calendar.MINUTE, minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        if (!isDaily && !isWeekly && !isWeekend && repeatDays.isEmpty()) {
            if (calendar.before(now) || calendar == now) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            return calendar.timeInMillis
        }

        if (isDaily) {
            if (calendar.before(now) || calendar == now) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }
            return calendar.timeInMillis
        }

        if (isWeekend) {
            val today = calendar.get(Calendar.DAY_OF_WEEK)
            val todayIsWeekend = today == Calendar.SATURDAY || today == Calendar.SUNDAY

            if (todayIsWeekend && calendar.after(now)) {
                return calendar.timeInMillis
            }

            while (true) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
                val day = calendar.get(Calendar.DAY_OF_WEEK)
                if (day == Calendar.SATURDAY || day == Calendar.SUNDAY) break
            }
            return calendar.timeInMillis
        }

        val calendarDays = repeatDays.map { day ->
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
        }.toSet()

        val currentDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
        if (calendarDays.contains(currentDayOfWeek) && calendar.after(now)) {
            return calendar.timeInMillis
        }

        var daysToAdd = 1
        while (daysToAdd <= 7) {
            calendar.add(Calendar.DAY_OF_MONTH, 1)
            if (calendarDays.contains(calendar.get(Calendar.DAY_OF_WEEK))) break
            daysToAdd++
        }

        return calendar.timeInMillis
    }

    private fun scheduleAlarm(
        context: Context,
        timeInMillis: Long,
        alarmId: Int,
        title: String,
        message: String,
        repeatDays: List<Int>,
        isDaily: Boolean,
        isWeekly: Boolean,
        isWeekend: Boolean,
        maxSnoozes: Int,
        snoozeDurationMinutes: Int,
        maxVolumePercent: Int,
        volumeRampUpDurationSeconds: Int,
        tempVolumeReductionPercent: Int,
        tempVolumeReductionDurationSeconds: Int
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val triggerIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.the_good_alarm.ALARM_TRIGGERED"
            putExtra("alarmId", alarmId)
            putExtra("title", title)
            putExtra("message", message)
            putExtra("screenRoute", "/alarm")
            putExtra("repeatDays", repeatDays.toIntArray())
            putExtra("isDaily", isDaily)
            putExtra("isWeekly", isWeekly)
            putExtra("isWeekend", isWeekend)
            putExtra("maxSnoozes", maxSnoozes)
            putExtra("snoozeDurationMinutes", snoozeDurationMinutes)
            putExtra("maxVolumePercent", maxVolumePercent)
            putExtra("volumeRampUpDurationSeconds", volumeRampUpDurationSeconds)
            putExtra("tempVolumeReductionPercent", tempVolumeReductionPercent)
            putExtra("tempVolumeReductionDurationSeconds", tempVolumeReductionDurationSeconds)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            triggerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            }
        } catch (security: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            }
        }
    }

    private fun scheduleHabit(
        context: Context,
        timeInMillis: Long,
        habitId: String,
        occurrenceKey: String,
        title: String,
        message: String
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val triggerIntent = Intent(context, HabitReceiver::class.java).apply {
            action = HabitReceiver.HABIT_ACTION
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
            context,
            requestCode,
            triggerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            }
        } catch (security: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
            }
        }
    }

    private fun stableRequestCode(key: String): Int {
        val h = key.hashCode().toLong()
        val abs = kotlin.math.abs(h)
        return (abs % 2147483647L).toInt()
    }
}
