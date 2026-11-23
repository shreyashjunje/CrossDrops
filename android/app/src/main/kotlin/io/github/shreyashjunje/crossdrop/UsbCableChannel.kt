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
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Platform channel `crossdrop/usb_cable` (Dart side:
 * lib/platform/usb_cable.dart): an iPhone on the USB cable (D-073).
 *
 * Plug-in events, USB access, the send-by-cable bridge ([CableBridge]) and
 * the cable test ([UsbTunnelProbe]). Only ports, states and the test
 * report cross the channel; file bytes stay in [CableBridge] (hard rule 2).
 *
 * - `devices` -> [{id, name}]: attached iPhones.
 * - `cableStart {port, ports, id, name}`: starts the bridge to the
 *   plugged-in iPhone, or gives a running one new ports. Errors:
 *   `disconnected`, `permission_denied`.
 * - `cableStop`.
 * - `probe {port?}` -> text report of the cable test. The bridge pauses
 *   meanwhile.
 *
 * Events on `crossdrop/usb_cable/events`: {type: attached, id, name},
 * {type: detached, id}, {type: cable, state, code}.
 *
 * Names are never logged (hard rule 7).
 */
class UsbCableChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val channel = MethodChannel(messenger, "crossdrop/usb_cable")
    private val eventChannel = EventChannel(messenger, "crossdrop/usb_cable/events")
    private val usb = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var permissionWaiter: ((Boolean) -> Unit)? = null

    // Main thread only. [cablePaused]: the cable test has the iPhone; the
    // bridge starts again after it.
    private var bridge: CableBridge? = null
    private var cableConfig: CableBridge.Config? = null
    private var cablePaused = false

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
        stopBridge()
        io.shutdown()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        for (d in iphones()) attached(d)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    private fun attached(d: UsbDevice) {
        if (!isIphone(d)) return
        emit(mapOf("type" to "attached", "id" to d.deviceName, "name" to nameOf(d)))
    }

    private fun detached(d: UsbDevice) {
        if (d.vendorId != APPLE_VENDOR_ID) return
        if (bridge?.device?.deviceName == d.deviceName) stopBridge()
        emit(mapOf("type" to "detached", "id" to d.deviceName))
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> result.success(
                iphones().map { mapOf("id" to it.deviceName, "name" to nameOf(it)) },
            )
            "probe" -> probe(call.argument<Number>("port")?.toInt(), result)
            "cableStart" -> {
                cableConfig = CableBridge.Config(
                    port = call.argument<Number>("port")!!.toInt(),
                    allowed = call.argument<List<Number>>("ports")!!.map { it.toInt() }.toSet(),
                    deviceId = call.argument<String>("id")!!,
                    name = call.argument<String>("name")!!,
                )
                if (cablePaused) result.success(null) else startBridge(result)
            }
            "cableStop" -> {
                cableConfig = null
                stopBridge()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // --- Devices and access ---

    private fun iphones(): List<UsbDevice> = usb.deviceList.values.filter(::isIphone)

    /** An Apple device that shows a camera interface: an iPhone or iPad. */
    private fun isIphone(d: UsbDevice): Boolean {
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
                log("USB access denied")
                result.error("permission_denied", null, null)
            }
        }
        val intent = Intent(ACTION_PERMISSION).setPackage(activity.packageName)
        // Mutable: the system adds EXTRA_PERMISSION_GRANTED. Explicit
        // (package set), as Android 14 requires for mutable intents.
        val pending = PendingIntent.getBroadcast(activity, 0, intent, PendingIntent.FLAG_MUTABLE)
        usb.requestPermission(d, pending)
    }

    // --- Send by cable (D-073) ---

    private fun startBridge(result: MethodChannel.Result) {
        val config = cableConfig ?: return result.success(null)
        val d = iphones().firstOrNull()
        if (d == null) {
            result.error("disconnected", null, null)
            return
        }
        val running = bridge
        if (running != null && running.device.deviceName == d.deviceName) {
            running.update(config)
            result.success(null)
            return
        }
        stopBridge()
        withPermission(d, result) {
            lateinit var b: CableBridge
            b = CableBridge(usb, d, config) { state, code ->
                emit(mapOf("type" to "cable", "state" to state, "code" to code))
                if (state == "stopped") main.post { if (bridge === b) bridge = null }
            }
            bridge = b
            b.start()
            result.success(null)
        }
    }

    private fun stopBridge() {
        bridge?.stop()
        bridge = null
    }

    /** Cable test: the bridge waits, then [UsbTunnelProbe] runs. */
    private fun probe(port: Int?, result: MethodChannel.Result) {
        val d = usb.deviceList.values.firstOrNull { it.vendorId == APPLE_VENDOR_ID }
        if (d == null) {
            result.success("No iPhone found on the cable.")
            return
        }
        withPermission(d, result) {
            cablePaused = true
            stopBridge()
            io.execute {
                val report = UsbTunnelProbe(usb).run(d, port).joinToString("\n")
                log("probe:\n$report")
                main.post {
                    result.success(report)
                    cablePaused = false
                    if (cableConfig != null) startBridge(Quiet)
                }
            }
        }
    }

    /** For starts nobody waits on. */
    private object Quiet : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, message: String?, details: Any?) {}
        override fun notImplemented() {}
    }

    private fun log(message: String) {
        android.util.Log.i("crossdrop.usb", message)
    }

    companion object {
        const val APPLE_VENDOR_ID = 0x05AC
        private const val ACTION_PERMISSION = "io.github.shreyashjunje.crossdrop.USB_PERMISSION"
    }
}
