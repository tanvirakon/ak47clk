package com.example.ak47clk

import android.content.Context
import android.media.RingtoneManager
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File

/**
 * Stores the user-chosen alarm sound: either a system tone or a video copied into app storage.
 * Separate prefs file so alarm cleanup never wipes it.
 */
object RingtoneStore {
    private const val PREFS = "settings_prefs"
    private const val KEY_TONE = "ringtone_uri"
    private const val KEY_MODE = "ringtone_mode"        // "tone" | "video"
    private const val KEY_VIDEO_NAME = "video_name"
    private const val VIDEO_FILE = "alarm_video"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- tone ----
    fun save(context: Context, uri: Uri?) {
        prefs(context).edit()
            .putString(KEY_TONE, uri?.toString())
            .putString(KEY_MODE, "tone")
            .apply()
        videoFile(context).delete() // free storage when switching back to a tone
    }

    fun savedUri(context: Context): Uri? =
        prefs(context).getString(KEY_TONE, null)?.let { Uri.parse(it) }

    /** Tone uri to play: saved tone, else system default alarm. (Also the fallback in video mode.) */
    fun uriToPlay(context: Context): Uri =
        savedUri(context) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

    // ---- video ----
    fun videoFile(context: Context) = File(context.filesDir, VIDEO_FILE)

    /** True if video mode is selected and the copied file exists. */
    fun isVideoMode(context: Context): Boolean =
        prefs(context).getString(KEY_MODE, "tone") == "video" && videoFile(context).length() > 0

    /** Copies the picked video into app storage (blocking - call off the main thread). */
    fun saveVideo(context: Context, source: Uri) {
        val tmp = File(context.filesDir, "$VIDEO_FILE.tmp")
        try {
            context.contentResolver.openInputStream(source)!!.use { input ->
                tmp.outputStream().use { input.copyTo(it, 1 shl 16) }
            }
        } catch (e: Exception) {
            tmp.delete() // never leave a half-copied file behind; old video stays intact
            throw e
        }
        val dest = videoFile(context)
        dest.delete()
        if (!tmp.renameTo(dest)) throw IllegalStateException("Could not store video")
        prefs(context).edit()
            .putString(KEY_MODE, "video")
            .putString(KEY_VIDEO_NAME, displayName(context, source) ?: "Video")
            .apply()
    }

    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) { null }

    // ---- label for settings ----
    fun name(context: Context): String {
        if (isVideoMode(context)) {
            return "Video: " + (prefs(context).getString(KEY_VIDEO_NAME, null) ?: "Video")
        }
        val uri = savedUri(context) ?: return "Default"
        return try {
            RingtoneManager.getRingtone(context, uri)?.getTitle(context) ?: "Default"
        } catch (e: Exception) {
            "Default"
        }
    }
}
