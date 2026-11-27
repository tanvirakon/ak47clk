package com.example.ak47clk

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Single source of truth for all alarms (native side, JSON in SharedPreferences).
 *
 * Every alarm has its own unique [Alarm.id] which is also its AlarmManager request code,
 * so two groups can contain the same time without clashing.
 */
object AlarmStore {
    private const val PREFS = "alarm_store"
    private const val KEY_GROUPS = "groups"
    private const val KEY_NEXT_ID = "next_id"
    private const val KEY_MIGRATED = "migrated_v1"
    private const val TAG = "AlarmStore"

    /** IDs start high so they never collide with the old hour*100+minute request codes (max 2359). */
    private const val FIRST_ID = 100_000

    data class Alarm(val id: Int, val hour: Int, val minute: Int)

    data class Group(
        val id: Int,
        val fromHour: Int?, val fromMinute: Int?,   // null for migrated "individual" alarms
        val toHour: Int?, val toMinute: Int?,
        val interval: Int?,
        var enabled: Boolean,
        val alarms: MutableList<Alarm>,
        val single: Boolean = false,   // normal alarm (one time) instead of an interval range
        val label: String? = null,
        /** Repeat days bitmask: bit (Calendar.DAY_OF_WEEK - 1), Sun = bit 0 .. Sat = bit 6. 0 = Once. */
        val days: Int = 0,
        /** "Skip next": rings before this time are skipped (0 = none). */
        var skipUntil: Long = 0,
        /** First ring that is being skipped (for the "Skipping Thu" note). */
        var skipAt: Long = 0,
    ) {
        val repeats get() = days != 0
        /** Minutes past midnight where one "run" of this group starts. */
        val startMin get() = if (fromHour != null && fromMinute != null) fromHour * 60 + fromMinute
            else alarms.firstOrNull()?.let { it.hour * 60 + it.minute } ?: 0
        fun offsetOf(a: Alarm) = ((a.hour * 60 + a.minute) - startMin + 1440) % 1440
    }

    const val DAILY = 0x7F

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---------------- read / write ----------------

    @Synchronized
    fun load(c: Context): MutableList<Group> {
        val raw = prefs(c).getString(KEY_GROUPS, null) ?: return mutableListOf()
        return try {
            val arr = JSONArray(raw)
            MutableList(arr.length()) { i -> groupFromJson(arr.getJSONObject(i)) }
        } catch (e: Exception) {
            Log.e(TAG, "Corrupt store, starting empty", e)
            mutableListOf()
        }
    }

    @Synchronized
    fun save(c: Context, groups: List<Group>) {
        val arr = JSONArray()
        groups.forEach { arr.put(groupToJson(it)) }
        prefs(c).edit().putString(KEY_GROUPS, arr.toString()).commit()
    }

    @Synchronized
    private fun newId(c: Context): Int {
        val p = prefs(c)
        val id = p.getInt(KEY_NEXT_ID, FIRST_ID)
        p.edit().putInt(KEY_NEXT_ID, id + 1).commit()
        return id
    }

    /**
     * JSON handed to Flutter, plus "nextAt" (next ring of enabled groups, after skips)
     * and "snoozeAt" (earliest pending snooze of any of its alarms).
     */
    fun toJsonString(c: Context, groups: List<Group>): String {
        val snoozes = AlarmScheduler.pendingSnoozes(c)
        val arr = JSONArray()
        groups.forEach { g ->
            arr.put(groupToJson(g).apply {
                if (g.enabled && g.alarms.isNotEmpty()) put("nextAt", g.alarms.minOf { AlarmScheduler.nextTrigger(g, it) })
                g.alarms.mapNotNull { snoozes[it.id] }.minOrNull()?.let { put("snoozeAt", it) }
            })
        }
        return arr.toString()
    }

    /** Cancel every pending snooze of a group (alarm itself unchanged). */
    fun cancelSnoozes(c: Context, groupId: Int) {
        load(c).find { it.id == groupId }?.alarms?.forEach { AlarmScheduler.cancelSnooze(c, it.id) }
    }

    // ---------------- operations ----------------

    /**
     * Times from start to end every [interval] minutes. If end < start the range wraps past
     * midnight (e.g. 23:00 -> 01:00). end == start gives a single alarm.
     */
    fun intervalTimes(fromH: Int, fromM: Int, toH: Int, toM: Int, interval: Int): List<Pair<Int, Int>> {
        require(interval > 0) { "Interval must be > 0" }
        val start = fromH * 60 + fromM
        var end = toH * 60 + toM
        if (end < start) end += 24 * 60
        val out = mutableListOf<Pair<Int, Int>>()
        var t = start
        while (t <= end) {
            val m = t % (24 * 60)
            out.add(m / 60 to m % 60)
            t += interval
        }
        return out
    }

    fun createGroup(c: Context, fromH: Int, fromM: Int, toH: Int, toM: Int, interval: Int, days: Int): Group {
        val groups = load(c)
        val alarms = intervalTimes(fromH, fromM, toH, toM, interval)
            .map { (h, m) -> Alarm(newId(c), h, m) }
            .toMutableList()
        val g = Group(newId(c), fromH, fromM, toH, toM, interval, true, alarms, days = days and DAILY)
        groups.add(g)
        save(c, groups)
        return g
    }

    private fun cleanLabel(label: String?) = label?.trim()?.take(60)?.ifEmpty { null }

    /** Normal alarm (one time). */
    fun createSingle(c: Context, h: Int, m: Int, label: String?, days: Int): Group {
        val groups = load(c)
        val g = Group(
            id = newId(c), fromHour = null, fromMinute = null, toHour = null, toMinute = null,
            interval = null, enabled = true, alarms = mutableListOf(Alarm(newId(c), h, m)),
            single = true, label = cleanLabel(label), days = days and DAILY,
        )
        groups.add(g)
        save(c, groups)
        return g
    }

    /** Change time/label/days of a single alarm. Keeps its alarm id; turns it back on, clears skip. */
    fun updateSingle(c: Context, groupId: Int, h: Int, m: Int, label: String?, days: Int): Group? {
        val groups = load(c)
        val i = groups.indexOfFirst { it.id == groupId && it.single }
        if (i < 0) return null
        val old = groups[i]
        val alarm = Alarm(old.alarms.firstOrNull()?.id ?: newId(c), h, m)
        val g = old.copy(
            enabled = true, alarms = mutableListOf(alarm), label = cleanLabel(label),
            days = days and DAILY, skipUntil = 0, skipAt = 0,
        )
        groups[i] = g
        save(c, groups)
        return g
    }

    /**
     * An alarm rang. Once: a single alarm switches off; an interval group switches off after its
     * last time. Repeating: schedule this alarm's next ring.
     */
    fun onFired(c: Context, alarmId: Int): Group? {
        val groups = load(c)
        val g = groups.find { gr -> gr.alarms.any { it.id == alarmId } } ?: return null
        val a = g.alarms.first { it.id == alarmId }
        if (!g.enabled) return g
        if (g.repeats) {
            AlarmScheduler.schedule(c, g, a, System.currentTimeMillis() + 60_000)
        } else if (g.single || g.offsetOf(a) == g.alarms.maxOf { g.offsetOf(it) }) {
            g.enabled = false
            g.alarms.forEach { if (it.id != alarmId) AlarmScheduler.cancel(c, it) }
            save(c, groups)
        }
        return g
    }

    /** Skip the next ring (whole next run for interval groups). Returns false if not repeating. */
    fun skipNext(c: Context, groupId: Int): Boolean {
        val groups = load(c)
        val g = groups.find { it.id == groupId } ?: return false
        if (!g.repeats || g.alarms.isEmpty()) return false
        val now = System.currentTimeMillis()
        val first = g.alarms.minByOrNull { AlarmScheduler.nextTrigger(g, it, now) }!!
        val t0 = AlarmScheduler.nextTrigger(g, first, now)
        val runStart = t0 - g.offsetOf(first) * 60_000L
        val runEnd = runStart + g.alarms.maxOf { g.offsetOf(it) } * 60_000L
        g.enabled = true
        g.skipAt = t0
        g.skipUntil = runEnd + 1
        save(c, groups)
        g.alarms.forEach { AlarmScheduler.schedule(c, g, it); AlarmScheduler.cancelSnooze(c, it.id) }
        return true
    }

    /** Turn a group on/off. Clears any skip; off also cancels snoozes. */
    fun setEnabled(c: Context, groupId: Int, enabled: Boolean) {
        val groups = load(c)
        val g = groups.find { it.id == groupId } ?: return
        g.enabled = enabled
        g.skipUntil = 0
        g.skipAt = 0
        save(c, groups)
        g.alarms.forEach {
            if (enabled) AlarmScheduler.schedule(c, g, it)
            else { AlarmScheduler.cancel(c, it); AlarmScheduler.cancelSnooze(c, it.id) }
        }
    }

    fun findByAlarmId(c: Context, alarmId: Int): Group? =
        load(c).find { gr -> gr.alarms.any { it.id == alarmId } }

    // ---------------- JSON ----------------

    private fun groupToJson(g: Group) = JSONObject().apply {
        put("id", g.id)
        g.fromHour?.let { put("fromHour", it) }
        g.fromMinute?.let { put("fromMinute", it) }
        g.toHour?.let { put("toHour", it) }
        g.toMinute?.let { put("toMinute", it) }
        g.interval?.let { put("interval", it) }
        put("enabled", g.enabled)
        if (g.single) put("single", true)
        g.label?.let { put("label", it) }
        put("days", g.days)
        if (g.skipUntil > 0) put("skipUntil", g.skipUntil).put("skipAt", g.skipAt)
        put("alarms", JSONArray().apply {
            g.alarms.forEach { a ->
                put(JSONObject().put("id", a.id).put("hour", a.hour).put("minute", a.minute))
            }
        })
    }

    private fun groupFromJson(o: JSONObject): Group {
        fun optInt(k: String) = if (o.has(k)) o.getInt(k) else null
        val arr = o.getJSONArray("alarms")
        val single = o.optBoolean("single", false)
        return Group(
            id = o.getInt("id"),
            fromHour = optInt("fromHour"), fromMinute = optInt("fromMinute"),
            toHour = optInt("toHour"), toMinute = optInt("toMinute"),
            interval = optInt("interval"),
            enabled = o.optBoolean("enabled", true),
            alarms = MutableList(arr.length()) { i ->
                val a = arr.getJSONObject(i)
                Alarm(a.getInt("id"), a.getInt("hour"), a.getInt("minute"))
            },
            single = single,
            label = if (o.has("label")) o.getString("label") else null,
            // Saved before repeat days existed: singles were Once, interval groups meant Daily.
            days = if (o.has("days")) o.getInt("days") else if (single) 0 else DAILY,
            skipUntil = o.optLong("skipUntil", 0),
            skipAt = o.optLong("skipAt", 0),
        )
    }

    // ---------------- one-time migration from the old format ----------------

    /**
     * Old app kept groups in Flutter prefs ("groupId|h:m,h:m;...", groupId = "fh:fm-th:tm-interval"
     * or "single") and scheduled alarms with request code hour*100+minute.
     * Import those groups, cancel every old-style pending alarm, and let the caller reschedule.
     * Returns true if a migration ran.
     */
    @Synchronized
    fun migrateIfNeeded(c: Context): Boolean {
        val p = prefs(c)
        if (p.getBoolean(KEY_MIGRATED, false)) return false

        val flutter = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = flutter.getString("flutter.stored_alarm_groups", null)
        val oldNative = c.getSharedPreferences("alarm_prefs", Context.MODE_PRIVATE)
        val groups = load(c)
        val oldTimes = mutableSetOf<Pair<Int, Int>>()

        try {
            raw?.split(';')?.filter { it.isNotBlank() }?.forEach { gs ->
                val parts = gs.split('|')
                if (parts.size != 2 || parts[1].isBlank()) return@forEach
                val oldId = parts[0]
                val times = parts[1].split(',').mapNotNull { t ->
                    val hm = t.split(':')
                    if (hm.size == 2) hm[0].trim().toIntOrNull()?.let { h ->
                        hm[1].trim().toIntOrNull()?.let { m -> h to m }
                    } else null
                }
                if (times.isEmpty()) return@forEach
                oldTimes.addAll(times)

                val meta = oldId.split('-')
                val from = meta.getOrNull(0)?.split(':')
                val to = meta.getOrNull(1)?.split(':')
                val isInterval = oldId != "single" && meta.size == 3 && from?.size == 2 && to?.size == 2
                val enabled = flutter.getBoolean("flutter.alarm_group_enabled_$oldId", true)

                groups.add(
                    Group(
                        id = newId(c),
                        fromHour = if (isInterval) from!![0].toIntOrNull() else null,
                        fromMinute = if (isInterval) from!![1].toIntOrNull() else null,
                        toHour = if (isInterval) to!![0].toIntOrNull() else null,
                        toMinute = if (isInterval) to!![1].toIntOrNull() else null,
                        interval = if (isInterval) meta[2].toIntOrNull() else null,
                        enabled = enabled,
                        alarms = times.map { (h, m) -> Alarm(newId(c), h, m) }.toMutableList(),
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Migration parse failed (continuing)", e)
        }

        // Also collect any times the old native side had scheduled.
        oldNative.all.forEach { (k, v) ->
            if (k.startsWith("alarm_") && k != "alarm_list" && v is String) {
                val hm = v.split(':')
                if (hm.size == 2) {
                    val h = hm[0].toIntOrNull(); val m = hm[1].toIntOrNull()
                    if (h != null && m != null) oldTimes.add(h to m)
                }
            }
        }
        oldTimes.forEach { (h, m) -> AlarmScheduler.cancelLegacy(c, h, m) }

        save(c, groups)
        oldNative.edit().clear().commit()
        p.edit().putBoolean(KEY_MIGRATED, true).commit()
        Log.d(TAG, "Migrated ${groups.size} groups, cancelled ${oldTimes.size} legacy alarms")
        return true
    }
}
