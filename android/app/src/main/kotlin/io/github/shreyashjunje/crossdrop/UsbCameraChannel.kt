package io.github.shreyashjunje.crossdrop

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.mtp.MtpConstants
import android.mtp.MtpDevice
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.system.Os
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Platform channel `crossdrop/usb_camera` (Dart side:
 * lib/platform/usb_camera.dart, D-067).
 *
 * Reads photos from an iPhone plugged into this phone, through the
 * iPhone's camera interface (PTP) and android.mtp.MtpDevice. This phone is
 * the USB host; the iPhone needs no app.
 *
 * Only handles, names, cache paths and MediaStore URIs cross the channel
 * (hard rule 2). Copies go straight into a pending MediaStore item, the
 * same way received files do (D-040).
 *
 * - `devices` -> [{id, name}]: attached Apple devices with a still-image
 *   interface.
 * - `open {id}`: asks for USB access if needed and opens the device.
 *   Errors: `permission_denied`, `busy` (another app holds it),
 *   `locked` (no storage yet: locked, or "Allow" not tapped),
 *   `disconnected`.
 * - `nextPage {max}` -> {objects: [{handle, name, folder, size, takenMs}],
 *   done, seen}. Walks the folders newest first. size -1 = unknown.
 * - `thumbnail {handle}` -> cache file path or null.
 * - `importFile {handle, name, mime, collection, expectedSize?, takenMs?}`
 *   -> {uri, collection, bytes}. Errors: `size_mismatch`, `cancelled`,
 *   `disconnected`, `no_space`, `io`.
 * - `probe {port?}` -> text report of the cable test (UsbTunnelProbe).
 *   Closes the open device first.
 * - `cancelCurrent`: stops the copy in progress between chunks.
 * - `close`.
 *
 * Events on `crossdrop/usb_camera/events`: {type: attached, id, name},
 * {type: detached, id}, {type: progress, handle, bytes}.
 *
 * Every MtpDevice call runs on one thread: the class is not thread-safe.
 * Names are never logged (hard rule 7).
 */
class UsbCameraChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val save: SaveChannel,
) : EventChannel.StreamHandler {
    private val channel = MethodChannel(messenger, "crossdrop/usb_camera")
    private val eventChannel = EventChannel(messenger, "crossdrop/usb_camera/events")
    private val usb = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mtp = Executors.newSingleThreadExecutor()
    private val ticker: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancel = AtomicBoolean(false)
    private val quick = ConcurrentLinkedQueue<Runnable>()

    private var sink: EventChannel.EventSink? = null
    private var permissionWaiter: ((Boolean) -> Unit)? = null

    // Touched only on the mtp thread.
    private var device: MtpDevice? = null
    private var openId: String? = null
    private var walk: Walk? = null

    /** False once the device refused a partial read; then whole files. */
    private var partialReads = true

    private val thumbDir: File get() = File(activity.cacheDir, "usb_thumbs")

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> deviceOf(intent)?.let(::attached)
                UsbManager.ACTION_USB_DEVICE_DETACHED -> deviceOf(intent)?.let(::detached)
                ACTION_PERMISSION -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    permissionWaiter?.invoke(granted)
                    permissionWaiter = null
                }
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
        eventChannel.setStreamHandler(this)
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_PERMISSION)
        }
        // System broadcasts still arrive with NOT_EXPORTED; the permission
        // answer comes through our own PendingIntent.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(receiver, filter)
        }
        clearThumbs()
    }

    /** The activity was started or reached by a USB attach intent. */
    fun onIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            deviceOf(intent)?.let(::attached)
        }
    }

    fun dispose() {
        try {
            activity.unregisterReceiver(receiver)
        } catch (ignored: IllegalArgumentException) {
        }
        cancel.set(true)
        mtp.execute { closeDevice() }
        mtp.shutdown()
        ticker.shutdownNow()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        for (d in cameras()) attached(d)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    private fun attached(d: UsbDevice) {
        if (!isCamera(d)) return
        emit(mapOf("type" to "attached", "id" to d.deviceName, "name" to nameOf(d)))
    }

    private fun detached(d: UsbDevice) {
        if (d.vendorId != APPLE_VENDOR_ID) return
        val id = d.deviceName
        // Stops a copy between chunks; the next device call fails anyway.
        cancel.set(true)
        mtp.execute { if (openId == id) closeDevice() }
        emit(mapOf("type" to "detached", "id" to id))
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> result.success(
                cameras().map { mapOf("id" to it.deviceName, "name" to nameOf(it)) },
            )
            "open" -> open(call.argument<String>("id")!!, result)
            "nextPage" -> onMtpQuick(result) { nextPage(call.argument<Number>("max")?.toInt() ?: 500) }
            "thumbnail" -> onMtpQuick(result) { thumbnail(call.argument<Number>("handle")!!.toInt()) }
            "importFile" -> {
                cancel.set(false)
                onMtp(result) {
                    importFile(
                        handle = call.argument<Number>("handle")!!.toInt(),
                        name = call.argument<String>("name")!!,
                        mime = call.argument<String>("mime")!!,
                        collection = call.argument<String>("collection")!!,
                        expectedSize = call.argument<Number>("expectedSize")?.toLong(),
                        takenMs = call.argument<Number>("takenMs")?.toLong(),
                    )
                }
            }
            "probe" -> probe(call.argument<Number>("port")?.toInt(), result)
            "cancelCurrent" -> {
                cancel.set(true)
                result.success(null)
            }
            "close" -> {
                cancel.set(true)
                onMtp(result) {
                    closeDevice()
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    // --- Devices and access ---

    private fun cameras(): List<UsbDevice> = usb.deviceList.values.filter(::isCamera)

    private fun isCamera(d: UsbDevice): Boolean {
        if (d.vendorId != APPLE_VENDOR_ID) return false
        for (i in 0 until d.interfaceCount) {
            if (d.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) return true
        }
        return false
    }

    private fun nameOf(d: UsbDevice): String = d.productName?.takeIf { it.isNotBlank() } ?: "iPhone"

    @Suppress("DEPRECATION")
    private fun deviceOf(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private fun open(id: String, result: MethodChannel.Result) {
        val d = usb.deviceList[id]
        if (d == null || !isCamera(d)) {
            result.error("disconnected", null, null)
            return
        }
        withPermission(d, result) { onMtp(result) { openOnMtp(d) } }
    }

    /** Cable test: closes any open import first, then runs [UsbTunnelProbe]. */
    private fun probe(port: Int?, result: MethodChannel.Result) {
        val d = usb.deviceList.values.firstOrNull { it.vendorId == APPLE_VENDOR_ID }
        if (d == null) {
            result.success("No iPhone found on the cable.")
            return
        }
        withPermission(d, result) {
            onMtp(result) {
                closeDevice()
                UsbTunnelProbe(usb).run(d, port).joinToString("\n").also { log("probe:\n$it") }
            }
        }
    }

    private fun withPermission(d: UsbDevice, result: MethodChannel.Result, go: () -> Unit) {
        if (usb.hasPermission(d)) {
            go()
            return
        }
        // A second request replaces the first; its caller gets "denied".
        permissionWaiter?.invoke(false)
        permissionWaiter = { granted ->
            if (granted) {
                go()
            } else {
                log("open: USB access denied")
                result.error("permission_denied", null, null)
            }
        }
        val intent = Intent(ACTION_PERMISSION).setPackage(activity.packageName)
        // Mutable: the system adds EXTRA_PERMISSION_GRANTED. Explicit
        // (package set), as Android 14 requires for mutable intents.
        val pending = PendingIntent.getBroadcast(activity, 0, intent, PendingIntent.FLAG_MUTABLE)
        usb.requestPermission(d, pending)
    }

    private fun openOnMtp(d: UsbDevice): Any? {
        closeDevice()
        clearThumbs()
        val connection = usb.openDevice(d)
        if (connection == null) {
            log("open: Android refused to open the device")
            throw ChannelError("busy")
        }
        val m = MtpDevice(d)
        // Fails when another app (Files, a gallery) has claimed the
        // interface.
        if (!m.open(connection)) {
            connection.close()
            log("open: camera interface held elsewhere")
            throw ChannelError("busy")
        }
        val storages = m.storageIds
        if (storages == null || storages.isEmpty()) {
            m.close()
            log("open: no storage (locked or Allow not tapped)")
            throw ChannelError("locked")
        }
        device = m
        openId = d.deviceName
        partialReads = true
        walk = Walk(storages)
        log("open: ${storages.size} storage(s)")
        return null
    }

    private fun closeDevice() {
        try {
            device?.close()
        } catch (ignored: Exception) {
        }
        device = null
        openId = null
        walk = null
        clearThumbs()
    }

    private fun requireDevice(): MtpDevice = device ?: throw ChannelError("disconnected")

    /** A device call failed: unplugged, or a real error. */
    private fun failure(): ChannelError =
        ChannelError(if (openId != null && usb.deviceList.containsKey(openId)) "io" else "disconnected")

    // --- Listing ---

    /**
     * Folders still to read, first in first out. Each folder's entries are
     * read last to first, so the newest folder (`1xxAPPLE` with the
     * highest number) and the newest files in it come first.
     */
    private inner class Walk(storages: IntArray) {
        val folders = ArrayDeque<Pair<Int, Int>>()
        var files = ArrayDeque<Int>()
        var storage = 0
        val seen = HashSet<Int>()
        var count = 0

        init {
            for (s in storages) folders.addLast(s to ROOT)
        }
    }

    private fun nextPage(max: Int): Map<String, Any?> {
        val m = requireDevice()
        val w = walk ?: throw ChannelError("disconnected")
        val out = ArrayList<Map<String, Any?>>()
        while (out.size < max) {
            if (w.files.isEmpty()) {
                val (storage, parent) = w.folders.removeFirstOrNull() ?: break
                val handles = m.getObjectHandles(storage, 0, parent) ?: throw failure()
                w.storage = storage
                // Newest files last in a folder; read them first.
                w.files = ArrayDeque(handles.reversed())
                continue
            }
            val h = w.files.removeFirst()
            if (!w.seen.add(h)) continue
            val info = m.getObjectInfo(h) ?: continue
            if (info.format == MtpConstants.FORMAT_ASSOCIATION) {
                w.folders.addLast(w.storage to h)
                continue
            }
            // 0xFFFFFFFF: 4 GB or more, which PTP's 32-bit field cannot
            // say. Sent as unknown (-1); copied whole and checked >= 4 GiB.
            val size = info.compressedSizeLong.let { if (it >= UNKNOWN_SIZE) -1L else it }
            val taken = info.dateCreated.takeIf { it > 0 } ?: info.dateModified
            out.add(
                mapOf(
                    "handle" to h,
                    "name" to (info.name ?: ""),
                    "folder" to info.parent,
                    "size" to size,
                    "takenMs" to taken,
                ),
            )
            w.count++
        }
        val done = w.files.isEmpty() && w.folders.isEmpty()
        if (done) log("list: ${w.count} files")
        return mapOf("objects" to out, "done" to done, "seen" to w.count)
    }

    private fun thumbnail(handle: Int): String? {
        val m = requireDevice()
        val file = File(thumbDir, "$handle.jpg")
        if (file.exists()) return file.path
        val bytes = m.getThumbnail(handle) ?: return null
        thumbDir.mkdirs()
        val tmp = File(thumbDir, "$handle.tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(file)) {
            tmp.delete()
            return null
        }
        return file.path
    }

    private fun clearThumbs() {
        thumbDir.listFiles()?.forEach { it.delete() }
    }

    // --- Copying ---

    private fun importFile(
        handle: Int,
        name: String,
        mime: String,
        collection: String,
        expectedSize: Long?,
        takenMs: Long?,
    ): Map<String, Any?> {
        val m = requireDevice()
        var used = collection
        val uri = try {
            save.insertPending(name, mime, collection, takenMs)
        } catch (e: ChannelError) {
            if (e.code != "unsupported" || collection == "files") throw e
            used = "files"
            save.insertPending(name, mime, "files", null)
        }
        try {
            val bytes = activity.contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
                val n = if (expectedSize != null && expectedSize < UNKNOWN_SIZE && partialReads) {
                    copyInChunks(m, handle, pfd, expectedSize) ?: copyWhole(m, handle, pfd, expectedSize)
                } else {
                    copyWhole(m, handle, pfd, expectedSize)
                }
                Os.fsync(pfd.fileDescriptor)
                n
            } ?: throw ChannelError("io")
            save.publish(uri)
            return mapOf("uri" to uri.toString(), "collection" to used, "bytes" to bytes)
        } catch (e: Exception) {
            save.deleteItem(uri)
            throw e
        }
    }

    /**
     * Reads [size] bytes in 1 MB parts (hard rule 1) and never asks for
     * more than declared (hard rule 6). Null if the device does not
     * support partial reads; [copyWhole] is then used from now on.
     */
    private fun copyInChunks(m: MtpDevice, handle: Int, pfd: ParcelFileDescriptor, size: Long): Long? {
        val buffer = ByteArray(CHUNK)
        val out = FileOutputStream(pfd.fileDescriptor)
        var offset = 0L
        var lastEvent = 0L
        while (offset < size) {
            if (cancel.get()) throw ChannelError("cancelled")
            val want = minOf(CHUNK.toLong(), size - offset)
            val n = try {
                m.getPartialObject(handle, offset, want, buffer)
            } catch (e: IOException) {
                if (offset == 0L && device != null && usb.deviceList.containsKey(openId)) {
                    log("partial reads refused; copying whole files")
                    partialReads = false
                    return null
                }
                throw failure()
            }
            if (n <= 0 || n > want) throw failure()
            out.write(buffer, 0, n.toInt())
            offset += n
            runQuick()
            val now = System.nanoTime()
            if (now - lastEvent > PROGRESS_NS) {
                lastEvent = now
                emit(mapOf("type" to "progress", "handle" to handle, "bytes" to offset))
            }
        }
        // The device must have nothing past the declared end.
        val extra = try {
            m.getPartialObject(handle, size, 1, buffer)
        } catch (e: IOException) {
            0L
        }
        if (extra > 0) throw ChannelError("size_mismatch")
        return offset
    }

    /**
     * One GetObject for the whole file, for devices without partial reads
     * and files of 4 GB and more. Progress comes from the file's size on
     * disk; the size is checked once it is done.
     */
    private fun copyWhole(m: MtpDevice, handle: Int, pfd: ParcelFileDescriptor, expected: Long?): Long {
        if (cancel.get()) throw ChannelError("cancelled")
        Os.ftruncate(pfd.fileDescriptor, 0)
        val poll = ticker.scheduleAtFixedRate({
            try {
                val now = Os.fstat(pfd.fileDescriptor).st_size
                emit(mapOf("type" to "progress", "handle" to handle, "bytes" to now))
            } catch (ignored: Exception) {
            }
        }, PROGRESS_MS, PROGRESS_MS, TimeUnit.MILLISECONDS)
        val ok = try {
            m.importFile(handle, pfd)
        } finally {
            poll.cancel(false)
        }
        if (!ok) throw failure()
        val size = Os.fstat(pfd.fileDescriptor).st_size
        // Unknown means PTP said "4 GB or more".
        val matches = if (expected == null) size >= UNKNOWN_SIZE else size == expected
        if (!matches) throw ChannelError("size_mismatch")
        return size
    }

    private fun onMtp(result: MethodChannel.Result, work: () -> Any?) {
        try {
            mtp.execute(task(result, work))
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            result.error("disconnected", null, null)
        }
    }

    /**
     * Short calls (a preview, a page of the list): also run between the
     * 1 MB parts of a copy, so the screen does not wait for a whole file.
     * Whichever comes first, the copy loop or the queue, runs it.
     */
    private fun onMtpQuick(result: MethodChannel.Result, work: () -> Any?) {
        val t = task(result, work)
        quick.add(t)
        try {
            mtp.execute { runQuick() }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            if (quick.remove(t)) result.error("disconnected", null, null)
        }
    }

    /** On the mtp thread only. */
    private fun runQuick() {
        while (true) (quick.poll() ?: return).run()
    }

    private fun task(result: MethodChannel.Result, work: () -> Any?) = Runnable {
        try {
            val value = work()
            main.post { result.success(value) }
        } catch (e: Exception) {
            val code = errorCode(e)
            log("failed: $code")
            main.post { result.error(code, null, null) }
        }
    }

    private fun log(message: String) {
        android.util.Log.i("crossdrop.usb", message)
    }

    companion object {
        const val APPLE_VENDOR_ID = 0x05AC
        private const val ACTION_PERMISSION = "io.github.shreyashjunje.crossdrop.USB_PERMISSION"

        /** "Children of the root" for GetObjectHandles. */
        private const val ROOT = -1
        private const val UNKNOWN_SIZE = 0xFFFFFFFFL
        private const val CHUNK = 1 shl 20
        private const val PROGRESS_MS = 250L
        private const val PROGRESS_NS = PROGRESS_MS * 1_000_000
    }
}
