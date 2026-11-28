package com.example.ak47clk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Buttons + swipe on the timer / stopwatch notifications. */
class ClockActionReceiver : BroadcastReceiver() {
    companion object {
        const val TIMER_TOGGLE = "com.example.ak47clk.TIMER_TOGGLE"
        const val TIMER_ADD = "com.example.ak47clk.TIMER_ADD"
        const val TIMER_CANCEL = "com.example.ak47clk.TIMER_CANCEL"
        const val TIMER_SWIPED = "com.example.ak47clk.TIMER_SWIPED"
        const val SW_TOGGLE = "com.example.ak47clk.SW_TOGGLE"
        const val SW_LAP = "com.example.ak47clk.SW_LAP"
        const val SW_RESET = "com.example.ak47clk.SW_RESET"
        const val SW_SWIPED = "com.example.ak47clk.SW_SWIPED"
    }

    override fun onReceive(c: Context, intent: Intent) {
        try {
            when (intent.action) {
                TIMER_TOGGLE -> TimerStore.toggle(c)
                TIMER_ADD -> TimerStore.addMinute(c)
                TIMER_CANCEL -> TimerStore.cancel(c)
                // Swiped: paused -> reset; running (Android 14+ lets you swipe) -> put it back.
                TIMER_SWIPED -> if (TimerStore.state(c).paused) TimerStore.cancel(c) else ClockNotif.timer(c)
                SW_TOGGLE -> StopwatchStore.toggle(c)
                SW_LAP -> StopwatchStore.lap(c)
                SW_RESET -> StopwatchStore.reset(c)
                SW_SWIPED -> if (StopwatchStore.state(c).running) ClockNotif.stopwatch(c) else StopwatchStore.reset(c)
                else -> return
            }
            MainActivity.notifyClockChanged() // app open? refresh the tab
        } catch (e: Exception) {
            Log.e("ClockAction", "Action ${intent.action} failed", e)
        }
    }
}
