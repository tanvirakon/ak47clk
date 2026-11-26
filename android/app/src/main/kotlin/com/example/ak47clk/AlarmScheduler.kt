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

    fun schedule(c: Context, a: AlarmStore.Alarm) =
        scheduleAt(c, pending(c, a), nextTrigger(a.hour, a.minute))

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
                if (g.enabled) { schedule(c, a); n++ } else cancel(c, a)
            }
        }
        TimerStore.restore(c)
        Log.d(TAG, "Rescheduled $n alarms")
    }
}
