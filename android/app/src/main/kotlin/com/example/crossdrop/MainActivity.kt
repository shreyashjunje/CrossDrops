package com.example.crossdrop

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var source: SourceChannel? = null
    private var save: SaveChannel? = null
    private var share: ShareChannel? = null
    private var hotspot: HotspotChannel? = null
    private var network: NetworkChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        source = SourceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        save = SaveChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        share = ShareChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        hotspot = HotspotChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        network = NetworkChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // Dart side: lib/platform/local_network.dart. Android has no Local
        // Network permission, so `probe` always answers "granted".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crossdrop/local_network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probe" -> result.success("granted")
                    "openSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crossdrop/open")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> result.success(openSaved(call.argument<String>("location")))
                    else -> result.notImplemented()
                }
            }
        // Dart side: lib/platform/free_space.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crossdrop/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path missing", null)
                        } else {
                            try {
                                // The folder may not exist yet; ask for its
                                // nearest existing parent (same volume).
                                var dir: File? = File(path)
                                while (dir != null && !dir.exists()) dir = dir.parentFile
                                result.success(StatFs((dir ?: File("/")).path).availableBytes)
                            } catch (e: IllegalArgumentException) {
                                result.error("statfs_failed", null, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // `crossdrop/open` (Dart side: lib/platform/open_file.dart, D-051).
    // `open {location}` -> true if a viewer was started. Only MediaStore
    // URIs, where received files are saved; anything else is refused.
    private fun openSaved(location: String?): Boolean {
        val uri = location?.let(Uri::parse) ?: return false
        if (uri.scheme != "content" || uri.authority != MediaStore.AUTHORITY) return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, contentResolver.getType(uri))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState) // runs configureFlutterEngine
        // A recreated activity (rotation, process restore) already had it.
        if (savedInstanceState == null) share?.handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        share?.handle(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (hotspot?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The hotspot and the network binding belong to this engine.
        hotspot?.stop()
        network?.dispose()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // FlutterActivity is not a ComponentActivity, so the document picker
    // uses the classic result callback.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (source?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
