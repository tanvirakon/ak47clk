package com.example.ak47clk

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.SystemClock

/** Low-latency "dial tick" for the wheel picker. Plays on the system (touch-sound) volume. */
object TickSound {
    private var pool: SoundPool? = null
    private var soundId = 0
    private var loaded = false
    private var lastAt = 0L

    fun init(c: Context) {
        if (pool != null) return
        pool = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            SoundPool.Builder()
                .setMaxStreams(3)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                ).build()
        } else {
            @Suppress("DEPRECATION")
            SoundPool(3, AudioManager.STREAM_SYSTEM, 0)
        }.also { p ->
            p.setOnLoadCompleteListener { _, _, status -> loaded = status == 0 }
            soundId = p.load(c.applicationContext, R.raw.wheel_tick, 1)
        }
    }

    fun play() {
        if (!loaded) return
        // Fast flings fire many steps; cap at ~1 tick per 25 ms so it stays crisp, not buzzy.
        val now = SystemClock.uptimeMillis()
        if (now - lastAt < 25) return
        lastAt = now
        pool?.play(soundId, 0.6f, 0.6f, 1, 0, 1f)
    }
}
