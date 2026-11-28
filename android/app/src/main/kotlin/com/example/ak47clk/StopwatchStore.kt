package com.example.ak47clk

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Stopwatch state (native, so the notification buttons work with the app closed).
 *  running : counting now
 *  start   : epoch ms of the last Start
 *  acc     : ms banked before the last Start
 *  laps    : cumulative ms at each lap
 */
object StopwatchStore {
    private const val PREFS = "stopwatch_store"

    data class State(val running: Boolean, val start: Long, val acc: Long, val laps: List<Long>) {
        fun elapsed(now: Long = System.currentTimeMillis()) = acc + if (running) now - start else 0
        val active get() = running || acc > 0
    }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun state(c: Context): State {
        val p = prefs(c)
        val laps = try {
            val a = JSONArray(p.getString("laps", "[]"))
            List(a.length()) { a.getLong(it) }
        } catch (_: Exception) { emptyList() }
        return State(p.getBoolean("running", false), p.getLong("start", 0), p.getLong("acc", 0), laps)
    }

    /** "init" = false until Flutter first saves (lets it migrate the old Dart-side state once). */
    fun getJson(c: Context): String {
        val s = state(c)
        return JSONObject()
            .put("running", s.running)
            .put("start", s.start)
            .put("acc", s.acc)
            .put("laps", JSONArray(s.laps))
            .put("init", prefs(c).getBoolean("init", false))
            .toString()
    }

    fun set(c: Context, s: State) {
        prefs(c).edit()
            .putBoolean("running", s.running)
            .putLong("start", s.start)
            .putLong("acc", s.acc)
            .putString("laps", JSONArray(s.laps).toString())
            .putBoolean("init", true)
            .commit()
        ClockNotif.stopwatch(c)
    }

    fun toggle(c: Context) {
        val s = state(c)
        val now = System.currentTimeMillis()
        set(c, if (s.running) s.copy(running = false, acc = s.elapsed(now))
               else s.copy(running = true, start = now))
    }

    fun lap(c: Context) {
        val s = state(c)
        if (s.running) set(c, s.copy(laps = s.laps + s.elapsed()))
    }

    fun reset(c: Context) = set(c, State(false, 0, 0, emptyList()))

    /** After reboot / update: bring the notification back. */
    fun restore(c: Context) = ClockNotif.stopwatch(c)
}
