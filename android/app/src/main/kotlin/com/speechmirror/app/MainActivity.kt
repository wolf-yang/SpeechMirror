package com.speechmirror.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OverlayFlutterChannel.install(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
