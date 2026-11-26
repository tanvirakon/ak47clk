package com.example.ak47clk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/**
 * Countdown timer state (native = survives app kill / reboot).
 *  end   > 0 : running, rings at this epoch ms
 *  left  > 0 : paused with this many ms left
 *  total     : full duration (for the progress ring)
 * Both 0 = idle.
 */
object TimerStore {
    private const val PREFS = "timer_store"
    private const val CHANNEL = "timer_ongoing"
    private const val NOTIF_ID = 47
    private const val TAG = "TimerStore"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun getJson(c: Context): String {
        val p = prefs(c)
        return JSONObject()
            .put("end", p.getLong("end", 0))
            .put("left", p.getLong("left", 0))
            .put("total", p.getLong("total", 0))
            .toString()
    }

    /** Save state from Flutter and (re)schedule / cancel the ring + notification. */
    fun set(c: Context, end: Long, left: Long, total: Long) {
        prefs(c).edit().putLong("end", end).putLong("left", left).putLong("total", total).commit()
        if (end > 0) AlarmScheduler.scheduleTimer(c, end) else AlarmScheduler.cancelTimer(c)
        updateNotification(c, end, left)
    }

    /** Timer rang: back to idle. */
    fun onRang(c: Context) {
        prefs(c).edit().putLong("end", 0).putLong("left", 0).commit()
        cancelNotification(c)
    }

    /** After reboot / time change: reschedule a running timer, drop one that expired while off. */
    fun restore(c: Context) {
        val p = prefs(c)
        val end = p.getLong("end", 0)
        if (end <= 0) return
        if (end > System.currentTimeMillis()) {
            AlarmScheduler.scheduleTimer(c, end)
            updateNotification(c, end, 0)
        } else {
            onRang(c)
        }
    }

    // ---------------- ongoing notification ----------------

    private fun fmt(ms: Long): String {
        val s = (ms + 999) / 1000
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%02d:%02d", m, sec)
    }

    private fun updateNotification(c: Context, end: Long, left: Long) {
        if (end <= 0 && left <= 0) { cancelNotification(c); return }
        try {
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Timer", NotificationManager.IMPORTANCE_LOW).apply {
                        setSound(null, null)
                        enableVibration(false)
                        setShowBadge(false)
                    }
                )
            }
            val open = PendingIntent.getActivity(
                c, NOTIF_ID, Intent(c, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )
            val b = NotificationCompat.Builder(c, CHANNEL)
                .setSmallIcon(R.mipmap.launcher_icon)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(open)
            if (end > 0) {
                // Live countdown drawn by the system (no app process needed).
                b.setContentTitle("Timer")
                    .setWhen(end)
                    .setShowWhen(true)
                    .setUsesChronometer(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) b.setChronometerCountDown(true)
                else b.setContentText("Running")
            } else {
                b.setContentTitle("Timer paused").setContentText("${fmt(left)} left").setShowWhen(false)
            }
            nm.notify(NOTIF_ID, b.build())
        } catch (e: Exception) {
            Log.e(TAG, "Timer notification failed", e) // e.g. notifications denied on 13+
        }
    }

    private fun cancelNotification(c: Context) {
        try {
            (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
        } catch (_: Exception) {}
    }
}
