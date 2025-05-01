package com.example.ak47clk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.provider.AlarmClock
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {
    private val CHANNEL_ID = "flutter_alarm_channel"
    private val NOTIFICATION_ID = 1

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "Alarm received!")
        
        val hour = intent.getIntExtra("HOUR", 0)
        val minute = intent.getIntExtra("MINUTE", 0)
        
        // Launch our AlarmActivity directly
        val alarmIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        context.startActivity(alarmIntent)
        
        // Also create a notification as a backup
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Create the notification channel (required for API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Flutter Alarm Clock",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarms from Flutter Alarm Clock app"
                enableLights(true)
                enableVibration(true)
                
                // Set alarm sound
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                setSound(alarmSound, audioAttributes)
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // Build the notification
        val pendingIntent = PendingIntent.getActivity(
            context, 
            (hour * 100) + minute, 
            alarmIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Alarm")
            .setContentText("Alarm set for ${formatTime(hour, minute)}")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()
            
        // Show the notification
        notificationManager.notify((hour * 100) + minute, notification)
    }
    
    private fun formatTime(hour: Int, minute: Int): String {
        val hourFormatted = if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        val amPm = if (hour >= 12) "PM" else "AM"
        return String.format("%d:%02d %s", hourFormatted, minute, amPm)
    }
}