package com.example.crossdrop

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Platform channel `crossdrop/network` (Dart side: lib/platform/network.dart).
 *
 * - `interfaces` -> list of `{name, ip, prefix}` for every IPv4 address,
 *   including the hotspot's, which ConnectivityManager does not list.
 * - `wifiState` -> `{connected, validated, isDefault, bound, frequencyMhz,
 *   linkMbps}`; native to Dart `wifiChanged` with the same map.
 * - `bind {wifi}` -> binds the whole process to the Wi-Fi network, or
 *   clears the binding. True on success.
 *
 * Why the whole process: `dart:io` creates its own sockets, so
 * `Network.getSocketFactory()` cannot be used. CrossDrop makes no calls
 * outside the local network (CLAUDE.md hard rule 8), so nothing else is
 * affected. The decision to bind is made in Dart (D-056).
 */
class NetworkChannel(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "crossdrop/network")
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())
    private var wifiNetwork: Network? = null
    private var wifiCaps: NetworkCapabilities? = null
    private var bound = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            main.post {
                wifiNetwork = network
                wifiCaps = caps
                report()
            }
        }

        override fun onLost(network: Network) {
            main.post {
                if (network == wifiNetwork) {
                    wifiNetwork = null
                    wifiCaps = null
                    // A binding to a lost network makes every new socket
                    // fail; clear it at once.
                    if (bound) {
                        cm.bindProcessToNetwork(null)
                        bound = false
                    }
                    report()
                }
            }
        }
    }

    // The default network changes (Wi-Fi <-> mobile data) without a Wi-Fi
    // capability change.
    private val defaultCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            main.post { report() }
        }

        override fun onLost(network: Network) {
            main.post { report() }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "interfaces" -> result.success(interfaces())
                "wifiState" -> result.success(wifiState())
                "bind" -> result.success(bind(call.argument<Boolean>("wifi") == true))
                else -> result.notImplemented()
            }
        }
        cm.registerNetworkCallback(
            NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(),
            callback,
        )
        cm.registerDefaultNetworkCallback(defaultCallback)
    }

    fun dispose() {
        cm.unregisterNetworkCallback(callback)
        cm.unregisterNetworkCallback(defaultCallback)
    }

    private fun report() {
        channel.invokeMethod("wifiChanged", wifiState())
    }

    private fun wifiState(): Map<String, Any?> {
        val caps = wifiCaps
        val network = wifiNetwork
        val info = caps?.transportInfo as? WifiInfo
        return mapOf(
            "connected" to (network != null),
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "isDefault" to (network != null && cm.activeNetwork == network),
            "bound" to bound,
            "frequencyMhz" to info?.frequency?.takeIf { it > 0 },
            "linkMbps" to info?.linkSpeed?.takeIf { it > 0 },
        )
    }

    private fun bind(wifi: Boolean): Boolean {
        val target = if (wifi) wifiNetwork ?: return false else null
        val ok = cm.bindProcessToNetwork(target)
        bound = ok && wifi
        return ok
    }

    private fun interfaces(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val all = try {
            NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        for (i in all) {
            for (a in i.interfaceAddresses) {
                val ip = a.address as? Inet4Address ?: continue
                out.add(
                    mapOf(
                        "name" to i.name,
                        "ip" to (ip.hostAddress ?: continue),
                        "prefix" to a.networkPrefixLength.toInt(),
                    ),
                )
            }
        }
        return out
    }
}
