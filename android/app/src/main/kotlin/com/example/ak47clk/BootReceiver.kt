package com.example.ak47clk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager forgets everything on reboot, app update, or clock/timezone change.
 * Reschedule straight from AlarmStore - no need to open the app (Android blocks that anyway).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("BootReceiver", "Rescheduling alarms after ${intent.action}")
        val pending = goAsync()
        Thread {
            try {
                AlarmScheduler.rescheduleAll(context.applicationContext)
            } catch (e: Exception) {
                Log.e("BootReceiver", "Reschedule failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
