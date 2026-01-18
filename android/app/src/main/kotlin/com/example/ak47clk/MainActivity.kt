package com.example.ak47clk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
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
        
        // Request to be exempt from battery optimization
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestBatteryOptimizationExemption()
        }
        
        // Request SYSTEM_ALERT_WINDOW permission for full-screen intents
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val settings = android.provider.Settings.canDrawOverlays(this)
            if (!settings) {
                Log.d(TAG, "Requesting SYSTEM_ALERT_WINDOW permission")
                val intent = Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName"))
                try {
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to request overlay permission", e)
                }
            }
        }
        
        // Load saved alarms from SharedPreferences
        loadSavedAlarms()
        
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
                        
                        // Clear all alarm preferences
                        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
                        sharedPrefs.edit().clear().apply()
                        
                        // Save empty alarm list
                        saveAlarmList()
                        
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
        
        // Create intent for AlarmReceiver
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
        
        // Store alarm time in SharedPreferences for restoration after reboot and app restart
        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        sharedPrefs.edit().putString("alarm_${hour}_${minute}", "$hour:$minute").apply()
        
        // Save the current list of alarms
        saveAlarmList()
        
        // Set the alarm - only set it once, no backup repeating alarms
        // This prevents alarms from ringing multiple times
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // For Android 12+, need to check if permission is granted
            if (alarmManager.canScheduleExactAlarms()) {
                // Set exact alarm that allows while idle
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                // Request permission if not granted
                requestScheduleExactAlarmPermission()
                
                // Use less precise method as fallback
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // For Android 6.0+
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent
            )
        } else {
            // For older Android versions
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
        
        // Cancel the primary exact alarm
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        } else {
            PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT)
        }
        
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Cancelled alarm for $hour:$minute")
        
        // Remove from SharedPreferences
        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        sharedPrefs.edit().remove("alarm_${hour}_${minute}").apply()
        
        // Save the current list of alarms
        saveAlarmList()
        
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
    

    @RequiresApi(Build.VERSION_CODES.S)
    private fun checkAlarmPermission() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (!alarmManager.canScheduleExactAlarms()) {
            // For Android 12+, need to request permission
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            startActivity(intent)
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun requestBatteryOptimizationExemption() {
        val packageName = packageName
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        
        if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
            try {
                // Request to be exempted from battery optimization
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to request battery optimization exemption", e)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun requestScheduleExactAlarmPermission() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request SCHEDULE_EXACT_ALARM permission", e)
        }
    }
    
    override fun onResume() {
        super.onResume()
        
        // Check if we need to restore alarms (e.g., after reboot)
        if (intent?.getBooleanExtra("RESTORE_ALARMS", false) == true) {
            restoreAlarms()
        }
    }
    
    override fun onPause() {
        super.onPause()
        
        // Save alarm list when app goes to background
        saveAlarmList()
    }
    
    /**
     * Restore alarms from SharedPreferences after device reboot
     */
    private fun restoreAlarms() {
        Log.d(TAG, "Restoring alarms from preferences")
        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        val allPrefs = sharedPrefs.all
        
        for ((key, value) in allPrefs) {
            if (key.startsWith("alarm_") && value is String) {
                try {
                    val parts = value.split(":")
                    if (parts.size == 2) {
                        val hour = parts[0].toInt()
                        val minute = parts[1].toInt()
                        Log.d(TAG, "Restoring alarm for $hour:$minute")
                        setAlarm(hour, minute)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error restoring alarm: $value", e)
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkAlarmPermission()
        }
    }
    
    /**
     * Save the current list of alarms to SharedPreferences
     */
    private fun saveAlarmList() {
        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        val editor = sharedPrefs.edit()
        
        // Save the entire alarm list as a comma-separated string
        val alarmListString = alarms.joinToString(",")
        editor.putString("alarm_list", alarmListString)
        
        // Apply changes
        editor.apply()
        
        Log.d(TAG, "Saved alarm list: $alarmListString")
    }
    
    /**
     * Load saved alarms from SharedPreferences
     */
    private fun loadSavedAlarms() {
        val sharedPrefs = getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        
        // Get the alarm list string
        val alarmListString = sharedPrefs.getString("alarm_list", "")
        
        // Clear current alarm list
        alarms.clear()
        
        // Parse and add each alarm
        if (!alarmListString.isNullOrEmpty()) {
            val alarmArray = alarmListString.split(",")
            
            for (alarm in alarmArray) {
                if (alarm.trim().isNotEmpty()) {
                    alarms.add(alarm.trim())
                    Log.d(TAG, "Loaded alarm: $alarm")
                }
            }
        }
        
        Log.d(TAG, "Loaded ${alarms.size} alarms from preferences")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Save the alarm list before destroying
        saveAlarmList()
        
        try {
            unregisterReceiver(alarmReceiver)
        } catch (e: Exception) {
            // Ignore if receiver wasn't registered
        }
    }
}