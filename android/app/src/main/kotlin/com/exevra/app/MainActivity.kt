package com.exevra.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI. Extends [FlutterFragmentActivity] because local_auth
 * needs a FragmentActivity for the biometric prompt.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Any>("enabled")
                        if (enabled !is Boolean) {
                            result.error(
                                "invalid_argument",
                                "setSecure expects a boolean 'enabled' argument.",
                                null,
                            )
                        } else {
                            runOnUiThread {
                                setSecure(enabled)
                                result.success(null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Hides the window from screenshots, screen recording and the recents preview. */
    private fun setSecure(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private companion object {
        const val SECURE_WINDOW_CHANNEL = "exevra/secure_window"
    }
}
