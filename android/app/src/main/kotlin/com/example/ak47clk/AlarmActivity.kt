package com.example.ak47clk

import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class AlarmActivity : AppCompatActivity() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Set up the window to appear over EVERYTHING including lock screen and other apps
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )
        
        // Modern API for appearing over lock screen and other apps
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            
            // Force unlock the keyguard
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (keyguardManager.isKeyguardLocked) {
                keyguardManager.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissError() {
                        // If dismissal fails, use older method as fallback
                        window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
                    }
                })
            }
        }
        
        // Use a wake lock to keep the CPU running
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
            "AK47Clock:AlarmWakeLock"
        )
        wakeLock?.acquire(10*60*1000L) // 10 minutes
        
        setContentView(R.layout.activity_alarm)
        
        // Get alarm time
        val hour = intent.getIntExtra("HOUR", 0)
        val minute = intent.getIntExtra("MINUTE", 0)
        
        // Format the time
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
        }
        val timeFormat = SimpleDateFormat("h:mm a", Locale.getDefault())
        val formattedTime = timeFormat.format(calendar.time)
        
        // Set the alarm time in the UI
        val timeTextView = findViewById<TextView>(R.id.timeTextView)
        timeTextView.text = formattedTime
        
        // Set up dismiss button
        val dismissButton = findViewById<Button>(R.id.dismissButton)
        dismissButton.setOnClickListener {
            dismissAlarm(hour, minute)
        }
        
        // Start alarm sound and vibration
        startAlarmSound()
        startVibration()
    }
    
    private fun startAlarmSound() {
        // Get the default alarm sound
        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)  // Use USAGE_ALARM for proper audio focus
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                    .build()
            )
            setDataSource(applicationContext, alarmSound)
            isLooping = true
            setVolume(1.0f, 1.0f)
            prepare()
            start()
        }
    }
    
    private fun startVibration() {
        // Get the vibrator service
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        
        // Create a vibration pattern: 0ms delay, 500ms vibrate, 500ms sleep, repeat
        val pattern = longArrayOf(0, 500, 500)
        
        // Start vibration
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }
    
    private fun dismissAlarm(hour: Int, minute: Int) {
        Log.d("AlarmActivity", "Dismissing alarm for $hour:$minute - FORCE STOP")
        
        // FIRST: Stop the service immediately using static method
        AlarmService.requestStop()
        
        // Stop local alarm sound and vibration
        stopAlarm()
        
        // Cancel the alarm in AlarmManager so it doesn't fire again
        cancelAlarmInManager(hour, minute)
        
        // Stop the service using multiple methods to ensure it stops
        val serviceIntent = Intent(this, AlarmService::class.java).apply {
            putExtra("STOP_ALARM", true)
        }
        
        // Method 1: Start service with stop command
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            Log.d("AlarmActivity", "Sent stop command via startService")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "Error starting service with stop command: ${e.message}", e)
        }
        
        // Method 2: Stop service directly
        try {
            stopService(serviceIntent)
            Log.d("AlarmActivity", "Called stopService")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "Error calling stopService: ${e.message}", e)
        }
        
        // Method 3: Try again after a short delay to ensure it stops
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            try {
                AlarmService.requestStop()
                stopService(serviceIntent)
                Log.d("AlarmActivity", "Retry stop after delay")
            } catch (e: Exception) {
                Log.e("AlarmActivity", "Error in delayed stop: ${e.message}", e)
            }
        }, 100)
        
        finish()
    }
    
    private fun cancelAlarmInManager(hour: Int, minute: Int) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "com.example.ak47clk.ALARM"
                putExtra("HOUR", hour)
                putExtra("MINUTE", minute)
            }
            val requestCode = (hour * 100) + minute
            
            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.getBroadcast(
                    this,
                    requestCode,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            } else {
                PendingIntent.getBroadcast(
                    this,
                    requestCode,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT
                )
            }
            
            alarmManager.cancel(pendingIntent)
            Log.d("AlarmActivity", "Cancelled alarm in AlarmManager for $hour:$minute")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "Failed to cancel alarm in AlarmManager: ${e.message}", e)
        }
    }
    
    private fun stopAlarm() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        
        vibrator?.cancel()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }
}