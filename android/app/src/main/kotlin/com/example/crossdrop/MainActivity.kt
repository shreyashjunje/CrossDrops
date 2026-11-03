package com.example.crossdrop

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var source: SourceChannel? = null
    private var save: SaveChannel? = null
    private var share: ShareChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        source = SourceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        save = SaveChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        share = ShareChannel(this, flutterEngine.dartExecutor.binaryMessenger)
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

    // FlutterActivity is not a ComponentActivity, so the document picker
    // uses the classic result callback.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (source?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
