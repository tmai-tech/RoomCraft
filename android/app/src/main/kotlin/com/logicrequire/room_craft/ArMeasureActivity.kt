package com.logicrequire.room_craft

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.MotionEvent
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.Color
import com.google.ar.sceneform.rendering.MaterialFactory
import com.google.ar.sceneform.rendering.ShapeFactory
import com.google.ar.sceneform.ux.ArFragment
import com.google.ar.sceneform.ux.BaseArFragment
import kotlin.math.sqrt

/**
 * Guided AR room measure: tap two floor points for WIDTH, then two for LENGTH.
 * Returns meters to Flutter via Activity result.
 *
 * Uses ARCore plane hit-testing (same class of tech as magicplan-style phone scan).
 */
class ArMeasureActivity : AppCompatActivity() {

    private lateinit var arFragment: ArFragment
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveDistance: TextView
    private lateinit var measuredSummary: TextView
    private lateinit var btnDone: MaterialButton
    private lateinit var btnUndo: MaterialButton

    private val anchors = mutableListOf<AnchorNode>()
    private var widthMeters: Double? = null
    private var lengthMeters: Double? = null

    /** 0 = measure width (need 2 taps), 1 = measure length (need 2 taps), 2 = done */
    private var phase = 0
    private var tapsInPhase = 0
    private var phaseStartWorld: Vector3? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar_measure)

        stepTitle = findViewById(R.id.step_title)
        stepHint = findViewById(R.id.step_hint)
        liveDistance = findViewById(R.id.live_distance)
        measuredSummary = findViewById(R.id.measured_summary)
        btnDone = findViewById(R.id.btn_done)
        btnUndo = findViewById(R.id.btn_undo)
        findViewById<MaterialButton>(R.id.btn_cancel).setOnClickListener {
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
        btnUndo.setOnClickListener { undoLast() }
        btnDone.setOnClickListener { finishWithResult() }

        arFragment = supportFragmentManager.findFragmentById(R.id.ar_fragment) as ArFragment
        arFragment.setOnTapArPlaneListener(
            BaseArFragment.OnTapArPlaneListener { hitResult: HitResult, plane: Plane, _: MotionEvent ->
                if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) {
                    Toast.makeText(this, "Tap the floor plane", Toast.LENGTH_SHORT).show()
                    return@OnTapArPlaneListener
                }
                if (plane.trackingState != TrackingState.TRACKING) return@OnTapArPlaneListener
                onFloorTap(hitResult)
            },
        )

        updateUi()
    }

    private fun onFloorTap(hit: HitResult) {
        if (phase >= 2) return

        val anchor = hit.createAnchor()
        val anchorNode = AnchorNode(anchor).apply {
            setParent(arFragment.arSceneView.scene)
        }
        anchors.add(anchorNode)
        addMarker(anchorNode)

        val world = anchorNode.worldPosition
        tapsInPhase++

        if (tapsInPhase == 1) {
            phaseStartWorld = world
            liveDistance.text = "Point 1 set — tap the other end"
        } else if (tapsInPhase >= 2) {
            val start = phaseStartWorld ?: world
            val dist = distance(start, world)
            if (phase == 0) {
                widthMeters = dist.toDouble()
                phase = 1
                tapsInPhase = 0
                phaseStartWorld = null
                Toast.makeText(
                    this,
                    String.format("Width: %.2f m (%.1f ft)", dist, dist * 3.28084f),
                    Toast.LENGTH_SHORT,
                ).show()
            } else {
                lengthMeters = dist.toDouble()
                phase = 2
                tapsInPhase = 0
                phaseStartWorld = null
                Toast.makeText(
                    this,
                    String.format("Length: %.2f m (%.1f ft)", dist, dist * 3.28084f),
                    Toast.LENGTH_SHORT,
                ).show()
            }
            updateUi()
        }
    }

    private fun addMarker(parent: AnchorNode) {
        MaterialFactory.makeOpaqueWithColor(this, Color(0.0f, 0.75f, 0.65f))
            .thenAccept { material ->
                val sphere = ShapeFactory.makeSphere(0.03f, Vector3.zero(), material)
                Node().apply {
                    setParent(parent)
                    renderable = sphere
                }
            }
    }

    private fun distance(a: Vector3, b: Vector3): Float {
        val dx = a.x - b.x
        val dy = a.y - b.y
        val dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun undoLast() {
        if (anchors.isNotEmpty()) {
            val last = anchors.removeAt(anchors.lastIndex)
            last.anchor?.detach()
            last.setParent(null)
        }
        // Reset phase state simply
        widthMeters = null
        lengthMeters = null
        phase = 0
        tapsInPhase = 0
        phaseStartWorld = null
        // Clear all anchors for clean redo
        while (anchors.isNotEmpty()) {
            val n = anchors.removeAt(anchors.lastIndex)
            n.anchor?.detach()
            n.setParent(null)
        }
        updateUi()
        liveDistance.text = "—"
    }

    private fun updateUi() {
        when (phase) {
            0 -> {
                stepTitle.text = "Step 1 — Room width"
                stepHint.text =
                    "Move phone until a white grid appears on the floor. " +
                        "Tap one corner of a wall, then the other corner of the SAME wall."
            }
            1 -> {
                stepTitle.text = "Step 2 — Room length"
                stepHint.text =
                    "Tap two ends of the adjacent wall (the depth of the room)."
            }
            else -> {
                stepTitle.text = "Done — measurements ready"
                stepHint.text = "Tap Use measurements to build your plan."
            }
        }
        val w = widthMeters
        val l = lengthMeters
        measuredSummary.text = buildString {
            if (w != null) {
                append(String.format("Width: %.2f m (%.1f ft)", w, w * 3.28084))
            }
            if (l != null) {
                if (isNotEmpty()) append("\n")
                append(String.format("Length: %.2f m (%.1f ft)", l, l * 3.28084))
            }
            if (w != null && l != null) {
                append(String.format("\nArea ≈ %.1f m²", w * l))
            }
        }
        btnDone.isEnabled = w != null && l != null && w > 0.5 && l > 0.5
        if (w != null && l != null) {
            liveDistance.text = String.format("%.1f × %.1f ft", w * 3.28084, l * 3.28084)
        }
    }

    private fun finishWithResult() {
        val w = widthMeters
        val l = lengthMeters
        if (w == null || l == null || w < 0.5 || l < 0.5) {
            Toast.makeText(this, "Measure both width and length first", Toast.LENGTH_SHORT).show()
            return
        }
        val data = Intent().apply {
            putExtra(EXTRA_WIDTH_M, w)
            putExtra(EXTRA_LENGTH_M, l)
            putExtra(EXTRA_WIDTH_FT, w * 3.28084)
            putExtra(EXTRA_LENGTH_FT, l * 3.28084)
        }
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    companion object {
        const val EXTRA_WIDTH_M = "width_m"
        const val EXTRA_LENGTH_M = "length_m"
        const val EXTRA_WIDTH_FT = "width_ft"
        const val EXTRA_LENGTH_FT = "length_ft"
        const val REQUEST_CODE = 7142
    }
}
