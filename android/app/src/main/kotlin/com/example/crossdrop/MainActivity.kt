package com.example.crossdrop

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
