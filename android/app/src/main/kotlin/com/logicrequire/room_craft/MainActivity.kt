package com.logicrequire.room_craft

import android.app.Activity
import android.content.Intent
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter bridge for ARCore guided room measure.
 *
 * Channel: com.logicrequire.room_craft/ar_measure
 * Methods:
 *  - isAvailable → { supported, installNeeded, message }
 *  - measureRoom({ mode: "quick"|"chain" }) → launches AR UI
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.logicrequire.room_craft/ar_measure"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(checkArCore())
                    "measureRoom" -> {
                        val mode = call.argument<String>("mode") ?: ArMeasureActivity.MODE_QUICK
                        launchMeasure(result, mode)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkArCore(): Map<String, Any> {
        return try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)
            when {
                availability.isTransient -> mapOf(
                    "supported" to false,
                    "installNeeded" to true,
                    "message" to "Checking ARCore… try again in a moment",
                )
                availability.isSupported -> {
                    val install = ArCoreApk.getInstance().requestInstall(this, true)
                    if (install == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                        mapOf(
                            "supported" to true,
                            "installNeeded" to true,
                            "message" to "Install or update Google Play Services for AR",
                        )
                    } else {
                        mapOf(
                            "supported" to true,
                            "installNeeded" to false,
                            "message" to "ARCore ready",
                        )
                    }
                }
                else -> mapOf(
                    "supported" to false,
                    "installNeeded" to false,
                    "message" to "This device does not support ARCore",
                )
            }
        } catch (e: UnavailableException) {
            mapOf(
                "supported" to false,
                "installNeeded" to false,
                "message" to (e.message ?: "ARCore unavailable"),
            )
        } catch (e: Exception) {
            mapOf(
                "supported" to false,
                "installNeeded" to false,
                "message" to (e.message ?: "AR check failed"),
            )
        }
    }

    private fun launchMeasure(result: MethodChannel.Result, mode: String) {
        if (pendingResult != null) {
            result.error("BUSY", "AR measure already in progress", null)
            return
        }
        val status = checkArCore()
        if (status["supported"] != true) {
            result.error("UNSUPPORTED", status["message"] as? String ?: "AR not supported", status)
            return
        }
        pendingResult = result
        val intent = Intent(this, ArMeasureActivity::class.java).apply {
            putExtra(ArMeasureActivity.EXTRA_MODE, mode)
        }
        startActivityForResult(intent, ArMeasureActivity.REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != ArMeasureActivity.REQUEST_CODE) return
        val pending = pendingResult
        pendingResult = null
        if (pending == null) return

        if (resultCode == Activity.RESULT_OK && data != null) {
            val widthFt = data.getDoubleExtra(ArMeasureActivity.EXTRA_WIDTH_FT, 0.0)
            val lengthFt = data.getDoubleExtra(ArMeasureActivity.EXTRA_LENGTH_FT, 0.0)
            val widthM = data.getDoubleExtra(ArMeasureActivity.EXTRA_WIDTH_M, 0.0)
            val lengthM = data.getDoubleExtra(ArMeasureActivity.EXTRA_LENGTH_M, 0.0)
            val mode = data.getStringExtra(ArMeasureActivity.EXTRA_MODE) ?: ArMeasureActivity.MODE_QUICK
            val wallsFt = data.getDoubleArrayExtra(ArMeasureActivity.EXTRA_WALLS_FT)?.toList() ?: emptyList()
            val wallsM = data.getDoubleArrayExtra(ArMeasureActivity.EXTRA_WALLS_M)?.toList() ?: emptyList()
            pending.success(
                mapOf(
                    "widthFt" to widthFt,
                    "lengthFt" to lengthFt,
                    "widthM" to widthM,
                    "lengthM" to lengthM,
                    "mode" to mode,
                    "wallsFt" to wallsFt,
                    "wallsM" to wallsM,
                    "source" to "arcore",
                ),
            )
        } else {
            pending.error("CANCELLED", "User cancelled AR measure", null)
        }
    }
}
