package io.github.shreyashjunje.crossdrop

import android.hardware.usb.UsbConfiguration
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import java.io.IOException
import java.nio.ByteBuffer

/**
 * Cable test (D-067 follow-up): can this phone reach an app on a plugged-in
 * iPhone through Apple's USB multiplexing protocol (usbmux), the way
 * iTunes and Xcode do? Answers each step as a line of plain text for the
 * owner to paste back. Sends no file data; opens and resets two TCP
 * connections inside the tunnel.
 *
 * usbmux framing follows the open-source usbmuxd (libimobiledevice):
 * a version handshake, then TCP headers carried in usbmux packets, all
 * big-endian.
 *
 * Reports USB descriptors, Android version and model only: no names,
 * serial numbers or photos (hard rule 7).
 */
class UsbTunnelProbe(private val usb: UsbManager) {
    fun run(d: UsbDevice, port: Int?): List<String> {
        val out = ArrayList<String>()
        out += "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}), ${Build.MANUFACTURER} ${Build.MODEL}"
        out += "Device: product 0x%04x, %d configuration(s)".format(d.productId, d.configurationCount)
        var muxConfig: UsbConfiguration? = null
        var muxIntf: UsbInterface? = null
        var ptp: UsbInterface? = null
        for (c in 0 until d.configurationCount) {
            val cfg = d.getConfiguration(c)
            val list = (0 until cfg.interfaceCount).map { cfg.getInterface(it) }
            out += "  config ${cfg.id}: " + list.joinToString(", ") {
                "${it.interfaceClass}/${it.interfaceSubclass}/${it.interfaceProtocol}"
            }
            for (i in list) {
                if (ptp == null && i.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) ptp = i
                if (muxIntf == null && i.interfaceClass == 255 && i.interfaceSubclass == 254 && i.interfaceProtocol == 2) {
                    muxConfig = cfg
                    muxIntf = i
                }
            }
        }
        val conn = usb.openDevice(d)
        if (conn == null) {
            out += "FAIL: Android would not open the device"
            return out
        }
        try {
            ptp?.let {
                val free = conn.claimInterface(it, false)
                out += if (free) "Camera interface: free" else "Camera interface: held by another app or the system"
                if (free) conn.releaseInterface(it)
            }
            val cfg = muxConfig
            val intf = muxIntf
            if (cfg == null || intf == null) {
                out += "FAIL: no usbmux interface in any configuration"
                return out
            }
            var claimed = conn.claimInterface(intf, true)
            if (!claimed) {
                val switched = conn.setConfiguration(cfg)
                out += "Switch to config ${cfg.id}: " + if (switched) "ok" else "refused"
                claimed = switched && conn.claimInterface(intf, true)
            }
            out += "Claim usbmux interface: " + if (claimed) "ok" else "FAIL"
            if (!claimed) return out
            val mux = Mux(conn, intf)
            val version = try {
                mux.handshake()
            } catch (e: IOException) {
                null
            }
            out += if (version == null) "Handshake: FAIL (no answer)" else "Handshake: ok, version $version"
            if (version == null) return out
            out += "Built-in service (port 62078): " + mux.connect(LOCKDOWN_PORT, 1)
            if (port != null) out += "CrossDrop (port $port): " + mux.connect(port, 2)
            conn.releaseInterface(intf)
        } catch (e: Exception) {
            out += "FAIL: ${e.javaClass.simpleName}"
        } finally {
            conn.close()
        }
        return out
    }

    private class Mux(private val conn: UsbDeviceConnection, intf: UsbInterface) {
        private val bulkOut: UsbEndpoint
        private val bulkIn: UsbEndpoint
        private var version = 0
        private var txSeq = 0
        private var rxSeq = 0xFFFF
        private val buffer = ByteArray(16384)

        init {
            val eps = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                .filter { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK }
            bulkOut = eps.first { it.direction == UsbConstants.USB_DIR_OUT }
            bulkIn = eps.first { it.direction == UsbConstants.USB_DIR_IN }
        }

        /** The device's protocol version; null if it did not answer. */
        fun handshake(): Int? {
            send(PROTO_VERSION, ByteBuffer.allocate(12).putInt(2).putInt(0).putInt(0).array())
            val deadline = System.currentTimeMillis() + TIMEOUT_MS
            while (true) {
                val (proto, body) = receive(deadline) ?: return null
                if (proto != PROTO_VERSION || body.remaining() < 4) continue
                val major = body.int
                version = major
                if (major >= 2) send(PROTO_SETUP, byteArrayOf(7))
                return major
            }
        }

        /** "reachable", "refused (nothing listening)" or "no answer". */
        fun connect(port: Int, sport: Int): String {
            send(PROTO_TCP, tcp(sport, port, 0, 0, TH_SYN))
            val deadline = System.currentTimeMillis() + TIMEOUT_MS
            while (true) {
                val (proto, body) = receive(deadline) ?: return "no answer"
                if (proto != PROTO_TCP || body.remaining() < 20) continue
                val from = body.short.toInt() and 0xFFFF
                val to = body.short.toInt() and 0xFFFF
                if (from != port || to != sport) continue
                val flags = body.get(body.position() + 9).toInt()
                if (flags and TH_RST != 0) return "refused (nothing listening)"
                if (flags and (TH_SYN or TH_ACK) == (TH_SYN or TH_ACK)) {
                    send(PROTO_TCP, tcp(sport, port, 1, 1, TH_RST))
                    return "reachable"
                }
            }
        }

        private fun tcp(sport: Int, dport: Int, seq: Int, ack: Int, flags: Int): ByteArray =
            ByteBuffer.allocate(20)
                .putShort(sport.toShort()).putShort(dport.toShort())
                .putInt(seq).putInt(ack)
                .put(0x50.toByte()).put(flags.toByte())
                .putShort((WINDOW shr 8).toShort()).putShort(0).putShort(0)
                .array()

        private fun send(proto: Int, body: ByteArray) {
            val header = if (version >= 2) 16 else 8
            val b = ByteBuffer.allocate(header + body.size).putInt(proto).putInt(header + body.size)
            if (version >= 2) {
                if (proto == PROTO_SETUP) {
                    txSeq = 0
                    rxSeq = 0xFFFF
                }
                b.putInt(MAGIC).putShort(txSeq.toShort()).putShort(rxSeq.toShort())
                txSeq = (txSeq + 1) and 0xFFFF
            }
            val bytes = b.put(body).array()
            if (conn.bulkTransfer(bulkOut, bytes, bytes.size, TIMEOUT_MS.toInt()) != bytes.size) {
                throw IOException("send")
            }
            // A transfer that fills whole packets needs a zero-length one.
            if (bytes.size % bulkOut.maxPacketSize == 0) conn.bulkTransfer(bulkOut, bytes, 0, TIMEOUT_MS.toInt())
        }

        /** One usbmux packet as (protocol, body), or null at [deadline]. */
        private fun receive(deadline: Long): Pair<Int, ByteBuffer>? {
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) return null
                val n = conn.bulkTransfer(bulkIn, buffer, buffer.size, left.toInt())
                val header = if (version >= 2) 16 else 8
                if (n < header) continue
                val b = ByteBuffer.wrap(buffer, 0, n)
                val proto = b.int
                if (b.int != n) continue
                if (version >= 2) {
                    b.int // magic
                    b.short // device's tx sequence
                    rxSeq = b.short.toInt() and 0xFFFF
                }
                return proto to b.slice()
            }
        }
    }

    private companion object {
        const val LOCKDOWN_PORT = 62078
        const val PROTO_VERSION = 0
        const val PROTO_SETUP = 2
        const val PROTO_TCP = 6
        const val MAGIC = 0xfeedface.toInt()
        const val TH_RST = 0x04
        const val TH_SYN = 0x02
        const val TH_ACK = 0x10
        const val WINDOW = 131072
        const val TIMEOUT_MS = 3000L
    }
}
