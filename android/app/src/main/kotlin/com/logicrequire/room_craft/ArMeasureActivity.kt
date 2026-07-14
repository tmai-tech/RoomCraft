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
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Guided AR room measure.
 *
 * Modes (intent EXTRA_MODE):
 *  - "quick" (default): width then length (2 segments)
 *  - "chain": walk all 4 walls A→B→C→D (more accurate, designer-style)
 *
 * Uses ARCore plane hit-testing on the floor.
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
    /** Completed wall lengths in meters, order A,B,C,D (or W,L for quick). */
    private val wallMeters = mutableListOf<Double>()

    private var chainMode = false
    private var tapsInSegment = 0
    private var segmentStart: Vector3? = null

    private val wallLabelsQuick = listOf("Width (Wall A)", "Length (Wall B)")
    private val wallLabelsChain = listOf(
        "Wall A (first width side)",
        "Wall B (first length side)",
        "Wall C (opposite width)",
        "Wall D (opposite length)",
    )

    private val totalWalls: Int
        get() = if (chainMode) 4 else 2

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar_measure)

        chainMode = intent.getStringExtra(EXTRA_MODE) == MODE_CHAIN

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

    private fun labels(): List<String> =
        if (chainMode) wallLabelsChain else wallLabelsQuick

    private fun onFloorTap(hit: HitResult) {
        if (wallMeters.size >= totalWalls) return

        val anchor = hit.createAnchor()
        val anchorNode = AnchorNode(anchor).apply {
            setParent(arFragment.arSceneView.scene)
        }
        anchors.add(anchorNode)
        addMarker(anchorNode, wallMeters.size)

        val world = anchorNode.worldPosition
        tapsInSegment++

        if (tapsInSegment == 1) {
            segmentStart = world
            liveDistance.text = "Corner 1 set — tap other end of this wall"
        } else if (tapsInSegment >= 2) {
            val start = segmentStart ?: world
            val dist = distance(start, world).toDouble()
            if (dist < 0.4) {
                Toast.makeText(this, "Segment too short — retake this wall", Toast.LENGTH_SHORT).show()
                // Remove last two anchors for this failed segment
                removeLastAnchor()
                removeLastAnchor()
                tapsInSegment = 0
                segmentStart = null
                return
            }
            wallMeters.add(dist)
            tapsInSegment = 0
            segmentStart = null
            val label = labels().getOrElse(wallMeters.size - 1) { "Wall" }
            Toast.makeText(
                this,
                String.format(
                    "%s: %.2f m (%.1f ft)",
                    label,
                    dist,
                    dist * M_TO_FT,
                ),
                Toast.LENGTH_SHORT,
            ).show()
            updateUi()
        }
    }

    private fun removeLastAnchor() {
        if (anchors.isEmpty()) return
        val last = anchors.removeAt(anchors.lastIndex)
        last.anchor?.detach()
        last.setParent(null)
    }

    private fun addMarker(parent: AnchorNode, wallIndex: Int) {
        // Alternate colors per wall for readability
        val colors = listOf(
            Color(0.0f, 0.75f, 0.65f),
            Color(0.3f, 0.55f, 0.95f),
            Color(0.95f, 0.65f, 0.15f),
            Color(0.75f, 0.4f, 0.9f),
        )
        val c = colors[wallIndex % colors.size]
        MaterialFactory.makeOpaqueWithColor(this, c)
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
        // Undo current in-progress segment taps, or last completed wall
        if (tapsInSegment > 0) {
            repeat(tapsInSegment) { removeLastAnchor() }
            tapsInSegment = 0
            segmentStart = null
        } else if (wallMeters.isNotEmpty()) {
            wallMeters.removeAt(wallMeters.lastIndex)
            // Each completed wall used 2 anchors
            removeLastAnchor()
            removeLastAnchor()
        }
        updateUi()
        liveDistance.text = "—"
    }

    private fun resolvedWidthM(): Double? {
        if (wallMeters.isEmpty()) return null
        return if (chainMode && wallMeters.size >= 3) {
            // Avg opposite width walls A & C
            val a = wallMeters[0]
            val c = if (wallMeters.size >= 3) wallMeters[2] else a
            (a + c) / 2.0
        } else {
            wallMeters.getOrNull(0)
        }
    }

    private fun resolvedLengthM(): Double? {
        if (wallMeters.size < 2) return null
        return if (chainMode && wallMeters.size >= 4) {
            val b = wallMeters[1]
            val d = wallMeters[3]
            (b + d) / 2.0
        } else if (chainMode && wallMeters.size >= 2) {
            wallMeters[1]
        } else {
            wallMeters.getOrNull(1)
        }
    }

    private fun updateUi() {
        val n = wallMeters.size
        val labels = labels()
        if (n >= totalWalls) {
            stepTitle.text = "Done — measurements ready"
            stepHint.text = if (chainMode) {
                "Opposite walls were averaged for a more stable rectangle. Tap Use measurements."
            } else {
                "Tap Use measurements to build your plan."
            }
        } else {
            stepTitle.text = "Step ${n + 1}/$totalWalls — ${labels[n]}"
            stepHint.text = if (chainMode) {
                "Walk clockwise around the room. Point at the floor grid. " +
                    "Tap one corner of this wall, then the other corner."
            } else {
                "Move phone until a white grid appears on the floor. " +
                    "Tap one corner of this wall, then the other corner."
            }
        }

        measuredSummary.text = buildString {
            wallMeters.forEachIndexed { i, m ->
                val lab = labels.getOrElse(i) { "Wall ${i + 1}" }
                append(String.format("%s: %.2f m (%.1f ft)\n", lab, m, m * M_TO_FT))
            }
            val w = resolvedWidthM()
            val l = resolvedLengthM()
            if (w != null && l != null && n >= (if (chainMode) 4 else 2)) {
                append(String.format("→ Room ≈ %.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT))
                if (chainMode && wallMeters.size >= 4) {
                    val dw = abs(wallMeters[0] - wallMeters[2])
                    val dl = abs(wallMeters[1] - wallMeters[3])
                    if (dw > 0.25 || dl > 0.25) {
                        append(
                            String.format(
                                "\n⚠ Opposite walls differ by up to %.0f cm — room may not be a perfect rectangle",
                                maxOf(dw, dl) * 100,
                            ),
                        )
                    }
                }
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
            val last = wallMeters.last()
            liveDistance.text = String.format("Last: %.1f ft", last * M_TO_FT)
        } else {
            liveDistance.text = "—"
        }
    }

    private fun finishWithResult() {
        val w = resolvedWidthM()
        val l = resolvedLengthM()
        if (w == null || l == null || w < 0.5 || l < 0.5) {
            Toast.makeText(this, "Finish all wall measurements first", Toast.LENGTH_SHORT).show()
            return
        }
        val wallsFt = wallMeters.map { it * M_TO_FT }.toDoubleArray()
        val wallsM = wallMeters.toDoubleArray()
        val data = Intent().apply {
            putExtra(EXTRA_WIDTH_M, w)
            putExtra(EXTRA_LENGTH_M, l)
            putExtra(EXTRA_WIDTH_FT, w * M_TO_FT)
            putExtra(EXTRA_LENGTH_FT, l * M_TO_FT)
            putExtra(EXTRA_MODE, if (chainMode) MODE_CHAIN else MODE_QUICK)
            putExtra(EXTRA_WALLS_M, wallsM)
            putExtra(EXTRA_WALLS_FT, wallsFt)
        }
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    companion object {
        const val EXTRA_WIDTH_M = "width_m"
        const val EXTRA_LENGTH_M = "length_m"
        const val EXTRA_WIDTH_FT = "width_ft"
        const val EXTRA_LENGTH_FT = "length_ft"
        const val EXTRA_MODE = "mode"
        const val EXTRA_WALLS_M = "walls_m"
        const val EXTRA_WALLS_FT = "walls_ft"
        const val MODE_QUICK = "quick"
        const val MODE_CHAIN = "chain"
        const val REQUEST_CODE = 7142
        private const val M_TO_FT = 3.28084
    }
}
