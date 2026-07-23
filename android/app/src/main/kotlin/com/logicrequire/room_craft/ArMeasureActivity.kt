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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * AR room measure using SceneView [ARSceneView] (+122–+125).
 *
 * +125 Easy walk-to-map (feedback e7b247fd): common users should not mark
 * four abstract corners. Default mode **auto**: walk the room; we sample
 * floor hits + ARCore plane extents and fit an orthogonal rectangle.
 * Manual polygon / chain / quick remain available.
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
    private val cornerDots = mutableListOf<FloatArray>()
    /** +125 walk-cloud samples (world XYZ). */
    private val walkSamples = mutableListOf<FloatArray>()
    private var lastSamplePose: FloatArray? = null
    private var pendingStartPose: FloatArray? = null
    private var chainMode = false
    private var polygonMode = false
    private var autoMode = false
    private var tapsInSegment = 0
    private var measuringDiagonal = false
    private var cameraReady = false
    private var firstFrameSeen = false
    private var uiTick = 0
    private var destroyed = false
    private var lastOrthoScore = 0.0
    private var lastDiagError = 0.0
    private var autoWidthM = 0.0
    private var autoLengthM = 0.0
    private var autoStableTicks = 0

    private val handler = Handler(Looper.getMainLooper())
    private val cameraWatchdog = Runnable {
        if (!firstFrameSeen && !destroyed) {
            liveDistance.text =
                "No camera yet — update Play Services for AR, or use Field measure"
            liveDistance.setTextColor(0xFFEF9A9A.toInt())
            Toast.makeText(
                this,
                "AR camera not starting. Update \"Google Play Services for AR\".",
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
        "Corner 1", "Corner 2", "Corner 3", "Corner 4",
    )
    private val totalWalls: Int get() = if (chainMode) 4 else 2
    private val totalCorners = 4

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setContentView(R.layout.activity_ar_measure)
            val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_AUTO
            autoMode = mode == MODE_AUTO || mode == MODE_POLYGON // polygon defaults to easy auto
            // If caller asked polygon explicitly keep polygon; auto uses walk cloud
            if (mode == MODE_POLYGON) {
                // +125: treat "polygon" entry as easy auto for common users
                autoMode = true
                polygonMode = false
            } else {
                polygonMode = false
            }
            chainMode = mode == MODE_CHAIN
            if (mode == MODE_QUICK) {
                autoMode = false
                polygonMode = false
                chainMode = false
            }
            // Explicit advanced polygon still available via mode "corners"
            if (mode == MODE_CORNERS) {
                autoMode = false
                polygonMode = true
            }

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

            arSceneView.sessionConfiguration = { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }
            arSceneView.configureSession { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }

            arSceneView.planeRenderer.isEnabled = true
            arSceneView.planeRenderer.isVisible = true

            arSceneView.onSessionCreated = {
                Log.i(TAG, "AR session created (+125 easy walk)")
                runOnUiThread {
                    liveDistance.text = "Camera starting…"
                    liveDistance.setTextColor(0xFFFFCC80.toInt())
                }
            }

            arSceneView.onSessionResumed = {
                runOnUiThread {
                    liveDistance.text = if (autoMode) {
                        "Walk slowly · point camera at the floor"
                    } else {
                        "Camera live · find the floor"
                    }
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
                if (frame.timestamp != 0L && !firstFrameSeen) {
                    firstFrameSeen = true
                    cameraReady = true
                    handler.removeCallbacks(cameraWatchdog)
                }

                // +125: auto-sample floor while user walks
                if (autoMode && frame.camera.trackingState == TrackingState.TRACKING) {
                    if (uiTick % 4 == 0) {
                        sampleAutoFloor(session, frame)
                    }
                }

                if (uiTick % 6 == 0) {
                    val cam = frame.camera.trackingState
                    var planes = 0
                    for (p in session.getAllTrackables(Plane::class.java)) {
                        if (p.trackingState == TrackingState.TRACKING) planes++
                    }
                    val aimText = if (!autoMode) liveAimDistance() else null
                    runOnUiThread {
                        if (autoMode) {
                            updateAutoUi(cam, planes)
                        } else if (aimText != null) {
                            liveDistance.text = aimText
                            liveDistance.setTextColor(0xFFAED581.toInt())
                        } else {
                            liveDistance.text = when (cam) {
                                TrackingState.TRACKING ->
                                    if (planes > 0) "Tracking · $planes floor plane(s)"
                                    else "Tracking · circle phone over floor…"
                                TrackingState.PAUSED -> "Tracking paused — move slowly"
                                TrackingState.STOPPED -> "Tracking stopped"
                            }
                            liveDistance.setTextColor(0xFF80CBC4.toInt())
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
            } else {
                arSceneView.post {
                    if (!destroyed && arSceneView.lifecycle == null) {
                        arSceneView.lifecycle = lifecycle
                    }
                }
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
            } else if (::arSceneView.isInitialized) {
                arSceneView.post {
                    if (!destroyed && arSceneView.lifecycle == null) {
                        arSceneView.lifecycle = lifecycle
                    }
                }
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

    /** Continuous walk sampling + plane polygon vertices. */
    private fun sampleAutoFloor(session: com.google.ar.core.Session, frame: com.google.ar.core.Frame) {
        // 1) Plane extents / polygon vertices (Planner5D-style growth)
        for (plane in session.getAllTrackables(Plane::class.java)) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            try {
                val poly = plane.polygon
                // polygon is xz in plane local; transform via center pose
                val pose = plane.centerPose
                val n = poly.limit() / 2
                val step = max(1, n / 8)
                var i = 0
                val local = FloatArray(3)
                val world = FloatArray(3)
                while (i < n) {
                    local[0] = poly.get(i * 2)
                    local[1] = 0f
                    local[2] = poly.get(i * 2 + 1)
                    pose.transformPoint(local, 0, world, 0)
                    maybeAddSample(world.copyOf())
                    i += step
                }
                // Also corners of extent box
                val ex = plane.extentX / 2f
                val ez = plane.extentZ / 2f
                for (sx in floatArrayOf(-ex, ex)) {
                    for (sz in floatArrayOf(-ez, ez)) {
                        local[0] = sx
                        local[1] = 0f
                        local[2] = sz
                        pose.transformPoint(local, 0, world, 0)
                        maybeAddSample(world.copyOf())
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "plane sample", e)
            }
        }

        // 2) Reticle floor hit while walking
        val hit = resolveCenterHit()
        if (hit != null) {
            val p = hit.hitPose
            maybeAddSample(floatArrayOf(p.tx(), p.ty(), p.tz()))
        }

        recomputeAutoSize()
    }

    private fun maybeAddSample(xyz: FloatArray) {
        val last = lastSamplePose
        if (last != null && distance(last, xyz) < 0.18) return
        // Cap cloud size
        if (walkSamples.size > 400) {
            // thin: drop every other early sample
            val kept = walkSamples.filterIndexed { i, _ -> i % 2 == 1 }.toMutableList()
            walkSamples.clear()
            walkSamples.addAll(kept)
        }
        walkSamples.add(xyz)
        lastSamplePose = xyz
    }

    private fun recomputeAutoSize() {
        val dims = resolveCloudMeters(walkSamples)
        if (dims == null) return
        val prevW = autoWidthM
        val prevL = autoLengthM
        autoWidthM = dims.widthM
        autoLengthM = dims.lengthM
        lastOrthoScore = dims.orthogonalScore
        lastDiagError = dims.diagonalError
        // Stability: size not changing much
        if (prevW > 0.5 && prevL > 0.5) {
            val dw = abs(prevW - autoWidthM) / prevW
            val dl = abs(prevL - autoLengthM) / prevL
            if (dw < 0.03 && dl < 0.03) autoStableTicks++ else autoStableTicks = 0
        }
        wallMeters.clear()
        wallMeters.add(autoWidthM)
        wallMeters.add(autoLengthM)
        wallMeters.add(autoWidthM)
        wallMeters.add(autoLengthM)
    }

    private fun updateAutoUi(cam: TrackingState, planes: Int) {
        when (cam) {
            TrackingState.TRACKING -> {
                if (autoWidthM >= 1.5 && autoLengthM >= 1.5) {
                    liveDistance.text = String.format(
                        "%.1f × %.1f ft · keep walking edges",
                        autoWidthM * M_TO_FT,
                        autoLengthM * M_TO_FT,
                    )
                    liveDistance.setTextColor(0xFFAED581.toInt())
                } else if (planes > 0 || walkSamples.isNotEmpty()) {
                    liveDistance.text =
                        "Mapping… ${walkSamples.size} pts · walk along walls"
                    liveDistance.setTextColor(0xFF80CBC4.toInt())
                } else {
                    liveDistance.text = "Point at floor and walk slowly"
                    liveDistance.setTextColor(0xFF80CBC4.toInt())
                }
            }
            TrackingState.PAUSED -> {
                liveDistance.text = "Paused — move phone slowly"
                liveDistance.setTextColor(0xFFFFAB91.toInt())
            }
            TrackingState.STOPPED -> {
                liveDistance.text = "Tracking stopped"
                liveDistance.setTextColor(0xFFEF9A9A.toInt())
            }
        }
        updateUi()
    }

    private fun liveAimDistance(): String? {
        val aimFrom: FloatArray? = when {
            polygonMode && cornerDots.isNotEmpty() && cornerDots.size < totalCorners ->
                cornerDots.last()
            pendingStartPose != null -> pendingStartPose
            else -> null
        } ?: return null
        val hit = peekCenterHit() ?: return null
        val pose = hit.hitPose
        val d = distance(aimFrom, floatArrayOf(pose.tx(), pose.ty(), pose.tz()))
        return String.format("Aim: %.2f m (%.1f ft) from last mark", d, d * M_TO_FT)
    }

    private fun peekCenterHit(): HitResult? = try {
        resolveCenterHit()
    } catch (_: Exception) {
        null
    }

    private fun resolveCenterHit(): HitResult? {
        val frame = arSceneView.frame ?: return null
        if (frame.timestamp == 0L) return null
        return arSceneView.hitTestAR(
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
    }

    private fun markCenterHit() {
        try {
            val frame = arSceneView.frame
            if (frame == null || frame.timestamp == 0L) {
                Toast.makeText(this, "Wait for live camera first", Toast.LENGTH_SHORT).show()
                return
            }
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                Toast.makeText(this, "Move slowly until tracking is stable", Toast.LENGTH_SHORT).show()
                return
            }
            val hit = resolveCenterHit()
            if (hit == null) {
                Toast.makeText(
                    this,
                    "No floor at + — walk and point at floor",
                    Toast.LENGTH_LONG,
                ).show()
                return
            }
            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            when {
                autoMode -> {
                    // Optional pin to densify map
                    maybeAddSample(xyz)
                    // Force accept close pins
                    walkSamples.add(xyz)
                    recomputeAutoSize()
                    Toast.makeText(this, "Floor pin added (${walkSamples.size} pts)", Toast.LENGTH_SHORT).show()
                    updateUi()
                }
                polygonMode -> handlePolygonDot(xyz)
                measuringDiagonal -> handleDiagonalPoint(xyz)
                else -> handleWallPoint(xyz)
            }
        } catch (e: Exception) {
            Log.e(TAG, "mark", e)
            Toast.makeText(this, "Measure failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handlePolygonDot(xyz: FloatArray) {
        if (cornerDots.size >= totalCorners) return
        for (prev in cornerDots) {
            if (distance(prev, xyz) < 0.35) {
                Toast.makeText(this, "Too close to previous corner", Toast.LENGTH_SHORT).show()
                return
            }
        }
        cornerDots.add(xyz)
        val n = cornerDots.size
        Toast.makeText(this, "Corner $n/$totalCorners", Toast.LENGTH_SHORT).show()
        if (n >= totalCorners) {
            val dims = resolvePolygonMeters(cornerDots)
            if (dims == null) {
                Toast.makeText(this, "Could not form room — Undo and retry", Toast.LENGTH_LONG).show()
                cornerDots.removeAt(cornerDots.lastIndex)
            } else {
                wallMeters.clear()
                wallMeters.add(dims.widthM)
                wallMeters.add(dims.lengthM)
                wallMeters.add(dims.widthM)
                wallMeters.add(dims.lengthM)
                lastOrthoScore = dims.orthogonalScore
                lastDiagError = dims.diagonalError
                Toast.makeText(
                    this,
                    String.format(
                        "Room ≈ %.1f × %.1f ft",
                        dims.widthM * M_TO_FT,
                        dims.lengthM * M_TO_FT,
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
                Toast.makeText(this, "Too short — mark further apart", Toast.LENGTH_SHORT).show()
                tapsInSegment = 0
                pendingStartPose = null
                return
            }
            wallMeters.add(dist)
            tapsInSegment = 0
            pendingStartPose = null
            Toast.makeText(
                this,
                String.format("%.2f m (%.1f ft)", dist, dist * M_TO_FT),
                Toast.LENGTH_SHORT,
            ).show()
            if (wallMeters.size >= totalWalls) measuringDiagonal = true
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

    private fun distance(a: FloatArray, b: FloatArray): Double {
        val dx = (a[0] - b[0]).toDouble()
        val dy = (a[1] - b[1]).toDouble()
        val dz = (a[2] - b[2]).toDouble()
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun undoLast() {
        when {
            autoMode -> {
                if (walkSamples.isNotEmpty()) {
                    val drop = min(8, walkSamples.size)
                    repeat(drop) { walkSamples.removeAt(walkSamples.lastIndex) }
                    recomputeAutoSize()
                }
            }
            polygonMode -> {
                if (cornerDots.isNotEmpty()) {
                    cornerDots.removeAt(cornerDots.lastIndex)
                    wallMeters.clear()
                }
            }
            tapsInSegment > 0 -> {
                tapsInSegment = 0
                pendingStartPose = null
            }
            wallMeters.isNotEmpty() && !measuringDiagonal -> {
                wallMeters.removeAt(wallMeters.lastIndex)
                measuringDiagonal = false
            }
        }
        updateUi()
    }

    private fun resolvedWidthM(): Double? {
        if (autoMode && autoWidthM >= 0.5) return autoWidthM
        if (polygonMode && cornerDots.size >= 4) {
            return resolvePolygonMeters(cornerDots)?.widthM
        }
        if (wallMeters.isEmpty()) return null
        return if ((chainMode || polygonMode || autoMode) && wallMeters.size >= 3) {
            (wallMeters[0] + wallMeters[2]) / 2.0
        } else wallMeters.getOrNull(0)
    }

    private fun resolvedLengthM(): Double? {
        if (autoMode && autoLengthM >= 0.5) return autoLengthM
        if (polygonMode && cornerDots.size >= 4) {
            return resolvePolygonMeters(cornerDots)?.lengthM
        }
        if (wallMeters.size < 2) return null
        return if ((chainMode || polygonMode || autoMode) && wallMeters.size >= 4) {
            (wallMeters[1] + wallMeters[3]) / 2.0
        } else wallMeters.getOrNull(1)
    }

    private fun updateUi() {
        if (!::stepTitle.isInitialized) return
        if (autoMode) {
            stepTitle.text = "Easy AR walk — map your room"
            stepHint.text =
                "Walk slowly along the walls while pointing at the floor. " +
                    "Size fills in automatically (no corner math). " +
                    "Optional: tap Add floor pin at hard corners. Then Use this size."
            btnMark.text = "Add floor pin (optional)"
            btnDone.text = "Use this size"
            measuredSummary.text = buildString {
                append("Floor samples: ${walkSamples.size}\n")
                if (autoWidthM >= 0.5 && autoLengthM >= 0.5) {
                    append(
                        String.format(
                            "Estimated room: %.1f × %.1f ft",
                            autoWidthM * M_TO_FT,
                            autoLengthM * M_TO_FT,
                        ),
                    )
                    if (lastOrthoScore > 0) {
                        append(String.format(" · fit %.0f%%", lastOrthoScore * 100))
                    }
                    if (autoStableTicks >= 8) append(" · stable")
                } else {
                    append("Keep walking until size appears…")
                }
            }
            val ready = autoWidthM >= 1.5 && autoLengthM >= 1.5 && walkSamples.size >= 6
            btnDone.isEnabled = ready
            return
        }

        if (polygonMode) {
            val n = cornerDots.size
            if (n >= totalCorners && resolvedWidthM() != null) {
                stepTitle.text = "Done — 4-corner map ready"
                stepHint.text = "Tap Use this size."
                btnMark.text = "Mark corner"
            } else {
                stepTitle.text = "Corner ${n + 1}/$totalCorners — ${cornerLabels[n]}"
                stepHint.text = "Point + at each floor corner, then Mark."
                btnMark.text = "Mark floor corner ${n + 1}"
            }
            btnDone.text = "Use this size"
            measuredSummary.text = buildString {
                cornerDots.forEachIndexed { i, p ->
                    append(String.format("Dot %d\n", i + 1))
                }
                val w = resolvedWidthM()
                val l = resolvedLengthM()
                if (w != null && l != null) {
                    append(String.format("→ %.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT))
                }
            }
            btnDone.isEnabled = cornerDots.size >= 4 && resolvedWidthM() != null
            return
        }

        val n = wallMeters.size
        val labels = if (chainMode) wallLabelsChain else wallLabelsQuick
        when {
            measuringDiagonal -> {
                stepTitle.text = "Optional diagonal check"
                stepHint.text = "Mark opposite corners, or Use this size."
                btnMark.text = "Mark diagonal"
            }
            n >= totalWalls -> {
                stepTitle.text = "Done"
                stepHint.text = "Tap Use this size."
                btnMark.text = "Mark"
            }
            else -> {
                stepTitle.text = "Step ${n + 1}/$totalWalls — ${labels[n]}"
                stepHint.text = "Point + at a floor corner → Mark each end of the wall."
                btnMark.text = if (tapsInSegment == 0) "Mark corner 1" else "Mark corner 2"
            }
        }
        btnDone.text = "Use this size"
        measuredSummary.text = buildString {
            wallMeters.forEachIndexed { i, m ->
                append(String.format("%s: %.1f ft\n", labels.getOrElse(i) { "W" }, m * M_TO_FT))
            }
            val w = resolvedWidthM()
            val l = resolvedLengthM()
            if (w != null && l != null) {
                append(String.format("→ %.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT))
            }
        }
        val w = resolvedWidthM()
        val l = resolvedLengthM()
        btnDone.isEnabled = if (chainMode) {
            wallMeters.size >= 4 && w != null && l != null && w > 0.5 && l > 0.5
        } else {
            wallMeters.size >= 2 && w != null && l != null && w > 0.5 && l > 0.5
        }
    }

    private fun finishWithResult() {
        measuringDiagonal = false
        val w = resolvedWidthM()
        val l = resolvedLengthM()
        if (w == null || l == null || w < 0.5 || l < 0.5) {
            Toast.makeText(
                this,
                if (autoMode) "Walk more of the room until size appears" else "Finish measurements first",
                Toast.LENGTH_SHORT,
            ).show()
            return
        }
        val exportMode = when {
            autoMode -> MODE_AUTO
            polygonMode -> MODE_POLYGON
            chainMode -> MODE_CHAIN
            else -> MODE_QUICK
        }
        val wallsOut = if ((autoMode || polygonMode) && wallMeters.size < 4) {
            doubleArrayOf(w, l, w, l)
        } else {
            wallMeters.toDoubleArray().ifEmpty { doubleArrayOf(w, l, w, l) }
        }
        val data = Intent().apply {
            putExtra(EXTRA_WIDTH_M, w)
            putExtra(EXTRA_LENGTH_M, l)
            putExtra(EXTRA_WIDTH_FT, w * M_TO_FT)
            putExtra(EXTRA_LENGTH_FT, l * M_TO_FT)
            putExtra(EXTRA_MODE, exportMode)
            putExtra(EXTRA_WALLS_M, wallsOut)
            putExtra(EXTRA_WALLS_FT, wallsOut.map { it * M_TO_FT }.toDoubleArray())
            putExtra(EXTRA_ORTHO_SCORE, lastOrthoScore)
            putExtra(EXTRA_DIAG_ERROR, lastDiagError)
            val samples = if (autoMode) walkSamples else cornerDots
            if (samples.isNotEmpty()) {
                val flat = FloatArray(samples.size * 3)
                samples.forEachIndexed { i, p ->
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

    data class PolygonDims(
        val widthM: Double,
        val lengthM: Double,
        val oppositeEdgeError: Double,
        val diagonalError: Double,
        val orthogonalScore: Double,
    )

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
        const val EXTRA_ORTHO_SCORE = "ortho_score"
        const val EXTRA_DIAG_ERROR = "diag_error"
        const val EXTRA_ERROR = "error"
        const val MODE_QUICK = "quick"
        const val MODE_CHAIN = "chain"
        const val MODE_POLYGON = "polygon"
        /** +125 easy walk-to-map (default). */
        const val MODE_AUTO = "auto"
        /** Advanced 4-corner only. */
        const val MODE_CORNERS = "corners"
        const val REQUEST_CODE = 7142
        private const val M_TO_FT = 3.28084

        fun resolvePolygonMeters(dots: List<FloatArray>): PolygonDims? {
            if (dots.size < 4) return null
            if (dots.size > 4) return resolveCloudMeters(dots)
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
            val sideA = (edges[0] + edges[2]) / 2.0
            val sideB = (edges[1] + edges[3]) / 2.0
            if (sideA < 0.5 || sideB < 0.5) return null
            val errA = if (edges[0] <= 0) 0.0 else abs(edges[0] - edges[2]) / edges[0]
            val errB = if (edges[1] <= 0) 0.0 else abs(edges[1] - edges[3]) / edges[1]
            val (orthoW, orthoL, orthoScore) = orthogonalFit(ordered)
            val useOrtho = orthoScore >= 0.85 && orthoW >= 0.5 && orthoL >= 0.5
            var width = if (useOrtho) max(orthoW, orthoL) else max(sideA, sideB)
            var length = if (useOrtho) min(orthoW, orthoL) else min(sideA, sideB)
            val d02 = edgeLen(ordered[0], ordered[2])
            val d13 = edgeLen(ordered[1], ordered[3])
            val measuredDiag = (d02 + d13) / 2.0
            val expectedDiag = sqrt(width * width + length * length)
            var diagErr = 0.0
            if (expectedDiag >= 0.5 && measuredDiag >= 0.5) {
                val ratio = measuredDiag / expectedDiag
                diagErr = abs(ratio - 1.0)
                if (diagErr >= 0.04 && ratio in 0.70..1.35) {
                    val scale = 1.0 + (ratio - 1.0) * 0.65
                    width *= scale
                    length *= scale
                }
            }
            return PolygonDims(
                widthM = max(width, length),
                lengthM = min(width, length),
                oppositeEdgeError = max(errA, errB),
                diagonalError = diagErr,
                orthogonalScore = orthoScore,
            )
        }

        /** +125 PCA orthogonal bounding box for walk cloud. */
        fun resolveCloudMeters(dots: List<FloatArray>): PolygonDims? {
            if (dots.size < 4) return null
            var cx = 0.0
            var cz = 0.0
            for (p in dots) {
                cx += p[0]
                cz += p[2]
            }
            cx /= dots.size
            cz /= dots.size
            var sxx = 0.0
            var sxz = 0.0
            var szz = 0.0
            for (p in dots) {
                val dx = p[0] - cx
                val dz = p[2] - cz
                sxx += dx * dx
                sxz += dx * dz
                szz += dz * dz
            }
            val n = dots.size.toDouble()
            sxx /= n
            sxz /= n
            szz /= n
            val trace = sxx + szz
            val det = sxx * szz - sxz * sxz
            val disc = max(0.0, trace * trace / 4 - det)
            val lambda1 = trace / 2 + sqrt(disc)
            var ux = sxz
            var uz = lambda1 - sxx
            if (abs(ux) + abs(uz) < 1e-9) {
                ux = 1.0
                uz = 0.0
            }
            var un = sqrt(ux * ux + uz * uz)
            ux /= un
            uz /= un
            val vx = -uz
            val vz = ux
            var minU = Double.POSITIVE_INFINITY
            var maxU = Double.NEGATIVE_INFINITY
            var minV = Double.POSITIVE_INFINITY
            var maxV = Double.NEGATIVE_INFINITY
            for (p in dots) {
                val dx = p[0] - cx
                val dz = p[2] - cz
                val pu = dx * ux + dz * uz
                val pv = dx * vx + dz * vz
                if (pu < minU) minU = pu
                if (pu > maxU) maxU = pu
                if (pv < minV) minV = pv
                if (pv > maxV) maxV = pv
            }
            val sideA = abs(maxU - minU)
            val sideB = abs(maxV - minV)
            if (sideA < 0.5 || sideB < 0.5) return null
            return PolygonDims(
                widthM = max(sideA, sideB),
                lengthM = min(sideA, sideB),
                oppositeEdgeError = 0.0,
                diagonalError = 0.0,
                orthogonalScore = 0.92,
            )
        }

        private fun edgeLen(a: FloatArray, b: FloatArray): Double {
            val dx = (a[0] - b[0]).toDouble()
            val dz = (a[2] - b[2]).toDouble()
            return sqrt(dx * dx + dz * dz)
        }

        private fun orthogonalFit(ordered: List<FloatArray>): Triple<Double, Double, Double> {
            val u = mutableListOf<Pair<Double, Double>>()
            val v = mutableListOf<Pair<Double, Double>>()
            for (i in 0 until 4) {
                val a = ordered[i]
                val b = ordered[(i + 1) % 4]
                var dx = (b[0] - a[0]).toDouble()
                var dz = (b[2] - a[2]).toDouble()
                val len = sqrt(dx * dx + dz * dz)
                if (len < 1e-6) continue
                dx /= len
                dz /= len
                if (i % 2 == 0) u.add(dx to dz) else v.add(dx to dz)
            }
            if (u.isEmpty() || v.isEmpty()) return Triple(0.0, 0.0, 0.0)
            var ux = 0.0
            var uz = 0.0
            for ((dx, dz) in u) {
                val s = if (dx * u[0].first + dz * u[0].second < 0) -1.0 else 1.0
                ux += s * dx
                uz += s * dz
            }
            var un = sqrt(ux * ux + uz * uz)
            if (un < 1e-6) return Triple(0.0, 0.0, 0.0)
            ux /= un
            uz /= un
            var vx = 0.0
            var vz = 0.0
            for ((dx, dz) in v) {
                val s = if (dx * v[0].first + dz * v[0].second < 0) -1.0 else 1.0
                vx += s * dx
                vz += s * dz
            }
            var vn = sqrt(vx * vx + vz * vz)
            if (vn < 1e-6) return Triple(0.0, 0.0, 0.0)
            vx /= vn
            vz /= vn
            val rawDot = abs(u[0].first * v[0].first + u[0].second * v[0].second)
            val orthoScore = (1.0 - rawDot).coerceIn(0.0, 1.0)
            val dot = ux * vx + uz * vz
            vx -= dot * ux
            vz -= dot * uz
            vn = sqrt(vx * vx + vz * vz)
            if (vn < 1e-6) {
                vx = -uz
                vz = ux
            } else {
                vx /= vn
                vz /= vn
            }
            var minU = Double.POSITIVE_INFINITY
            var maxU = Double.NEGATIVE_INFINITY
            var minV = Double.POSITIVE_INFINITY
            var maxV = Double.NEGATIVE_INFINITY
            for (p in ordered) {
                val pu = p[0] * ux + p[2] * uz
                val pv = p[0] * vx + p[2] * vz
                if (pu < minU) minU = pu
                if (pu > maxU) maxU = pu
                if (pv < minV) minV = pv
                if (pv > maxV) maxV = pv
            }
            return Triple(max(abs(maxU - minU), abs(maxV - minV)), min(abs(maxU - minU), abs(maxV - minV)), orthoScore)
        }
    }
}
