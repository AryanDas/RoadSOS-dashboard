package com.example.roadsos

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.roadsos/sensors"
        private var channelInstance: MethodChannel? = null

        fun sendFeaturesToFlutter(features: FloatArray) {
            val list = features.toList()
            channelInstance?.invokeMethod("onSensorUpdate", list)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channelInstance?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensorService" -> {
                    startSensorService()
                    result.success("Sensor Foreground Service Started Successfully.")
                }
                "stopSensorService" -> {
                    stopSensorService()
                    result.success("Sensor Foreground Service Stopped.")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startSensorService() {
        val intent = Intent(this, SensorService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopSensorService() {
        val intent = Intent(this, SensorService::class.java)
        stopService(intent)
    }
}
