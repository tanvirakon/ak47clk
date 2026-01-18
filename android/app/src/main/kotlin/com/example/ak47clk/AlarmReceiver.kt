package com.example.ak47clk

import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.AlarmClock
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {
    private val CHANNEL_ID = "flutter_alarm_channel"
    private val NOTIFICATION_ID = 1

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "Alarm received!")
        
        val hour = intent.getIntExtra("HOUR", 0)
        val minute = intent.getIntExtra("MINUTE", 0)
        
        // Get a WakeLock to ensure the device wakes up
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or 
            PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AK47Clock:AlarmReceiverWakeLock"
        )
        wakeLock.acquire(5 * 1000L) // 5 seconds
        
        try {
            // Create service intent
            val serviceIntent = Intent(context, AlarmService::class.java).apply {
                putExtra("HOUR", hour)
                putExtra("MINUTE", minute)
            }
            
            // Start the foreground service (this will handle launching the activity)
            Log.d("AlarmReceiver", "Starting AlarmService")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Failed to start service: ${e.message}", e)
        } finally {
            // Release the wake lock
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }
    
    private fun formatTime(hour: Int, minute: Int): String {
        val hourFormatted = if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        val amPm = if (hour >= 12) "PM" else "AM"
        return String.format("%d:%02d %s", hourFormatted, minute, amPm)
    }
}