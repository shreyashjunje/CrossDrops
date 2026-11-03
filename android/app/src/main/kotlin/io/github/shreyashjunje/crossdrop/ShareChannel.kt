package io.github.shreyashjunje.crossdrop

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel `crossdrop/share` (Dart side: lib/platform/share_inbox.dart).
 *
 * Collects files shared to CrossDrop with ACTION_SEND or ACTION_SEND_MULTIPLE
 * (D-044). Only content URIs of other apps are accepted: a `file://` URI, or
 * one of CrossDrop's own, could make it send its private files.
 *
 * - `takePending` -> list of `{uris, textOnly, rejected}` and clears it.
 * - Native to Dart `arrived` when a share comes in while the app runs.
 *
 * The read grant that comes with the intent lasts while this process
 * lives; the files are read in place, not copied.
 */
class ShareChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "crossdrop/share")
    private val pending = mutableListOf<Map<String, Any>>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> {
                    result.success(pending.toList())
                    pending.clear()
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Called with the launch intent and with every new one. */
    fun handle(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val uris = LinkedHashSet<Uri>()
        if (action == Intent.ACTION_SEND) {
            stream(intent)?.let { uris.add(it) }
        } else {
            streams(intent)?.let { uris.addAll(it) }
        }
        intent.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) }
        }
        var rejected = 0
        val accepted = mutableListOf<String>()
        for (u in uris) {
            if (isAcceptable(u)) accepted.add(u.toString()) else rejected++
        }
        val textOnly = accepted.isEmpty() && rejected == 0 &&
            (intent.hasExtra(Intent.EXTRA_TEXT) || intent.hasExtra(Intent.EXTRA_HTML_TEXT))
        pending.add(mapOf("uris" to accepted, "textOnly" to textOnly, "rejected" to rejected))
        // Handled: a configuration change must not deliver it again.
        intent.action = null
        channel.invokeMethod("arrived", null)
    }

    private fun isAcceptable(uri: Uri): Boolean {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return false
        val authority = uri.authority ?: return false
        return !authority.startsWith(activity.packageName)
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
}
