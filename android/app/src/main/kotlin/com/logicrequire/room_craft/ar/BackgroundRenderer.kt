package com.logicrequire.room_craft.ar

import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.util.Log
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Camera background renderer — aligned with ARCore hello_ar sample (+121).
 *
 * Black-screen fixes:
 * - Seed tex coords before first geometry transform
 * - Check shader compile / program link
 * - Do not suppress forever when timestamp is 0 (caller shows status)
 * - Disable blend/cull for fullscreen OES quad
 */
class BackgroundRenderer {
    private lateinit var quadVertices: FloatBuffer
    private lateinit var quadTexCoordTransformed: FloatBuffer
    private var quadProgram = 0
    private var quadPositionParam = 0
    private var quadTexCoordParam = 0
    private var textureIdInternal = -1
    private var geometryReady = false
    private var framesDrawn = 0

    val textureId: Int get() = textureIdInternal
    val hasDrawnCamera: Boolean get() = framesDrawn > 0

    fun createOnGlThread(@Suppress("UNUSED_PARAMETER") context: Context) {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureIdInternal = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureIdInternal)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )

        val numVertices = 4
        if (!::quadVertices.isInitialized) {
            val bbVertices = ByteBuffer.allocateDirect(QUAD_COORDS.size * FLOAT_SIZE)
            bbVertices.order(ByteOrder.nativeOrder())
            quadVertices = bbVertices.asFloatBuffer()
            quadVertices.put(QUAD_COORDS)
            quadVertices.position(0)

            val bbTex = ByteBuffer.allocateDirect(numVertices * TEXCOORDS_PER_VERTEX * FLOAT_SIZE)
            bbTex.order(ByteOrder.nativeOrder())
            quadTexCoordTransformed = bbTex.asFloatBuffer()
            // Identity UVs until ARCore supplies display-geometry transform
            quadTexCoordTransformed.put(QUAD_TEXCOORDS)
            quadTexCoordTransformed.position(0)
        }

        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        quadProgram = GLES20.glCreateProgram()
        GLES20.glAttachShader(quadProgram, vertexShader)
        GLES20.glAttachShader(quadProgram, fragmentShader)
        GLES20.glLinkProgram(quadProgram)
        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(quadProgram, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            val err = GLES20.glGetProgramInfoLog(quadProgram)
            Log.e(TAG, "Program link failed: $err")
            throw RuntimeException("Camera shader link failed: $err")
        }
        GLES20.glUseProgram(quadProgram)
        quadPositionParam = GLES20.glGetAttribLocation(quadProgram, "a_Position")
        quadTexCoordParam = GLES20.glGetAttribLocation(quadProgram, "a_TexCoord")
        geometryReady = false
        framesDrawn = 0
        checkGlError("createOnGlThread")
    }

    /**
     * @return true if a camera frame was drawn
     */
    fun draw(frame: Frame): Boolean {
        if (textureIdInternal < 0 || quadProgram == 0) return false

        // First frame after setDisplayGeometry, and whenever display geometry changes
        if (frame.hasDisplayGeometryChanged() || !geometryReady) {
            frame.transformCoordinates2d(
                Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                quadVertices,
                Coordinates2d.TEXTURE_NORMALIZED,
                quadTexCoordTransformed,
            )
            geometryReady = true
        }

        // No camera image yet — leave clear color (caller shows "starting camera")
        if (frame.timestamp == 0L) {
            return false
        }

        // Draw camera image as fullscreen quad
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glDisable(GLES20.GL_CULL_FACE)
        GLES20.glDisable(GLES20.GL_BLEND)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureIdInternal)
        GLES20.glUseProgram(quadProgram)

        GLES20.glVertexAttribPointer(
            quadPositionParam,
            COORDS_PER_VERTEX,
            GLES20.GL_FLOAT,
            false,
            0,
            quadVertices,
        )
        GLES20.glVertexAttribPointer(
            quadTexCoordParam,
            TEXCOORDS_PER_VERTEX,
            GLES20.GL_FLOAT,
            false,
            0,
            quadTexCoordTransformed,
        )
        GLES20.glEnableVertexAttribArray(quadPositionParam)
        GLES20.glEnableVertexAttribArray(quadTexCoordParam)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(quadPositionParam)
        GLES20.glDisableVertexAttribArray(quadTexCoordParam)

        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        framesDrawn++
        return true
    }

    companion object {
        private const val TAG = "BgRenderer"
        private const val FLOAT_SIZE = 4
        private const val COORDS_PER_VERTEX = 3
        private const val TEXCOORDS_PER_VERTEX = 2

        // Fullscreen NDC quad (triangle strip)
        private val QUAD_COORDS = floatArrayOf(
            -1.0f, -1.0f, 0.0f,
            -1.0f, +1.0f, 0.0f,
            +1.0f, -1.0f, 0.0f,
            +1.0f, +1.0f, 0.0f,
        )
        private val QUAD_TEXCOORDS = floatArrayOf(
            0.0f, 1.0f,
            0.0f, 0.0f,
            1.0f, 1.0f,
            1.0f, 0.0f,
        )

        private const val VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
               gl_Position = a_Position;
               v_TexCoord = a_TexCoord;
            }
        """

        // OES external texture (ARCore camera)
        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, v_TexCoord);
            }
        """

        private fun loadShader(type: Int, code: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, code)
            GLES20.glCompileShader(shader)
            val compiled = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
            if (compiled[0] == 0) {
                val err = GLES20.glGetShaderInfoLog(shader)
                Log.e(TAG, "Shader compile failed: $err")
                GLES20.glDeleteShader(shader)
                throw RuntimeException("Shader compile failed: $err")
            }
            return shader
        }

        private fun checkGlError(op: String) {
            var error = GLES20.glGetError()
            while (error != GLES20.GL_NO_ERROR) {
                Log.e(TAG, "$op: glError $error")
                error = GLES20.glGetError()
            }
        }
    }
}
