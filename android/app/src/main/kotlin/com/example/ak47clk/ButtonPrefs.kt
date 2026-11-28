package com.example.ak47clk

import android.content.Context
import org.json.JSONObject

/**
 * What the hardware buttons do while an alarm / timer is ringing.
 * Values: nothing (default), snooze5, snooze10, snooze15, silence, off.
 */
object ButtonPrefs {
    private const val PREFS = "button_prefs"
    const val POWER = "power"
    const val VOL_UP = "volUp"
    const val VOL_DOWN = "volDown"
    const val NOTHING = "nothing"
    private val KEYS = listOf(POWER, VOL_UP, VOL_DOWN)
    private val VALUES = setOf(NOTHING, "snooze5", "snooze10", "snooze15", "silence", "off")

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun get(c: Context, key: String): String =
        prefs(c).getString(key, NOTHING).takeIf { it in VALUES } ?: NOTHING

    fun set(c: Context, key: String, value: String) {
        if (key in KEYS && value in VALUES) prefs(c).edit().putString(key, value).apply()
    }

    fun getJson(c: Context): String = JSONObject().apply { KEYS.forEach { put(it, get(c, it)) } }.toString()

    /** "snooze10" -> 10, else null. */
    fun snoozeMinutes(value: String): Int? = value.removePrefix("snooze").takeIf { value.startsWith("snooze") }?.toIntOrNull()
}
