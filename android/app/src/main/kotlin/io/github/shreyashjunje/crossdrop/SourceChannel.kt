package io.github.shreyashjunje.crossdrop

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
 * - `pickFolder` -> `{files: [{uri, name, size, mime?, modifiedMs?, folder}],
 *   skipped}` from ACTION_OPEN_DOCUMENT_TREE (D-075): every file in the
 *   folder and its subfolders, read in place through the tree's
 *   persistable grant. `folder` starts with the folder's own name. Hidden
 *   files are left out; more than [MAX_FOLDER_FILES] are left out and
 *   counted in `skipped`. An empty list if the user backed out.
 * - `release {uris}` gives persistable grants back; a file of a picked
 *   folder gives back the folder's grant.
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
        const val FOLDER_REQUEST = 0xCD02

        /** The protocol's limit per offer (maxFilesPerOffer). */
        private const val MAX_FOLDER_FILES = 10000
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
            "pickFolder" -> pickFolder(result)
            "release" -> background(result) {
                val grants = call.argument<List<String>>("uris")!!.map { grantOf(Uri.parse(it)) }.distinct()
                for (u in grants) releaseGrant(u)
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

    private fun pickFolder(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "a picker is already open", null)
            return
        }
        pickResult = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), FOLDER_REQUEST)
        } catch (e: Exception) {
            pickResult = null
            result.error("no_picker", null, null)
        }
    }

    private fun onFolderPicked(result: MethodChannel.Result, resultCode: Int, data: Intent?) {
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(mapOf("files" to emptyList<Any>(), "skipped" to 0))
            return
        }
        try {
            resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            // Still readable while the app runs.
        }
        background(result) {
            // No picked file would ever hand the grant back: release it now (D-078).
            val picked = try {
                walk(tree)
            } catch (e: Exception) {
                releaseGrant(tree)
                throw e
            }
            if ((picked["files"] as List<*>).isEmpty()) releaseGrant(tree)
            picked
        }
    }

    private fun releaseGrant(u: Uri) {
        try {
            resolver.releasePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            // Not persisted (a share or a MediaStore item).
        }
    }

    /** Every file under [tree], breadth first, with its folder path. */
    private fun walk(tree: Uri): Map<String, Any> {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        var rootName = "Folder"
        query(DocumentsContract.buildDocumentUriUsingTree(tree, rootId), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)) { c ->
            if (!c.isNull(0)) rootName = c.getString(0)
        }
        val files = ArrayList<Map<String, Any?>>()
        var skipped = 0
        val queue = ArrayDeque<Pair<String, String>>()
        queue.add(rootId to rootName)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        while (queue.isNotEmpty()) {
            val (docId, folder) = queue.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            resolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: continue
                    // Hidden files (.nomedia, .thumbnails, ...) are not the user's.
                    if (name.startsWith(".")) continue
                    val mime = c.getString(2)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        queue.add(id to "$folder/$name")
                        continue
                    }
                    if (files.size >= MAX_FOLDER_FILES) {
                        skipped++
                        continue
                    }
                    files += mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "name" to name,
                        "mime" to mime,
                        "size" to (if (c.isNull(3)) -1L else c.getLong(3)),
                        "modifiedMs" to (if (c.isNull(4)) null else c.getLong(4)),
                        "folder" to folder,
                    )
                }
            }
        }
        return mapOf("files" to files, "skipped" to skipped)
    }

    /** The URI holding the persistable grant: a folder file's tree. */
    private fun grantOf(uri: Uri): Uri =
        try {
            if (DocumentsContract.isTreeUri(uri)) {
                DocumentsContract.buildTreeDocumentUri(uri.authority, DocumentsContract.getTreeDocumentId(uri))
            } else {
                uri
            }
        } catch (e: Exception) {
            uri
        }

    /** Called from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == FOLDER_REQUEST) {
            val result = pickResult ?: return true
            pickResult = null
            onFolderPicked(result, resultCode, data)
            return true
        }
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
