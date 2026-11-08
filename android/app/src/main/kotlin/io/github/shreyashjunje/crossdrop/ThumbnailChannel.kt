package io.github.shreyashjunje.crossdrop

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Platform channel `crossdrop/thumbnail` (Dart side:
 * lib/platform/thumbnails.dart).
 *
 * - `thumbnail {ref, px, kind}` -> path of a small JPEG in the cache, or
 *   null when the OS cannot make a preview. `ref` is a `content://` URI
 *   (MediaStore, a document) or a file path. Only the path of the preview
 *   crosses the channel, never file bytes (CLAUDE.md hard rule 2).
 *
 * Previews are cached under `cache/crossdrop_thumbs`, keyed by the
 * reference (and a file's size and date), and trimmed to [CACHE_BYTES].
 * References are never logged (hard rule 7).
 */
class ThumbnailChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "crossdrop/thumbnail")
    private val pool = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val dir = File(context.cacheDir, "crossdrop_thumbs")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "thumbnail") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val ref = call.argument<String>("ref")
            val px = (call.argument<Number>("px")?.toInt() ?: 192).coerceIn(32, 1024)
            val kind = call.argument<String>("kind") ?: "file"
            if (ref == null) {
                result.error("bad_args", null, null)
                return@setMethodCallHandler
            }
            pool.execute {
                val path = try {
                    thumbnail(ref, px, kind)
                } catch (e: Exception) {
                    null
                } catch (e: OutOfMemoryError) {
                    null
                }
                main.post { result.success(path) }
            }
        }
        pool.execute { trim() }
    }

    private fun thumbnail(ref: String, px: Int, kind: String): String? {
        val isContent = ref.startsWith("content://")
        val file = if (isContent) null else File(ref)
        if (file != null && !file.isFile) return null
        val key = sha1("$ref|$px|${file?.length() ?: 0}|${file?.lastModified() ?: 0}")
        val out = File(dir, "$key.jpg")
        if (out.length() > 0) {
            out.setLastModified(System.currentTimeMillis())
            return out.path
        }
        val size = Size(px, px)
        val bitmap = if (isContent) fromUri(Uri.parse(ref), size, kind) else fromFile(file!!, size, kind)
        bitmap ?: return null
        try {
            dir.mkdirs()
            val tmp = File(dir, "$key.tmp")
            FileOutputStream(tmp).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            if (!tmp.renameTo(out)) {
                tmp.delete()
                return null
            }
        } finally {
            bitmap.recycle()
        }
        return out.path
    }

    /** MediaStore and most document providers answer loadThumbnail. */
    private fun fromUri(uri: Uri, size: Size, kind: String): Bitmap? {
        try {
            return context.contentResolver.loadThumbnail(uri, size, null)
        } catch (e: Exception) {
            // A provider without thumbnails: decode it ourselves below.
        }
        return when (kind) {
            "photo" -> decodeSampled(size) { context.contentResolver.openInputStream(uri) }
            "video" -> frame(size) { it.setDataSource(context, uri) }
            else -> null
        }
    }

    private fun fromFile(file: File, size: Size, kind: String): Bitmap? = when (kind) {
        "photo" -> try {
            ThumbnailUtils.createImageThumbnail(file, size, null)
        } catch (e: Exception) {
            decodeSampled(size) { file.inputStream() }
        }
        "video" -> try {
            ThumbnailUtils.createVideoThumbnail(file, size, null)
        } catch (e: Exception) {
            frame(size) { it.setDataSource(file.path) }
        }
        else -> null
    }

    /** Two passes: read the bounds, then decode at about [size]. */
    private fun decodeSampled(size: Size, open: () -> java.io.InputStream?): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open()?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= size.width &&
            bounds.outHeight / (sample * 2) >= size.height
        ) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return open()?.use { BitmapFactory.decodeStream(it, null, opts) }
    }

    private fun frame(size: Size, source: (MediaMetadataRetriever) -> Unit): Bitmap? {
        val r = MediaMetadataRetriever()
        return try {
            source(r)
            r.getScaledFrameAtTime(
                -1,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                size.width,
                size.height,
            )
        } catch (e: Exception) {
            null
        } finally {
            try {
                r.release()
            } catch (e: Exception) {
                // Already released.
            }
        }
    }

    /** Keeps the cache under [CACHE_BYTES], least recently used first. */
    private fun trim() {
        val files = dir.listFiles()?.filter { it.isFile } ?: return
        var total = files.sumOf { it.length() }
        if (total <= CACHE_BYTES) return
        for (f in files.sortedBy { it.lastModified() }) {
            if (total <= CACHE_BYTES * 3 / 4) break
            total -= f.length()
            f.delete()
        }
    }

    private fun sha1(text: String): String =
        MessageDigest.getInstance("SHA-1").digest(text.toByteArray())
            .joinToString("") { "%02x".format(it) }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pool.shutdown()
    }

    private companion object {
        const val CACHE_BYTES = 48L * 1024 * 1024
    }
}
