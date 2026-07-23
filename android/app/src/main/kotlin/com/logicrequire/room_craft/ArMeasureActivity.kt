package com.logicrequire.room_craft

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.Config
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * AR room measure using SceneView [ARSceneView] (+122).
 *
 * Feedback a41da384 / e43505bf: custom GLSurfaceView camera stayed black.
 * SceneView owns Filament camera stream + ARCore session lifecycle.
 */
class ArMeasureActivity : AppCompatActivity() {

    private lateinit var arSceneView: ARSceneView
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveDistance: TextView
    private lateinit var measuredSummary: TextView
    private lateinit var btnMark: Button
    private lateinit var btnDone: Button
    private lateinit var btnUndo: Button

    private val wallMeters = mutableListOf<Double>()
    private var pendingStartPose: FloatArray? = null
    private var chainMode = false
    private var tapsInSegment = 0
    private var measuringDiagonal = false
    private var cameraReady = false
    private var uiTick = 0

    private val wallLabelsQuick = listOf("Width (Wall A)", "Length (Wall B)")
    private val wallLabelsChain = listOf(
        "Wall A (first width side)",
        "Wall B (first length side)",
        "Wall C (opposite width)",
        "Wall D (opposite length)",
    )
    private val totalWalls: Int get() = if (chainMode) 4 else 2

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setContentView(R.layout.activity_ar_measure)
            chainMode = intent.getStringExtra(EXTRA_MODE) == MODE_CHAIN

            arSceneView = findViewById(R.id.ar_scene_view)
            stepTitle = findViewById(R.id.step_title)
            stepHint = findViewById(R.id.step_hint)
            liveDistance = findViewById(R.id.live_distance)
            measuredSummary = findViewById(R.id.measured_summary)
            btnMark = findViewById(R.id.btn_mark)
            btnDone = findViewById(R.id.btn_done)
            btnUndo = findViewById(R.id.btn_undo)

            findViewById<Button>(R.id.btn_cancel).setOnClickListener {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
            btnUndo.setOnClickListener { undoLast() }
            btnDone.setOnClickListener { finishWithResult() }
            btnMark.setOnClickListener { markCenterHit() }

            // Wire SceneView lifecycle (creates session, camera stream)
            arSceneView.lifecycle = lifecycle
            arSceneView.planeRenderer.isEnabled = true
            arSceneView.planeRenderer.isVisible = true

            arSceneView.configureSession { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                config.instantPlacementMode = Config.InstantPlacementMode.DISABLED
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }

            arSceneView.onSessionCreated = {
                Log.i(TAG, "AR session created (SceneView)")
                runOnUiThread {
                    liveDistance.text = "Camera starting…"
                    liveDistance.setTextColor(0xFFFFCC80.toInt())
                }
            }

            arSceneView.onSessionResumed = {
                Log.i(TAG, "AR session resumed")
                runOnUiThread {
                    liveDistance.text = "Camera live · move phone to find floor"
                    liveDistance.setTextColor(0xFF80CBC4.toInt())
                    cameraReady = true
                }
            }

            arSceneView.onSessionFailed = { e ->
                Log.e(TAG, "AR session failed", e)
                runOnUiThread {
                    liveDistance.text = "AR failed: ${e.message}"
                    liveDistance.setTextColor(0xFFEF9A9A.toInt())
                    Toast.makeText(
                        this,
                        "AR failed: ${e.message}. Use Field measure or update Play Services for AR.",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }

            arSceneView.onSessionUpdated = { session, frame ->
                uiTick++
                val shouldUi = uiTick % 15 == 0 &&
                    !(wallMeters.size >= totalWalls && !measuringDiagonal) &&
                    pendingStartPose == null
                if (shouldUi) {
                    val cam = frame.camera.trackingState
                    var planes = 0
                    for (p in session.getAllTrackables(Plane::class.java)) {
                        if (p.trackingState == TrackingState.TRACKING) planes++
                    }
                    if (frame.timestamp != 0L && !cameraReady) {
                        cameraReady = true
                    }
                    runOnUiThread {
                        when (cam) {
                            TrackingState.TRACKING -> {
                                liveDistance.text = if (planes > 0) {
                                    "Tracking · $planes floor plane(s) — Mark ready"
                                } else {
                                    "Tracking · point at floor…"
                                }
                                liveDistance.setTextColor(0xFF80CBC4.toInt())
                            }
                            TrackingState.PAUSED -> {
                                liveDistance.text = "Tracking paused — move slowly"
                                liveDistance.setTextColor(0xFFFFAB91.toInt())
                            }
                            TrackingState.STOPPED -> {
                                liveDistance.text = "Tracking stopped"
                                liveDistance.setTextColor(0xFFEF9A9A.toInt())
                            }
                        }
                    }
                }
            }

            if (!hasCameraPermission()) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.CAMERA),
                    REQ_CAMERA,
                )
            }

            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            failAndFinish(e.message ?: "AR failed to start")
        }
    }

    override fun onDestroy() {
        try {
            if (::arSceneView.isInitialized) {
                arSceneView.destroy()
            }
        } catch (e: Exception) {
            Log.w(TAG, "destroy", e)
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA) {
            if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
                failAndFinish("Camera permission is required for AR measure")
            }
        }
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun failAndFinish(message: String) {
        try {
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        } catch (_: Exception) {
        }
        setResult(Activity.RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    private fun markCenterHit() {
        try {
            val frame = arSceneView.frame
            if (frame == null || frame.timestamp == 0L) {
                Toast.makeText(this, "Wait for live camera image first", Toast.LENGTH_SHORT).show()
                return
            }
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                Toast.makeText(
                    this,
                    "Move phone slowly until tracking is stable",
                    Toast.LENGTH_SHORT,
                ).show()
                return
            }

            // Prefer SceneView hit helper (horizontal plane at reticle)
            val hit: HitResult? = arSceneView.hitTestAR(
                planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING),
                planePoseInPolygon = true,
            ) ?: arSceneView.hitTestAR(
                planeTypes = setOf(
                    Plane.Type.HORIZONTAL_UPWARD_FACING,
                    Plane.Type.HORIZONTAL_DOWNWARD_FACING,
                    Plane.Type.VERTICAL,
                ),
                planePoseInPolygon = false,
            ) ?: run {
                // Fallback raw hit test at view center
                val cx = arSceneView.width / 2f
                val cy = arSceneView.height / 2f
                frame.hitTest(cx, cy).firstOrNull()
            }

            if (hit == null) {
                Toast.makeText(
                    this,
                    "No floor at center — wait for plane grid, then Mark",
                    Toast.LENGTH_LONG,
                ).show()
                return
            }

            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            if (measuringDiagonal) {
                handleDiagonalPoint(xyz)
            } else {
                handleWallPoint(xyz)
            }
        } catch (e: Exception) {
            Log.e(TAG, "mark", e)
            Toast.makeText(this, "Measure failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleWallPoint(xyz: FloatArray) {
        if (wallMeters.size >= totalWalls) return
        tapsInSegment++
        if (tapsInSegment == 1) {
            pendingStartPose = xyz
            liveDistance.text = "Corner 1 set — mark other end"
            liveDistance.setTextColor(0xFF80CBC4.toInt())
            Toast.makeText(this, "Corner 1 set", Toast.LENGTH_SHORT).show()
            updateUi()
        } else {
            val start = pendingStartPose
            if (start == null) {
                tapsInSegment = 0
                return
            }
            val dist = distance(start, xyz)
            if (dist < 0.4) {
                Toast.makeText(this, "Too short — mark corners further apart", Toast.LENGTH_SHORT).show()
                tapsInSegment = 0
                pendingStartPose = null
                return
            }
            wallMeters.add(dist)
            tapsInSegment = 0
            pendingStartPose = null
            val label = labels().getOrElse(wallMeters.size - 1) { "Wall" }
            Toast.makeText(
                this,
                String.format("%s: %.2f m (%.1f ft)", label, dist, dist * M_TO_FT),
                Toast.LENGTH_SHORT,
            ).show()
            if (wallMeters.size >= totalWalls) {
                measuringDiagonal = true
                Toast.makeText(
                    this,
                    "Optional diagonal, or Use measurements",
                    Toast.LENGTH_LONG,
                ).show()
            }
            updateUi()
        }
    }

    private fun handleDiagonalPoint(xyz: FloatArray) {
        tapsInSegment++
        if (tapsInSegment == 1) {
            pendingStartPose = xyz
            liveDistance.text = "Diagonal corner 1 — mark opposite"
        } else {
            val start = pendingStartPose ?: xyz
            val dist = distance(start, xyz)
            tapsInSegment = 0
            pendingStartPose = null
            measuringDiagonal = false
            applyDiagonalScale(dist)
            updateUi()
        }
    }

    private fun applyDiagonalScale(diagM: Double) {
        val w = resolvedWidthM() ?: return
        val l = resolvedLengthM() ?: return
        val expected = sqrt(w * w + l * l)
        if (expected < 0.5 || diagM < 0.5) return
        val ratio = diagM / expected
        if (abs(ratio - 1.0) < 0.04) {
            Toast.makeText(this, "Diagonal checks out (±4%)", Toast.LENGTH_SHORT).show()
            return
        }
        if (ratio < 0.7 || ratio > 1.35) {
            Toast.makeText(this, "Diagonal looks off — keeping wall measures", Toast.LENGTH_LONG).show()
            return
        }
        val scale = 1.0 + (ratio - 1.0) * 0.65
        for (i in wallMeters.indices) wallMeters[i] = wallMeters[i] * scale
        Toast.makeText(this, String.format("Scale refined (×%.2f)", scale), Toast.LENGTH_LONG).show()
    }

    private fun labels() = if (chainMode) wallLabelsChain else wallLabelsQuick

    private fun distance(a: FloatArray, b: FloatArray): Double {
        val dx = (a[0] - b[0]).toDouble()
        val dy = (a[1] - b[1]).toDouble()
        val dz = (a[2] - b[2]).toDouble()
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun undoLast() {
        if (tapsInSegment > 0) {
            tapsInSegment = 0
            pendingStartPose = null
            updateUi()
            return
        }
        if (wallMeters.isNotEmpty() && !measuringDiagonal) {
            wallMeters.removeAt(wallMeters.lastIndex)
            measuringDiagonal = false
        }
        updateUi()
    }

    private fun resolvedWidthM(): Double? {
        if (wallMeters.isEmpty()) return null
        return if (chainMode && wallMeters.size >= 3) {
            (wallMeters[0] + wallMeters[2]) / 2.0
        } else wallMeters.getOrNull(0)
    }

    private fun resolvedLengthM(): Double? {
        if (wallMeters.size < 2) return null
        return if (chainMode && wallMeters.size >= 4) {
            (wallMeters[1] + wallMeters[3]) / 2.0
        } else wallMeters.getOrNull(1)
    }

    private fun updateUi() {
        if (!::stepTitle.isInitialized) return
        val n = wallMeters.size
        val labels = labels()
        when {
            measuringDiagonal -> {
                stepTitle.text = "Accuracy check — diagonal (optional)"
                stepHint.text = "Mark two opposite corners, or Use measurements."
                btnMark.text = "Mark diagonal corner"
            }
            n >= totalWalls -> {
                stepTitle.text = "Done — measurements ready"
                stepHint.text = "Tap Use measurements to build your plan."
                btnMark.text = "Mark corner"
            }
            else -> {
                stepTitle.text = "Step ${n + 1}/$totalWalls — ${labels[n]}"
                stepHint.text =
                    "You should see LIVE camera + floor grid. " +
                        "Point + at a floor corner → Mark. Other end of the same wall next."
                btnMark.text = if (tapsInSegment == 0) "Mark corner 1" else "Mark corner 2"
            }
        }

        measuredSummary.text = buildString {
            wallMeters.forEachIndexed { i, m ->
                append(String.format("%s: %.2f m (%.1f ft)\n", labels.getOrElse(i) { "W" }, m, m * M_TO_FT))
            }
            val w = resolvedWidthM()
            val l = resolvedLengthM()
            if (w != null && l != null && n >= (if (chainMode) 4 else 2)) {
                append(String.format("→ Room ≈ %.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT))
            }
        }

        val w = resolvedWidthM()
        val l = resolvedLengthM()
        val ready = if (chainMode) {
            wallMeters.size >= 4 && w != null && l != null && w > 0.5 && l > 0.5
        } else {
            wallMeters.size >= 2 && w != null && l != null && w > 0.5 && l > 0.5
        }
        btnDone.isEnabled = ready
        if (ready && w != null && l != null) {
            liveDistance.text = String.format("%.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT)
            liveDistance.setTextColor(0xFF80CBC4.toInt())
        } else if (wallMeters.isNotEmpty() && pendingStartPose == null) {
            liveDistance.text = String.format("Last: %.1f ft", wallMeters.last() * M_TO_FT)
        }
    }

    private fun finishWithResult() {
        measuringDiagonal = false
        val w = resolvedWidthM()
        val l = resolvedLengthM()
        if (w == null || l == null || w < 0.5 || l < 0.5) {
            Toast.makeText(this, "Finish wall measurements first", Toast.LENGTH_SHORT).show()
            return
        }
        val data = Intent().apply {
            putExtra(EXTRA_WIDTH_M, w)
            putExtra(EXTRA_LENGTH_M, l)
            putExtra(EXTRA_WIDTH_FT, w * M_TO_FT)
            putExtra(EXTRA_LENGTH_FT, l * M_TO_FT)
            putExtra(EXTRA_MODE, if (chainMode) MODE_CHAIN else MODE_QUICK)
            putExtra(EXTRA_WALLS_M, wallMeters.toDoubleArray())
            putExtra(EXTRA_WALLS_FT, wallMeters.map { it * M_TO_FT }.toDoubleArray())
        }
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    companion object {
        private const val TAG = "ArMeasure"
        private const val REQ_CAMERA = 7145
        const val EXTRA_WIDTH_M = "width_m"
        const val EXTRA_LENGTH_M = "length_m"
        const val EXTRA_WIDTH_FT = "width_ft"
        const val EXTRA_LENGTH_FT = "length_ft"
        const val EXTRA_MODE = "mode"
        const val EXTRA_WALLS_M = "walls_m"
        const val EXTRA_WALLS_FT = "walls_ft"
        const val EXTRA_ERROR = "error"
        const val MODE_QUICK = "quick"
        const val MODE_CHAIN = "chain"
        const val REQUEST_CODE = 7142
        private const val M_TO_FT = 3.28084
    }
}
