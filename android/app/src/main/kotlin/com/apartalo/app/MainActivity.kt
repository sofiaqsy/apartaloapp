package com.apartalo.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.apartalo/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getManufacturer" -> {
                    result.success(Build.MANUFACTURER)
                }
                "getModel" -> {
                    result.success(Build.MODEL)
                }
                "isSunmi" -> {
                    val isSunmi = Build.MANUFACTURER.lowercase().contains("sunmi")
                    result.success(isSunmi)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
