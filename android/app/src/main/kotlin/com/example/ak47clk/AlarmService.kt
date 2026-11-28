package com.example.ak47clk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmService : Service() {
    companion object {
        const val ALARM_CHANNEL_ID = "alarm_fullscreen_v2"

        @Volatile
        private var instance: AlarmService? = null
        
        fun getInstance(): AlarmService? = instance
        
        @Volatile
        private var shouldStop: Boolean = false
        
        fun requestStop() {
            shouldStop = true
            instance?.stopAlarm()
        }
    }
    
    private var powerManager: PowerManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private val handler = Handler(Looper.getMainLooper())
    private var hour: Int = 0
    private var minute: Int = 0
    private var isStopped: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        shouldStop = false
        Log.d("AlarmService", "Service created, instance set")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AlarmService", "Service started with intent: ${intent?.getBooleanExtra("STOP_ALARM", false)}")
        
        // Check if stop was requested
        if (shouldStop || intent?.getBooleanExtra("STOP_ALARM", false) == true) {
            Log.d("AlarmService", "Stop requested, stopping immediately")
            isStopped = true
            shouldStop = false
            stopAlarm()
            return START_NOT_STICKY
        }
        
        // If already stopped, don't start again
        if (isStopped) {
            Log.d("AlarmService", "Service already stopped, ignoring start command")
            return START_NOT_STICKY
        }
        
        hour = intent?.getIntExtra("HOUR", 0) ?: 0
        minute = intent?.getIntExtra("MINUTE", 0) ?: 0
        
        // Get wake lock - keep it for longer
        powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager?.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AK47Clock:AlarmServiceWakeLock"
        )?.apply {
            acquire(10 * 60 * 1000L) // 10 minutes
        }
        
        // Get audio manager
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        
        // Request audio focus
        requestAudioFocus()
        
        // Start playing alarm sound immediately
        startVibration()
        if (RingtoneStore.isVideoMode(this)) {
            // AlarmActivity plays the video + its audio. Safety net: if the video hasn't
            // started in 4s (activity blocked / bad file), ring the tone so the alarm is never silent.
            AlarmActivity.videoStarted = false
            handler.postDelayed({
                if (!isStopped && !silenced && !AlarmActivity.videoStarted) {
                    Log.w("AlarmService", "Video didn't start, falling back to tone")
                    startAlarmSound()
                }
            }, 4000)
        } else {
            startAlarmSound()
        }
        
        // Create notification
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Old channel played the system default sound on top of our ringtone. Channels are
            // immutable once created, so use a new silent one; MediaPlayer handles all audio.
            notificationManager.deleteNotificationChannel("flutter_alarm_channel")
            val channel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Ringing alarms"
                enableVibration(false)
                setSound(null, null)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // Create the alarm activity intent
        val alarmIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("HOUR", hour)
            putExtra("MINUTE", minute)
            putExtra(AlarmScheduler.EXTRA_ID, intent?.getIntExtra(AlarmScheduler.EXTRA_ID, -1) ?: -1)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
        }
        
        // Create pending intent
        val pendingIntent = PendingIntent.getActivity(
            this,
            (hour * 100) + minute,
            alarmIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        // Build notification
        val notification = NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle("Alarm")
            .setContentText("Alarm set for ${formatTime(hour, minute)}")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setSilent(true)
            .build()
        
        // Start foreground service with notification
        // The service type is already declared in AndroidManifest.xml as systemExempted
        // For Android 13+, we can optionally specify it, but it's not required since it's in manifest
        startForeground(1, notification)
        
        // IMPORTANT: Launch the activity immediately
        // This ensures it launches even when another app is in foreground
        handler.post {
            Log.d("AlarmService", "Launching alarm activity from service")
            try {
                startActivity(alarmIntent)
                Log.d("AlarmService", "Activity launch successful")
            } catch (e: Exception) {
                Log.e("AlarmService", "Failed to start activity: ${e.message}", e)
                // Try again after a delay
                handler.postDelayed({
                    try {
                        startActivity(alarmIntent)
                        Log.d("AlarmService", "Activity launch successful on retry")
                    } catch (e2: Exception) {
                        Log.e("AlarmService", "Retry failed: ${e2.message}", e2)
                    }
                }, 1000)
            }
        }
        
        // Set up recurring check to stop if requested (runs every 200ms)
        val stopChecker = object : Runnable {
            override fun run() {
                if (shouldStop || isStopped) {
                    Log.d("AlarmService", "Stop detected in periodic check, stopping now")
                    stopAlarm()
                } else if (!isStopped) {
                    // Continue checking if not stopped
                    handler.postDelayed(this, 200)
                }
            }
        }
        handler.postDelayed(stopChecker, 200)
        
        // Use START_NOT_STICKY so the service doesn't restart if killed
        // This prevents alarms from continuing after dismissal
        return START_NOT_STICKY
    }
    
    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(false)
                .setWillPauseWhenDucked(false)
                .build()
            
            audioManager?.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                null,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }
    
    /** Button set to "Silence": stop sound + vibration, keep the ring screen until swiped. */
    @Volatile var silenced = false
        private set

    fun silence() {
        silenced = true
        stopToneOnly()
        try { vibrator?.cancel() } catch (_: Exception) {}
    }

    /** Stop service-side tone (used when the video kicks in late, after the fallback tone started). */
    fun stopToneOnly() {
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
    }

    private fun startAlarmSound() {
        if (mediaPlayer != null) return
        try {
            val alarmSound = RingtoneStore.uriToPlay(this)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        // No FLAG_AUDIBILITY_ENFORCED: on many phones it ignores the alarm volume (always max).
                        .build()
                )
                setDataSource(applicationContext, alarmSound)
                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
            }
            Log.d("AlarmService", "Alarm sound started")
        } catch (e: Exception) {
            Log.e("AlarmService", "Failed to start alarm sound: ${e.message}", e)
            // Fallback to system default alarm if chosen ringtone fails
            try {
                mediaPlayer?.release()
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    setDataSource(applicationContext, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (e2: Exception) {
                Log.e("AlarmService", "Default alarm sound failed too", e2)
            }
        }
    }
    
    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        
        val pattern = longArrayOf(0, 500, 500)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
        Log.d("AlarmService", "Vibration started")
    }
    
    private fun stopAlarm() {
        if (isStopped) {
            Log.d("AlarmService", "Alarm already stopped, skipping")
            return
        }
        
        Log.d("AlarmService", "Stopping alarm - FORCE STOP")
        isStopped = true
        shouldStop = true
        
        // Stop media player IMMEDIATELY - this is critical
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer!!.isPlaying) {
                    mediaPlayer!!.stop()
                }
                mediaPlayer!!.release()
                Log.d("AlarmService", "Media player stopped and released")
            }
        } catch (e: Exception) {
            Log.e("AlarmService", "Error stopping media player: ${e.message}", e)
        }
        mediaPlayer = null
        
        // Stop vibration IMMEDIATELY
        try {
            vibrator?.cancel()
            Log.d("AlarmService", "Vibration cancelled")
        } catch (e: Exception) {
            Log.e("AlarmService", "Error stopping vibration: ${e.message}", e)
        }
        
        // Release audio focus
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let {
                    audioManager?.abandonAudioFocusRequest(it)
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager?.abandonAudioFocus(null)
            }
            Log.d("AlarmService", "Audio focus released")
        } catch (e: Exception) {
            Log.e("AlarmService", "Error releasing audio focus: ${e.message}", e)
        }
        
        // Release wake lock
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d("AlarmService", "Wake lock released")
            }
        } catch (e: Exception) {
            Log.e("AlarmService", "Error releasing wake lock: ${e.message}", e)
        }
        
        // Stop foreground service and self - do this on handler to ensure it happens
        handler.post {
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
                Log.d("AlarmService", "Foreground service stopped")
            } catch (e: Exception) {
                Log.e("AlarmService", "Error stopping foreground: ${e.message}", e)
            }
            
            try {
                stopSelf()
                Log.d("AlarmService", "Service stopSelf called")
            } catch (e: Exception) {
                Log.e("AlarmService", "Error calling stopSelf: ${e.message}", e)
            }
        }
        
        Log.d("AlarmService", "Alarm stopped completely")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d("AlarmService", "Service destroyed")
        stopAlarm()
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        instance = null
        shouldStop = false
    }
    
    private fun formatTime(hour: Int, minute: Int): String {
        val hourFormatted = if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        val amPm = if (hour >= 12) "PM" else "AM"
        return String.format("%d:%02d %s", hourFormatted, minute, amPm)
    }
}
