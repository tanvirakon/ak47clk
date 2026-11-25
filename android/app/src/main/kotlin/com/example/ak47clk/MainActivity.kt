package com.example.ak47clk

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.ak47clk/alarm"
    private val TAG = "AK47ClockAlarm"
    private val RINGTONE_REQUEST = 4747
    private val VIDEO_REQUEST = 4748
    private var pendingRingtoneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        requestBatteryOptimizationExemption()
        requestOverlayPermission()
        requestExactAlarmPermissionIfNeeded()

        // Import alarms from the old storage format once, and schedule them under new ids.
        if (AlarmStore.migrateIfNeeded(this)) AlarmScheduler.rescheduleAll(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // ---------- alarms ----------
                    "getGroups" -> result.success(AlarmStore.toJsonString(AlarmStore.load(this)))

                    "createGroup" -> {
                        val g = AlarmStore.createGroup(
                            this,
                            call.argument<Int>("fromHour")!!, call.argument<Int>("fromMinute")!!,
                            call.argument<Int>("toHour")!!, call.argument<Int>("toMinute")!!,
                            call.argument<Int>("interval")!!,
                        )
                        g.alarms.forEach { AlarmScheduler.schedule(this, it) }
                        result.success(g.alarms.size)
                    }

                    "setGroupEnabled" -> {
                        val id = call.argument<Int>("groupId")!!
                        val enabled = call.argument<Boolean>("enabled")!!
                        val groups = AlarmStore.load(this)
                        groups.find { it.id == id }?.let { g ->
                            g.enabled = enabled
                            g.alarms.forEach {
                                if (enabled) AlarmScheduler.schedule(this, it) else AlarmScheduler.cancel(this, it)
                            }
                        }
                        AlarmStore.save(this, groups)
                        result.success(true)
                    }

                    "deleteGroup" -> {
                        val id = call.argument<Int>("groupId")!!
                        val groups = AlarmStore.load(this)
                        groups.find { it.id == id }?.alarms?.forEach { AlarmScheduler.cancel(this, it) }
                        groups.removeAll { it.id == id }
                        AlarmStore.save(this, groups)
                        result.success(true)
                    }

                    "deleteAlarm" -> {
                        val id = call.argument<Int>("alarmId")!!
                        val groups = AlarmStore.load(this)
                        groups.forEach { g ->
                            g.alarms.filter { it.id == id }.forEach { AlarmScheduler.cancel(this, it) }
                            g.alarms.removeAll { it.id == id }
                        }
                        groups.removeAll { it.alarms.isEmpty() }
                        AlarmStore.save(this, groups)
                        result.success(true)
                    }

                    // ---------- ringtone / video ----------
                    "getRingtoneName" -> result.success(RingtoneStore.name(this))

                    "pickRingtone" -> {
                        pendingRingtoneResult?.success(null)
                        pendingRingtoneResult = result
                        val pick = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Alarm ringtone")
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, RingtoneStore.uriToPlay(this@MainActivity))
                        }
                        try {
                            startActivityForResult(pick, RINGTONE_REQUEST)
                        } catch (e: Exception) {
                            pendingRingtoneResult = null
                            result.error("RINGTONE_ERROR", "No ringtone picker", e.message)
                        }
                    }

                    "pickVideo" -> {
                        pendingRingtoneResult?.success(null)
                        pendingRingtoneResult = result
                        val pick = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "video/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        try {
                            startActivityForResult(Intent.createChooser(pick, "Choose alarm video"), VIDEO_REQUEST)
                        } catch (e: Exception) {
                            pendingRingtoneResult = null
                            result.error("VIDEO_ERROR", "No video picker", e.message)
                        }
                    }

                    // ---------- MIUI lock screen ----------
                    "lockScreenPermissionOk" -> result.success(MiuiPermissions.allGranted(this))
                    "openLockScreenPermission" -> { MiuiPermissions.openEditor(this); result.success(true) }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Method ${call.method} failed", e)
                result.error("ALARM_ERROR", e.message ?: "Failed", null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VIDEO_REQUEST) {
            val res = pendingRingtoneResult ?: return
            pendingRingtoneResult = null
            val src = data?.data
            if (resultCode != RESULT_OK || src == null) { res.success(null); return }
            // Copy off the main thread (videos can be large), reply on main thread.
            Thread {
                try {
                    RingtoneStore.saveVideo(applicationContext, src)
                    runOnUiThread { res.success(RingtoneStore.name(this)) }
                } catch (e: Exception) {
                    Log.e(TAG, "Saving video failed", e)
                    runOnUiThread { res.error("VIDEO_ERROR", "Could not save video", e.message) }
                }
            }.start()
            return
        }
        if (requestCode != RINGTONE_REQUEST) return
        val res = pendingRingtoneResult ?: return
        pendingRingtoneResult = null
        if (resultCode == RESULT_OK) {
            @Suppress("DEPRECATION")
            val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            // "Default" entry returns the settings default uri -> store null = use system default
            val isDefault = uri == null || uri == Settings.System.DEFAULT_ALARM_ALERT_URI
            RingtoneStore.save(this, if (isDefault) null else uri)
            res.success(RingtoneStore.name(this))
        } else {
            res.success(null) // cancelled
        }
    }

    // ---------------- permissions ----------------

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            Log.e(TAG, "Battery optimization request failed", e)
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || Settings.canDrawOverlays(this)) return
        try {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            Log.e(TAG, "Overlay permission request failed", e)
        }
    }

    private fun requestExactAlarmPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (am.canScheduleExactAlarms()) return
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            Log.e(TAG, "Exact alarm permission request failed", e)
        }
    }
}
