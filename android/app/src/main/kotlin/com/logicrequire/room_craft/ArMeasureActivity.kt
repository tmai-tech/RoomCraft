package com.logicrequire.room_craft

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * AR room measure using SceneView [ARSceneView] (+122/+123).
 *
 * Feedback a41da384 / e43505bf: custom GL camera stayed black.
 * SceneView owns Filament camera stream + ARCore session lifecycle.
 *
 * +123 multi-dot polygon (Planner5D-class):
 * - mode `polygon`: mark 4 floor corners (point cloud of corners) → W×L
 * - Instant Placement fallback when floor plane is slow
 * - configureSession **before** lifecycle (session create was eating late config)
 * - camera watchdog if stream never starts
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
    /** Floor-plane corner dots (world X,Y,Z) for polygon mode. */
    private val cornerDots = mutableListOf<FloatArray>()
    private var pendingStartPose: FloatArray? = null
    private var chainMode = false
    private var polygonMode = false
    private var tapsInSegment = 0
    private var measuringDiagonal = false
    private var cameraReady = false
    private var firstFrameSeen = false
    private var uiTick = 0
    private var destroyed = false

    private val handler = Handler(Looper.getMainLooper())
    private val cameraWatchdog = Runnable {
        if (!firstFrameSeen && !destroyed) {
            liveDistance.text =
                "No camera yet — install/update Play Services for AR, or use Field measure"
            liveDistance.setTextColor(0xFFEF9A9A.toInt())
            Toast.makeText(
                this,
                "AR camera not starting. Update \"Google Play Services for AR\", grant camera, good lighting.",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    private val wallLabelsQuick = listOf("Width (Wall A)", "Length (Wall B)")
    private val wallLabelsChain = listOf(
        "Wall A (first width side)",
        "Wall B (first length side)",
        "Wall C (opposite width)",
        "Wall D (opposite length)",
    )
    private val cornerLabels = listOf(
        "Corner 1 (SW)",
        "Corner 2 (SE)",
        "Corner 3 (NE)",
        "Corner 4 (NW)",
    )
    private val totalWalls: Int get() = if (chainMode) 4 else 2
    private val totalCorners = 4

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setContentView(R.layout.activity_ar_measure)
            val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_QUICK
            polygonMode = mode == MODE_POLYGON
            chainMode = mode == MODE_CHAIN

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

            // +123: apply config BEFORE lifecycle so session.create sees it
            arSceneView.sessionConfiguration = { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                // Instant placement = multi-dot works even before full floor mesh
                config.instantPlacementMode =
                    Config.InstantPlacementMode.LOCAL_Y_UP
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }
            arSceneView.configureSession { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                config.instantPlacementMode =
                    Config.InstantPlacementMode.LOCAL_Y_UP
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }

            arSceneView.planeRenderer.isEnabled = true
            arSceneView.planeRenderer.isVisible = true

            arSceneView.onSessionCreated = {
                Log.i(TAG, "AR session created (SceneView +123)")
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
                if (frame.timestamp != 0L) {
                    if (!firstFrameSeen) {
                        firstFrameSeen = true
                        cameraReady = true
                        handler.removeCallbacks(cameraWatchdog)
                    }
                }
                val busyMarking = if (polygonMode) {
                    cornerDots.size < totalCorners
                } else {
                    !(wallMeters.size >= totalWalls && !measuringDiagonal) &&
                        pendingStartPose == null
                }
                val shouldUi = uiTick % 12 == 0 && busyMarking
                if (shouldUi) {
                    val cam = frame.camera.trackingState
                    var planes = 0
                    for (p in session.getAllTrackables(Plane::class.java)) {
                        if (p.trackingState == TrackingState.TRACKING) planes++
                    }
                    runOnUiThread {
                        when (cam) {
                            TrackingState.TRACKING -> {
                                liveDistance.text = if (planes > 0) {
                                    if (polygonMode) {
                                        "Tracking · ${cornerDots.size}/$totalCorners dots · $planes plane(s)"
                                    } else {
                                        "Tracking · $planes floor plane(s) — Mark ready"
                                    }
                                } else {
                                    "Tracking · point at floor (instant mark OK)…"
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

            // Permission first so ARCore session can open on first resume
            if (!hasCameraPermission()) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.CAMERA),
                    REQ_CAMERA,
                )
            } else {
                // Wire lifecycle only when camera is allowed
                arSceneView.lifecycle = lifecycle
            }

            handler.postDelayed(cameraWatchdog, 6_000L)
            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            failAndFinish(e.message ?: "AR failed to start")
        }
    }

    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacks(cameraWatchdog)
        try {
            // Lifecycle already pauses; avoid double-destroy races on some OEMs
            if (::arSceneView.isInitialized) {
                try {
                    arSceneView.lifecycle = null
                } catch (_: Exception) {
                }
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
            } else if (::arSceneView.isInitialized && arSceneView.lifecycle == null) {
                arSceneView.lifecycle = lifecycle
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

            // Prefer horizontal plane in polygon; fall back to any plane / instant placement
            val hit: HitResult? = arSceneView.hitTestAR(
                planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING),
                planePoseInPolygon = true,
                instantPlacementPoint = false,
            ) ?: arSceneView.hitTestAR(
                planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING),
                planePoseInPolygon = false,
                instantPlacementPoint = true,
            ) ?: arSceneView.hitTestAR(
                planeTypes = setOf(
                    Plane.Type.HORIZONTAL_UPWARD_FACING,
                    Plane.Type.HORIZONTAL_DOWNWARD_FACING,
                    Plane.Type.VERTICAL,
                ),
                planePoseInPolygon = false,
                point = true,
                instantPlacementPoint = true,
            ) ?: run {
                val cx = arSceneView.width / 2f
                val cy = arSceneView.height / 2f
                frame.hitTest(cx, cy).firstOrNull()
                    ?: frame.hitTestInstantPlacement(cx, cy, 1.5f).firstOrNull()
            }

            if (hit == null) {
                Toast.makeText(
                    this,
                    "No floor at + — pan slowly, wait for grid, then Mark",
                    Toast.LENGTH_LONG,
                ).show()
                return
            }

            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            when {
                polygonMode -> handlePolygonDot(xyz)
                measuringDiagonal -> handleDiagonalPoint(xyz)
                else -> handleWallPoint(xyz)
            }
        } catch (e: Exception) {
            Log.e(TAG, "mark", e)
            Toast.makeText(this, "Measure failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    /** +123: multi-dot floor polygon — 4 corners → W×L. */
    private fun handlePolygonDot(xyz: FloatArray) {
        if (cornerDots.size >= totalCorners) return
        // Reject near-duplicate dots
        for (prev in cornerDots) {
            if (distance(prev, xyz) < 0.35) {
                Toast.makeText(this, "Too close to previous dot — mark another corner", Toast.LENGTH_SHORT).show()
                return
            }
        }
        cornerDots.add(xyz)
        val n = cornerDots.size
        Toast.makeText(
            this,
            "Dot $n/$totalCorners set",
            Toast.LENGTH_SHORT,
        ).show()
        if (n >= totalCorners) {
            val dims = resolvePolygonMeters(cornerDots)
            if (dims == null) {
                Toast.makeText(
                    this,
                    "Could not form room from dots — Undo and re-mark corners",
                    Toast.LENGTH_LONG,
                ).show()
                cornerDots.removeAt(cornerDots.lastIndex)
            } else {
                // Fill wallMeters as opposite-pair averages for chain-compatible export
                wallMeters.clear()
                wallMeters.add(dims.first)  // W
                wallMeters.add(dims.second) // L
                wallMeters.add(dims.first)  // opposite W
                wallMeters.add(dims.second) // opposite L
                Toast.makeText(
                    this,
                    String.format(
                        "Room ≈ %.1f × %.1f ft from 4-corner map",
                        dims.first * M_TO_FT,
                        dims.second * M_TO_FT,
                    ),
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
        updateUi()
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

    private fun labels() = when {
        polygonMode -> cornerLabels
        chainMode -> wallLabelsChain
        else -> wallLabelsQuick
    }

    private fun distance(a: FloatArray, b: FloatArray): Double {
        val dx = (a[0] - b[0]).toDouble()
        val dy = (a[1] - b[1]).toDouble()
        val dz = (a[2] - b[2]).toDouble()
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun undoLast() {
        if (polygonMode) {
            if (cornerDots.isNotEmpty()) {
                cornerDots.removeAt(cornerDots.lastIndex)
                wallMeters.clear()
            }
            updateUi()
            return
        }
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
        if (polygonMode && cornerDots.size >= 4) {
            return resolvePolygonMeters(cornerDots)?.first
        }
        if (wallMeters.isEmpty()) return null
        return if ((chainMode || polygonMode) && wallMeters.size >= 3) {
            (wallMeters[0] + wallMeters[2]) / 2.0
        } else wallMeters.getOrNull(0)
    }

    private fun resolvedLengthM(): Double? {
        if (polygonMode && cornerDots.size >= 4) {
            return resolvePolygonMeters(cornerDots)?.second
        }
        if (wallMeters.size < 2) return null
        return if ((chainMode || polygonMode) && wallMeters.size >= 4) {
            (wallMeters[1] + wallMeters[3]) / 2.0
        } else wallMeters.getOrNull(1)
    }

    private fun updateUi() {
        if (!::stepTitle.isInitialized) return
        if (polygonMode) {
            val n = cornerDots.size
            when {
                n >= totalCorners && resolvedWidthM() != null -> {
                    stepTitle.text = "Done — 4-corner map ready"
                    stepHint.text =
                        "Multi-dot floor map (Planner5D-style). Tap Use measurements."
                    btnMark.text = "Mark corner"
                }
                else -> {
                    stepTitle.text = "Dot ${n + 1}/$totalCorners — ${cornerLabels[n]}"
                    stepHint.text =
                        "LIVE camera + floor grid. Point + at each floor corner, walk around room. " +
                            "Mark 4 corners → auto W×L (not separate wall segments)."
                    btnMark.text = "Mark floor corner ${n + 1}"
                }
            }
            measuredSummary.text = buildString {
                cornerDots.forEachIndexed { i, p ->
                    append(String.format("Dot %d: (%.2f, %.2f)\n", i + 1, p[0], p[2]))
                }
                val w = resolvedWidthM()
                val l = resolvedLengthM()
                if (w != null && l != null) {
                    append(String.format("→ Room ≈ %.1f × %.1f ft (4-corner map)", w * M_TO_FT, l * M_TO_FT))
                }
            }
            val w = resolvedWidthM()
            val l = resolvedLengthM()
            val ready = cornerDots.size >= 4 && w != null && l != null && w > 0.5 && l > 0.5
            btnDone.isEnabled = ready
            if (ready && w != null && l != null) {
                liveDistance.text = String.format("%.1f × %.1f ft · 4 dots", w * M_TO_FT, l * M_TO_FT)
                liveDistance.setTextColor(0xFF80CBC4.toInt())
            }
            return
        }

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
            Toast.makeText(this, "Finish corner / wall measurements first", Toast.LENGTH_SHORT).show()
            return
        }
        val exportMode = when {
            polygonMode -> MODE_POLYGON
            chainMode -> MODE_CHAIN
            else -> MODE_QUICK
        }
        // For polygon, ensure 4 wall values for opposite-wall checks
        val wallsOut = if (polygonMode && wallMeters.size < 4) {
            doubleArrayOf(w, l, w, l)
        } else {
            wallMeters.toDoubleArray()
        }
        val data = Intent().apply {
            putExtra(EXTRA_WIDTH_M, w)
            putExtra(EXTRA_LENGTH_M, l)
            putExtra(EXTRA_WIDTH_FT, w * M_TO_FT)
            putExtra(EXTRA_LENGTH_FT, l * M_TO_FT)
            putExtra(EXTRA_MODE, exportMode)
            putExtra(EXTRA_WALLS_M, wallsOut)
            putExtra(EXTRA_WALLS_FT, wallsOut.map { it * M_TO_FT }.toDoubleArray())
            if (polygonMode && cornerDots.size >= 4) {
                val flat = FloatArray(cornerDots.size * 3)
                cornerDots.forEachIndexed { i, p ->
                    flat[i * 3] = p[0]
                    flat[i * 3 + 1] = p[1]
                    flat[i * 3 + 2] = p[2]
                }
                putExtra(EXTRA_CORNERS_M, flat)
            }
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
        const val EXTRA_CORNERS_M = "corners_m"
        const val EXTRA_ERROR = "error"
        const val MODE_QUICK = "quick"
        const val MODE_CHAIN = "chain"
        /** 4 floor-corner multi-dot map (Planner5D-style). */
        const val MODE_POLYGON = "polygon"
        const val REQUEST_CODE = 7142
        private const val M_TO_FT = 3.28084

        /**
         * Resolve W×L (meters) from 4+ floor dots.
         * Order by angle around centroid on XZ plane; average opposite edges.
         */
        fun resolvePolygonMeters(dots: List<FloatArray>): Pair<Double, Double>? {
            if (dots.size < 4) return null
            val pts = dots.take(4)
            var cx = 0.0
            var cz = 0.0
            for (p in pts) {
                cx += p[0]
                cz += p[2]
            }
            cx /= pts.size
            cz /= pts.size
            val ordered = pts.sortedBy { p ->
                atan2((p[2] - cz).toDouble(), (p[0] - cx).toDouble())
            }
            val edges = DoubleArray(4)
            for (i in 0 until 4) {
                val a = ordered[i]
                val b = ordered[(i + 1) % 4]
                val dx = (a[0] - b[0]).toDouble()
                val dz = (a[2] - b[2]).toDouble()
                edges[i] = sqrt(dx * dx + dz * dz)
            }
            // Opposite edges: 0↔2 and 1↔3
            val sideA = (edges[0] + edges[2]) / 2.0
            val sideB = (edges[1] + edges[3]) / 2.0
            if (sideA < 0.5 || sideB < 0.5) return null
            // Width = larger side (convention matches prior AR path)
            val width = maxOf(sideA, sideB)
            val length = minOf(sideA, sideB)
            // Consistency: opposite edges shouldn't diverge wildly
            val errA = if (edges[0] <= 0) 0.0 else abs(edges[0] - edges[2]) / edges[0]
            val errB = if (edges[1] <= 0) 0.0 else abs(edges[1] - edges[3]) / edges[1]
            if (errA > 0.45 || errB > 0.45) {
                // Still return OBB-ish average — room may be irregular
                Log.w(TAG, "Polygon opposite-edge error high: $errA / $errB")
            }
            return width to length
        }
    }
}
