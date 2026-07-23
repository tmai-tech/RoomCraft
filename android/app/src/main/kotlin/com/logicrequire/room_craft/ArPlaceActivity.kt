package com.logicrequire.room_craft

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.logicrequire.room_craft.ar.BackgroundRenderer
import com.logicrequire.room_craft.ar.DisplayRotationHelper
import java.util.ArrayList
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.sqrt

/**
 * AR place furniture — same +121 black-camera pipeline as [ArMeasureActivity].
 */
class ArPlaceActivity : AppCompatActivity(), GLSurfaceView.Renderer {

    companion object {
        const val REQUEST_CODE = 7144
        const val EXTRA_WIDTH_FT = "width_ft"
        const val EXTRA_LENGTH_FT = "length_ft"
        const val EXTRA_PLACEMENTS = "placements"
        private const val TAG = "ArPlace"
        private const val REQ_CAMERA = 7146
        private const val M_TO_FT = 3.280839895
        private val FURN_TYPES = listOf(
            "sofa", "bed", "table", "chair", "wardrobe",
            "tvUnit", "desk", "plant", "lamp", "bookshelf",
        )
    }

    private lateinit var surfaceView: GLSurfaceView
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveInfo: TextView
    private lateinit var btnPlace: Button
    private lateinit var btnNextType: Button
    private lateinit var btnDone: Button
    private lateinit var btnUndo: Button

    private var session: Session? = null
    private lateinit var displayRotationHelper: DisplayRotationHelper
    private val backgroundRenderer = BackgroundRenderer()
    private val installRequested = AtomicBoolean(false)
    @Volatile private var surfaceCreated = false
    @Volatile private var sessionResumed = false
    @Volatile private var textureBound = false

    private var origin: FloatArray? = null
    private var xAxis: FloatArray? = null
    private var zAxis: FloatArray? = null
    private val placed = mutableListOf<Placed>()
    private var typeIndex = 0
    private var roomWidthFt: Double = 12.0
    private var roomLengthFt: Double = 12.0

    private val placeRequested = AtomicBoolean(false)
    private val trackingUiCounter = AtomicInteger(0)
    private var firstFrameAtMs = 0L
    private var cameraOk = false
    private var blackScreenWarned = false

    private data class Placed(
        val type: String,
        val world: FloatArray,
        val anchor: Anchor,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            roomWidthFt = intent.getDoubleExtra(EXTRA_WIDTH_FT, 12.0).coerceIn(3.0, 120.0)
            roomLengthFt = intent.getDoubleExtra(EXTRA_LENGTH_FT, 12.0).coerceIn(3.0, 120.0)
            setContentView(R.layout.activity_ar_place)
            displayRotationHelper = DisplayRotationHelper(this)

            surfaceView = findViewById(R.id.ar_surface)
            stepTitle = findViewById(R.id.step_title)
            stepHint = findViewById(R.id.step_hint)
            liveInfo = findViewById(R.id.live_info)
            btnPlace = findViewById(R.id.btn_place)
            btnNextType = findViewById(R.id.btn_next_type)
            btnDone = findViewById(R.id.btn_done)
            btnUndo = findViewById(R.id.btn_undo)

            findViewById<Button>(R.id.btn_cancel).setOnClickListener {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
            btnPlace.setOnClickListener { placeRequested.set(true) }
            btnNextType.setOnClickListener {
                typeIndex = (typeIndex + 1) % FURN_TYPES.size
                updateUi()
            }
            btnUndo.setOnClickListener { undoLast() }
            btnDone.setOnClickListener { finishWithResult() }

            surfaceView.preserveEGLContextOnPause = true
            surfaceView.setEGLContextClientVersion(2)
            surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            surfaceView.setRenderer(this)
            surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

            updateUi()
            liveInfo.text = "Starting camera…"
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            Toast.makeText(this, "AR place failed: ${e.message}", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun currentType() = FURN_TYPES[typeIndex]

    private fun updateUi() {
        when {
            origin == null -> {
                stepTitle.text = "AR place · Step 1/3 — SW origin"
                stepHint.text =
                    "Wait until you SEE the live camera (not black). " +
                        "Then Tracking · floor planes → Mark SW corner."
                btnPlace.text = "Mark origin (SW)"
            }
            xAxis == null || zAxis == null -> {
                stepTitle.text = "AR place · Step 2/3 — width axis (+X)"
                stepHint.text = "Mark SE corner along the WIDTH wall from SW."
                btnPlace.text = "Mark +X (SE / width end)"
            }
            else -> {
                stepTitle.text = "AR place · Step 3/3 · ${currentType()} (${placed.size})"
                stepHint.text =
                    "Place ${currentType()} on floor. Room " +
                        "${"%.0f".format(roomWidthFt)}×${"%.0f".format(roomLengthFt)} ft."
                btnPlace.text = "Place ${currentType()}"
            }
        }
        if (origin != null && xAxis != null) {
            liveInfo.text = placed.joinToString(" · ") { it.type }.ifEmpty { "Axes set" }
        }
    }

    private fun projectToPlanFt(world: FloatArray): Pair<Double, Double> {
        val o = origin ?: return 0.0 to 0.0
        val xU = xAxis
        val zU = zAxis
        val dx = (world[0] - o[0]).toDouble()
        val dy = (world[1] - o[1]).toDouble()
        val dz = (world[2] - o[2]).toDouble()
        if (xU == null || zU == null) {
            return kotlin.math.abs(dx) * M_TO_FT to kotlin.math.abs(dz) * M_TO_FT
        }
        val fromLeftM = dx * xU[0] + dy * xU[1] + dz * xU[2]
        val fromBottomM = dx * zU[0] + dy * zU[1] + dz * zU[2]
        return fromLeftM * M_TO_FT to fromBottomM * M_TO_FT
    }

    private fun setAxesFromXPoint(xPoint: FloatArray): Boolean {
        val o = origin ?: return false
        var vx = (xPoint[0] - o[0]).toDouble()
        var vz = (xPoint[2] - o[2]).toDouble()
        val len = sqrt(vx * vx + vz * vz)
        if (len < 0.25) {
            Toast.makeText(this, "Too close to origin — mark far end of width wall", Toast.LENGTH_SHORT).show()
            return false
        }
        vx /= len
        vz /= len
        var zx = -vz
        var zz = vx
        val zLen = sqrt(zx * zx + zz * zz)
        if (zLen < 1e-6) {
            zx = 0.0
            zz = 1.0
        } else {
            zx /= zLen
            zz /= zLen
        }
        xAxis = floatArrayOf(vx.toFloat(), 0f, vz.toFloat())
        zAxis = floatArrayOf(zx.toFloat(), 0f, zz.toFloat())
        Toast.makeText(this, "Axes set — place furniture", Toast.LENGTH_SHORT).show()
        return true
    }

    override fun onResume() {
        super.onResume()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
            return
        }
        try {
            if (session == null) {
                when (ArCoreApk.getInstance().requestInstall(this, !installRequested.get())) {
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                        installRequested.set(true)
                        return
                    }
                    else -> {}
                }
                session = Session(this).also { s ->
                    val config = Config(s)
                    config.updateMode = Config.UpdateMode.BLOCKING
                    config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    config.focusMode = Config.FocusMode.AUTO
                    // +121: depth OFF — black camera on many devices
                    config.depthMode = Config.DepthMode.DISABLED
                    config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                    s.configure(config)
                }
            }
            try {
                session?.resume()
                sessionResumed = true
            } catch (e: CameraNotAvailableException) {
                sessionResumed = false
                liveInfo.text = "Camera busy — close other camera apps"
            }
            surfaceView.onResume()
            displayRotationHelper.onResume()
        } catch (e: Exception) {
            Log.e(TAG, "onResume", e)
            Toast.makeText(this, "AR resume failed: ${e.message}", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                onResume()
            } else {
                Toast.makeText(this, "Camera permission required", Toast.LENGTH_LONG).show()
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            surfaceView.onPause()
            displayRotationHelper.onPause()
            sessionResumed = false
            textureBound = false
            session?.pause()
        } catch (e: Exception) {
            Log.w(TAG, "onPause", e)
        }
    }

    override fun onDestroy() {
        try {
            placed.forEach {
                try {
                    it.anchor.detach()
                } catch (_: Exception) {
                }
            }
            session?.close()
            session = null
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.05f, 0.05f, 0.08f, 1f)
        try {
            backgroundRenderer.createOnGlThread(this)
            surfaceCreated = true
            firstFrameAtMs = SystemClock.elapsedRealtime()
        } catch (e: Exception) {
            Log.e(TAG, "GL create", e)
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = session ?: return
        if (!surfaceCreated || backgroundRenderer.textureId < 0) return
        try {
            displayRotationHelper.updateSessionIfNeeded(session)
            session.setCameraTextureName(backgroundRenderer.textureId)
            textureBound = true
            if (!sessionResumed) {
                runOnUiThread {
                    try {
                        session.resume()
                        sessionResumed = true
                    } catch (e: CameraNotAvailableException) {
                        liveInfo.text = "Camera busy — close other apps"
                    }
                }
                return
            }
            val frame = session.update()
            val drew = backgroundRenderer.draw(frame)
            if (drew && !cameraOk) {
                cameraOk = true
                runOnUiThread { liveInfo.text = "Camera OK · find floor" }
            }
            if (!cameraOk && !blackScreenWarned && firstFrameAtMs > 0 &&
                SystemClock.elapsedRealtime() - firstFrameAtMs > 3500
            ) {
                blackScreenWarned = true
                runOnUiThread {
                    liveInfo.text = "No camera image — retry AR"
                    Toast.makeText(
                        this,
                        "AR camera failed (black). Update Play Services for AR and retry.",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }

            val n = trackingUiCounter.incrementAndGet()
            if (n % 12 == 0 && cameraOk && (origin == null || xAxis == null)) {
                var planes = 0
                for (p in session.getAllTrackables(Plane::class.java)) {
                    if (p.trackingState == TrackingState.TRACKING) planes++
                }
                val cam = frame.camera.trackingState
                runOnUiThread {
                    liveInfo.text = when (cam) {
                        TrackingState.TRACKING ->
                            if (planes > 0) "Tracking · $planes floor plane(s)"
                            else "Tracking · point at floor…"
                        TrackingState.PAUSED -> "Tracking paused"
                        TrackingState.STOPPED -> "Tracking stopped"
                    }
                }
            }

            if (placeRequested.compareAndSet(true, false)) {
                processPlaceOnGlThread(session, frame)
            }
        } catch (e: CameraNotAvailableException) {
            sessionResumed = false
        } catch (e: Exception) {
            Log.w(TAG, "draw", e)
        }
    }

    private fun processPlaceOnGlThread(session: Session, frame: Frame) {
        try {
            if (!cameraOk) {
                runOnUiThread {
                    Toast.makeText(this, "Wait for camera image first", Toast.LENGTH_SHORT).show()
                }
                return
            }
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                runOnUiThread {
                    Toast.makeText(this, "Move phone slowly until tracking locks", Toast.LENGTH_SHORT).show()
                }
                return
            }
            val w = surfaceView.width
            val h = surfaceView.height
            if (w <= 0 || h <= 0) return
            val hits = frame.hitTest(w / 2f, h / 2f)
            val hit = hits.firstOrNull {
                it.trackable is Plane &&
                    (it.trackable as Plane).type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    (it.trackable as Plane).trackingState == TrackingState.TRACKING
            } ?: hits.firstOrNull { it.trackable is Plane } ?: hits.firstOrNull()

            if (hit == null) {
                runOnUiThread {
                    Toast.makeText(this, "No floor at center — point at floor", Toast.LENGTH_SHORT).show()
                }
                return
            }
            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            val anchor = hit.createAnchor()
            runOnUiThread {
                when {
                    origin == null -> {
                        origin = xyz
                        Toast.makeText(this, "Origin set — mark +X along width", Toast.LENGTH_SHORT).show()
                        updateUi()
                    }
                    xAxis == null || zAxis == null -> {
                        if (setAxesFromXPoint(xyz)) {
                            try {
                                anchor.detach()
                            } catch (_: Exception) {
                            }
                            updateUi()
                        }
                    }
                    else -> {
                        placed.add(Placed(currentType(), xyz, anchor))
                        val (fl, fb) = projectToPlanFt(xyz)
                        Toast.makeText(
                            this,
                            String.format(
                                "Placed %s @ %.1f × %.1f ft",
                                currentType(),
                                fl.coerceIn(0.0, roomWidthFt),
                                fb.coerceIn(0.0, roomLengthFt),
                            ),
                            Toast.LENGTH_SHORT,
                        ).show()
                        updateUi()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "processPlace", e)
            runOnUiThread {
                Toast.makeText(this, "Place failed: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun undoLast() {
        placeRequested.set(false)
        if (placed.isNotEmpty()) {
            val last = placed.removeAt(placed.lastIndex)
            try {
                last.anchor.detach()
            } catch (_: Exception) {
            }
            updateUi()
            return
        }
        if (xAxis != null || zAxis != null) {
            xAxis = null
            zAxis = null
            updateUi()
            return
        }
        if (origin != null) {
            origin = null
            updateUi()
        }
    }

    private fun finishWithResult() {
        placeRequested.set(false)
        if (origin == null) {
            Toast.makeText(this, "Mark origin first", Toast.LENGTH_SHORT).show()
            return
        }
        if (xAxis == null || zAxis == null) {
            Toast.makeText(this, "Mark +X before Done", Toast.LENGTH_SHORT).show()
            return
        }
        val list = ArrayList<HashMap<String, Any>>()
        for (p in placed) {
            val (left, bottom) = projectToPlanFt(p.world)
            list.add(
                hashMapOf(
                    "type" to p.type,
                    "fromLeftFt" to left.coerceIn(0.0, roomWidthFt),
                    "fromBottomFt" to bottom.coerceIn(0.0, roomLengthFt),
                    "oriented" to true,
                ),
            )
        }
        val data = Intent()
        data.putExtra(EXTRA_PLACEMENTS, list)
        setResult(Activity.RESULT_OK, data)
        finish()
    }
}
