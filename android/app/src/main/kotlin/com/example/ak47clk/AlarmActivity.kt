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
        
        // Show ON TOP of the lock screen and wake the display - WITHOUT dismissing the keyguard.
        // (Dismissing it forces the PIN/fingerprint prompt, which is exactly what we don't want:
        //  the alarm must be visible and stoppable while the phone stays locked.)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        
        // Use a wake lock to keep the CPU running
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
            "AK47Clock:AlarmWakeLock"
        )
        wakeLock?.acquire(10*60*1000L) // 10 minutes
        
        setContentView(R.layout.activity_alarm)
        volumeControlStream = android.media.AudioManager.STREAM_ALARM // volume keys adjust alarm volume
        
        // Get alarm time
        val hour = intent.getIntExtra("HOUR", 0)
        val minute = intent.getIntExtra("MINUTE", 0)
        
        // Format the time
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
        }
        findViewById<TextView>(R.id.timeTextView).text =
            SimpleDateFormat("h:mm", Locale.getDefault()).format(calendar.time)
        findViewById<TextView>(R.id.ampmTextView).text =
            SimpleDateFormat("a", Locale.getDefault()).format(calendar.time).uppercase()
        findViewById<TextView>(R.id.dateTextView).text =
            SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Calendar.getInstance().time)

        // Show the alarm's label (if any) under the date.
        val alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ID, -1)
        val label = try {
            when (alarmId) {
                AlarmScheduler.TIMER_ID -> "Time's up"
                AlarmScheduler.TEST_ID -> "Test alarm"
                -1 -> null
                else -> AlarmStore.findByAlarmId(this, alarmId)?.label
            }
        } catch (e: Exception) { null }
        if (!label.isNullOrBlank()) {
            findViewById<TextView>(R.id.labelTextView).apply {
                text = label
                visibility = android.view.View.VISIBLE
            }
        }

        ringHour = hour
        ringMinute = minute
        ringAlarmId = alarmId
        setupSwipeToDismiss(hour, minute, alarmId)
        registerPowerButton()
        quietServiceNotification()

        if (RingtoneStore.isVideoMode(this)) {
            startVideo()
            if (AlarmService.getInstance() == null) startVibration()
        } else {
            startPulse()
            // AlarmService already plays sound + vibration; only play here if it isn't running
            // (otherwise the ringtone plays twice, slightly offset = echo).
            if (AlarmService.getInstance() == null) {
                startAlarmSound()
                startVibration()
            }
        }
    }

    companion object {
        /** Set true once the alarm video is actually playing (AlarmService checks this for its tone fallback). */
        @Volatile var videoStarted = false
    }

    private var videoPlayer: MediaPlayer? = null

    // ---------------- hardware buttons (Settings > Buttons while ringing) ----------------
    private var ringHour = 0
    private var ringMinute = 0
    private var ringAlarmId = -1
    private var buttonDone = false // turned off / snoozed by a button: ignore further presses
    private var silenced = false
    private var screenOffReceiver: android.content.BroadcastReceiver? = null

    private val canSnooze get() =
        ringAlarmId != -1 && ringAlarmId != AlarmScheduler.TIMER_ID && ringAlarmId != AlarmScheduler.TEST_ID

    /** Run the action chosen for a button. Returns false for "nothing" (normal behaviour). */
    private fun runButtonAction(key: String): Boolean {
        val action = ButtonPrefs.get(this, key)
        if (action == ButtonPrefs.NOTHING) return false
        if (buttonDone) return true
        val snooze = ButtonPrefs.snoozeMinutes(action)
        when {
            action == "silence" -> silenceAlarm()
            snooze != null && canSnooze -> { buttonDone = true; snoozeAlarm(ringAlarmId, snooze, ringHour, ringMinute) }
            else -> { buttonDone = true; dismissAlarm(ringHour, ringMinute) } // "off", or snooze on timer/test
        }
        return true
    }

    /** Stop sound + vibration; the screen stays so you can still swipe off / snooze. */
    private fun silenceAlarm() {
        if (silenced) return
        silenced = true
        AlarmService.getInstance()?.silence()
        try { mediaPlayer?.stop() } catch (_: Exception) {}
        mediaPlayer?.release()
        mediaPlayer = null
        try { videoPlayer?.setVolume(0f, 0f) } catch (_: Exception) {}
        vibrator?.cancel()
        findViewById<TextView>(R.id.swipeHint)?.text =
            if (canSnooze) "Silenced · swipe up to turn off · down to snooze" else "Silenced · swipe up to turn off"
    }

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent): Boolean {
        val key = when (keyCode) {
            android.view.KeyEvent.KEYCODE_VOLUME_UP -> ButtonPrefs.VOL_UP
            android.view.KeyEvent.KEYCODE_VOLUME_DOWN -> ButtonPrefs.VOL_DOWN
            else -> return super.onKeyDown(keyCode, event)
        }
        if (ButtonPrefs.get(this, key) == ButtonPrefs.NOTHING) return super.onKeyDown(keyCode, event)
        if (event.repeatCount == 0) runButtonAction(key)
        return true // consumed: no volume change
    }

    override fun onKeyUp(keyCode: Int, event: android.view.KeyEvent): Boolean {
        val key = when (keyCode) {
            android.view.KeyEvent.KEYCODE_VOLUME_UP -> ButtonPrefs.VOL_UP
            android.view.KeyEvent.KEYCODE_VOLUME_DOWN -> ButtonPrefs.VOL_DOWN
            else -> return super.onKeyUp(keyCode, event)
        }
        return if (ButtonPrefs.get(this, key) == ButtonPrefs.NOTHING) super.onKeyUp(keyCode, event) else true
    }

    /** Apps can't read the power key, but pressing it turns the screen off -> we catch that. */
    private fun registerPowerButton() {
        if (ButtonPrefs.get(this, ButtonPrefs.POWER) == ButtonPrefs.NOTHING) return
        val r = object : android.content.BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                if (i.action == Intent.ACTION_SCREEN_OFF) runButtonAction(ButtonPrefs.POWER)
            }
        }
        try {
            androidx.core.content.ContextCompat.registerReceiver(
                this, r, android.content.IntentFilter(Intent.ACTION_SCREEN_OFF),
                androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED
            )
            screenOffReceiver = r
        } catch (e: Exception) {
            Log.e("AlarmActivity", "Power button receiver failed", e)
        }
    }

    /** Fullscreen, center-cropped, looping video with its audio on the ALARM stream. */
    private fun startVideo() {
        val texture = findViewById<android.view.TextureView>(R.id.videoView)
        texture.visibility = View.VISIBLE
        findViewById<View>(R.id.scrimTop).visibility = View.VISIBLE
        findViewById<View>(R.id.scrimBottom).visibility = View.VISIBLE
        findViewById<View>(R.id.pulseRing1).visibility = View.GONE
        findViewById<View>(R.id.pulseRing2).visibility = View.GONE

        texture.surfaceTextureListener = object : android.view.TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(st: android.graphics.SurfaceTexture, w: Int, h: Int) {
                try {
                    videoPlayer = MediaPlayer().apply {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                .build()
                        )
                        setDataSource(RingtoneStore.videoFile(this@AlarmActivity).absolutePath)
                        setSurface(android.view.Surface(st))
                        isLooping = true // loops until swiped off
                        setOnVideoSizeChangedListener { _, vw, vh -> centerCrop(texture, vw, vh) }
                        setOnPreparedListener {
                            if (silenced) it.setVolume(0f, 0f)
                            it.start()
                            videoStarted = true
                            AlarmService.getInstance()?.stopToneOnly() // in case fallback tone kicked in
                        }
                        setOnErrorListener { _, what, extra ->
                            Log.e("AlarmActivity", "Video error $what/$extra, falling back to tone")
                            videoFailed()
                            true
                        }
                        prepareAsync()
                    }
                } catch (e: Exception) {
                    Log.e("AlarmActivity", "Video start failed", e)
                    videoFailed()
                }
            }
            override fun onSurfaceTextureSizeChanged(st: android.graphics.SurfaceTexture, w: Int, h: Int) {
                videoPlayer?.let { centerCrop(texture, it.videoWidth, it.videoHeight) }
            }
            override fun onSurfaceTextureDestroyed(st: android.graphics.SurfaceTexture) = true
            override fun onSurfaceTextureUpdated(st: android.graphics.SurfaceTexture) {}
        }
    }

    /** Scale video to fill the screen without stretching (crop the overflow). */
    private fun centerCrop(view: android.view.TextureView, vw: Int, vh: Int) {
        if (vw == 0 || vh == 0 || view.width == 0 || view.height == 0) return
        val w = view.width.toFloat()
        val h = view.height.toFloat()
        val scale = maxOf(w / vw, h / vh)
        val m = android.graphics.Matrix()
        m.setScale(vw * scale / w, vh * scale / h, w / 2, h / 2)
        view.setTransform(m)
    }

    /** Video unusable: back to the normal look + tone (service fallback handles audio if running). */
    private fun videoFailed() {
        try { videoPlayer?.release() } catch (_: Exception) {}
        videoPlayer = null
        findViewById<View>(R.id.videoView).visibility = View.GONE
        findViewById<View>(R.id.scrimTop).visibility = View.GONE
        findViewById<View>(R.id.scrimBottom).visibility = View.GONE
        findViewById<View>(R.id.pulseRing1).visibility = View.VISIBLE
        findViewById<View>(R.id.pulseRing2).visibility = View.VISIBLE
        startPulse()
        if (AlarmService.getInstance() == null) startAlarmSound()
    }
    
    private val pulseAnimators = mutableListOf<android.animation.Animator>()

    /** Two rings expanding + fading, offset by half a cycle. */
    private fun startPulse() {
        listOf(R.id.pulseRing1 to 0L, R.id.pulseRing2 to 1200L).forEach { (id, delay) ->
            val ring = findViewById<View>(id)
            ring.alpha = 0f
            val anim = android.animation.AnimatorSet().apply {
                playTogether(
                    android.animation.ObjectAnimator.ofFloat(ring, View.SCALE_X, 0.85f, 1.5f).apply { repeatCount = android.animation.ValueAnimator.INFINITE },
                    android.animation.ObjectAnimator.ofFloat(ring, View.SCALE_Y, 0.85f, 1.5f).apply { repeatCount = android.animation.ValueAnimator.INFINITE },
                    android.animation.ObjectAnimator.ofFloat(ring, View.ALPHA, 0.7f, 0f).apply { repeatCount = android.animation.ValueAnimator.INFINITE }
                )
                duration = 2400
                startDelay = delay
                interpolator = android.view.animation.DecelerateInterpolator()
            }
            anim.start()
            pulseAnimators.add(anim)
        }
    }

    /**
     * Drag pill up past threshold -> OFF. Drag it down onto a target -> snooze 5 / 10 / 15 min
     * (target nearest the finger). Otherwise spring back. Timer has no snooze.
     */
    @android.annotation.SuppressLint("ClickableViewAccessibility")
    private fun setupSwipeToDismiss(hour: Int, minute: Int, alarmId: Int) {
        val pill = findViewById<View>(R.id.dismissPill)
        val hint = findViewById<TextView>(R.id.swipeHint)
        val row = findViewById<View>(R.id.snoozeRow)
        val targets = listOf(R.id.snooze5 to 5, R.id.snooze10 to 10, R.id.snooze15 to 15)
            .map { (id, min) -> findViewById<View>(id) to min }
        val canSnooze = alarmId != -1 && alarmId != AlarmScheduler.TIMER_ID && alarmId != AlarmScheduler.TEST_ID
        if (!canSnooze) {
            row.visibility = View.GONE
            hint.text = "Swipe up to turn off"
        }
        val density = resources.displayMetrics.density
        val threshold = 160 * density
        val snoozeThreshold = 80 * density
        var startX = 0f
        var startY = 0f
        var done = false
        var picked: Pair<View, Int>? = null

        fun nearest(rawX: Float) = targets.minByOrNull { (t, _) ->
            val loc = IntArray(2).also { t.getLocationOnScreen(it) }
            kotlin.math.abs(loc[0] + t.width / 2f - rawX)
        }

        fun highlight(p: Pair<View, Int>?) {
            if (p?.first == picked?.first) return
            picked = p
            if (p != null) pill.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
            targets.forEach { (t, _) ->
                val on = t == p?.first
                t.animate().scaleX(if (on) 1.18f else 1f).scaleY(if (on) 1.18f else 1f)
                    .alpha(if (on || p == null) 1f else 0.5f).setDuration(120).start()
            }
        }

        fun springBack() {
            pill.animate().translationX(0f).translationY(0f).alpha(1f).setDuration(200).start()
            hint.animate().alpha(1f).setDuration(200).start()
            row.animate().alpha(0.45f).setDuration(200).start()
            highlight(null)
        }

        pill.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> { startX = e.rawX; startY = e.rawY; true }
                android.view.MotionEvent.ACTION_MOVE -> {
                    val dy = e.rawY - startY
                    if (dy <= 0 || !canSnooze) {
                        // Up = OFF
                        v.translationX = 0f
                        v.translationY = dy.coerceAtMost(0f)
                        val p = (-v.translationY / threshold).coerceIn(0f, 1f)
                        v.alpha = 1f - 0.5f * p
                        hint.alpha = 1f - p
                        row.alpha = 0.45f * (1f - p)
                        highlight(null)
                    } else {
                        // Down = snooze; pill follows the finger toward a target
                        v.translationX = e.rawX - startX
                        v.translationY = dy
                        val p = (dy / snoozeThreshold).coerceIn(0f, 1f)
                        hint.alpha = 1f - p
                        row.alpha = 0.45f + 0.55f * p
                        highlight(if (dy >= snoozeThreshold * 0.5f) nearest(e.rawX) else null)
                    }
                    true
                }
                android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                    val target = picked
                    if (!done && -v.translationY >= threshold) {
                        done = true
                        v.animate().translationY(-threshold * 2).alpha(0f).setDuration(150)
                            .withEndAction { dismissAlarm(hour, minute) }.start()
                    } else if (!done && canSnooze && target != null && v.translationY >= snoozeThreshold) {
                        done = true
                        v.animate().alpha(0f).setDuration(150)
                            .withEndAction { snoozeAlarm(alarmId, target.second, hour, minute) }.start()
                    } else {
                        springBack()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun snoozeAlarm(alarmId: Int, minutes: Int, hour: Int, minute: Int) {
        try {
            AlarmScheduler.snooze(this, alarmId, minutes)
            android.widget.Toast.makeText(this, "Snoozed for $minutes min", android.widget.Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.e("AlarmActivity", "Snooze failed", e)
        }
        RingLog.log(this, "snooze", alarmId) { it.put("min", minutes) }
        dismissAlarm(hour, minute, log = false)
    }

    /** Replace the heads-up notification with a silent one so it doesn't cover the screen. */
    private fun quietServiceNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    android.app.NotificationChannel("alarm_ongoing", "Ringing alarm", android.app.NotificationManager.IMPORTANCE_LOW)
                )
            }
            val n = androidx.core.app.NotificationCompat.Builder(this, "alarm_ongoing")
                .setSmallIcon(R.mipmap.launcher_icon)
                .setContentTitle("Alarm ringing")
                .setOngoing(true)
                .setSilent(true)
                .build()
            if (AlarmService.getInstance() != null) nm.notify(1, n)
        } catch (e: Exception) {
            Log.e("AlarmActivity", "quietServiceNotification failed", e)
        }
    }

    private fun startAlarmSound() {
        // Get the default alarm sound
        val alarmSound = RingtoneStore.uriToPlay(this)
        mediaPlayer = try { buildPlayer(alarmSound) } catch (e: Exception) {
            Log.e("AlarmActivity", "Chosen ringtone failed, using default", e)
            try { buildPlayer(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)) } catch (e2: Exception) { null }
        }
    }

    private fun buildPlayer(alarmSound: android.net.Uri): MediaPlayer {
        return MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)  // Use USAGE_ALARM for proper audio focus
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
    
    private fun dismissAlarm(hour: Int, minute: Int, log: Boolean = true) {
        Log.d("AlarmActivity", "Dismissing alarm for $hour:$minute - FORCE STOP")
        if (log) RingLog.log(this, "off", ringAlarmId)

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
        try { mediaPlayer?.stop() } catch (_: Exception) {}
        mediaPlayer?.release()
        mediaPlayer = null

        try { videoPlayer?.stop() } catch (_: Exception) {}
        videoPlayer?.release()
        videoPlayer = null

        vibrator?.cancel()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        screenOffReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        screenOffReceiver = null
        pulseAnimators.forEach { it.cancel() }
        stopAlarm()
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }
}