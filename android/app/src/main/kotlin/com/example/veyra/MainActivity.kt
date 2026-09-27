package com.example.veyra

import com.example.veyra.e2ee.E2eeBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        E2eeBridge(this, flutterEngine.dartExecutor.binaryMessenger).register()
    }
}
