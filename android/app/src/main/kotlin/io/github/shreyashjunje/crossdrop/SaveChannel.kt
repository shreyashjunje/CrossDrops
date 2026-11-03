package io.github.shreyashjunje.crossdrop

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/**
 * Platform channel `crossdrop/save` (Dart side: lib/platform/android_store.dart).
 *
 * Received files are written straight into a pending MediaStore item, then
 * published (D-040): no temporary copy, no extra space. Dart writes the
 * bytes through the descriptor; none cross this channel.
 *
 * - `create {name, mime, collection, takenMs?}` -> `{uri, fd}`. `collection`
 *   is `photos` (Pictures/CrossDrop), `videos` (Movies/CrossDrop) or `files`
 *   (Download/CrossDrop). The item is pending: hidden from other apps until
 *   published. Errors: `unsupported` (the collection refuses this MIME
 *   type), `no_space`, `io`.
 * - `open {uri}` -> fd, read-write. Error `not_found` if the item is gone.
 * - `publish {uri}` -> the final display name (MediaStore may rename on a
 *   clash, "IMG_1 (1).jpg").
 * - `delete {uri}`: never fails for a missing item.
 * - `cleanupPending {olderThanMs, keep}` -> count: deletes this app's
 *   pending items older than the cutoff that no session still uses.
 */
class SaveChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "crossdrop/save")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val resolver: ContentResolver get() = context.contentResolver

    init {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> background(result) {
                create(
                    call.argument<String>("name")!!,
                    call.argument<String>("mime")!!,
                    call.argument<String>("collection")!!,
                    call.argument<Number>("takenMs")?.toLong(),
                )
            }
            "open" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val pfd = resolver.openFileDescriptor(uri, "rw") ?: throw FileNotFoundException()
                pfd.detachFd()
            }
            "publish" -> background(result) { publish(Uri.parse(call.argument<String>("uri")!!)) }
            "delete" -> background(result) {
                try {
                    resolver.delete(Uri.parse(call.argument<String>("uri")!!), null, null)
                } catch (e: Exception) {
                    // Gone already, or not ours.
                }
                null
            }
            "cleanupPending" -> background(result) {
                cleanupPending(
                    call.argument<Number>("olderThanMs")!!.toLong(),
                    call.argument<List<String>>("keep")!!.toSet(),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun collectionUri(collection: String): Uri {
        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        return when (collection) {
            "photos" -> MediaStore.Images.Media.getContentUri(volume)
            "videos" -> MediaStore.Video.Media.getContentUri(volume)
            else -> MediaStore.Downloads.getContentUri(volume)
        }
    }

    private fun relativePath(collection: String): String = when (collection) {
        "photos" -> Environment.DIRECTORY_PICTURES
        "videos" -> Environment.DIRECTORY_MOVIES
        else -> Environment.DIRECTORY_DOWNLOADS
    } + "/CrossDrop"

    private fun create(name: String, mime: String, collection: String, takenMs: Long?): Map<String, Any> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath(collection))
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            if (takenMs != null && collection != "files") {
                put(MediaStore.MediaColumns.DATE_TAKEN, takenMs)
            }
        }
        val uri = try {
            resolver.insert(collectionUri(collection), values)
        } catch (e: IllegalArgumentException) {
            // "MIME type ... cannot be inserted into ..."
            throw ChannelError("unsupported")
        } ?: throw ChannelError("io")
        try {
            val pfd = resolver.openFileDescriptor(uri, "rw") ?: throw FileNotFoundException()
            return mapOf("uri" to uri.toString(), "fd" to pfd.detachFd())
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {
            }
            throw e
        }
    }

    private fun publish(uri: Uri): String? {
        val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        if (resolver.update(uri, values, null, null) == 0) throw FileNotFoundException()
        return try {
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun cleanupPending(olderThanMs: Long, keep: Set<String>): Int {
        var deleted = 0
        val cutoffSeconds = olderThanMs / 1000
        for (collection in listOf("photos", "videos", "files")) {
            val base = collectionUri(collection)
            val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DATE_ADDED)
            val selection = "${MediaStore.MediaColumns.IS_PENDING} = 1 AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND " +
                "${MediaStore.MediaColumns.DATE_ADDED} < ?"
            val args = arrayOf("${relativePath(collection)}%", cutoffSeconds.toString())
            val cursor = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val bundle = Bundle().apply {
                        putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                        putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
                        putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
                    }
                    resolver.query(base, projection, bundle, null)
                } else {
                    @Suppress("DEPRECATION")
                    resolver.query(MediaStore.setIncludePending(base), projection, selection, args, null)
                }
            } catch (e: Exception) {
                null
            } ?: continue
            cursor.use { c ->
                while (c.moveToNext()) {
                    val uri = ContentUris.withAppendedId(base, c.getLong(0))
                    if (keep.contains(uri.toString())) continue
                    try {
                        if (resolver.delete(uri, null, null) > 0) deleted++
                    } catch (e: Exception) {
                        // Not ours (another app's pending item): skip.
                    }
                }
            }
        }
        return deleted
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                val code = errorCode(e)
                main.post { result.error(code, null, null) }
            }
        }
    }
}
