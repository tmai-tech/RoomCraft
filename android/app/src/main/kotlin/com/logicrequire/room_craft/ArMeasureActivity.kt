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
import com.logicrequire.room_craft.ar.WalkMapView
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
 * +126: robust percentile hull + outlier trim + coverage coaching
 * (Planner5D-class walk completeness; Open3D-style SOR).
 * Manual polygon / chain / quick remain available.
 */
class ArMeasureActivity : AppCompatActivity() {

    private lateinit var arSceneView: ARSceneView
    private lateinit var walkMap: WalkMapView
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
    /** +127 Home Scan: camera pose trail while walking (world XYZ meters). */
    private val poseSamples = mutableListOf<FloatArray>()
    private var lastSamplePose: FloatArray? = null
    private var lastPoseSample: FloatArray? = null
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
    /** +126: angular coverage of walk cloud (0..1). */
    private var lastCoverageScore = 0.0
    /** +126: largest ARCore horizontal plane extents (world XZ). */
    private var planeExtentXM = 0.0
    private var planeExtentZM = 0.0
    /** +131: Depth API enabled only when session supports it. */
    private var depthEnabled = false
    private var depthSampleCount = 0
    /**
     * +135 wall-distance lock:
     * - opposite vertical plane pairs (primary)
     * - heading-bin camera→wall ranges (secondary when planes sparse)
     */
    private val wallRangeBins = Array(8) { mutableListOf<Double>() }
    private var wallLockWidthM = 0.0
    private var wallLockLengthM = 0.0
    private var wallLockPairs = 0

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
            walkMap = findViewById(R.id.walk_map)
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

            // +131: enable Depth only when supported (always-on AUTOMATIC blacked
            // camera on many OEMs in +121). Unsupported devices stay DISABLED.
            arSceneView.sessionConfiguration = { session, config ->
                depthEnabled = try {
                    session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
                } catch (_: Exception) {
                    false
                }
                config.depthMode = if (depthEnabled) {
                    Config.DepthMode.AUTOMATIC
                } else {
                    Config.DepthMode.DISABLED
                }
                // +128: horizontal + vertical so wall planes densify the floor map
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
                config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                Log.i(TAG, "depthEnabled=$depthEnabled (+131)")
            }
            arSceneView.configureSession { session, config ->
                depthEnabled = try {
                    session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
                } catch (_: Exception) {
                    false
                }
                config.depthMode = if (depthEnabled) {
                    Config.DepthMode.AUTOMATIC
                } else {
                    Config.DepthMode.DISABLED
                }
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
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

                // +125/+127/+130/+131: floor + pose + features + optional depth rays
                if (autoMode && frame.camera.trackingState == TrackingState.TRACKING) {
                    if (uiTick % 4 == 0) {
                        sampleAutoFloor(session, frame)
                        sampleCameraPose(frame)
                    }
                    // +130: sparse ARCore feature points near floor
                    if (uiTick % 10 == 0) {
                        sampleFeaturePointsNearFloor(frame)
                    }
                    // +131: depth-assisted wall/floor rays when Depth API supported
                    if (depthEnabled && uiTick % 12 == 0) {
                        sampleDepthAssistRays(frame)
                    }
                    // +135: wall-distance samples (vertical planes / mid hits)
                    if (uiTick % 8 == 0) {
                        sampleWallRanges(frame)
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

    /** +128: live top-down dots + room box (OpenCV-style understanding). */
    private fun refreshWalkMap() {
        if (!::walkMap.isInitialized) return
        val floor = walkSamples.map { it[0] to it[2] }
        val poses = poseSamples.map { it[0] to it[2] }
        walkMap.setData(
            floorXz = floor,
            poseXz = poses,
            widthM = autoWidthM.toFloat(),
            lengthM = autoLengthM.toFloat(),
        )
    }

    /** +127: record camera motion trail for Home Scan package / future cloud. */
    private fun sampleCameraPose(frame: com.google.ar.core.Frame) {
        try {
            val pose = frame.camera.pose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            val last = lastPoseSample
            if (last != null) {
                val dx = xyz[0] - last[0]
                val dy = xyz[1] - last[1]
                val dz = xyz[2] - last[2]
                // ~12 cm motion threshold
                if (dx * dx + dy * dy + dz * dz < 0.014f) return
            }
            lastPoseSample = xyz
            if (poseSamples.size > 400) {
                val kept = poseSamples.filterIndexed { i, _ -> i % 2 == 1 }.toMutableList()
                poseSamples.clear()
                poseSamples.addAll(kept)
            }
            poseSamples.add(xyz)
        } catch (e: Exception) {
            Log.w(TAG, "pose sample", e)
        }
    }

    /** Continuous walk sampling + plane polygon vertices. */
    private fun sampleAutoFloor(session: com.google.ar.core.Session, frame: com.google.ar.core.Frame) {
        var maxEx = 0f
        var maxEz = 0f
        // Vertical walls for +135 wall-to-wall lock: (nx, nz, centerX, centerZ)
        val verticals = mutableListOf<FloatArray>()
        // 1) Horizontal + vertical plane samples (Planner5D-style growth)
        for (plane in session.getAllTrackables(Plane::class.java)) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (plane.type == Plane.Type.VERTICAL) {
                try {
                    sampleVerticalPlaneBase(plane)
                    val pose = plane.centerPose
                    // ARCore: pose +Y is the plane normal
                    val n = FloatArray(3)
                    pose.getYAxis(n, 0)
                    val nx = n[0]
                    val nz = n[2]
                    val nn = sqrt((nx * nx + nz * nz).toDouble()).toFloat()
                    if (nn > 0.3f) {
                        verticals.add(
                            floatArrayOf(
                                nx / nn,
                                nz / nn,
                                pose.tx(),
                                pose.tz(),
                            ),
                        )
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "vertical plane sample", e)
                }
                continue
            }
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            try {
                val poly = plane.polygon
                // polygon is xz in plane local; transform via center pose
                val pose = plane.centerPose
                val n = poly.limit() / 2
                val step = max(1, n / 10)
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
                if (plane.extentX > maxEx) maxEx = plane.extentX
                if (plane.extentZ > maxEz) maxEz = plane.extentZ
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
        if (maxEx > 0.5f) planeExtentXM = max(planeExtentXM, maxEx.toDouble())
        if (maxEz > 0.5f) planeExtentZM = max(planeExtentZM, maxEz.toDouble())
        if (verticals.size >= 2) {
            updateWallLockFromVerticals(verticals)
        }

        // 2) Reticle floor hit while walking (+ multi-ray for denser edge map)
        val hit = resolveCenterHit()
        if (hit != null) {
            val p = hit.hitPose
            maybeAddSample(floatArrayOf(p.tx(), p.ty(), p.tz()))
        }
        // Off-center rays (±12% of screen) capture wall-edge floor while walking
        if (uiTick % 8 == 0) {
            sampleScreenHit(0.38f, 0.55f)
            sampleScreenHit(0.62f, 0.55f)
            sampleScreenHit(0.50f, 0.68f)
        }

        recomputeAutoSize()
    }

    /**
     * +135: opposite vertical plane pairs → wall-to-wall meters (Planner5D / CAD class).
     * Distance along shared normal between anti-parallel walls.
     */
    private fun updateWallLockFromVerticals(verticals: List<FloatArray>) {
        val dists = mutableListOf<Double>()
        for (i in verticals.indices) {
            val a = verticals[i]
            for (j in i + 1 until verticals.size) {
                val b = verticals[j]
                val dot = a[0] * b[0] + a[1] * b[1]
                // Opposite walls: normals anti-parallel
                if (dot > -0.75f) continue
                val dx = (b[2] - a[2]).toDouble()
                val dz = (b[3] - a[3]).toDouble()
                // Project separation onto A's normal
                val dist = abs(dx * a[0] + dz * a[1])
                if (dist in 1.5..25.0) dists.add(dist)
            }
        }
        if (dists.isEmpty()) return
        dists.sort()
        // Use largest two distinct axes if possible
        val largest = dists.last()
        var second = 0.0
        for (k in dists.size - 2 downTo 0) {
            val d = dists[k]
            // Different dimension if differs by >15%
            if (abs(d - largest) / largest > 0.15) {
                second = d
                break
            }
        }
        if (second < 1.5) second = largest // square room fallback uses one pair twice carefully
        wallLockWidthM = max(largest, second)
        wallLockLengthM = if (second >= 1.5) min(largest, second) else largest * 0.85
        wallLockPairs = dists.size
    }

    /**
     * +128: project vertical wall plane base into floor cloud so looking at
     * walls grows the map (Planner5D walk captures walls + floor).
     */
    private fun sampleVerticalPlaneBase(plane: Plane) {
        val pose = plane.centerPose
        val ex = plane.extentX / 2f
        val local = FloatArray(3)
        val world = FloatArray(3)
        val yFloor = lastSamplePose?.get(1) ?: 0f
        for (sx in floatArrayOf(-ex, 0f, ex)) {
            local[0] = sx
            local[1] = 0f
            local[2] = 0f
            pose.transformPoint(local, 0, world, 0)
            maybeAddSample(floatArrayOf(world[0], yFloor, world[2]))
        }
    }

    /**
     * +130: densify floor cloud from ARCore feature [PointCloud] near floor Y.
     * Feature points improve room edge capture while walking (Open3D sparse map).
     */
    private fun sampleFeaturePointsNearFloor(frame: com.google.ar.core.Frame) {
        try {
            val cloud = frame.acquirePointCloud()
            try {
                val buf = cloud.points
                val yRef = lastSamplePose?.get(1)
                    ?: frame.camera.pose.ty() - 1.4f // rough floor from eye height
                var i = 0
                var added = 0
                // PointCloud buffer: x,y,z,confidence floats
                while (buf.remaining() >= 4 && added < 24) {
                    val x = buf.get()
                    val y = buf.get()
                    val z = buf.get()
                    val conf = buf.get()
                    i++
                    if (conf < 0.35f) continue
                    // Keep points within ~35 cm of estimated floor
                    if (kotlin.math.abs(y - yRef) > 0.35f) continue
                    // Subsample: every ~3rd qualifying point
                    if (i % 3 != 0) continue
                    maybeAddSample(floatArrayOf(x, yRef, z))
                    added++
                }
            } finally {
                cloud.release()
            }
        } catch (_: Exception) {
            // Point cloud not available on this frame — ignore
        }
    }

    /**
     * +131: screen-edge hit tests (depth improves hits when AUTOMATIC supported).
     * Adds floor/wall base points so incomplete plane mesh under-sizes less.
     */
    private fun sampleDepthAssistRays(frame: com.google.ar.core.Frame) {
        try {
            if (arSceneView.width <= 0 || arSceneView.height <= 0) return
            val yFloor = lastSamplePose?.get(1) ?: 0f
            val rays = arrayOf(
                0.18f to 0.58f,
                0.82f to 0.58f,
                0.50f to 0.42f,
                0.50f to 0.72f,
                0.30f to 0.50f,
                0.70f to 0.50f,
            )
            for ((nx, ny) in rays) {
                val cx = arSceneView.width * nx
                val cy = arSceneView.height * ny
                val hits = frame.hitTest(cx, cy)
                val best = hits.firstOrNull { h ->
                    val t = h.trackable
                    t is Plane && t.trackingState == TrackingState.TRACKING
                } ?: hits.firstOrNull()
                if (best != null) {
                    val p = best.hitPose
                    // Project to floor Y for planar cloud fit
                    maybeAddSample(floatArrayOf(p.tx(), yFloor, p.tz()))
                    depthSampleCount++
                }
            }
        } catch (_: Exception) {
        }
    }

    /**
     * +135 wall-distance lock: measure camera → wall hit range by heading.
     * Uses vertical planes first (true walls), then mid-height Instant Placement.
     */
    private fun sampleWallRanges(frame: com.google.ar.core.Frame) {
        try {
            if (arSceneView.width <= 0 || arSceneView.height <= 0) return
            val cam = frame.camera.pose
            val camX = cam.tx().toDouble()
            val camZ = cam.tz().toDouble()
            // Forward vector on XZ from camera rotation
            val fwd = FloatArray(3)
            cam.getTransformedAxis(2, 1f, fwd) // -Z is forward in ARCore; use axis 2
            // Heading of camera look on XZ (prefer -Z forward)
            var hx = (-fwd[0]).toDouble()
            var hz = (-fwd[2]).toDouble()
            val hLen = sqrt(hx * hx + hz * hz)
            if (hLen < 1e-4) return
            hx /= hLen
            hz /= hLen

            val rays = arrayOf(
                0.50f to 0.42f, // slightly above center (walls, not floor)
                0.35f to 0.45f,
                0.65f to 0.45f,
            )
            for ((nx, ny) in rays) {
                val cx = arSceneView.width * nx
                val cy = arSceneView.height * ny
                val hits = frame.hitTest(cx, cy)
                val best = hits.firstOrNull { h ->
                    val t = h.trackable
                    t is Plane &&
                        t.type == Plane.Type.VERTICAL &&
                        t.trackingState == TrackingState.TRACKING
                } ?: hits.firstOrNull { h ->
                    val t = h.trackable
                    t is Plane && t.trackingState == TrackingState.TRACKING
                }
                if (best == null) continue
                val p = best.hitPose
                val dx = p.tx().toDouble() - camX
                val dz = p.tz().toDouble() - camZ
                val dist = sqrt(dx * dx + dz * dz)
                // Plausible wall clearance while walking inside a room
                if (dist < 0.40 || dist > 8.0) continue
                // Prefer hits roughly in look direction
                val lookDot = (dx * hx + dz * hz) / dist
                if (lookDot < 0.35) continue
                val heading = atan2(dz, dx) // world XZ heading of hit
                var bin = ((heading + Math.PI) / (2 * Math.PI) * 8).toInt()
                if (bin < 0) bin = 0
                if (bin > 7) bin = 7
                val bucket = wallRangeBins[bin]
                if (bucket.size > 40) {
                    // thin early samples
                    val kept = bucket.filterIndexed { i, _ -> i % 2 == 1 }.toMutableList()
                    bucket.clear()
                    bucket.addAll(kept)
                }
                bucket.add(dist)
                if (depthEnabled) depthSampleCount++
            }
            recomputeWallLock()
        } catch (_: Exception) {
        }
    }

    /**
     * Secondary wall lock from heading-bin ranges when vertical plane pairs
     * are sparse (user walked but ARCore hasn't meshed both opposite walls).
     */
    private fun recomputeWallLock() {
        // Prefer vertical-plane pairs when we already have ≥2
        if (wallLockPairs >= 2 && wallLockWidthM >= 1.8) return
        fun med(vals: List<Double>): Double {
            if (vals.isEmpty()) return 0.0
            val s = vals.sorted()
            return s[s.size / 2]
        }
        val axes = mutableListOf<Double>()
        for (i in 0 until 4) {
            val a = med(wallRangeBins[i])
            val b = med(wallRangeBins[i + 4])
            if (a >= 0.40 && b >= 0.40) axes.add(a + b)
        }
        if (axes.size < 2) return
        axes.sortDescending()
        val ww = max(axes[0], axes[1])
        val ll = min(axes[0], axes[1])
        if (ww < 1.5 || ll < 1.2) return
        // Soft fill only if empty or expand under-size lock
        if (wallLockPairs == 0) {
            wallLockWidthM = ww
            wallLockLengthM = ll
            wallLockPairs = 1 // weaker than plane pairs
        } else if (ww > wallLockWidthM && ww / wallLockWidthM <= 1.35) {
            wallLockWidthM = wallLockWidthM * 0.4 + ww * 0.6
            wallLockLengthM = wallLockLengthM * 0.4 + ll * 0.6
        }
    }

    private fun sampleScreenHit(nx: Float, ny: Float) {
        try {
            val frame = arSceneView.frame ?: return
            if (frame.timestamp == 0L) return
            val cx = arSceneView.width * nx
            val cy = arSceneView.height * ny
            val hits = frame.hitTest(cx, cy)
            val best = hits.firstOrNull { h ->
                val t = h.trackable
                t is Plane &&
                    t.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    t.trackingState == TrackingState.TRACKING
            } ?: hits.firstOrNull()
            if (best != null) {
                val p = best.hitPose
                maybeAddSample(floatArrayOf(p.tx(), p.ty(), p.tz()))
            }
        } catch (_: Exception) {
        }
    }

    private fun maybeAddSample(xyz: FloatArray) {
        val last = lastSamplePose
        if (last != null && distance(last, xyz) < 0.14) return
        // Cap cloud size
        if (walkSamples.size > 500) {
            // thin: drop every other early sample
            val kept = walkSamples.filterIndexed { i, _ -> i % 2 == 1 }.toMutableList()
            walkSamples.clear()
            walkSamples.addAll(kept)
        }
        walkSamples.add(xyz)
        lastSamplePose = xyz
    }

    private fun recomputeAutoSize() {
        val dims = resolveCloudMeters(walkSamples) ?: return
        val prevW = autoWidthM
        val prevL = autoLengthM
        var w = dims.widthM
        var l = dims.lengthM
        lastCoverageScore = dims.coverageScore
        lastOrthoScore = dims.orthogonalScore
        lastDiagError = dims.diagonalError

        // +128/+130: expand using camera pose trail (interior path + adaptive standoff)
        val poseDims = if (poseSamples.size >= 8) resolveCloudMeters(poseSamples) else null
        if (poseDims != null) {
            var stand = 0.75 // Planner5D-class half-standoff meters
            // Adaptive: half-gap between floor cloud and pose path when floor is larger
            val gapW = (max(w, l) - max(poseDims.widthM, poseDims.lengthM)) / 2.0
            val gapL = (min(w, l) - min(poseDims.widthM, poseDims.lengthM)) / 2.0
            val gap = max(gapW, gapL)
            if (lastCoverageScore >= 0.5 && gap in 0.30..1.40) {
                stand = (stand * 0.35 + gap * 0.65).coerceIn(0.35, 1.25)
            }
            val poseW = max(poseDims.widthM, poseDims.lengthM) + 2 * stand
            val poseL = min(poseDims.widthM, poseDims.lengthM) + 2 * stand
            if (lastCoverageScore < 0.75) {
                w = max(w, w * 0.45 + poseW * 0.55)
                l = max(l, l * 0.45 + poseL * 0.55)
            } else {
                w = max(w, min(poseW, w * 1.12))
                l = max(l, min(poseL, l * 1.12))
            }
            lastCoverageScore = max(lastCoverageScore, poseDims.coverageScore * 0.9)
        }

        // +126: fuse largest ARCore plane extent when coverage still incomplete
        // (partial walk underestimates; plane growth helps — Planner5D tip)
        val pW = max(planeExtentXM, planeExtentZM)
        val pL = min(planeExtentXM, planeExtentZM)
        if (pW >= 1.0 && pL >= 1.0 && lastCoverageScore < 0.85) {
            // Soft expand toward plane if plane is larger but within 25%
            if (pW > w && pW / w <= 1.25) w = w * 0.55 + pW * 0.45
            if (pL > l && pL / l <= 1.25) l = l * 0.55 + pL * 0.45
        }

        // +135: wall-to-wall lock from opposite vertical planes (highest trust)
        if (wallLockWidthM >= 1.8 && wallLockLengthM >= 1.5 && wallLockPairs > 0) {
            val ww = max(wallLockWidthM, wallLockLengthM)
            val ll = min(wallLockWidthM, wallLockLengthM)
            // Prefer wall lock when cloud is smaller (under-size) or agrees within 18%
            val agreeW = abs(ww - max(w, l)) / ww
            val agreeL = abs(ll - min(w, l)) / ll
            if (ww > max(w, l) * 0.95 || agreeW < 0.18) {
                w = if (agreeW < 0.12) w * 0.35 + ww * 0.65 else max(w, ww * 0.92)
            }
            if (ll > min(w, l) * 0.95 || agreeL < 0.18) {
                l = if (agreeL < 0.12) l * 0.35 + ll * 0.65 else max(l, ll * 0.92)
            }
            // Strong lock: both dimensions from wall pairs
            if (wallLockPairs >= 2 && agreeW < 0.20 && agreeL < 0.20) {
                w = ww
                l = ll
                lastOrthoScore = max(lastOrthoScore, 0.96)
                lastCoverageScore = max(lastCoverageScore, 0.85)
            }
        }

        autoWidthM = max(w, l)
        autoLengthM = min(w, l)
        refreshWalkMap()
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
                    // +132: size ready = Done ready (never fake 100% cover wait).
                    // +135: auto-finish only when map quality is OK (avoids 10×10 half-walks).
                    val readyNow = walkSamples.size >= 8 || poseSamples.size >= 12
                    val qualityOk = lastCoverageScore >= 0.55 ||
                        (walkSamples.size >= 28 && poseSamples.size >= 20 && lastCoverageScore >= 0.40) ||
                        (wallLockWidthM >= 2.0 && wallLockLengthM >= 1.5 && walkSamples.size >= 16)
                    liveDistance.text = if (readyNow && qualityOk) {
                        String.format(
                            "%.1f × %.1f ft — tap Done",
                            autoWidthM * M_TO_FT,
                            autoLengthM * M_TO_FT,
                        )
                    } else if (readyNow) {
                        String.format(
                            "%.1f × %.1f ft — walk all walls…",
                            autoWidthM * M_TO_FT,
                            autoLengthM * M_TO_FT,
                        )
                    } else {
                        String.format(
                            "%.1f × %.1f ft — keep walking…",
                            autoWidthM * M_TO_FT,
                            autoLengthM * M_TO_FT,
                        )
                    }
                    liveDistance.setTextColor(
                        if (readyNow && qualityOk) 0xFFAED581.toInt() else 0xFFFFCC80.toInt(),
                    )
                    // Auto-finish only when size stable AND walk quality OK (+135)
                    if (readyNow && qualityOk && autoStableTicks >= 12 && !destroyed) {
                        handler.post {
                            if (!destroyed && autoMode) finishWithResult()
                        }
                    }
                } else if (planes > 0 || walkSamples.isNotEmpty()) {
                    liveDistance.text =
                        "Mapping room… walk around"
                    liveDistance.setTextColor(0xFF80CBC4.toInt())
                } else {
                    liveDistance.text = "Walk around the room slowly"
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
        val aimFrom: FloatArray = when {
            polygonMode && cornerDots.isNotEmpty() && cornerDots.size < totalCorners ->
                cornerDots.last()
            pendingStartPose != null -> pendingStartPose!!
            else -> return null
        }
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
            stepTitle.text = "Scan the room"
            stepHint.text =
                "Walk around the room with the camera on the floor. " +
                    "This measures room size only. Furniture is added on the plan after you tap Done."
            btnMark.visibility = android.view.View.GONE
            btnDone.text = "Done — open plan"
            measuredSummary.text = buildString {
                if (autoWidthM >= 0.5 && autoLengthM >= 0.5) {
                    append(
                        String.format(
                            "Room ~%.0f × %.0f ft",
                            autoWidthM * M_TO_FT,
                            autoLengthM * M_TO_FT,
                        ),
                    )
                    append(" · ${walkSamples.size} map points")
                    if (wallLockPairs > 0) append(" · walls locked")
                    if (depthEnabled) append(" · depth")
                    append("\nTap Done to open your plan with furniture.")
                } else {
                    append("Walk around until room size appears…")
                }
            }
            // +132: Done as soon as we have a usable size — never wait for 100% cover
            val ready = autoWidthM >= 1.5 && autoLengthM >= 1.5 &&
                (walkSamples.size >= 8 || poseSamples.size >= 12)
            btnDone.isEnabled = ready
            return
        }

        if (polygonMode) {
            btnMark.visibility = android.view.View.VISIBLE
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
            val arr = wallMeters.toDoubleArray()
            if (arr.isEmpty()) doubleArrayOf(w, l, w, l) else arr
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
            putExtra(EXTRA_COVERAGE_SCORE, lastCoverageScore)
            putExtra(EXTRA_DEPTH_ENABLED, depthEnabled)
            putExtra(EXTRA_DEPTH_SAMPLES, depthSampleCount)
            putExtra(EXTRA_WALL_LOCK_W_M, wallLockWidthM)
            putExtra(EXTRA_WALL_LOCK_L_M, wallLockLengthM)
            putExtra(EXTRA_WALL_LOCK_PAIRS, wallLockPairs)
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
            // +127 Home Scan pose trail
            if (poseSamples.isNotEmpty()) {
                val flatP = FloatArray(poseSamples.size * 3)
                poseSamples.forEachIndexed { i, p ->
                    flatP[i * 3] = p[0]
                    flatP[i * 3 + 1] = p[1]
                    flatP[i * 3 + 2] = p[2]
                }
                putExtra(EXTRA_POSES_M, flatP)
            }
            putExtra(EXTRA_SAMPLE_COUNT, if (autoMode) walkSamples.size else cornerDots.size)
            putExtra(EXTRA_POSE_COUNT, poseSamples.size)
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
        val coverageScore: Double = 1.0,
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
        /** +127 camera pose trail flat x,y,z meters. */
        const val EXTRA_POSES_M = "poses_m"
        const val EXTRA_SAMPLE_COUNT = "sample_count"
        const val EXTRA_POSE_COUNT = "pose_count"
        const val EXTRA_ORTHO_SCORE = "ortho_score"
        const val EXTRA_DIAG_ERROR = "diag_error"
        /** +126 walk angular coverage 0..1. */
        const val EXTRA_COVERAGE_SCORE = "coverage_score"
        /** +131 Depth API was enabled for this measure. */
        const val EXTRA_DEPTH_ENABLED = "depth_enabled"
        const val EXTRA_DEPTH_SAMPLES = "depth_samples"
        /** +135 opposite vertical plane wall-to-wall (meters). */
        const val EXTRA_WALL_LOCK_W_M = "wall_lock_w_m"
        const val EXTRA_WALL_LOCK_L_M = "wall_lock_l_m"
        const val EXTRA_WALL_LOCK_PAIRS = "wall_lock_pairs"
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

        /** +125/+126 robust PCA + percentile hull for walk cloud. */
        fun resolveCloudMeters(dots: List<FloatArray>): PolygonDims? {
            if (dots.size < 4) return null
            var work = statisticalOutlierTrim(dots)
            if (work.size < 4) work = dots
            var cx = 0.0
            var cz = 0.0
            for (p in work) {
                cx += p[0]
                cz += p[2]
            }
            cx /= work.size
            cz /= work.size
            var sxx = 0.0
            var sxz = 0.0
            var szz = 0.0
            for (p in work) {
                val dx = p[0] - cx
                val dz = p[2] - cz
                sxx += dx * dx
                sxz += dx * dz
                szz += dz * dz
            }
            val n = work.size.toDouble()
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
            val us = ArrayList<Double>(work.size)
            val vs = ArrayList<Double>(work.size)
            for (p in work) {
                val dx = p[0] - cx
                val dz = p[2] - cz
                us.add(dx * ux + dz * uz)
                vs.add(dx * vx + dz * vz)
            }
            var sideA = abs(percentile(us, 0.98) - percentile(us, 0.02))
            var sideB = abs(percentile(vs, 0.98) - percentile(vs, 0.02))
            val cov = angularCoverage(work, cx, cz)
            if (cov >= 0.75) {
                val sideA2 = abs(percentile(us, 0.995) - percentile(us, 0.005))
                val sideB2 = abs(percentile(vs, 0.995) - percentile(vs, 0.005))
                sideA = sideA * 0.70 + sideA2 * 0.30
                sideB = sideB * 0.70 + sideB2 * 0.30
            }
            if (sideA < 0.5 || sideB < 0.5) return null
            val ortho = (0.78 + 0.20 * cov).coerceIn(0.70, 0.98)
            return PolygonDims(
                widthM = max(sideA, sideB),
                lengthM = min(sideA, sideB),
                oppositeEdgeError = 0.0,
                diagonalError = 0.0,
                orthogonalScore = ortho,
                coverageScore = cov,
            )
        }

        private fun angularCoverage(
            pts: List<FloatArray>,
            cx: Double,
            cz: Double,
        ): Double {
            if (pts.isEmpty()) return 0.0
            val bins = IntArray(8)
            for (p in pts) {
                val a = atan2(p[2] - cz, p[0] - cx)
                var i = ((a + Math.PI) / (2 * Math.PI) * 8).toInt()
                if (i < 0) i = 0
                if (i > 7) i = 7
                bins[i]++
            }
            val filled = bins.count { it > 0 }
            return filled / 8.0
        }

        private fun statisticalOutlierTrim(pts: List<FloatArray>): List<FloatArray> {
            var work = pts
            repeat(2) {
                if (work.size < 8) return work
                var mx = 0.0
                var mz = 0.0
                for (p in work) {
                    mx += p[0]
                    mz += p[2]
                }
                mx /= work.size
                mz /= work.size
                val dists = work.map { p ->
                    val dx = p[0] - mx
                    val dz = p[2] - mz
                    sqrt(dx * dx + dz * dz)
                }
                val med = percentile(dists, 0.5)
                val mad = percentile(dists.map { abs(it - med) }, 0.5)
                if (mad < 0.05) return work
                val thr = med + 3.5 * mad * 1.4826
                val kept = work.filterIndexed { i, _ -> dists[i] <= thr }
                if (kept.size < 4 || kept.size == work.size) return work
                work = kept
            }
            return work
        }

        private fun percentile(values: List<Double>, p: Double): Double {
            if (values.isEmpty()) return 0.0
            val s = values.sorted()
            if (s.size == 1) return s[0]
            val t = p.coerceIn(0.0, 1.0) * (s.size - 1)
            val i = t.toInt()
            val f = t - i
            if (i >= s.size - 1) return s.last()
            return s[i] * (1 - f) + s[i + 1] * f
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
