package com.example.crossdrop

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.SoftApConfiguration
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel `crossdrop/hotspot` (Dart side: lib/platform/hotspot.dart).
 *
 * Starts a LocalOnlyHotspot (ARCHITECTURE.md, scenario 4): a Wi-Fi network
 * with a random name and password and no internet, for the iPhone to join.
 *
 * - `start` -> `{ssid, password, security}`, after asking for the
 *   permission if needed. Errors: `permission`, `location_off`,
 *   `tethering_on`, `no_channel`, `disallowed`, `unsupported_security`,
 *   `failed`.
 * - `stop` closes the reservation; the system tears the hotspot down when
 *   no app holds one.
 * - Native to Dart `stopped` when the user or the system stops it.
 *
 * Permissions: Android 13+ NEARBY_WIFI_DEVICES (neverForLocation);
 * Android 10-12 ACCESS_FINE_LOCATION (with COARSE, as Android 12 needs
 * both in one request). The name and password are never logged.
 */
class HotspotChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "crossdrop/hotspot")
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val main = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun permissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            )
        }

    private fun hasPermission(): Boolean =
        permissions().all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun start(result: MethodChannel.Result) {
        if (pendingStart != null || pendingPermission != null) {
            result.error("busy", null, null)
            return
        }
        if (hasPermission()) {
            startGranted(result)
        } else {
            pendingPermission = result
            activity.requestPermissions(permissions(), REQUEST_CODE)
        }
    }

    /** Forwarded from MainActivity. True if it was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        if (hasPermission()) startGranted(result) else result.error("permission", null, null)
        return true
    }

    private fun startGranted(result: MethodChannel.Result) {
        // Before Android 13 the hotspot needs location services on, or it
        // throws a SecurityException.
        if (Build.VERSION.SDK_INT < 33 && !locationOn()) {
            result.error("location_off", null, null)
            return
        }
        // Only one request per app: close a leftover one first.
        reservation?.close()
        reservation = null
        pendingStart = result
        val timeout = Runnable { finishStart(error = "failed") }
        main.postDelayed(timeout, START_TIMEOUT_MS)
        try {
            wifi.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                        main.removeCallbacks(timeout)
                        val info = describe(r)
                        if (pendingStart == null) {
                            r.close() // Timed out meanwhile.
                            return
                        }
                        if (info == null) {
                            r.close()
                            finishStart(error = "unsupported_security")
                        } else {
                            reservation = r
                            finishStart(value = info)
                        }
                    }

                    override fun onStopped() {
                        main.removeCallbacks(timeout)
                        reservation = null
                        if (pendingStart != null) {
                            finishStart(error = "failed")
                        } else {
                            channel.invokeMethod("stopped", null)
                        }
                    }

                    override fun onFailed(reason: Int) {
                        main.removeCallbacks(timeout)
                        finishStart(error = failure(reason))
                    }
                },
                main,
            )
        } catch (e: SecurityException) {
            main.removeCallbacks(timeout)
            finishStart(error = if (hasPermission()) "location_off" else "permission")
        } catch (e: IllegalStateException) {
            // "Caller already has an active LocalOnlyHotspot request".
            main.removeCallbacks(timeout)
            finishStart(error = "failed")
        }
    }

    private fun finishStart(value: Map<String, String>? = null, error: String? = null) {
        val result = pendingStart ?: return
        pendingStart = null
        if (error != null) result.error(error, null, null) else result.success(value)
    }

    fun stop() {
        reservation?.close()
        reservation = null
    }

    private fun locationOn(): Boolean {
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isLocationEnabled
    }

    private fun failure(reason: Int): String = when (reason) {
        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE -> "tethering_on"
        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "no_channel"
        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED -> "disallowed"
        else -> "failed"
    }

    /** Name, password and security; null for open networks. */
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String>? =
        if (Build.VERSION.SDK_INT >= 30) describe(r.softApConfiguration) else describeLegacy(r)

    private fun describe(c: SoftApConfiguration): Map<String, String>? {
        val ssid = if (Build.VERSION.SDK_INT >= 33) {
            c.wifiSsid?.bytes?.let { String(it, Charsets.UTF_8) }
        } else {
            @Suppress("DEPRECATION")
            c.ssid
        }
        val password = c.passphrase
        val security = when (c.securityType) {
            SoftApConfiguration.SECURITY_TYPE_WPA2_PSK -> "wpa2"
            SoftApConfiguration.SECURITY_TYPE_WPA3_SAE_TRANSITION -> "wpa3t"
            SoftApConfiguration.SECURITY_TYPE_WPA3_SAE -> "wpa3"
            else -> null
        }
        if (ssid == null || password == null || security == null) return null
        return mapOf("ssid" to ssid, "password" to password, "security" to security)
    }

    @Suppress("DEPRECATION")
    private fun describeLegacy(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String>? {
        val c: WifiConfiguration = r.wifiConfiguration ?: return null
        val ssid = c.SSID?.let(::unquote) ?: return null
        val password = c.preSharedKey?.let(::unquote) ?: return null
        return mapOf("ssid" to ssid, "password" to password, "security" to "wpa2")
    }

    private fun unquote(s: String): String =
        if (s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) s.substring(1, s.length - 1) else s

    companion object {
        private const val REQUEST_CODE = 7301
        private const val START_TIMEOUT_MS = 20_000L
    }
}
