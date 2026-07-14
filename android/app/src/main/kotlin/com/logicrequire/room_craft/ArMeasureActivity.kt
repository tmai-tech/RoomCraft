package com.logicrequire.room_craft

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import android.widget.Button
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
 * Guided AR room measure — crash-hardened.
 * Failures finish the activity with EXTRA_ERROR instead of killing the process.
 */
class ArMeasureActivity : AppCompatActivity() {

    private var arFragment: ArFragment? = null
    private lateinit var stepTitle: TextView
    private lateinit var stepHint: TextView
    private lateinit var liveDistance: TextView
    private lateinit var measuredSummary: TextView
    private lateinit var btnDone: Button
    private lateinit var btnUndo: Button

    private val anchors = mutableListOf<AnchorNode>()
    private val wallMeters = mutableListOf<Double>()

    private var chainMode = false
    private var tapsInSegment = 0
    private var segmentStart: Vector3? = null
    private var diagonalMeters: Double? = null
    private var measuringDiagonal = false

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
        try {
            setContentView(R.layout.activity_ar_measure)

            chainMode = intent.getStringExtra(EXTRA_MODE) == MODE_CHAIN

            stepTitle = findViewById(R.id.step_title)
            stepHint = findViewById(R.id.step_hint)
            liveDistance = findViewById(R.id.live_distance)
            measuredSummary = findViewById(R.id.measured_summary)
            btnDone = findViewById(R.id.btn_done)
            btnUndo = findViewById(R.id.btn_undo)

            findViewById<Button>(R.id.btn_cancel).setOnClickListener {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
            btnUndo.setOnClickListener { safeUndo() }
            btnDone.setOnClickListener { finishWithResult() }

            // Add fragment programmatically so load failures can be caught
            val frag = ArFragment()
            supportFragmentManager.beginTransaction()
                .replace(R.id.ar_container, frag)
                .commitNowAllowingStateLoss()
            arFragment = frag
            frag.setOnTapArPlaneListener(
                BaseArFragment.OnTapArPlaneListener { hitResult: HitResult, plane: Plane, _: MotionEvent ->
                    try {
                        if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) {
                            Toast.makeText(this, "Tap the floor plane", Toast.LENGTH_SHORT).show()
                            return@OnTapArPlaneListener
                        }
                        if (plane.trackingState != TrackingState.TRACKING) return@OnTapArPlaneListener
                        onFloorTap(hitResult)
                    } catch (e: Exception) {
                        Log.e(TAG, "tap failed", e)
                        Toast.makeText(this, "Tap failed: ${e.message}", Toast.LENGTH_SHORT).show()
                    }
                },
            )

            updateUi()
        } catch (e: Exception) {
            Log.e(TAG, "onCreate failed", e)
            failAndFinish(e.message ?: "AR measure failed to start")
        }
    }

    private fun failAndFinish(message: String) {
        try {
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        } catch (_: Exception) {
        }
        val data = Intent().putExtra(EXTRA_ERROR, message)
        setResult(Activity.RESULT_CANCELED, data)
        finish()
    }

    private fun labels(): List<String> =
        if (chainMode) wallLabelsChain else wallLabelsQuick

    private fun onFloorTap(hit: HitResult) {
        val frag = arFragment ?: return
        if (measuringDiagonal) {
            onDiagonalTap(hit)
            return
        }
        if (wallMeters.size >= totalWalls) return

        val anchor = hit.createAnchor()
        val anchorNode = AnchorNode(anchor).apply {
            setParent(frag.arSceneView.scene)
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
                String.format("%s: %.2f m (%.1f ft)", label, dist, dist * M_TO_FT),
                Toast.LENGTH_SHORT,
            ).show()
            if (wallMeters.size >= totalWalls) {
                measuringDiagonal = true
                Toast.makeText(
                    this,
                    "Optional: tap opposite corners (diagonal) to verify scale",
                    Toast.LENGTH_LONG,
                ).show()
            }
            updateUi()
        }
    }

    private fun onDiagonalTap(hit: HitResult) {
        val frag = arFragment ?: return
        val anchor = hit.createAnchor()
        val anchorNode = AnchorNode(anchor).apply {
            setParent(frag.arSceneView.scene)
        }
        anchors.add(anchorNode)
        addMarker(anchorNode, 0)
        val world = anchorNode.worldPosition
        tapsInSegment++
        if (tapsInSegment == 1) {
            segmentStart = world
            liveDistance.text = "Diagonal corner 1 — tap opposite corner"
        } else {
            val start = segmentStart ?: world
            val dist = distance(start, world).toDouble()
            diagonalMeters = dist
            tapsInSegment = 0
            segmentStart = null
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
            Toast.makeText(
                this,
                "Diagonal looks off — keeping wall measures",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        val blend = 0.65
        val scale = 1.0 + (ratio - 1.0) * blend
        for (i in wallMeters.indices) {
            wallMeters[i] = wallMeters[i] * scale
        }
        Toast.makeText(
            this,
            String.format("Scale refined from diagonal (×%.2f)", scale),
            Toast.LENGTH_LONG,
        ).show()
    }

    private fun removeLastAnchor() {
        if (anchors.isEmpty()) return
        val last = anchors.removeAt(anchors.lastIndex)
        try {
            last.anchor?.detach()
            last.setParent(null)
        } catch (e: Exception) {
            Log.w(TAG, "detach anchor", e)
        }
    }

    private fun addMarker(parent: AnchorNode, wallIndex: Int) {
        try {
            val colors = listOf(
                Color(0.0f, 0.75f, 0.65f),
                Color(0.3f, 0.55f, 0.95f),
                Color(0.95f, 0.65f, 0.15f),
                Color(0.75f, 0.4f, 0.9f),
            )
            val c = colors[wallIndex % colors.size]
            MaterialFactory.makeOpaqueWithColor(this, c)
                .thenAccept { material ->
                    try {
                        val sphere = ShapeFactory.makeSphere(0.03f, Vector3.zero(), material)
                        Node().apply {
                            setParent(parent)
                            renderable = sphere
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "marker render", e)
                    }
                }
                .exceptionally { e ->
                    Log.w(TAG, "marker material", e)
                    null
                }
        } catch (e: Exception) {
            Log.w(TAG, "addMarker", e)
        }
    }

    private fun distance(a: Vector3, b: Vector3): Float {
        val dx = a.x - b.x
        val dy = a.y - b.y
        val dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun safeUndo() {
        try {
            undoLast()
        } catch (e: Exception) {
            Log.e(TAG, "undo", e)
        }
    }

    private fun undoLast() {
        if (measuringDiagonal && tapsInSegment > 0) {
            repeat(tapsInSegment) { removeLastAnchor() }
            tapsInSegment = 0
            segmentStart = null
            updateUi()
            return
        }
        if (measuringDiagonal && diagonalMeters != null) {
            diagonalMeters = null
            measuringDiagonal = true
            updateUi()
            return
        }
        if (tapsInSegment > 0) {
            repeat(tapsInSegment) { removeLastAnchor() }
            tapsInSegment = 0
            segmentStart = null
        } else if (wallMeters.isNotEmpty()) {
            wallMeters.removeAt(wallMeters.lastIndex)
            removeLastAnchor()
            removeLastAnchor()
            measuringDiagonal = false
            diagonalMeters = null
        }
        updateUi()
        liveDistance.text = "—"
    }

    private fun resolvedWidthM(): Double? {
        if (wallMeters.isEmpty()) return null
        return if (chainMode && wallMeters.size >= 3) {
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
            (wallMeters[1] + wallMeters[3]) / 2.0
        } else {
            wallMeters.getOrNull(1)
        }
    }

    private fun updateUi() {
        if (!::stepTitle.isInitialized) return
        val n = wallMeters.size
        val labels = labels()
        if (measuringDiagonal) {
            stepTitle.text = "Accuracy check — diagonal (optional)"
            stepHint.text =
                "Tap two OPPOSITE corners, or press Use measurements to skip."
        } else if (n >= totalWalls) {
            stepTitle.text = "Done — measurements ready"
            stepHint.text = "Tap Use measurements to build your plan."
        } else {
            stepTitle.text = "Step ${n + 1}/$totalWalls — ${labels[n]}"
            stepHint.text =
                "Point at the floor until a grid appears. Tap one corner, then the other end of this wall."
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
            }
        }

        val w = resolvedWidthM()
        val l = resolvedLengthM()
        val ready = if (chainMode) {
            wallMeters.size >= 4 && w != null && l != null && w > 0.5 && l > 0.5
        } else {
            wallMeters.size >= 2 && w != null && l != null && w > 0.5 && l > 0.5
        }
        // Allow done during optional diagonal phase once walls are ready
        btnDone.isEnabled = ready || (measuringDiagonal && w != null && l != null)
        if (ready && w != null && l != null) {
            liveDistance.text = String.format("%.1f × %.1f ft", w * M_TO_FT, l * M_TO_FT)
        } else if (wallMeters.isNotEmpty()) {
            liveDistance.text = String.format("Last: %.1f ft", wallMeters.last() * M_TO_FT)
        } else if (!measuringDiagonal) {
            liveDistance.text = "—"
        }
    }

    private fun finishWithResult() {
        // Allow skip diagonal
        measuringDiagonal = false
        val w = resolvedWidthM()
        val l = resolvedLengthM()
        if (w == null || l == null || w < 0.5 || l < 0.5) {
            Toast.makeText(this, "Finish wall measurements first", Toast.LENGTH_SHORT).show()
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
