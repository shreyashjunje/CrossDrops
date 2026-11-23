package io.github.shreyashjunje.crossdrop

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Apple's USB multiplexing protocol (usbmux), host side (D-073): many
 * TCP-like connections to ports on a plugged-in iPhone, over the bulk
 * endpoints of its usbmux interface.
 *
 * Framing follows the open-source usbmuxd (libimobiledevice), protocol
 * version 2: a 16-byte header (protocol, length, magic, packet sequence
 * numbers) and, for TCP, a 20-byte TCP header. USB is reliable, so there
 * are no retransmissions; usbmux has no FIN, a connection ends with RST.
 *
 * Threads: one reads USB and hands payloads to connections without ever
 * blocking on them; one writes USB in queue order. A connection's
 * [MuxConnection.write] blocks until the iPhone's window has room.
 * Received bytes are acknowledged at once with the free room of the
 * connection's own buffer as window, so a slow consumer slows only its
 * own connection.
 *
 * Never logs payloads (hard rule 7).
 */
class UsbMux private constructor(
    private val conn: UsbDeviceConnection,
    private val bulkIn: UsbEndpoint,
    private val bulkOut: UsbEndpoint,
    private val onDead: (String) -> Unit,
) {
    private val out = LinkedBlockingQueue<Out>()
    private val connections = ConcurrentHashMap<Int, MuxConnection>()
    private val dead = AtomicBoolean(false)
    private var nextPort = 1

    // Packet sequence numbers of the v2 header; writer thread only.
    private var txSeq = 0
    @Volatile private var rxSeq = 0xFFFF

    private sealed class Out {
        /** [c] and [endSeq]: a data packet; the writer records what is on the wire. */
        class Packet(val proto: Int, val body: ByteArray, val c: MuxConnection? = null, val endSeq: Int = 0) : Out()
        class Ack(val c: MuxConnection) : Out()
        object Stop : Out()
    }

    val isDead: Boolean get() = dead.get()

    /**
     * Opens a connection to [port] on the iPhone; null if nothing listens
     * there or it does not answer in [timeoutMs]. [onData] gets each
     * payload (its own copy) on the USB thread and must not block;
     * [onClose] runs once when the connection ends, from either side.
     */
    fun connect(
        port: Int,
        timeoutMs: Long,
        onData: (ByteArray) -> Unit,
        onClose: () -> Unit,
    ): MuxConnection? {
        if (dead.get()) return null
        val c = MuxConnection(allocatePort(), port, onData, onClose)
        connections[c.sport] = c
        enqueue(Out.Packet(PROTO_TCP, c.header(TH_SYN, 0, 0)))
        if (!c.connected.await(timeoutMs, TimeUnit.MILLISECONDS) || !c.isOpen) {
            c.reset()
            return null
        }
        return c
    }

    fun close(why: String = "closed") {
        if (!dead.compareAndSet(false, true)) return
        out.clear()
        out.offer(Out.Stop)
        for (c in connections.values) c.drop()
        connections.clear()
        try {
            conn.close()
        } catch (ignored: Exception) {
        }
        onDead(why)
    }

    @Synchronized
    private fun allocatePort(): Int {
        while (true) {
            val p = nextPort
            nextPort = if (nextPort >= 65535) 1 else nextPort + 1
            if (!connections.containsKey(p)) return p
        }
    }

    private fun enqueue(o: Out) {
        if (!dead.get()) out.offer(o)
    }

    // --- USB threads ---

    private fun start() {
        Thread(::readLoop, "usbmux-in").apply { isDaemon = true }.start()
        Thread(::writeLoop, "usbmux-out").apply { isDaemon = true }.start()
    }

    private fun writeLoop() {
        try {
            while (!dead.get()) {
                when (val o = out.take()) {
                    is Out.Stop -> return
                    is Out.Packet -> {
                        sendPacket(o.proto, o.body)
                        o.c?.wireSeq = o.endSeq
                    }
                    is Out.Ack -> {
                        // Coalesced: the newest ack and window go out once,
                        // with the sequence number already on the wire.
                        o.c.ackQueued.set(false)
                        if (o.c.isOpen) sendPacket(PROTO_TCP, o.c.header(TH_ACK, 0, o.c.wireSeq))
                    }
                }
            }
        } catch (e: IOException) {
            close("usb write failed")
        } catch (e: InterruptedException) {
            close("stopped")
        }
    }

    private fun sendPacket(proto: Int, body: ByteArray) {
        val size = HEADER + body.size
        val b = ByteBuffer.allocate(size)
            .putInt(proto).putInt(size).putInt(MAGIC)
            .putShort(txSeq.toShort()).putShort(rxSeq.toShort())
            .put(body)
        txSeq = (txSeq + 1) and 0xFFFF
        val bytes = b.array()
        if (conn.bulkTransfer(bulkOut, bytes, size, USB_TIMEOUT_MS) != size) throw IOException("send")
        // A transfer that fills whole packets needs a zero-length one.
        if (size % bulkOut.maxPacketSize == 0) conn.bulkTransfer(bulkOut, bytes, 0, USB_TIMEOUT_MS)
    }

    private fun readLoop() {
        val buf = ByteArray(READ_BUFFER)
        var filled = 0
        try {
            while (!dead.get()) {
                // 16 KB reads like usbmuxd's (USB_MRU): a long usbmux packet
                // spans several, and none waits half full for more. A -1
                // before the timeout means the device is gone; at the
                // timeout, nothing was in flight.
                val started = System.currentTimeMillis()
                val n = conn.bulkTransfer(bulkIn, buf, filled, USB_MRU, READ_TIMEOUT_MS)
                if (n < 0) {
                    if (System.currentTimeMillis() - started >= READ_TIMEOUT_MS - 100) continue
                    close("unplugged")
                    return
                }
                filled += n
                var at = 0
                while (filled - at >= HEADER) {
                    val b = ByteBuffer.wrap(buf, at, filled - at)
                    val proto = b.int
                    val len = b.int
                    if (len < HEADER || len > MAX_PACKET) {
                        close("bad usbmux packet")
                        return
                    }
                    if (filled - at < len) break
                    b.int // magic
                    b.short // device's packet sequence
                    rxSeq = b.short.toInt() and 0xFFFF
                    if (proto == PROTO_TCP) onTcp(buf, at + HEADER, len - HEADER)
                    at += len
                }
                if (at > 0) {
                    System.arraycopy(buf, at, buf, 0, filled - at)
                    filled -= at
                }
            }
        } catch (e: Exception) {
            close("usb read failed")
        }
    }

    private fun onTcp(buf: ByteArray, off: Int, len: Int) {
        if (len < TCP_HEADER) return
        val b = ByteBuffer.wrap(buf, off, len)
        b.short // the iPhone's port
        val to = b.short.toInt() and 0xFFFF
        val seq = b.int
        val ack = b.int
        val dataOffset = ((b.get().toInt() and 0xFF) shr 4) * 4
        val flags = b.get().toInt() and 0xFF
        val win = (b.short.toInt() and 0xFFFF) shl 8
        val c = connections[to] ?: return
        if (dataOffset < TCP_HEADER || dataOffset > len) return
        c.onPacket(flags, seq, ack, win, buf, off + dataOffset, len - dataOffset)
    }

    /** One connection to a port on the iPhone. */
    inner class MuxConnection(
        val sport: Int,
        val dport: Int,
        private val onData: (ByteArray) -> Unit,
        private val onClose: () -> Unit,
    ) {
        val connected = CountDownLatch(1)
        val ackQueued = AtomicBoolean(false)
        private val lock = Object()
        private val closed = AtomicBoolean(false)
        @Volatile private var open = false

        // Our side: next sequence number to send, and what the iPhone has
        // acknowledged and allows (its window). [wireSeq]: end of what the
        // writer has sent, for pure acks.
        @Volatile var wireSeq = 1
        private var seq = 0
        private var peerAck = 0
        private var peerWindow = 0

        // Their side: next byte we expect, and bytes received but not yet
        // consumed (taken out of our window until [consumed]).
        @Volatile private var ackNo = 0
        private var buffered = 0
        private var advertised = WINDOW

        val isOpen: Boolean get() = open && !closed.get()

        /** The TCP header for [flags], [dataLen] bytes to follow, from [at]. */
        fun header(flags: Int, dataLen: Int, at: Int): ByteArray {
            val window = synchronized(lock) {
                advertised = (WINDOW - buffered).coerceAtLeast(0)
                advertised
            }
            return ByteBuffer.allocate(TCP_HEADER + dataLen)
                .putShort(sport.toShort()).putShort(dport.toShort())
                .putInt(at)
                .putInt(ackNo)
                .put(0x50.toByte()).put(flags.toByte())
                .putShort((window shr 8).coerceAtMost(0xFFFF).toShort())
                .putShort(0).putShort(0)
                .array()
        }

        fun onPacket(flags: Int, theirSeq: Int, theirAck: Int, win: Int, buf: ByteArray, off: Int, len: Int) {
            if (flags and TH_RST != 0) {
                drop()
                return
            }
            synchronized(lock) {
                peerAck = theirAck
                peerWindow = win
                lock.notifyAll()
            }
            if (!open) {
                if (flags and (TH_SYN or TH_ACK) == (TH_SYN or TH_ACK)) {
                    synchronized(lock) { seq = 1 }
                    ackNo = theirSeq + 1
                    open = true
                    enqueue(Out.Packet(PROTO_TCP, header(TH_ACK, 0, 1)))
                    connected.countDown()
                }
                return
            }
            if (len <= 0) return
            synchronized(lock) { buffered += len }
            ackNo += len
            onData(buf.copyOfRange(off, off + len))
            queueAck()
        }

        /** [n] received bytes left this side; opens the window again. */
        fun consumed(n: Int) {
            val reopen = synchronized(lock) {
                buffered -= n
                // Tell the iPhone when the window it knows is under half.
                advertised < WINDOW / 2
            }
            if (reopen) queueAck()
        }

        private fun queueAck() {
            if (ackQueued.compareAndSet(false, true)) enqueue(Out.Ack(this))
        }

        /** Sends [len] bytes, waiting for room in the iPhone's window. */
        fun write(data: ByteArray, len: Int) {
            var at = 0
            while (at < len) {
                val n: Int
                val body: ByteArray
                val start: Int
                synchronized(lock) {
                    while (isOpen && peerWindow - (seq - peerAck) <= 0) lock.wait(1000)
                    if (!isOpen) throw IOException("closed")
                    n = minOf(MAX_PAYLOAD, len - at, peerWindow - (seq - peerAck))
                    start = seq
                    seq += n
                    body = header(TH_ACK, n, start)
                }
                System.arraycopy(data, at, body, TCP_HEADER, n)
                enqueue(Out.Packet(PROTO_TCP, body, this, start + n))
                at += n
            }
        }

        /** Ends the connection from this side. */
        fun reset() {
            if (open && !closed.get()) {
                // After every queued data packet, so it carries their end.
                val end = synchronized(lock) { seq }
                enqueue(Out.Packet(PROTO_TCP, header(TH_RST, 0, end)))
            }
            drop()
        }

        /** Forgets the connection; [onClose] runs once. */
        fun drop() {
            if (!closed.compareAndSet(false, true)) return
            connections.remove(sport, this)
            connected.countDown()
            synchronized(lock) { lock.notifyAll() }
            onClose()
        }
    }

    companion object {
        const val PROTO_VERSION = 0
        const val PROTO_SETUP = 2
        const val PROTO_TCP = 6
        const val MAGIC = 0xfeedface.toInt()
        const val HEADER = 16
        const val TCP_HEADER = 20
        const val TH_SYN = 0x02
        const val TH_RST = 0x04
        const val TH_ACK = 0x10

        /** usbmuxd's USB_MTU for what the host sends. */
        const val MAX_PAYLOAD = 3 * 16384 - HEADER - TCP_HEADER

        /** Receive window per connection. */
        const val WINDOW = 512 * 1024
        const val MAX_PACKET = 256 * 1024
        const val USB_MRU = 16384
        const val READ_BUFFER = MAX_PACKET + USB_MRU
        const val READ_TIMEOUT_MS = 1000
        const val USB_TIMEOUT_MS = 5000
        const val HANDSHAKE_TIMEOUT_MS = 3000L

        /**
         * Claims [intf] (the usbmux interface: class 255, subclass 254,
         * protocol 2), does the version 2 handshake and starts the
         * threads. Throws [IOException] with a short reason.
         */
        fun open(conn: UsbDeviceConnection, intf: UsbInterface, onDead: (String) -> Unit): UsbMux {
            val eps = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                .filter { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK }
            val bulkOut = eps.firstOrNull { it.direction == UsbConstants.USB_DIR_OUT } ?: throw IOException("no bulk out")
            val bulkIn = eps.firstOrNull { it.direction == UsbConstants.USB_DIR_IN } ?: throw IOException("no bulk in")
            handshake(conn, bulkIn, bulkOut)
            val mux = UsbMux(conn, bulkIn, bulkOut, onDead)
            // SETUP restarts the packet sequence numbers (usbmuxd).
            mux.txSeq = 0
            mux.rxSeq = 0xFFFF
            mux.sendPacket(PROTO_SETUP, byteArrayOf(7))
            mux.start()
            return mux
        }

        /** Sends VERSION 2 and waits for the device's answer. */
        private fun handshake(conn: UsbDeviceConnection, bulkIn: UsbEndpoint, bulkOut: UsbEndpoint) {
            // Before the version is agreed, the header has 8 bytes.
            val req = ByteBuffer.allocate(20).putInt(PROTO_VERSION).putInt(20)
                .putInt(2).putInt(0).putInt(0).array()
            if (conn.bulkTransfer(bulkOut, req, req.size, USB_TIMEOUT_MS) != req.size) throw IOException("handshake send")
            val buf = ByteArray(USB_MRU)
            val deadline = System.currentTimeMillis() + HANDSHAKE_TIMEOUT_MS
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) throw IOException("no handshake answer")
                val n = conn.bulkTransfer(bulkIn, buf, buf.size, left.toInt())
                if (n < 12) continue
                val b = ByteBuffer.wrap(buf, 0, n)
                if (b.int != PROTO_VERSION) continue
                b.int // length
                val major = b.int
                if (major < 2) throw IOException("usbmux version $major")
                return
            }
        }
    }
}
