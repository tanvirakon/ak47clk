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
    private var pendingTab = -1

    companion object {
        const val EXTRA_OPEN_TAB = "openTab"

        @Volatile
        private var channel: MethodChannel? = null

        /** Timer / stopwatch changed from the notification: tell Flutter (if running) to reload. */
        fun notifyClockChanged() {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try { channel?.invokeMethod("clockChanged", null) } catch (_: Exception) {}
            }
        }

        /** A ring / snooze / off was logged: tell Flutter (if running) to refresh stats. */
        fun notifyStatsChanged() {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try { channel?.invokeMethod("statsChanged", null) } catch (_: Exception) {}
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val tab = intent.getIntExtra(EXTRA_OPEN_TAB, -1)
        if (tab >= 0) {
            try { channel?.invokeMethod("openTab", tab) } catch (_: Exception) {}
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingTab = intent?.getIntExtra(EXTRA_OPEN_TAB, -1) ?: -1

        // No permission popups on launch: the Alarm page lists missing ones as tappable banners.
        TickSound.init(this)

        // Import alarms from the old storage format once, and schedule them under new ids.
        if (AlarmStore.migrateIfNeeded(this)) AlarmScheduler.rescheduleAll(this)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // ---------- alarms ----------
                    "getGroups" -> result.success(AlarmStore.toJsonString(this, AlarmStore.load(this)))

                    "cancelSnooze" -> {
                        AlarmStore.cancelSnoozes(this, call.argument<Int>("groupId")!!)
                        result.success(true)
                    }

                    "createGroup" -> {
                        val g = AlarmStore.createGroup(
                            this,
                            call.argument<Int>("fromHour")!!, call.argument<Int>("fromMinute")!!,
                            call.argument<Int>("toHour")!!, call.argument<Int>("toMinute")!!,
                            call.argument<Int>("interval")!!,
                            call.argument<Int>("days") ?: 0,
                        )
                        g.alarms.forEach { AlarmScheduler.schedule(this, g, it) }
                        result.success(g.alarms.size)
                    }

                    "createSingle" -> {
                        val g = AlarmStore.createSingle(
                            this,
                            call.argument<Int>("hour")!!, call.argument<Int>("minute")!!,
                            call.argument<String>("label"),
                            call.argument<Int>("days") ?: 0,
                        )
                        g.alarms.forEach { AlarmScheduler.schedule(this, g, it) }
                        result.success(g.id)
                    }

                    "updateSingle" -> {
                        val g = AlarmStore.updateSingle(
                            this, call.argument<Int>("groupId")!!,
                            call.argument<Int>("hour")!!, call.argument<Int>("minute")!!,
                            call.argument<String>("label"),
                            call.argument<Int>("days") ?: 0,
                        )
                        // Same id = same PendingIntent, so this replaces the old trigger time.
                        g?.alarms?.forEach { AlarmScheduler.schedule(this, g, it); AlarmScheduler.cancelSnooze(this, it.id) }
                        result.success(g != null)
                    }

                    "setGroupEnabled" -> {
                        AlarmStore.setEnabled(this, call.argument<Int>("groupId")!!, call.argument<Boolean>("enabled")!!)
                        result.success(true)
                    }

                    "skipNext" -> result.success(AlarmStore.skipNext(this, call.argument<Int>("groupId")!!))

                    "deleteGroup" -> {
                        val id = call.argument<Int>("groupId")!!
                        val groups = AlarmStore.load(this)
                        groups.find { it.id == id }?.alarms?.forEach {
                            AlarmScheduler.cancel(this, it); AlarmScheduler.cancelSnooze(this, it.id)
                        }
                        groups.removeAll { it.id == id }
                        AlarmStore.save(this, groups)
                        result.success(true)
                    }

                    "deleteAlarm" -> {
                        val id = call.argument<Int>("alarmId")!!
                        val groups = AlarmStore.load(this)
                        groups.forEach { g ->
                            g.alarms.filter { it.id == id }.forEach {
                                AlarmScheduler.cancel(this, it); AlarmScheduler.cancelSnooze(this, it.id)
                            }
                            g.alarms.removeAll { it.id == id }
                        }
                        groups.removeAll { it.alarms.isEmpty() }
                        AlarmStore.save(this, groups)
                        result.success(true)
                    }

                    // ---------- stats ----------
                    "getRingLog" -> result.success(
                        RingLog.readJson(this, (call.argument<Number>("since") ?: 0).toLong()))

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

                    "testAlarm" -> {
                        AlarmScheduler.scheduleTest(this, call.argument<Int>("seconds") ?: 10)
                        result.success(true)
                    }

                    "wheelTick" ->{ TickSound.play(); result.success(null) }

                    // ---------- countdown timer ----------
                    "getTimer" -> result.success(TimerStore.getJson(this))
                    "setTimer" -> {
                        fun long(k: String) = (call.argument<Number>(k) ?: 0).toLong()
                        TimerStore.set(this, long("end"), long("left"), long("total"))
                        result.success(true)
                    }

                    // ---------- stopwatch ----------
                    "getStopwatch" -> result.success(StopwatchStore.getJson(this))
                    "setStopwatch" -> {
                        fun long(k: String) = (call.argument<Number>(k) ?: 0).toLong()
                        val laps = (call.argument<List<Number>>("laps") ?: emptyList()).map { it.toLong() }
                        StopwatchStore.set(this, StopwatchStore.State(
                            call.argument<Boolean>("running") ?: false, long("start"), long("acc"), laps))
                        result.success(true)
                    }

                    // ---------- hardware buttons while ringing ----------
                    "getButtons" -> result.success(ButtonPrefs.getJson(this))
                    "setButton" -> {
                        ButtonPrefs.set(this, call.argument<String>("key") ?: "", call.argument<String>("value") ?: "")
                        result.success(true)
                    }

                    // Notification tapped -> which tab to open (-1 = none)
                    "takeOpenTab" -> { result.success(pendingTab); pendingTab = -1 }

                    // ---------- MIUI lock screen ----------
                    "lockScreenPermissionOk" -> result.success(MiuiPermissions.allGranted(this))
                    "openLockScreenPermission" -> { MiuiPermissions.openEditor(this); result.success(true) }

                    // ---------- permission banners ----------
                    "missingPermissions" -> result.success(missingPermissions())
                    "openPermission" -> { openPermission(call.argument<String>("key") ?: ""); result.success(true) }

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

    /** Keys of permissions still missing, in display order. Each check is version-guarded. */
    private fun missingPermissions(): List<String> {
        val out = mutableListOf<String>()
        if (!androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()) out.add("notifications")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !(getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()) out.add("exactAlarm")
        if (Build.VERSION.SDK_INT >= 34 &&
            !getSystemService(android.app.NotificationManager::class.java).canUseFullScreenIntent()) out.add("fullScreen")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) out.add("overlay")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !(getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)) out.add("battery")
        if (!MiuiPermissions.allGranted(this)) out.add("miuiLockScreen")
        return out
    }

    private fun openPermission(key: String) {
        when (key) {
            "notifications" -> {
                val prefs = getSharedPreferences("settings_prefs", Context.MODE_PRIVATE)
                // Android 13+: first tap shows the system dialog; after that (or if denied) open settings.
                if (Build.VERSION.SDK_INT >= 33 && !prefs.getBoolean("notif_asked", false)) {
                    prefs.edit().putBoolean("notif_asked", true).apply()
                    requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4749)
                } else {
                    openSettings(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        else null
                    )
                }
            }
            "exactAlarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                openSettings(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
            "fullScreen" -> if (Build.VERSION.SDK_INT >= 34)
                openSettings(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
            "overlay" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                openSettings(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            "battery" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                openSettings(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
            "miuiLockScreen" -> MiuiPermissions.openEditor(this)
        }
    }

    /** Open a settings screen; fall back to the app's info page if this phone doesn't have it. */
    private fun openSettings(intent: Intent?) {
        try {
            if (intent != null) { startActivity(intent); return }
        } catch (e: Exception) {
            Log.w(TAG, "Settings screen not available, opening app details", e)
        }
        try {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            Log.e(TAG, "Could not open app settings", e)
        }
    }

}
