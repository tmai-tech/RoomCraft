package com.logicrequire.room_craft.ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.max
import kotlin.math.min

/**
 * Top-down live map of Home Scan walk (+128).
 * Floor hits as dots, pose trail as line, fitted room as rectangle —
 * OpenCV-style "what the scan understands" while walking.
 */
class WalkMapView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val hits = mutableListOf<Pair<Float, Float>>() // XZ world meters
    private val poses = mutableListOf<Pair<Float, Float>>()
    private var roomW = 0f
    private var roomL = 0f
    private var minX = 0f
    private var maxX = 1f
    private var minZ = 0f
    private var maxZ = 1f

    private val paintHit = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#80CBC4")
        style = Paint.Style.FILL
    }
    private val paintPose = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFCC80")
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }
    private val paintRoom = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFFFFF")
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private val paintGrid = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#33FFFFFF")
        style = Paint.Style.STROKE
        strokeWidth = 1f
    }
    private val paintBg = Paint().apply {
        color = Color.parseColor("#CC102027")
    }
    private val paintLabel = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#B2DFDB")
        textSize = 28f
    }

    fun setData(
        floorXz: List<Pair<Float, Float>>,
        poseXz: List<Pair<Float, Float>>,
        widthM: Float,
        lengthM: Float,
    ) {
        hits.clear()
        hits.addAll(floorXz)
        poses.clear()
        poses.addAll(poseXz)
        roomW = widthM
        roomL = lengthM
        recomputeBounds()
        postInvalidateOnAnimation()
    }

    private fun recomputeBounds() {
        var x0 = Float.POSITIVE_INFINITY
        var x1 = Float.NEGATIVE_INFINITY
        var z0 = Float.POSITIVE_INFINITY
        var z1 = Float.NEGATIVE_INFINITY
        fun acc(p: Pair<Float, Float>) {
            x0 = min(x0, p.first)
            x1 = max(x1, p.first)
            z0 = min(z0, p.second)
            z1 = max(z1, p.second)
        }
        hits.forEach { acc(it) }
        poses.forEach { acc(it) }
        if (roomW > 0.5f && roomL > 0.5f && hits.isNotEmpty()) {
            // Expand to show fitted room box centered on cloud
            val cx = (x0 + x1) / 2f
            val cz = (z0 + z1) / 2f
            x0 = min(x0, cx - roomW / 2f)
            x1 = max(x1, cx + roomW / 2f)
            z0 = min(z0, cz - roomL / 2f)
            z1 = max(z1, cz + roomL / 2f)
        }
        if (!x0.isFinite() || x1 - x0 < 0.5f) {
            x0 = 0f
            x1 = 4f
            z0 = 0f
            z1 = 4f
        }
        val pad = max((x1 - x0), (z1 - z0)) * 0.12f + 0.3f
        minX = x0 - pad
        maxX = x1 + pad
        minZ = z0 - pad
        maxZ = z1 + pad
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w < 2 || h < 2) return
        canvas.drawRoundRect(0f, 0f, w, h, 16f, 16f, paintBg)

        // Grid
        for (i in 0..4) {
            val gx = w * i / 4f
            val gy = h * i / 4f
            canvas.drawLine(gx, 0f, gx, h, paintGrid)
            canvas.drawLine(0f, gy, w, gy, paintGrid)
        }

        fun mapX(x: Float): Float {
            val t = (x - minX) / (maxX - minX).coerceAtLeast(0.01f)
            return t * (w - 24f) + 12f
        }
        fun mapZ(z: Float): Float {
            val t = (z - minZ) / (maxZ - minZ).coerceAtLeast(0.01f)
            // Flip Z so top of view is "forward" when walking
            return (1f - t) * (h - 24f) + 12f
        }

        // Pose trail (path walked)
        if (poses.size >= 2) {
            val path = Path()
            path.moveTo(mapX(poses[0].first), mapZ(poses[0].second))
            for (i in 1 until poses.size) {
                path.lineTo(mapX(poses[i].first), mapZ(poses[i].second))
            }
            canvas.drawPath(path, paintPose)
        }

        // Floor hits
        val r = 5f
        for (p in hits) {
            canvas.drawCircle(mapX(p.first), mapZ(p.second), r, paintHit)
        }

        // Fitted room rectangle (axis-aligned on map from cloud center)
        if (roomW > 0.5f && roomL > 0.5f && hits.isNotEmpty()) {
            var sx = 0f
            var sz = 0f
            for (p in hits) {
                sx += p.first
                sz += p.second
            }
            val cx = sx / hits.size
            val cz = sz / hits.size
            val left = mapX(cx - roomW / 2f)
            val right = mapX(cx + roomW / 2f)
            val top = mapZ(cz + roomL / 2f)
            val bottom = mapZ(cz - roomL / 2f)
            canvas.drawRect(
                min(left, right),
                min(top, bottom),
                max(left, right),
                max(top, bottom),
                paintRoom,
            )
        }

        val label = when {
            hits.isEmpty() -> "Walk floor — map builds live"
            roomW > 0.5f -> String.format("%.1f×%.1f m · %d pts", roomW, roomL, hits.size)
            else -> "${hits.size} floor pts · keep walking"
        }
        canvas.drawText(label, 14f, h - 14f, paintLabel)
    }
}
