package com.example.ak47clk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import java.text.DateFormat
import java.util.Date

/**
 * Silent ongoing notifications for the timer and stopwatch, with control buttons.
 * Running = can't be swiped (on Android 14+ a swipe just re-posts it). Paused = swipe resets.
 */
object ClockNotif {
    private const val CHANNEL = "clock_ongoing"
    const val TIMER_ID = 47
    const val STOPWATCH_ID = 48

    const val TAB_TIMER = 1
    const val TAB_STOPWATCH = 2

    private fun nm(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(c: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = nm(c)
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Timer & stopwatch", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Controls for a running timer or stopwatch"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
    }

    private val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

    private fun action(c: Context, act: String, req: Int): PendingIntent =
        PendingIntent.getBroadcast(c, req, Intent(c, ClockActionReceiver::class.java).setAction(act), piFlags)

    private fun openTab(c: Context, tab: Int): PendingIntent {
        val i = Intent(c, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_OPEN_TAB, tab)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(c, 97_000 + tab, i, piFlags)
    }

    private fun base(c: Context, title: String, tab: Int, ongoing: Boolean, swipeAction: String, req: Int) =
        NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(if (tab == TAB_TIMER) R.drawable.ic_stat_timer else R.drawable.ic_stat_stopwatch)
            .setContentTitle(title)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOngoing(ongoing)
            .setAutoCancel(false)
            .setContentIntent(openTab(c, tab))
            .setDeleteIntent(action(c, swipeAction, req))

    /** Big live clock: Chronometer counts by itself, no app updates needed. */
    private fun clockView(c: Context, sub: String, chronoBase: Long, started: Boolean, countDown: Boolean,
                          staticText: String?): RemoteViews {
        val v = RemoteViews(c.packageName, R.layout.notif_clock)
        if (staticText != null) {
            v.setViewVisibility(R.id.chrono, View.GONE)
            v.setViewVisibility(R.id.staticTime, View.VISIBLE)
            v.setTextViewText(R.id.staticTime, staticText)
        } else {
            v.setViewVisibility(R.id.chrono, View.VISIBLE)
            v.setViewVisibility(R.id.staticTime, View.GONE)
            if (countDown && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                v.setChronometerCountDown(R.id.chrono, true)
            }
            v.setChronometer(R.id.chrono, chronoBase, null, started)
        }
        v.setTextViewText(R.id.sub, sub)
        return v
    }

    private fun post(c: Context, id: Int, b: NotificationCompat.Builder) {
        try {
            ensureChannel(c)
            nm(c).notify(id, b.build())
        } catch (e: Exception) {
            Log.e("ClockNotif", "notify failed", e) // e.g. notifications blocked: timer still rings
        }
    }

    private fun cancel(c: Context, id: Int) {
        try { nm(c).cancel(id) } catch (_: Exception) {}
    }

    private fun fmt(ms: Long, roundUp: Boolean): String {
        val sec = if (roundUp) (ms + 999) / 1000 else ms / 1000
        val h = sec / 3600; val m = (sec / 60) % 60; val s = sec % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    // ---------------- timer ----------------

    fun timer(c: Context) {
        val s = TimerStore.state(c)
        val now = System.currentTimeMillis()
        if (!(s.running && s.end > now) && !s.paused) { cancel(c, TIMER_ID); return }

        val running = s.running
        val endText = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(s.end))
        val b = base(c, if (running) "Timer" else "Timer paused", TAB_TIMER, running, ClockActionReceiver.TIMER_SWIPED, 1)
        val view = if (running) {
            val left = s.end - now
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                clockView(c, "Ends $endText", SystemClock.elapsedRealtime() + left, true, true, null)
            } else {
                clockView(c, "Timer running", 0, false, false, "Ends $endText") // no countdown before Android 7
            }
        } else {
            clockView(c, "Paused", 0, false, false, fmt(s.left, true))
        }
        b.setContentText(if (running) "Ends $endText" else "Paused · ${fmt(s.left, true)} left")
            .setCustomContentView(view)
            .addAction(0, if (running) "Pause" else "Resume", action(c, ClockActionReceiver.TIMER_TOGGLE, 2))
            .addAction(0, "+1 min", action(c, ClockActionReceiver.TIMER_ADD, 3))
            .addAction(0, "Cancel", action(c, ClockActionReceiver.TIMER_CANCEL, 4))
        post(c, TIMER_ID, b)
    }

    // ---------------- stopwatch ----------------

    fun stopwatch(c: Context) {
        val s = StopwatchStore.state(c)
        if (!s.active) { cancel(c, STOPWATCH_ID); return }

        val elapsed = s.elapsed()
        val sub = when {
            s.laps.isEmpty() -> if (s.running) "Running" else "Paused"
            else -> {
                val last = s.laps.last() - (if (s.laps.size > 1) s.laps[s.laps.size - 2] else 0)
                "${if (s.running) "" else "Paused · "}Lap ${s.laps.size}: ${fmt(last, false)}"
            }
        }
        val view = if (s.running) {
            clockView(c, sub, SystemClock.elapsedRealtime() - elapsed, true, false, null)
        } else {
            clockView(c, sub, 0, false, false, fmt(elapsed, false))
        }
        val b = base(c, if (s.running) "Stopwatch" else "Stopwatch paused", TAB_STOPWATCH, s.running,
            ClockActionReceiver.SW_SWIPED, 11)
            .setContentText(sub)
            .setCustomContentView(view)
            .addAction(0, if (s.running) "Pause" else "Resume", action(c, ClockActionReceiver.SW_TOGGLE, 12))
        if (s.running) b.addAction(0, "Lap", action(c, ClockActionReceiver.SW_LAP, 13))
        b.addAction(0, "Reset", action(c, ClockActionReceiver.SW_RESET, 14))
        post(c, STOPWATCH_ID, b)
    }
}
