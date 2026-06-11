package com.example.smart_helmet

import android.content.Context
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "smart_helmet/telephony"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSimState") {
                    val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    // SIM_STATE_READY=5, ABSENT=1, PIN_REQUIRED=2, ...
                    result.success(tm.simState)
                } else {
                    result.notImplemented()
                }
            }
    }
}
