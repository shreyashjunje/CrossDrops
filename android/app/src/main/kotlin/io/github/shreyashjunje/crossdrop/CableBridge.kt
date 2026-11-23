package io.github.shreyashjunje.crossdrop

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The receiving Android's end of "send by cable" (D-073).
 *
 * Over [UsbMux] it keeps a control connection to the CrossDrop app on the
 * plugged-in iPhone (127.0.0.1:47913, 47914 or 47915 there), says hello
 * with this phone's receive port, and answers each `dial` by joining a
 * new usbmux connection to that iPhone port with a local socket to one of
 * [Config.allowed]: the receive server's own ports, never another.
 *
 * Every file byte stays in Kotlin (hard rule 2). [onState] gets
 * `starting`, `waiting` (no CrossDrop answering on the iPhone yet),
 * `connected` and `stopped` with a code: `open_failed`, `no_usbmux`,
 * `handshake`, `unplugged`, or null when stopped on purpose.
 */
class CableBridge(
    private val usb: UsbManager,
    val device: UsbDevice,
    @Volatile private var config: Config,
    private val report: (String, String?) -> Unit,
) {
    data class Config(val port: Int, val allowed: Set<Int>, val deviceId: String, val name: String)

    private val running = AtomicBoolean(true)
    private val work = Executors.newCachedThreadPool()
    @Volatile private var mux: UsbMux? = null
    @Volatile private var control: UsbMux.MuxConnection? = null
    private val thread = Thread(::run, "cable-bridge").apply { isDaemon = true }
    private var last: Pair<String, String?>? = null

    /** Reports a state once, not again while it stays the same. */
    @Synchronized
    private fun onState(state: String, code: String?) {
        if (last == state to code) return
        last = state to code
        report(state, code)
    }

    fun start() = thread.start()

    /** New ports or name: the iPhone hears a new hello. */
    fun update(c: Config) {
        config = c
        work.execute(::sendHello)
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        thread.interrupt()
        mux?.close("stopped")
        work.shutdownNow()
    }

    private fun run() {
        onState("starting", null)
        val conn = usb.openDevice(device)
        if (conn == null) {
            finish("open_failed")
            return
        }
        val intf = claimMux(conn)
        if (intf == null) {
            conn.close()
            finish("no_usbmux")
            return
        }
        val m = try {
            UsbMux.open(conn, intf) { why -> log("usbmux ended: $why") }
        } catch (e: IOException) {
            log("handshake failed: ${e.message}")
            conn.close()
            finish("handshake")
            return
        }
        mux = m
        log("usbmux ready")
        try {
            while (running.get() && !m.isDead) {
                val closed = CountDownLatch(1)
                val c = connectControl(m, closed)
                if (c == null) {
                    onState("waiting", null)
                    Thread.sleep(RETRY_MS)
                    continue
                }
                control = c
                sendHello()
                onState("connected", null)
                log("iPhone app connected")
                closed.await()
                control = null
                if (running.get() && !m.isDead) {
                    log("iPhone app gone")
                    onState("waiting", null)
                    Thread.sleep(RETRY_MS)
                }
            }
        } catch (e: InterruptedException) {
            // stop()
        }
        m.close("stopped")
        finish(if (running.get()) "unplugged" else null)
    }

    private fun finish(code: String?) {
        running.set(false)
        work.shutdownNow()
        onState("stopped", code)
    }

    /** The usbmux interface, claimed; switches configuration if needed. */
    private fun claimMux(conn: UsbDeviceConnection): UsbInterface? {
        for (c in 0 until device.configurationCount) {
            val cfg = device.getConfiguration(c)
            for (i in 0 until cfg.interfaceCount) {
                val intf = cfg.getInterface(i)
                if (intf.interfaceClass != 255 || intf.interfaceSubclass != 254 || intf.interfaceProtocol != 2) continue
                if (conn.claimInterface(intf, true)) return intf
                if (conn.setConfiguration(cfg) && conn.claimInterface(intf, true)) return intf
                log("usbmux interface refused")
                return null
            }
        }
        return null
    }

    private fun connectControl(m: UsbMux, closed: CountDownLatch): UsbMux.MuxConnection? {
        val lines = LineReader()
        for (port in CONTROL_PORTS) {
            var self: UsbMux.MuxConnection? = null
            val c = m.connect(
                port,
                CONNECT_TIMEOUT_MS,
                onData = { bytes ->
                    // USB thread: never block here.
                    for (line in lines.feed(bytes)) work.execute { onLine(line) }
                    self?.consumed(bytes.size)
                    if (lines.overflow) self?.reset()
                },
                onClose = { closed.countDown() },
            )
            self = c
            if (c != null) return c
        }
        return null
    }

    private fun sendHello() {
        val c = config
        val hello = JSONObject()
            .put("t", "hello").put("v", PROTOCOL_VERSION)
            .put("port", c.port).put("id", c.deviceId).put("name", c.name)
        sendLine(hello)
    }

    private fun sendLine(o: JSONObject) {
        val c = control ?: return
        val bytes = (o.toString() + "\n").toByteArray(Charsets.UTF_8)
        try {
            c.write(bytes, bytes.size)
        } catch (e: IOException) {
            // The control connection ended; the loop reconnects.
        }
    }

    private fun onLine(line: String) {
        val o = try {
            JSONObject(line)
        } catch (e: JSONException) {
            return
        }
        if (o.optString("t") != "dial") return
        val listen = o.optInt("listen", 0)
        val port = o.optInt("port", 0)
        if (listen !in 1..65535) return
        if (port !in config.allowed) {
            log("dial refused: not a receive port")
            fail(listen)
            return
        }
        dial(listen, port)
    }

    private fun fail(listen: Int) = sendLine(JSONObject().put("t", "fail").put("listen", listen))

    /** Joins local [port] to the iPhone's [listen] port. */
    private fun dial(listen: Int, port: Int) {
        val m = mux ?: return
        val local = Socket()
        try {
            local.tcpNoDelay = true
            local.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), port), CONNECT_TIMEOUT_MS.toInt())
        } catch (e: IOException) {
            closeQuietly(local)
            fail(listen)
            return
        }
        val pipe = Pipe(local)
        val c = m.connect(listen, CONNECT_TIMEOUT_MS, pipe::fromMux, pipe::muxClosed)
        if (c == null) {
            closeQuietly(local)
            fail(listen)
            return
        }
        pipe.start(c)
    }

    /** Bytes both ways between a local socket and a usbmux connection. */
    private inner class Pipe(private val socket: Socket) {
        private val toLocal = LinkedBlockingQueue<ByteArray>()

        fun fromMux(bytes: ByteArray) {
            toLocal.offer(bytes)
        }

        fun muxClosed() {
            toLocal.offer(EOF)
        }

        fun start(c: UsbMux.MuxConnection) {
            Thread({ localWriter(c) }, "cable-to-local").apply { isDaemon = true }.start()
            Thread({ localReader(c) }, "cable-to-iphone").apply { isDaemon = true }.start()
        }

        private fun localWriter(c: UsbMux.MuxConnection) {
            try {
                val out = socket.getOutputStream()
                while (true) {
                    val b = toLocal.take()
                    if (b === EOF) break
                    out.write(b)
                    c.consumed(b.size)
                }
                out.flush()
            } catch (e: Exception) {
                // Local side gone.
            } finally {
                closeQuietly(socket)
                c.reset()
            }
        }

        private fun localReader(c: UsbMux.MuxConnection) {
            val buf = ByteArray(UsbMux.MAX_PAYLOAD)
            try {
                val input = socket.getInputStream()
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) c.write(buf, n)
                }
            } catch (e: Exception) {
                // Either side gone.
            } finally {
                c.reset()
                closeQuietly(socket)
                toLocal.offer(EOF)
            }
        }
    }

    /** Splits control bytes into lines of at most [MAX_LINE] bytes. */
    private class LineReader {
        private val pending = ByteArrayOutputStream()
        var overflow = false
            private set

        @Synchronized
        fun feed(bytes: ByteArray): List<String> {
            val lines = ArrayList<String>()
            var start = 0
            for (i in bytes.indices) {
                if (bytes[i] != '\n'.code.toByte()) continue
                pending.write(bytes, start, i - start)
                start = i + 1
                if (pending.size() < MAX_LINE) lines += pending.toString("UTF-8") else overflow = true
                pending.reset()
            }
            pending.write(bytes, start, bytes.size - start)
            if (pending.size() >= MAX_LINE) overflow = true
            return lines
        }
    }

    private fun log(message: String) = Log.i(TAG, message)

    private companion object {
        const val TAG = "crossdrop.cable"
        const val PROTOCOL_VERSION = 1
        val CONTROL_PORTS = intArrayOf(47913, 47914, 47915)
        const val CONNECT_TIMEOUT_MS = 3000L
        const val RETRY_MS = 1000L
        const val MAX_LINE = 4096
        val EOF = ByteArray(0)

        fun closeQuietly(s: Socket) {
            try {
                s.close()
            } catch (ignored: IOException) {
            }
        }
    }
}
