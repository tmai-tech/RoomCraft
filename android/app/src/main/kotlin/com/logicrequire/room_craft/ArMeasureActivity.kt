package com.logicrequire.room_craft

import android.app.Activity
import android.content.Intent
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import com.logicrequire.room_craft.ar.BackgroundRenderer
import com.logicrequire.room_craft.ar.DisplayRotationHelper
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Pure ARCore room measure — no Sceneform (avoids common native crashes).
 *
 * User points the center reticle at floor corners and taps "Mark corner".
 * Modes: quick (width then length) or chain (walls A–D) + optional diagonal.
 */
class ArMeasureActivity : AppCompatActivity(), GLSurfaceView.Renderer {

    private lateinit var surfaceView: GLSurfaceView
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveDistance: TextView
    private lateinit var measuredSummary: TextView
    private lateinit var btnMark: Button
    private lateinit var btnDone: Button
    private lateinit var btnUndo: Button

    private var session: Session? = null
    private lateinit var displayRotationHelper: DisplayRotationHelper
    private val backgroundRenderer = BackgroundRenderer()

    private val installRequested = AtomicBoolean(false)
    private var surfaceCreated = false

    private val anchors = mutableListOf<Anchor>()
    private val wallMeters = mutableListOf<Double>()
    private var pendingStartPose: FloatArray? = null // world translation xyz of first corner in segment

    private var chainMode = false
    private var tapsInSegment = 0
    private var measuringDiagonal = false
    private var diagonalMeters: Double? = null

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
            setContentView(R.layout.activity_ar_measure)
            chainMode = intent.getStringExtra(EXTRA_MODE) == MODE_CHAIN
            displayRotationHelper = DisplayRotationHelper(this)

            surfaceView = findViewById(R.id.ar_surface)
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

            surfaceView.preserveEGLContextOnPause = true
            surfaceView.setEGLContextClientVersion(2)
            surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            surfaceView.setRenderer(this)
            surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
            surfaceView.setOnTouchListener { _, _ -> true } // consume; use button

            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            failAndFinish(e.message ?: "AR failed to start")
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            if (session == null) {
                when (ArCoreApk.getInstance().requestInstall(this, !installRequested.get())) {
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                        installRequested.set(true)
                        return
                    }
                    ArCoreApk.InstallStatus.INSTALLED -> {}
                }
                session = Session(this).also { configureSession(it) }
            }
            session?.resume()
            surfaceView.onResume()
            displayRotationHelper.onResume()
        } catch (e: UnavailableException) {
            Log.e(TAG, "AR unavailable", e)
            failAndFinish(e.message ?: "ARCore unavailable on this device")
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "camera", e)
            failAndFinish("Camera not available — close other camera apps and retry")
        } catch (e: Exception) {
            Log.e(TAG, "onResume", e)
            failAndFinish(e.message ?: "Could not start AR session")
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            if (::surfaceView.isInitialized) surfaceView.onPause()
            if (::displayRotationHelper.isInitialized) displayRotationHelper.onPause()
            session?.pause()
        } catch (e: Exception) {
            Log.w(TAG, "onPause", e)
        }
    }

    override fun onDestroy() {
        try {
            anchors.forEach { it.detach() }
            anchors.clear()
            session?.close()
            session = null
        } catch (e: Exception) {
            Log.w(TAG, "onDestroy", e)
        }
        super.onDestroy()
    }

    private fun configureSession(session: Session) {
        val config = Config(session)
        config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
            config.depthMode = Config.DepthMode.AUTOMATIC
        }
        session.configure(config)
    }

    private fun failAndFinish(message: String) {
        try {
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        } catch (_: Exception) {
        }
        setResult(Activity.RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    // ─── GLSurfaceView.Renderer ───────────────────────────────────────────

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
        try {
            backgroundRenderer.createOnGlThread(this)
            surfaceCreated = true
        } catch (e: Exception) {
            Log.e(TAG, "GL init", e)
            runOnUiThread { failAndFinish("Graphics init failed: ${e.message}") }
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = session ?: return
        if (!surfaceCreated) return
        try {
            displayRotationHelper.updateSessionIfNeeded(session)
            session.setCameraTextureName(backgroundRenderer.textureId)
            val frame = session.update()
            backgroundRenderer.draw(frame)
        } catch (e: Exception) {
            Log.w(TAG, "draw", e)
        }
    }

    // ─── Measure logic ───────────────────────────────────────────────────

    private fun markCenterHit() {
        val session = session
        if (session == null) {
            Toast.makeText(this, "AR session not ready", Toast.LENGTH_SHORT).show()
            return
        }
        try {
            val frame = session.update()
            val camera = frame.camera
            if (camera.trackingState != TrackingState.TRACKING) {
                Toast.makeText(
                    this,
                    "Move phone slowly until tracking is stable (look at the floor)",
                    Toast.LENGTH_SHORT,
                ).show()
                return
            }

            val cx = surfaceView.width / 2f
            val cy = surfaceView.height / 2f
            val hits = frame.hitTest(cx, cy)
            // Prefer horizontal plane hits
            val hit = hits.firstOrNull { h ->
                val t = h.trackable
                t is com.google.ar.core.Plane &&
                    t.type == com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    t.isPoseInPolygon(h.hitPose)
            } ?: hits.firstOrNull {
                it.trackable is com.google.ar.core.Plane
            } ?: hits.firstOrNull()

            if (hit == null) {
                Toast.makeText(
                    this,
                    "No floor detected at center — point at the floor and try again",
                    Toast.LENGTH_SHORT,
                ).show()
                return
            }

            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            val anchor = hit.createAnchor()
            anchors.add(anchor)

            if (measuringDiagonal) {
                handleDiagonalPoint(xyz)
            } else {
                handleWallPoint(xyz)
            }
        } catch (e: Exception) {
            Log.e(TAG, "markCenterHit", e)
            Toast.makeText(this, "Measure failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleWallPoint(xyz: FloatArray) {
        if (wallMeters.size >= totalWalls) return
        tapsInSegment++
        if (tapsInSegment == 1) {
            pendingStartPose = xyz
            liveDistance.text = "Corner 1 set — mark other end"
            Toast.makeText(this, "Corner 1 set", Toast.LENGTH_SHORT).show()
        } else {
            val start = pendingStartPose
            if (start == null) {
                tapsInSegment = 0
                return
            }
            val dist = distance(start, xyz)
            if (dist < 0.4) {
                Toast.makeText(this, "Too short — mark corners further apart", Toast.LENGTH_SHORT).show()
                // remove last two anchors
                detachLastAnchor()
                detachLastAnchor()
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
                    "Optional: mark two opposite corners for diagonal check",
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
            liveDistance.text = "Diagonal corner 1 — mark opposite corner"
        } else {
            val start = pendingStartPose ?: xyz
            val dist = distance(start, xyz)
            diagonalMeters = dist
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
        Toast.makeText(this, String.format("Scale refined from diagonal (×%.2f)", scale), Toast.LENGTH_LONG).show()
    }

    private fun labels() = if (chainMode) wallLabelsChain else wallLabelsQuick

    private fun distance(a: FloatArray, b: FloatArray): Double {
        val dx = (a[0] - b[0]).toDouble()
        val dy = (a[1] - b[1]).toDouble()
        val dz = (a[2] - b[2]).toDouble()
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun detachLastAnchor() {
        if (anchors.isEmpty()) return
        try {
            anchors.removeAt(anchors.lastIndex).detach()
        } catch (e: Exception) {
            Log.w(TAG, "detach", e)
        }
    }

    private fun undoLast() {
        if (tapsInSegment > 0) {
            detachLastAnchor()
            tapsInSegment = 0
            pendingStartPose = null
            updateUi()
            liveDistance.text = "—"
            return
        }
        if (wallMeters.isNotEmpty() && !measuringDiagonal) {
            wallMeters.removeAt(wallMeters.lastIndex)
            detachLastAnchor()
            detachLastAnchor()
            measuringDiagonal = false
            diagonalMeters = null
        }
        updateUi()
        liveDistance.text = "—"
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
                stepHint.text =
                    "Point center reticle at a corner, tap Mark. Then opposite corner. Or skip with Use measurements."
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
                    "Point the + reticle at a floor corner of this wall, then tap Mark corner. Repeat for the other end."
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
        } else if (wallMeters.isNotEmpty()) {
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
