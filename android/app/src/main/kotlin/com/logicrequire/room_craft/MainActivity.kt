package com.logicrequire.room_craft

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter bridge for ARCore guided room measure.
 * Crash-safe: never throws into Flutter; permission + AR install handled carefully.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.logicrequire.room_craft/ar_measure"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingMode: String = ArMeasureActivity.MODE_QUICK
    private var pendingPlace: Boolean = false
    private var pendingWidthFt: Double = 12.0
    private var pendingLengthFt: Double = 12.0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isAvailable" -> result.success(checkArCore(requestInstall = false))
                        "measureRoom" -> {
                            val mode = call.argument<String>("mode")
                                ?: ArMeasureActivity.MODE_QUICK
                            launchMeasure(result, mode)
                        }
                        "placeFurniture" -> {
                            val w = call.argument<Double>("widthFt") ?: 12.0
                            val l = call.argument<Double>("lengthFt") ?: 12.0
                            launchPlace(result, w, l)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("AR_ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }

    /**
     * @param requestInstall when true, may prompt user to install AR services
     *   (only call when user starts a measure, not on status probes).
     */
    private fun checkArCore(requestInstall: Boolean): Map<String, Any> {
        return try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)
            when {
                availability.isTransient -> mapOf(
                    "supported" to false,
                    "installNeeded" to true,
                    "message" to "Checking ARCore… try again in a moment",
                )
                availability.isSupported -> {
                    if (requestInstall) {
                        try {
                            val install = ArCoreApk.getInstance()
                                .requestInstall(this, /*userRequestedInstall=*/true)
                            if (install == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                                return mapOf(
                                    "supported" to true,
                                    "installNeeded" to true,
                                    "message" to "Install or update Google Play Services for AR, then try again",
                                )
                            }
                        } catch (e: Exception) {
                            return mapOf(
                                "supported" to false,
                                "installNeeded" to true,
                                "message" to (e.message ?: "AR install check failed"),
                            )
                        }
                    }
                    mapOf(
                        "supported" to true,
                        "installNeeded" to false,
                        "message" to "ARCore ready",
                    )
                }
                else -> mapOf(
                    "supported" to false,
                    "installNeeded" to false,
                    "message" to "This device does not support ARCore — use Easy photo/video scan",
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

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun launchMeasure(result: MethodChannel.Result, mode: String) {
        if (pendingResult != null) {
            result.error("BUSY", "AR measure already in progress", null)
            return
        }

        val status = checkArCore(requestInstall = true)
        if (status["supported"] != true) {
            result.error(
                "UNSUPPORTED",
                status["message"] as? String ?: "AR not supported",
                status,
            )
            return
        }
        if (status["installNeeded"] == true) {
            result.error(
                "INSTALL_NEEDED",
                status["message"] as? String ?: "Install AR services first",
                status,
            )
            return
        }

        if (!hasCameraPermission()) {
            pendingResult = result
            pendingMode = mode
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA,
            )
            return
        }

        startArActivity(result, mode)
    }

    private fun startArActivity(result: MethodChannel.Result, mode: String) {
        try {
            pendingResult = result
            pendingPlace = false
            val intent = Intent(this, ArMeasureActivity::class.java).apply {
                putExtra(ArMeasureActivity.EXTRA_MODE, mode)
            }
            startActivityForResult(intent, ArMeasureActivity.REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult = null
            result.error(
                "LAUNCH_FAILED",
                e.message ?: "Could not open AR measure",
                null,
            )
        }
    }

    private fun launchPlace(result: MethodChannel.Result, widthFt: Double, lengthFt: Double) {
        if (pendingResult != null) {
            result.error("BUSY", "AR already in progress", null)
            return
        }

        val status = checkArCore(requestInstall = true)
        if (status["supported"] != true) {
            result.error(
                "UNSUPPORTED",
                status["message"] as? String ?: "AR not supported",
                status,
            )
            return
        }
        if (status["installNeeded"] == true) {
            result.error(
                "INSTALL_NEEDED",
                status["message"] as? String ?: "Install AR services first",
                status,
            )
            return
        }

        if (!hasCameraPermission()) {
            pendingResult = result
            pendingPlace = true
            pendingWidthFt = widthFt
            pendingLengthFt = lengthFt
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA,
            )
            return
        }

        startPlaceActivity(result, widthFt, lengthFt)
    }

    private fun startPlaceActivity(
        result: MethodChannel.Result,
        widthFt: Double,
        lengthFt: Double,
    ) {
        try {
            pendingResult = result
            pendingPlace = true
            pendingWidthFt = widthFt
            pendingLengthFt = lengthFt
            val intent = Intent(this, ArPlaceActivity::class.java).apply {
                putExtra(ArPlaceActivity.EXTRA_WIDTH_FT, widthFt)
                putExtra(ArPlaceActivity.EXTRA_LENGTH_FT, lengthFt)
            }
            startActivityForResult(intent, ArPlaceActivity.REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult = null
            pendingPlace = false
            result.error(
                "LAUNCH_FAILED",
                e.message ?: "Could not open AR place",
                null,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CAMERA) return
        val pending = pendingResult
        if (pending == null) return

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            val place = pendingPlace
            val w = pendingWidthFt
            val l = pendingLengthFt
            val mode = pendingMode
            pendingResult = null
            pendingPlace = false
            if (place) {
                startPlaceActivity(pending, w, l)
            } else {
                startArActivity(pending, mode)
            }
        } else {
            pendingResult = null
            pendingPlace = false
            pending.error(
                "PERMISSION",
                "Camera permission is required for AR",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val pending = pendingResult
        if (pending == null) return

        if (requestCode == ArPlaceActivity.REQUEST_CODE) {
            pendingResult = null
            pendingPlace = false
            try {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    @Suppress("UNCHECKED_CAST")
                    val raw = data.getSerializableExtra(ArPlaceActivity.EXTRA_PLACEMENTS)
                        as? ArrayList<HashMap<String, Any>>
                    pending.success(
                        mapOf(
                            "placements" to (raw ?: emptyList<HashMap<String, Any>>()),
                            "source" to "arcore_place",
                        ),
                    )
                } else {
                    pending.error("CANCELLED", "User cancelled AR place", null)
                }
            } catch (e: Exception) {
                pending.error("AR_ERROR", e.message ?: "Bad AR place result", null)
            }
            return
        }

        if (requestCode != ArMeasureActivity.REQUEST_CODE) return
        pendingResult = null
        pendingPlace = false

        try {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val widthFt = data.getDoubleExtra(ArMeasureActivity.EXTRA_WIDTH_FT, 0.0)
                val lengthFt = data.getDoubleExtra(ArMeasureActivity.EXTRA_LENGTH_FT, 0.0)
                val widthM = data.getDoubleExtra(ArMeasureActivity.EXTRA_WIDTH_M, 0.0)
                val lengthM = data.getDoubleExtra(ArMeasureActivity.EXTRA_LENGTH_M, 0.0)
                val mode = data.getStringExtra(ArMeasureActivity.EXTRA_MODE)
                    ?: ArMeasureActivity.MODE_QUICK
                val wallsFt =
                    data.getDoubleArrayExtra(ArMeasureActivity.EXTRA_WALLS_FT)?.toList()
                        ?: emptyList()
                val wallsM =
                    data.getDoubleArrayExtra(ArMeasureActivity.EXTRA_WALLS_M)?.toList()
                        ?: emptyList()
                // +123/+124 multi-dot corners (flat x,y,z meters)
                val cornersFlat =
                    data.getFloatArrayExtra(ArMeasureActivity.EXTRA_CORNERS_M)?.map {
                        it.toDouble()
                    } ?: emptyList()
                val orthoScore =
                    data.getDoubleExtra(ArMeasureActivity.EXTRA_ORTHO_SCORE, 0.0)
                val diagError =
                    data.getDoubleExtra(ArMeasureActivity.EXTRA_DIAG_ERROR, 0.0)
                val coverageScore =
                    data.getDoubleExtra(ArMeasureActivity.EXTRA_COVERAGE_SCORE, 0.0)
                pending.success(
                    mapOf(
                        "widthFt" to widthFt,
                        "lengthFt" to lengthFt,
                        "widthM" to widthM,
                        "lengthM" to lengthM,
                        "mode" to mode,
                        "wallsFt" to wallsFt,
                        "wallsM" to wallsM,
                        "cornersM" to cornersFlat,
                        "orthogonalScore" to orthoScore,
                        "diagonalError" to diagError,
                        "coverageScore" to coverageScore,
                        "source" to "arcore",
                    ),
                )
            } else {
                val err = data?.getStringExtra(ArMeasureActivity.EXTRA_ERROR)
                if (err != null) {
                    pending.error("AR_FAILED", err, null)
                } else {
                    pending.error("CANCELLED", "User cancelled AR measure", null)
                }
            }
        } catch (e: Exception) {
            pending.error("AR_ERROR", e.message ?: "Bad AR result", null)
        }
    }

    companion object {
        private const val REQUEST_CAMERA = 7143
    }
}
