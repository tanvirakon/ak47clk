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
        
        // Create alarm activity intent with full screen flags
        val alarmIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        
        // Create a full-screen PendingIntent
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            (hour * 100) + minute,
            alarmIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        // Create a notification with high priority and full-screen intent
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Create the notification channel (required for API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "flutter_alarm_channel",
                "Flutter Alarm Clock",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarms from Flutter Alarm Clock app"
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                
                // Set alarm sound with regular volume
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)  // Changed from USAGE_ALARM to USAGE_NOTIFICATION
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)  // Changed from SONIFICATION to MUSIC
                    .build()
                setSound(alarmSound, audioAttributes)
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // Build the notification with full-screen intent
        val notification = NotificationCompat.Builder(context, "flutter_alarm_channel")
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle("Alarm")
            .setContentText("Alarm set for ${formatTime(hour, minute)}")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)  // Changed from MAX to DEFAULT
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)  // Changed from ALARM to MESSAGE
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))  // Changed from TYPE_ALARM to TYPE_NOTIFICATION
            .setVibrate(longArrayOf(0, 500, 500, 500))
            .build()
        
        // Get a WakeLock to ensure the device wakes up
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or 
            PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AK47Clock:AlarmReceiverWakeLock"
        )
        wakeLock.acquire(30 * 1000L) // 30 seconds
        
        try {
            // Show the notification
            notificationManager.notify((hour * 100) + minute, notification)
            
            // Also start the activity directly
            context.startActivity(alarmIntent)
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Failed to handle alarm", e)
        } finally {
            // Always release the wake lock
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