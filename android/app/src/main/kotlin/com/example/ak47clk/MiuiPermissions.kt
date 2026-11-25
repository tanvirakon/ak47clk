package com.example.ak47clk

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Xiaomi/MIUI blocks two app-ops by default that an alarm needs:
 *  10020 = "Show on lock screen"
 *  10021 = "Display pop-up windows while running in the background"
 * Without them the ring screen only appears after unlocking. They can't be requested with a
 * dialog - the user must enable them in MIUI's permission editor.
 */
object MiuiPermissions {
    private const val OP_SHOW_WHEN_LOCKED = 10020
    private const val OP_BACKGROUND_START = 10021

    fun isMiui(): Boolean = try {
        val c = Class.forName("android.os.SystemProperties")
        val v = c.getMethod("get", String::class.java).invoke(null, "ro.miui.ui.version.name") as String
        v.isNotEmpty()
    } catch (e: Exception) { false }

    /** True on non-MIUI phones, or if both MIUI ops are allowed. */
    fun allGranted(context: Context): Boolean {
        if (!isMiui()) return true
        return isAllowed(context, OP_SHOW_WHEN_LOCKED) && isAllowed(context, OP_BACKGROUND_START)
    }

    private fun isAllowed(context: Context, op: Int): Boolean = try {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val m = AppOpsManager::class.java.getMethod(
            "checkOpNoThrow", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, String::class.java
        )
        m.invoke(ops, op, android.os.Process.myUid(), context.packageName) as Int == AppOpsManager.MODE_ALLOWED
    } catch (e: Exception) {
        Log.w("MiuiPermissions", "Can't read op $op", e)
        true // can't tell -> don't nag
    }

    /** Opens MIUI "Other permissions" for this app; falls back to the normal app settings page. */
    fun openEditor(context: Context) {
        val intents = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                putExtra("extra_pkgname", context.packageName)
            },
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.AppPermissionsEditorActivity")
                putExtra("extra_pkgname", context.packageName)
            },
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        )
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(i)
                return
            } catch (_: Exception) {}
        }
    }
}
