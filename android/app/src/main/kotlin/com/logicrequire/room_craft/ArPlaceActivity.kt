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
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import java.util.ArrayList
import kotlin.math.sqrt

/**
 * AR place furniture via SceneView camera (+122). Same camera stack as measure.
 */
class ArPlaceActivity : AppCompatActivity() {

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

    private lateinit var arSceneView: ARSceneView
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveInfo: TextView
    private lateinit var btnPlace: Button
    private lateinit var btnNextType: Button
    private lateinit var btnDone: Button
    private lateinit var btnUndo: Button

    private var origin: FloatArray? = null
    private var xAxis: FloatArray? = null
    private var zAxis: FloatArray? = null
    private val placed = mutableListOf<Placed>()
    private var typeIndex = 0
    private var roomWidthFt: Double = 12.0
    private var roomLengthFt: Double = 12.0
    private var uiTick = 0

    private data class Placed(val type: String, val world: FloatArray)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            roomWidthFt = intent.getDoubleExtra(EXTRA_WIDTH_FT, 12.0).coerceIn(3.0, 120.0)
            roomLengthFt = intent.getDoubleExtra(EXTRA_LENGTH_FT, 12.0).coerceIn(3.0, 120.0)
            setContentView(R.layout.activity_ar_place)

            arSceneView = findViewById(R.id.ar_scene_view)
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

            arSceneView.lifecycle = lifecycle
            arSceneView.planeRenderer.isEnabled = true
            arSceneView.configureSession { _, config ->
                config.depthMode = Config.DepthMode.DISABLED
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                config.lightEstimationMode = Config.LightEstimationMode.DISABLED
                config.focusMode = Config.FocusMode.AUTO
            }
            arSceneView.onSessionFailed = { e ->
                runOnUiThread {
                    liveInfo.text = "AR failed: ${e.message}"
                    Toast.makeText(this, "AR failed: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
            arSceneView.onSessionResumed = {
                runOnUiThread { liveInfo.text = "Camera live · find floor" }
            }
            arSceneView.onSessionUpdated = { session, frame ->
                uiTick++
                if (uiTick % 15 != 0) return@onSessionUpdated
                if (origin != null && xAxis != null) return@onSessionUpdated
                var planes = 0
                for (p in session.getAllTrackables(Plane::class.java)) {
                    if (p.trackingState == TrackingState.TRACKING) planes++
                }
                val cam = frame.camera.trackingState
                runOnUiThread {
                    liveInfo.text = when (cam) {
                        TrackingState.TRACKING ->
                            if (planes > 0) "Tracking · $planes plane(s)"
                            else "Tracking · point at floor…"
                        TrackingState.PAUSED -> "Tracking paused"
                        TrackingState.STOPPED -> "Tracking stopped"
                    }
                }
            }

            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
            }
            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "onCreate", e)
            Toast.makeText(this, "AR place failed: ${e.message}", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    override fun onDestroy() {
        try {
            if (::arSceneView.isInitialized) arSceneView.destroy()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA &&
            (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED)
        ) {
            Toast.makeText(this, "Camera permission required", Toast.LENGTH_LONG).show()
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun currentType() = FURN_TYPES[typeIndex]

    private fun updateUi() {
        when {
            origin == null -> {
                stepTitle.text = "AR place · Step 1/3 — SW origin"
                stepHint.text = "Live camera required. Mark SW corner on the floor."
                btnPlace.text = "Mark origin (SW)"
            }
            xAxis == null || zAxis == null -> {
                stepTitle.text = "AR place · Step 2/3 — width axis (+X)"
                stepHint.text = "Mark SE corner along the WIDTH wall."
                btnPlace.text = "Mark +X (SE / width end)"
            }
            else -> {
                stepTitle.text = "AR place · ${currentType()} (${placed.size})"
                stepHint.text =
                    "Place ${currentType()}. Room ${"%.0f".format(roomWidthFt)}×${"%.0f".format(roomLengthFt)} ft."
                btnPlace.text = "Place ${currentType()}"
                liveInfo.text = placed.joinToString(" · ") { it.type }.ifEmpty { "Axes set" }
            }
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
            Toast.makeText(this, "Too close to origin", Toast.LENGTH_SHORT).show()
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
        Toast.makeText(this, "Axes set", Toast.LENGTH_SHORT).show()
        return true
    }

    private fun placeAtCenter() {
        try {
            val frame = arSceneView.frame
            if (frame == null || frame.timestamp == 0L) {
                Toast.makeText(this, "Wait for live camera first", Toast.LENGTH_SHORT).show()
                return
            }
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                Toast.makeText(this, "Wait for tracking", Toast.LENGTH_SHORT).show()
                return
            }
            val hit = arSceneView.hitTestAR(
                planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING),
            ) ?: frame.hitTest(arSceneView.width / 2f, arSceneView.height / 2f).firstOrNull()

            if (hit == null) {
                Toast.makeText(this, "No floor at center", Toast.LENGTH_SHORT).show()
                return
            }
            val pose = hit.hitPose
            val xyz = floatArrayOf(pose.tx(), pose.ty(), pose.tz())
            when {
                origin == null -> {
                    origin = xyz
                    Toast.makeText(this, "Origin set — mark +X", Toast.LENGTH_SHORT).show()
                    updateUi()
                }
                xAxis == null || zAxis == null -> {
                    if (setAxesFromXPoint(xyz)) updateUi()
                }
                else -> {
                    placed.add(Placed(currentType(), xyz))
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
        } catch (e: Exception) {
            Log.e(TAG, "place", e)
            Toast.makeText(this, "Place failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun undoLast() {
        if (placed.isNotEmpty()) {
            placed.removeAt(placed.lastIndex)
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
