package com.logicrequire.room_craft.ar

import android.content.Context
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.WindowManager
import com.google.ar.core.Session

/**
 * Tracks display rotation for ARCore viewport (+120/+121).
 * Only applies setDisplayGeometry when rotation or size actually change.
 */
class DisplayRotationHelper(context: Context) : DisplayManager.DisplayListener {
    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    @Suppress("DEPRECATION")
    private val display: Display =
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
    private var viewportChanged = true
    private var viewportWidth = 0
    private var viewportHeight = 0
    private var lastRotation = -1
    private var lastWidth = -1
    private var lastHeight = -1

    fun onResume() {
        displayManager.registerDisplayListener(this, null)
        viewportChanged = true
    }

    fun onPause() {
        displayManager.unregisterDisplayListener(this)
    }

    fun onSurfaceChanged(width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height
        viewportChanged = true
    }

    fun updateSessionIfNeeded(session: Session) {
        val w = viewportWidth
        val h = viewportHeight
        if (w <= 0 || h <= 0) return
        val rotation = display.rotation
        if (!viewportChanged && rotation == lastRotation && w == lastWidth && h == lastHeight) {
            return
        }
        session.setDisplayGeometry(rotation, w, h)
        lastRotation = rotation
        lastWidth = w
        lastHeight = h
        viewportChanged = false
    }

    override fun onDisplayAdded(displayId: Int) {}
    override fun onDisplayRemoved(displayId: Int) {}
    override fun onDisplayChanged(displayId: Int) {
        viewportChanged = true
    }
}
