package com.example.ak47clk

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * Append-only history of what happened to each alarm ring (for the Stats tab).
 * One JSON object per line in filesDir/ring_log.jsonl (covered by Android Auto Backup).
 *
 * Event: t (ms), type (ring | snooze | off), a (alarm id), g (group id),
 * run (start of this run/morning, ms), single (bool), snz (ring came from a snooze), min (snooze minutes).
 * Timer and test alarms are never logged. Logging must never break ringing: every call swallows errors.
 */
object RingLog {
    private const val FILE = "ring_log.jsonl"
    private const val TAG = "RingLog"
    private const val KEEP_MS = 400L * 24 * 3600 * 1000
    private const val TRIM_PREF = "ring_log_trim"

    private fun file(c: Context) = File(c.filesDir, FILE)

    private fun loggable(alarmId: Int) =
        alarmId != -1 && alarmId != AlarmScheduler.TIMER_ID && alarmId != AlarmScheduler.TEST_ID

    /**
     * Start of the run this alarm belongs to: the latest occurrence of its h:m (at or before now + 1 min),
     * minus its offset inside the group. Snoozed rings map back to the same run.
     */
    fun runStart(g: AlarmStore.Group, a: AlarmStore.Alarm, now: Long = System.currentTimeMillis()): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, a.hour)
            set(Calendar.MINUTE, a.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis > now + 60_000) add(Calendar.DAY_OF_YEAR, -1)
        }
        return cal.timeInMillis - g.offsetOf(a) * 60_000L
    }

    fun log(c: Context, type: String, alarmId: Int, extra: (JSONObject) -> Unit = {}) {
        if (!loggable(alarmId)) return
        try {
            val g = AlarmStore.findByAlarmId(c, alarmId) ?: return
            val a = g.alarms.first { it.id == alarmId }
            val now = System.currentTimeMillis()
            val o = JSONObject().apply {
                put("t", now)
                put("type", type)
                put("a", alarmId)
                put("g", g.id)
                put("run", runStart(g, a, now))
                put("single", g.single || g.alarms.size == 1)
                extra(this)
            }
            synchronized(this) {
                file(c).appendText(o.toString() + "\n")
                trimIfDue(c, now)
            }
            MainActivity.notifyStatsChanged()
        } catch (e: Exception) {
            Log.e(TAG, "log $type failed", e)
        }
    }

    /** Events newer than [since] as a JSON array string. */
    fun readJson(c: Context, since: Long): String {
        val arr = JSONArray()
        try {
            synchronized(this) {
                val f = file(c)
                if (f.exists()) f.forEachLine { line ->
                    try {
                        val o = JSONObject(line)
                        if (o.optLong("t") >= since) arr.put(o)
                    } catch (_: Exception) {} // skip a broken line
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "read failed", e)
        }
        return arr.toString()
    }

    /** Once a day drop events older than ~13 months. */
    private fun trimIfDue(c: Context, now: Long) {
        val p = c.getSharedPreferences(TRIM_PREF, Context.MODE_PRIVATE)
        if (now - p.getLong("last", 0) < 24 * 3600 * 1000L) return
        p.edit().putLong("last", now).apply()
        val f = file(c)
        if (!f.exists()) return
        val keep = f.readLines().filter { line ->
            try { JSONObject(line).optLong("t") >= now - KEEP_MS } catch (_: Exception) { false }
        }
        f.writeText(if (keep.isEmpty()) "" else keep.joinToString("\n", postfix = "\n"))
    }
}
