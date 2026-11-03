package com.example.crossdrop

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Platform channel `crossdrop/source` (Dart side: lib/platform/android_source.dart).
 *
 * Files to send are content URIs (MediaStore, Storage Access Framework,
 * share intents). Dart reads them through a file descriptor (D-036); no
 * file bytes cross this channel.
 *
 * - `open {uri}` -> `{fd, size, original}`: a read-only descriptor that
 *   Dart owns and closes. MediaStore items are opened with
 *   `setRequireOriginal` so Android does not strip the GPS location
 *   (needs ACCESS_MEDIA_LOCATION); `original` is false if that was not
 *   possible. Errors: `not_found`, `permission`, `not_seekable`, `io`.
 * - `describe {uris}` -> list of `{uri, name?, size (-1 unknown), mime?,
 *   modifiedMs?, takenMs?}`.
 * - `pickDocuments` -> list of URIs from ACTION_OPEN_DOCUMENT, each with a
 *   persistable read grant so a resume after a restart can read it again.
 * - `release {uris}` gives persistable grants back.
 * - `copy {uri, dest, id}` -> bytes: streams a provider that cannot seek or
 *   has no size into `dest` (a file in the app's staging folder).
 *   `cancelCopy {id}`. Errors: `no_space`, `not_found`, `permission`,
 *   `cancelled`, `io`.
 *
 * ContentResolver calls can block on slow providers, so all of them run
 * off the main thread.
 */
class SourceChannel(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val PICK_REQUEST = 0xCD01
        private const val BUFFER = 1024 * 1024
    }

    private val channel = MethodChannel(messenger, "crossdrop/source")
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val resolver: ContentResolver get() = activity.contentResolver
    private val copies = ConcurrentHashMap<String, AtomicBoolean>()
    private var pickResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> background(result) { open(Uri.parse(call.argument<String>("uri")!!)) }
            "describe" -> background(result) {
                call.argument<List<String>>("uris")!!.map { describe(Uri.parse(it)) }
            }
            "pickDocuments" -> pick(result)
            "release" -> background(result) {
                for (u in call.argument<List<String>>("uris")!!) {
                    try {
                        resolver.releasePersistableUriPermission(
                            Uri.parse(u),
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    } catch (e: SecurityException) {
                        // Not persisted (a share or a MediaStore item).
                    }
                }
                null
            }
            "copy" -> {
                val id = call.argument<String>("id")!!
                val cancel = AtomicBoolean(false)
                copies[id] = cancel
                background(result, onDone = { copies.remove(id) }) {
                    copy(
                        Uri.parse(call.argument<String>("uri")!!),
                        File(call.argument<String>("dest")!!),
                        cancel,
                    )
                }
            }
            "cancelCopy" -> {
                copies[call.argument<String>("id")!!]?.set(true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(uri: Uri): Map<String, Any> {
        var original = true
        var target = uri
        if (uri.authority == MediaStore.AUTHORITY) {
            val granted = activity.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) {
                try {
                    target = MediaStore.setRequireOriginal(uri)
                } catch (e: Exception) {
                    original = false
                }
            } else {
                original = false
            }
        }
        val pfd = try {
            resolver.openFileDescriptor(target, "r")
        } catch (e: Exception) {
            if (target != uri && (e is SecurityException || e is UnsupportedOperationException)) {
                // The original was refused; send the redacted copy.
                original = false
                resolver.openFileDescriptor(uri, "r")
            } else {
                throw e
            }
        } ?: throw FileNotFoundException()
        val size = pfd.statSize
        if (size < 0) {
            pfd.close()
            throw ChannelError("not_seekable")
        }
        return mapOf("fd" to pfd.detachFd(), "size" to size, "original" to original)
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>("uri" to uri.toString(), "size" to -1L)
        out["mime"] = try {
            resolver.getType(uri)
        } catch (e: Exception) {
            null
        }
        query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)) { c ->
            val name = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val size = c.getColumnIndex(OpenableColumns.SIZE)
            if (name >= 0 && !c.isNull(name)) out["name"] = c.getString(name)
            if (size >= 0 && !c.isNull(size)) out["size"] = c.getLong(size)
        }
        if (uri.authority == MediaStore.AUTHORITY) {
            query(uri, arrayOf(MediaStore.MediaColumns.DATE_TAKEN, MediaStore.MediaColumns.DATE_MODIFIED)) { c ->
                if (!c.isNull(0)) out["takenMs"] = c.getLong(0)
                if (!c.isNull(1)) out["modifiedMs"] = c.getLong(1) * 1000
            }
        } else if (DocumentsContract.isDocumentUri(activity, uri)) {
            query(uri, arrayOf(DocumentsContract.Document.COLUMN_LAST_MODIFIED)) { c ->
                if (!c.isNull(0)) out["modifiedMs"] = c.getLong(0)
            }
        }
        return out
    }

    /** Runs [read] on the first row. Providers that reject a column are skipped. */
    private fun query(uri: Uri, columns: Array<String>, read: (android.database.Cursor) -> Unit) {
        try {
            resolver.query(uri, columns, null, null, null)?.use { c ->
                if (c.moveToFirst()) read(c)
            }
        } catch (e: Exception) {
            // IllegalArgumentException for unknown columns, SecurityException.
        }
    }

    private fun copy(uri: Uri, dest: File, cancel: AtomicBoolean): Long {
        dest.parentFile?.mkdirs()
        var total = 0L
        try {
            val input = resolver.openInputStream(uri) ?: throw FileNotFoundException()
            input.use { inp ->
                FileOutputStream(dest).use { out ->
                    val buf = ByteArray(BUFFER)
                    while (true) {
                        if (cancel.get()) throw ChannelError("cancelled")
                        val n = inp.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        total += n
                    }
                    out.fd.sync()
                }
            }
        } catch (e: Exception) {
            dest.delete()
            throw e
        }
        return total
    }

    private fun pick(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "a picker is already open", null)
            return
        }
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: Exception) {
            pickResult = null
            result.error("no_picker", null, null)
        }
    }

    /** Called from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pickResult ?: return true
        pickResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return true
        }
        val uris = mutableListOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        val distinct = uris.distinct()
        for (u in distinct) {
            try {
                resolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: SecurityException) {
                // The provider does not offer persistable grants; it still
                // works while the app runs.
            }
        }
        result.success(distinct.map { it.toString() })
        return true
    }

    private fun background(
        result: MethodChannel.Result,
        onDone: () -> Unit = {},
        work: () -> Any?,
    ) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                val code = errorCode(e)
                main.post { result.error(code, null, null) }
            } finally {
                onDone()
            }
        }
    }
}

/** An error with a code for the Dart side. */
class ChannelError(val code: String) : Exception(code)

/** Maps exceptions to the channel's error codes. Messages are never sent:
 * they can hold file names (CLAUDE.md hard rule 7). */
fun errorCode(e: Throwable): String {
    if (e is ChannelError) return e.code
    // Disk full first: opening a file on a full disk throws
    // FileNotFoundException with ENOSPC in its message.
    var cause: Throwable? = e
    while (cause != null) {
        if (cause is ErrnoException &&
            (cause.errno == OsConstants.ENOSPC || cause.errno == OsConstants.EDQUOT)
        ) {
            return "no_space"
        }
        val m = cause.message
        if (m != null && (m.contains("ENOSPC") || m.contains("No space left") || m.contains("EDQUOT"))) {
            return "no_space"
        }
        if (cause is android.database.sqlite.SQLiteFullException) return "no_space"
        cause = cause.cause
    }
    return when (e) {
        is FileNotFoundException -> "not_found"
        is SecurityException -> "permission"
        is IllegalArgumentException, is UnsupportedOperationException -> "unsupported"
        else -> "io"
    }
}
