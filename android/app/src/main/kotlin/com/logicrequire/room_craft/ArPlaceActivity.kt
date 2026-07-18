package com.logicrequire.room_craft

import android.app.Activity
import android.content.Intent
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
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
import com.logicrequire.room_craft.ar.BackgroundRenderer
import com.logicrequire.room_craft.ar.DisplayRotationHelper
import java.util.ArrayList
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.sqrt

/**
 * AR place furniture on the live camera floor plane (Planner AR room planner path).
 *
 * Flow:
 * 1) Mark room origin (SW corner on floor)
 * 2) Cycle furniture types and Mark on floor to place each piece
 * 3) Done → returns placements relative to origin in feet
 *
 * Pure ARCore + camera background (no Sceneform). Furniture shown as counted
 * anchors; Flutter maps types to catalog sizes.
 */
class ArPlaceActivity : AppCompatActivity(), GLSurfaceView.Renderer {

    companion object {
        const val REQUEST_CODE = 7144
        const val EXTRA_WIDTH_FT = "width_ft"
        const val EXTRA_LENGTH_FT = "length_ft"
        const val EXTRA_PLACEMENTS = "placements"
        private const val TAG = "ArPlace"
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
    private var surfaceCreated = false

    private var origin: FloatArray? = null // world xyz of SW corner
    private val placed = mutableListOf<Placed>()
    private var typeIndex = 0
    private var roomWidthFt: Double = 12.0
    private var roomLengthFt: Double = 12.0

    private data class Placed(
        val type: String,
        val world: FloatArray,
        val anchor: Anchor,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
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
            btnPlace.setOnClickListener { placeAtCenter() }
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
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            Toast.makeText(this, "AR place failed: ${e.message}", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun currentType() = FURN_TYPES[typeIndex]

    private fun updateUi() {
        if (origin == null) {
            stepTitle.text = "AR place · Step 1 — room origin"
            stepHint.text =
                "Point + at the SW corner of the room on the floor, then Place. " +
                    "This anchors real-size placement."
            btnPlace.text = "Mark origin corner"
            liveInfo.text = "No origin yet"
        } else {
            stepTitle.text = "AR place · ${currentType()} (${placed.size} placed)"
            stepHint.text =
                "Point + where the ${currentType()} sits on the floor, then Place. " +
                    "Room ${"%.0f".format(roomWidthFt)}×${"%.0f".format(roomLengthFt)} ft · " +
                    "Next type cycles. Done returns layout."
            btnPlace.text = "Place ${currentType()}"
            liveInfo.text = placed.joinToString(" · ") { it.type }.ifEmpty { "Origin set" }
        }
    }

    private fun placeAtCenter() {
        try {
            val session = session ?: return
            val frame = session.update()
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                Toast.makeText(this, "Move phone slowly until tracking locks", Toast.LENGTH_SHORT).show()
                return
            }
            val cx = surfaceView.width / 2f
            val cy = surfaceView.height / 2f
            val hits = frame.hitTest(cx, cy)
            val hit = hits.firstOrNull {
                it.trackable is com.google.ar.core.Plane &&
                    (it.trackable as com.google.ar.core.Plane).type ==
                    com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING
            } ?: hits.firstOrNull { it.trackable is com.google.ar.core.Plane }
                ?: hits.firstOrNull()

            if (hit == null) {
                Toast.makeText(this, "No floor at center — point at floor", Toast.LENGTH_SHORT).show()
                return
            }
            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            val anchor = hit.createAnchor()

            if (origin == null) {
                origin = xyz
                Toast.makeText(this, "Origin set — place furniture on floor", Toast.LENGTH_SHORT).show()
            } else {
                placed.add(Placed(currentType(), xyz, anchor))
                Toast.makeText(this, "Placed ${currentType()}", Toast.LENGTH_SHORT).show()
            }
            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "placeAtCenter", e)
            Toast.makeText(this, "Place failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun undoLast() {
        if (placed.isNotEmpty()) {
            val last = placed.removeAt(placed.lastIndex)
            try {
                last.anchor.detach()
            } catch (_: Exception) {
            }
            updateUi()
            return
        }
        if (origin != null) {
            origin = null
            updateUi()
        }
    }

    private fun finishWithResult() {
        val o = origin
        if (o == null) {
            Toast.makeText(this, "Mark origin first", Toast.LENGTH_SHORT).show()
            return
        }
        val list = ArrayList<HashMap<String, Any>>()
        for (p in placed) {
            // Relative meters: X right, Z forward along room length approx
            val dxM = (p.world[0] - o[0]).toDouble()
            val dzM = (p.world[2] - o[2]).toDouble()
            // Plan feet from SW origin; abs handles phone facing either way
            var fromLeftFt = kotlin.math.abs(dxM) * M_TO_FT
            var fromBottomFt = kotlin.math.abs(dzM) * M_TO_FT
            // Clamp inside room (device QA polish — keep placements on plan)
            fromLeftFt = fromLeftFt.coerceIn(0.0, roomWidthFt)
            fromBottomFt = fromBottomFt.coerceIn(0.0, roomLengthFt)
            list.add(
                hashMapOf(
                    "type" to p.type,
                    "fromLeftFt" to fromLeftFt,
                    "fromBottomFt" to fromBottomFt,
                    "xM" to dxM,
                    "zM" to dzM,
                    "roomWidthFt" to roomWidthFt,
                    "roomLengthFt" to roomLengthFt,
                ),
            )
        }
        val data = Intent()
        data.putExtra(EXTRA_PLACEMENTS, list)
        setResult(Activity.RESULT_OK, data)
        finish()
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
                    else -> {}
                }
                session = Session(this).also { s ->
                    val config = Config(s)
                    config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    s.configure(config)
                }
            }
            session?.resume()
            surfaceView.onResume()
            displayRotationHelper.onResume()
        } catch (e: Exception) {
            Log.e(TAG, "onResume", e)
            Toast.makeText(this, "AR resume failed: ${e.message}", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            surfaceView.onPause()
            displayRotationHelper.onPause()
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
        surfaceCreated = true
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1f)
        try {
            backgroundRenderer.createOnGlThread(this)
            session?.setCameraTextureName(backgroundRenderer.textureId)
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
        try {
            displayRotationHelper.updateSessionIfNeeded(session)
            val frame = session.update()
            backgroundRenderer.draw(frame)
        } catch (e: CameraNotAvailableException) {
            Log.w(TAG, "camera", e)
        } catch (e: Exception) {
            Log.w(TAG, "draw", e)
        }
    }
}
