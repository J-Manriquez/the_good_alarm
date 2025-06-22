package com.example.the_good_alarm // Asegúrate de que este sea tu paquete correcto

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

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
        }
    }
    
    private fun restoreAlarmsFromPreferences(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val alarmsJson = prefs.getString("flutter.alarms", null)
            
            if (alarmsJson != null) {
                // Procesar las alarmas y reprogramarlas
                val mainIntent = Intent(context, MainActivity::class.java)
                mainIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                mainIntent.putExtra("restoreAlarms", true)
                mainIntent.putExtra("alarmsData", alarmsJson)
                context.startActivity(mainIntent)
            }
        } catch (e: Exception) {
            Log.e("BootReceiver", "Error restoring alarms", e)
        }
    }
}