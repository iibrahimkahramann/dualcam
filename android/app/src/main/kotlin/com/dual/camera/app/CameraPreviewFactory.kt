package com.dual.camera.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewFactory(private val cameraManager: DualCameraManager) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return object : PlatformView {
            override fun getView(): View {
                return cameraManager.getPrimaryPreviewView(context)
            }

            override fun dispose() {}
        }
    }
}

class HorizontalPreviewView(context: Context, private val cameraManager: DualCameraManager) :
    ImageView(context) {

    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null

    // Pre-allocated reusable double buffers (180x320 vertical, auto-cropped to 16:9 on GPU by CENTER_CROP)
    // 180 * 320 * 4 = 230 KB each. Total ~460 KB ever allocated. Zero GC churn!
    private val bufferA = Bitmap.createBitmap(180, 320, Bitmap.Config.ARGB_8888)
    private val bufferB = Bitmap.createBitmap(180, 320, Bitmap.Config.ARGB_8888)
    private var useBufferA = true

    @Volatile
    private var isUpdating = false

    private val updateRunnable = object : Runnable {
        override fun run() {
            if (!isUpdating) return
            try {
                captureFrame()
            } catch (e: Exception) {
                // Ignore transient errors
            }
            if (isUpdating) {
                bgHandler?.postDelayed(this, 50) // 20 FPS - smooth & zero main thread lag
            }
        }
    }

    init {
        scaleType = ScaleType.CENTER_CROP
        setBackgroundColor(Color.BLACK)
    }

    private fun captureFrame() {
        val preview = cameraManager.getPrimaryPreviewView(context)
        val textureView = findTextureView(preview) ?: return
        if (!textureView.isAvailable) return

        val targetBuffer = if (useBufferA) bufferA else bufferB
        try {
            // Hardware-accelerated scaling directly into pre-allocated 180x320 buffer on background thread
            textureView.getBitmap(targetBuffer)

            useBufferA = !useBufferA
            post {
                if (isUpdating) {
                    setImageBitmap(targetBuffer)
                }
            }
        } catch (e: Exception) {
            // Surface may be in transition
        }
    }

    private fun findTextureView(view: View?): TextureView? {
        if (view is TextureView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = findTextureView(view.getChildAt(i))
                if (child != null) return child
            }
        }
        return null
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isUpdating = true
        bgThread = HandlerThread("HorizPreviewThread").apply { start() }
        bgHandler = Handler(bgThread!!.looper)
        bgHandler?.post(updateRunnable)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }

    fun stop() {
        isUpdating = false
        bgHandler?.removeCallbacksAndMessages(null)
        try {
            bgThread?.quitSafely()
        } catch (e: Exception) {
            // Ignore
        }
        bgThread = null
        bgHandler = null
    }
}

class CameraHorizontalPreviewFactory(private val cameraManager: DualCameraManager) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = HorizontalPreviewView(context, cameraManager)
        return object : PlatformView {
            override fun getView(): View {
                return view
            }

            override fun dispose() {
                view.stop()
            }
        }
    }
}

class CameraFrontPreviewFactory(private val cameraManager: DualCameraManager) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return object : PlatformView {
            override fun getView(): View {
                return cameraManager.getFrontPreviewView(context)
            }

            override fun dispose() {}
        }
    }
}
