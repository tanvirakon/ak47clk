package com.example.ak47clk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

/** Talks to AlarmManager. Each alarm's unique id is its request code. */
object AlarmScheduler {
    const val ACTION_ALARM = "com.example.ak47clk.ALARM"
    const val EXTRA_ID = "ALARM_ID"
    private const val TAG = "AlarmScheduler"

    private fun flags() =
        PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

    private fun pending(c: Context, a: AlarmStore.Alarm): PendingIntent {
        val i = Intent(c, AlarmReceiver::class.java).apply {
            action = ACTION_ALARM
            putExtra(EXTRA_ID, a.id)
            putExtra("HOUR", a.hour)
            putExtra("MINUTE", a.minute)
        }
        return PendingIntent.getBroadcast(c, a.id, i, flags())
    }

    /** Next occurrence of h:m (today if still ahead, else tomorrow). */
    fun nextTrigger(h: Int, m: Int): Long = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, h)
        set(Calendar.MINUTE, m)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    /** Request code of the countdown timer (below alarm ids 100_000+, above legacy codes <= 2359). */
    const val TIMER_ID = 99_000

    private fun timerAlarm(at: Long): AlarmStore.Alarm {
        val cal = Calendar.getInstance().apply { timeInMillis = at }
        return AlarmStore.Alarm(TIMER_ID, cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))
    }

    fun scheduleTimer(c: Context, at: Long) = scheduleAt(c, pending(c, timerAlarm(at)), at)

    fun cancelTimer(c: Context) = cancel(c, timerAlarm(System.currentTimeMillis()))

    /** "Test alarm" from Settings: one ring after [seconds], same path as a real alarm. */
    const val TEST_ID = 98_500

    fun scheduleTest(c: Context, seconds: Int) {
        val at = System.currentTimeMillis() + seconds * 1000L
        val cal = Calendar.getInstance().apply { timeInMillis = at }
        val a = AlarmStore.Alarm(TEST_ID, cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))
        scheduleAt(c, pending(c, a), at)
    }

    /**
     * Next ring of alarm [a] in group [g] strictly after [after].
     * Once: next h:m. Repeating: days apply to the day a run STARTS, so 1 AM in an
     * 11 PM–1 AM Friday run rings early Saturday. Rings before g.skipUntil are skipped.
     */
    fun nextTrigger(g: AlarmStore.Group, a: AlarmStore.Alarm, after: Long = System.currentTimeMillis()): Long {
        if (!g.repeats) return nextTrigger(a.hour, a.minute)
        val bound = maxOf(after, g.skipUntil)
        val start = g.startMin
        val offset = g.offsetOf(a)
        for (d in -1..15) {
            val cal = Calendar.getInstance().apply {
                timeInMillis = bound
                add(Calendar.DAY_OF_YEAR, d)
                set(Calendar.HOUR_OF_DAY, start / 60)
                set(Calendar.MINUTE, start % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (g.days and (1 shl (cal.get(Calendar.DAY_OF_WEEK) - 1)) == 0) continue
            cal.add(Calendar.MINUTE, offset)
            if (cal.timeInMillis > bound) return cal.timeInMillis
        }
        return nextTrigger(a.hour, a.minute)
    }

    fun schedule(c: Context, g: AlarmStore.Group, a: AlarmStore.Alarm, after: Long = System.currentTimeMillis()) =
        scheduleAt(c, pending(c, a), nextTrigger(g, a, after))

    // ---------------- snooze ----------------
    // Own PendingIntent per alarm (request code = -alarmId), saved so it survives reboot.

    private const val SNOOZE_PREFS = "snooze_store"
    const val EXTRA_SNOOZE = "SNOOZE"

    private fun snoozePending(c: Context, alarmId: Int, at: Long): PendingIntent {
        val cal = Calendar.getInstance().apply { timeInMillis = at }
        val i = Intent(c, AlarmReceiver::class.java).apply {
            action = ACTION_ALARM
            putExtra(EXTRA_ID, alarmId)
            putExtra(EXTRA_SNOOZE, true)
            putExtra("HOUR", cal.get(Calendar.HOUR_OF_DAY))
            putExtra("MINUTE", cal.get(Calendar.MINUTE))
        }
        return PendingIntent.getBroadcast(c, -alarmId, i, flags())
    }

    fun snooze(c: Context, alarmId: Int, minutes: Int) {
        val at = System.currentTimeMillis() + minutes * 60_000L
        c.getSharedPreferences(SNOOZE_PREFS, Context.MODE_PRIVATE).edit().putLong(alarmId.toString(), at).commit()
        scheduleAt(c, snoozePending(c, alarmId, at), at)
    }

    /** Snoozed alarm rang: forget it. */
    fun snoozeRang(c: Context, alarmId: Int) {
        c.getSharedPreferences(SNOOZE_PREFS, Context.MODE_PRIVATE).edit().remove(alarmId.toString()).commit()
    }

    fun cancelSnooze(c: Context, alarmId: Int) {
        val p = c.getSharedPreferences(SNOOZE_PREFS, Context.MODE_PRIVATE)
        if (!p.contains(alarmId.toString())) return
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val op = snoozePending(c, alarmId, 0)
        am.cancel(op)
        op.cancel()
        p.edit().remove(alarmId.toString()).commit()
    }

    /** alarmId -> snooze time, future ones only. */
    fun pendingSnoozes(c: Context): Map<Int, Long> {
        val now = System.currentTimeMillis()
        return c.getSharedPreferences(SNOOZE_PREFS, Context.MODE_PRIVATE).all.mapNotNull { (k, v) ->
            val id = k.toIntOrNull()
            val at = v as? Long
            if (id != null && at != null && at > now) id to at else null
        }.toMap()
    }

    private fun restoreSnoozes(c: Context) {
        val p = c.getSharedPreferences(SNOOZE_PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        p.all.forEach { (k, v) ->
            val id = k.toIntOrNull()
            val at = v as? Long
            if (id == null || at == null || at <= now) p.edit().remove(k).apply()
            else scheduleAt(c, snoozePending(c, id, at), at)
        }
    }

    private fun scheduleAt(c: Context, op: PendingIntent, at: Long) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
            if (canExact) {
                // setAlarmClock = highest priority, exempt from Doze, shows the alarm icon.
                val show = PendingIntent.getActivity(
                    c, 0, Intent(c, MainActivity::class.java), flags()
                )
                am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), op)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Exact alarm not allowed, using inexact", e)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
        }
    }

    fun cancel(c: Context, a: AlarmStore.Alarm) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val op = pending(c, a)
        am.cancel(op)
        op.cancel()
    }

    /** Cancel an alarm scheduled by the OLD code (request code hour*100+minute). */
    fun cancelLegacy(c: Context, h: Int, m: Int) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val i = Intent(c, AlarmReceiver::class.java).apply {
            action = ACTION_ALARM
            putExtra("HOUR", h)
            putExtra("MINUTE", m)
        }
        val op = PendingIntent.getBroadcast(c, h * 100 + m, i, flags())
        am.cancel(op)
        op.cancel()
    }

    /** (Re)schedule every alarm in every enabled group; cancel the rest. Used on boot / app start. */
    fun rescheduleAll(c: Context) {
        AlarmStore.migrateIfNeeded(c)
        var n = 0
        AlarmStore.load(c).forEach { g ->
            g.alarms.forEach { a ->
                if (g.enabled) { schedule(c, g, a); n++ } else cancel(c, a)
            }
        }
        restoreSnoozes(c)
        TimerStore.restore(c)
        StopwatchStore.restore(c)
        Log.d(TAG, "Rescheduled $n alarms")
    }
}
