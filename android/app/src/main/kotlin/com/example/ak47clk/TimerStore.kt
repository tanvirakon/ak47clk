package com.example.ak47clk

import android.app.NotificationManager
import android.content.Context
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
    private const val NOTIF_ID = 47

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

    // ---------------- notification ----------------
    // No ongoing timer notification (removed on request). The timer still rings natively.
    // Only clears one left over from older versions.

    @Suppress("UNUSED_PARAMETER")
    private fun updateNotification(c: Context, end: Long, left: Long) = cancelNotification(c)

    private fun cancelNotification(c: Context) {
        try {
            (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
        } catch (_: Exception) {}
    }
}
