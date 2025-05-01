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
                "setIntervalAlarms" -> {
                    val fromHour = call.argument<Int>("fromHour") ?: 0
                    val fromMinute = call.argument<Int>("fromMinute") ?: 0
                    val toHour = call.argument<Int>("toHour") ?: 0
                    val toMinute = call.argument<Int>("toMinute") ?: 0
                    val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 10
                    
                    try {
                        Log.d(TAG, "Setting interval alarms from $fromHour:$fromMinute to $toHour:$toMinute with interval $intervalMinutes minutes")
                        val alarmTimes = setIntervalAlarms(fromHour, fromMinute, toHour, toMinute, intervalMinutes)
                        alarms.addAll(alarmTimes)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error setting interval alarms", e)
                        result.error("ALARM_ERROR", "Failed to set interval alarms", e.message)
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
                "deleteAllAlarms" -> {
                    try {
                        Log.d(TAG, "Deleting all alarms")
                        val alarmsToDelete = alarms.toList()
                        for (alarm in alarmsToDelete) {
                            val parts = alarm.split(":")
                            if (parts.size == 2) {
                                val hour = parts[0].toInt()
                                val minute = parts[1].toInt()
                                deleteAlarm(hour, minute)
                            }
                        }
                        alarms.clear()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error deleting all alarms", e)
                        result.error("ALARM_ERROR", "Failed to delete all alarms", e.message)
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
        
        // Create intent for AlarmReceiver (not directly for AlarmActivity)
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            action = ALARM_ACTION
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
        }
        
        // Create a unique request code for this alarm
        val requestCode = (hour * 100) + minute
        
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        } else {
            PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT)
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
        
        // Create the same intent used to set the alarm
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            action = ALARM_ACTION
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
        }
        val requestCode = (hour * 100) + minute
        
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
        } else {
            PendingIntent.getBroadcast(this, requestCode, intent, 0)
        }
        
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Alarm cancelled for $hour:$minute")
    }
    
    private fun setIntervalAlarms(fromHour: Int, fromMinute: Int, toHour: Int, toMinute: Int, intervalMinutes: Int): List<String> {
        val alarmTimes = mutableListOf<String>()
        
        // Calculate start and end times in minutes from midnight
        val startMinutes = (fromHour * 60) + fromMinute
        val endMinutes = (toHour * 60) + toMinute
        
        if (startMinutes > endMinutes) {
            throw IllegalArgumentException("Start time must be before end time")
        }
        
        // Set alarms at intervals
        var currentMinutes = startMinutes
        while (currentMinutes <= endMinutes) {
            val hour = currentMinutes / 60
            val minute = currentMinutes % 60
            
            setAlarm(hour, minute)
            alarmTimes.add("$hour:$minute")
            
            Log.d(TAG, "Added interval alarm at $hour:$minute")
            currentMinutes += intervalMinutes
        }
        
        return alarmTimes
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