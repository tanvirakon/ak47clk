package com.example.ak47clk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.ak47clk/alarm"
    private val ALARM_ACTION = "com.example.ak47clk.ALARM"
    private val TAG = "AK47ClockAlarm"
    private val alarms = mutableSetOf<String>()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register broadcast receiver for alarms
        val filter = IntentFilter(ALARM_ACTION)
        registerReceiver(alarmReceiver, filter)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            Log.d(TAG, "Method called: ${call.method}")
            when (call.method) {
                "setCustomAlarm", "setAlarm" -> {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    
                    try {
                        Log.d(TAG, "Setting alarm for $hour:$minute")
                        setAlarm(hour, minute)
                        alarms.add("$hour:$minute")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error setting alarm", e)
                        result.error("ALARM_ERROR", "Failed to set alarm", e.message)
                    }
                }
                "getAlarms" -> {
                    Log.d(TAG, "Getting alarms: ${alarms.toList()}")
                    result.success(alarms.toList())
                }
                "deleteAlarm" -> {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    
                    try {
                        Log.d(TAG, "Deleting alarm for $hour:$minute")
                        deleteAlarm(hour, minute)
                        alarms.remove("$hour:$minute")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error deleting alarm", e)
                        result.error("ALARM_ERROR", "Failed to delete alarm", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setAlarm(hour: Int, minute: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        // Create a unique request code for this alarm
        val requestCode = (hour * 100) + minute
        
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(this, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        } else {
            PendingIntent.getActivity(this, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT)
        }
        
        // Set the alarm time
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            
            // If the time is already passed today, set it for tomorrow
            if (timeInMillis < System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        
        // Set the alarm
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent
            )
        }
        
        Log.d(TAG, "Alarm set for $hour:$minute at ${calendar.time}")
    }
    
    private fun deleteAlarm(hour: Int, minute: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmActivity::class.java)
        val requestCode = (hour * 100) + minute
        
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
        } else {
            PendingIntent.getActivity(this, requestCode, intent, 0)
        }
        
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Alarm cancelled for $hour:$minute")
    }
    
    private val alarmReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == ALARM_ACTION) {
                val hour = intent.getIntExtra("HOUR", 0)
                val minute = intent.getIntExtra("MINUTE", 0)
                Log.d(TAG, "Alarm triggered for $hour:$minute")
                
                // Start our custom alarm activity instead of the system alarm
                val alarmIntent = Intent(context, AlarmActivity::class.java).apply {
                    putExtra("HOUR", hour)
                    putExtra("MINUTE", minute)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(alarmIntent)
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(alarmReceiver)
    }
}