package com.example.crossdrop

import android.content.Intent
import android.net.Uri
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
