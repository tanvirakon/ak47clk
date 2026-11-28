package com.example.ak47clk

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

    data class State(val end: Long, val left: Long, val total: Long) {
        val running get() = end > 0
        val paused get() = end <= 0 && left > 0
    }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun state(c: Context): State {
        val p = prefs(c)
        return State(p.getLong("end", 0), p.getLong("left", 0), p.getLong("total", 0))
    }

    fun getJson(c: Context): String {
        val s = state(c)
        return JSONObject()
            .put("end", s.end)
            .put("left", s.left)
            .put("total", s.total)
            .toString()
    }

    /** Save state and (re)schedule / cancel the ring + notification. */
    fun set(c: Context, end: Long, left: Long, total: Long) {
        prefs(c).edit().putLong("end", end).putLong("left", left).putLong("total", total).commit()
        if (end > 0) AlarmScheduler.scheduleTimer(c, end) else AlarmScheduler.cancelTimer(c)
        ClockNotif.timer(c)
    }

    // ---- notification buttons ----

    fun toggle(c: Context) {
        val s = state(c)
        val now = System.currentTimeMillis()
        when {
            s.running && s.end > now -> set(c, 0, s.end - now, s.total)
            s.paused -> set(c, now + s.left, 0, s.total)
        }
    }

    fun addMinute(c: Context) {
        val s = state(c)
        when {
            s.running -> set(c, s.end + 60_000, 0, s.total + 60_000)
            s.paused -> set(c, 0, s.left + 60_000, s.total + 60_000)
        }
    }

    fun cancel(c: Context) = set(c, 0, 0, state(c).total)

    /** Timer rang: back to idle. */
    fun onRang(c: Context) {
        prefs(c).edit().putLong("end", 0).putLong("left", 0).commit()
        ClockNotif.timer(c)
    }

    /** After reboot / time change: reschedule a running timer, drop one that expired while off. */
    fun restore(c: Context) {
        val s = state(c)
        if (s.running && s.end <= System.currentTimeMillis()) { onRang(c); return }
        if (s.running) AlarmScheduler.scheduleTimer(c, s.end)
        ClockNotif.timer(c)
    }
}
