package com.example.tensorflow_demo

import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.flare/display")
            .setMethodCallHandler { call, result ->
                if (call.method == "getRotation") {
                    @Suppress("DEPRECATION")
                    val rotation = (getSystemService(WINDOW_SERVICE) as WindowManager)
                        .defaultDisplay.rotation
                    // Surface.ROTATION_0=0, ROTATION_90=1, ROTATION_180=2, ROTATION_270=3
                    result.success(rotation)
                } else {
                    result.notImplemented()
                }
            }
    }
}
