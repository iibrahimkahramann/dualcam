package com.dual.camera.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ConcurrentCamera.SingleCameraConfig
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class DualCameraManager(private val context: Context, private val lifecycleOwner: LifecycleOwner) {

    private var cameraProvider: ProcessCameraProvider? = null
    private var primaryCamera: Camera? = null
    private var secondaryCamera: Camera? = null

    private var primaryPreviewView: PreviewView? = null
    private var frontPreviewView: PreviewView? = null
    private var primaryPreviewUseCase: Preview? = null
    private var frontPreviewUseCase: Preview? = null

    private var primaryImageCapture: ImageCapture? = null
    private var secondaryImageCapture: ImageCapture? = null

    private var videoCapture: VideoCapture<Recorder>? = null
    private var currentRecording: Recording? = null
    private var dualVideoRecorder: DualVideoRecorder? = null
    private var currentVideoFile: File? = null
    private var pendingRecordingCallback: ((Result<List<String>>) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recordingTimeoutRunnable: Runnable? = null

    private val cameraExecutor = Executors.newSingleThreadExecutor()

    // Reusable 9:16 buffers & geometry objects for real-time Dual Cam video compositing (zero per-frame GC allocation)
    private val videoMainBuffer = Bitmap.createBitmap(720, 1280, Bitmap.Config.ARGB_8888)
    private val videoPipBuffer = Bitmap.createBitmap(270, 480, Bitmap.Config.ARGB_8888)
    private val videoBitmapPaint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG
    )
    private val pipClipPath = Path()
    private val renderDrawMatrix = Matrix()
    private val renderCorrectionMatrix = Matrix()
    private val renderMainDstRect = RectF()
    private val renderPipDstRect = RectF()

    var isRunning: Boolean = false
        private set

    var isMultiCamSupported: Boolean = false
        private set

    var isDualCamModeEnabled: Boolean = false
    var isPipSwapped: Boolean = false
    var isWideAngleModeEnabled: Boolean = false
    var pipCornerIndex: Int = 1 // 0: topLeft, 1: topRight, 2: bottomLeft, 3: bottomRight
    var currentLensFacing: Int = CameraSelector.LENS_FACING_BACK
    private var isUltraWideLensSelected: Boolean = false

    init {
        detectMultiCamSupport()
    }

    var currentCaptureWidth = 1080
    var currentCaptureHeight = 1920
    var currentFPS = 30

    private val activeCamera: Camera?
        get() = if (isMultiCamSupported && isDualCamModeEnabled && isPipSwapped) {
            secondaryCamera ?: primaryCamera
        } else {
            primaryCamera
        }

    fun checkPermissions(callback: (Boolean) -> Unit) {
        val cameraGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        val audioGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        callback(cameraGranted && audioGranted)
    }

    fun initialize(callback: (Boolean) -> Unit) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                detectMultiCamSupport()
                start()
                callback(true)
            } catch (e: Exception) {
                e.printStackTrace()
                callback(false)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun detectMultiCamSupport() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            try {
                val cm = context.getSystemService(Context.CAMERA_SERVICE) as? android.hardware.camera2.CameraManager
                if (cm != null) {
                    val concurrentSets = cm.concurrentCameraIds
                    for (set in concurrentSets) {
                        val hasBack = set.any { id ->
                            cm.getCameraCharacteristics(id).get(android.hardware.camera2.CameraCharacteristics.LENS_FACING) ==
                                    android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK
                        }
                        val hasFront = set.any { id ->
                            cm.getCameraCharacteristics(id).get(android.hardware.camera2.CameraCharacteristics.LENS_FACING) ==
                                    android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT
                        }
                        if (hasBack && hasFront) {
                            isMultiCamSupported = true
                            return
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        val provider = cameraProvider
        if (provider != null) {
            try {
                val concurrentInfos = provider.availableConcurrentCameraInfos
                for (cameraList in concurrentInfos) {
                    val hasFront = cameraList.any { it.lensFacing == CameraSelector.LENS_FACING_FRONT }
                    val hasBack = cameraList.any { it.lensFacing == CameraSelector.LENS_FACING_BACK }
                    if (hasFront && hasBack) {
                        isMultiCamSupported = true
                        return
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        isMultiCamSupported = false
    }

    fun start() {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        if (isMultiCamSupported && isDualCamModeEnabled) {
            startConcurrentCameras(provider)
        } else {
            secondaryCamera = null
            secondaryImageCapture = null
            startSingleCamera(provider)
        }

        isRunning = true
    }

    private fun startSingleCamera(provider: ProcessCameraProvider) {
        try {
            val cameraSelector = if (isUltraWideLensSelected && currentLensFacing == CameraSelector.LENS_FACING_BACK) {
                getUltraWideCameraSelector(provider) ?: CameraSelector.Builder()
                    .requireLensFacing(currentLensFacing)
                    .build()
            } else {
                CameraSelector.Builder()
                    .requireLensFacing(currentLensFacing)
                    .build()
            }

            val preview = Preview.Builder().build()
            primaryPreviewUseCase = preview
            frontPreviewUseCase = null
            primaryPreviewView?.let { preview.setSurfaceProvider(it.surfaceProvider) }

            primaryImageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()

            val recorder = Recorder.Builder()
                .setQualitySelector(QualitySelector.from(Quality.HD))
                .build()
            videoCapture = VideoCapture.withOutput(recorder)

            primaryCamera = provider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                primaryImageCapture,
                videoCapture
            )

            // If device supports zoom ratio < 1.0 (smooth ultra-wide), apply it
            if (isUltraWideLensSelected) {
                val minRatio = primaryCamera?.cameraInfo?.zoomState?.value?.minZoomRatio ?: 1.0f
                if (minRatio <= 0.6f) {
                    primaryCamera?.cameraControl?.setZoomRatio(minRatio)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Binds back + front cameras concurrently with Preview + Preview so both streams get maximum
     * concurrent resolution (up to 1440p) and zero surface-combination conflicts.
     * Both photo capture and video recording in Dual Cam mode composite directly from the two
     * live PreviewViews.
     */
    private fun startConcurrentCameras(provider: ProcessCameraProvider) {
        try {
            provider.unbindAll()

            val backPreview = Preview.Builder().build()
            val frontPreview = Preview.Builder().build()
            primaryPreviewUseCase = backPreview
            frontPreviewUseCase = frontPreview
            primaryPreviewView?.let { backPreview.setSurfaceProvider(it.surfaceProvider) }
            frontPreviewView?.let { frontPreview.setSurfaceProvider(it.surfaceProvider) }

            val backGroup = UseCaseGroup.Builder().addUseCase(backPreview).build()
            val frontGroup = UseCaseGroup.Builder().addUseCase(frontPreview).build()

            val concurrentCamera = provider.bindToLifecycle(
                listOf(
                    SingleCameraConfig(CameraSelector.DEFAULT_BACK_CAMERA, backGroup, lifecycleOwner),
                    SingleCameraConfig(CameraSelector.DEFAULT_FRONT_CAMERA, frontGroup, lifecycleOwner)
                )
            )

            primaryCamera = concurrentCamera.cameras.firstOrNull {
                it.cameraInfo.lensFacing == CameraSelector.LENS_FACING_BACK
            }
            secondaryCamera = concurrentCamera.cameras.firstOrNull {
                it.cameraInfo.lensFacing == CameraSelector.LENS_FACING_FRONT
            }
            primaryImageCapture = null
            secondaryImageCapture = null
            videoCapture = null

            android.util.Log.d("DualCamDebug", "Concurrent Preview+Preview bind OK")
            return
        } catch (e: Exception) {
            android.util.Log.w("DualCamDebug", "Concurrent bind failed: ${e.message}")
        }

        // Fallback if device does not really support concurrent cameras
        try { provider.unbindAll() } catch (_: Exception) {}
        secondaryCamera = null
        secondaryImageCapture = null
        isMultiCamSupported = false
        startSingleCamera(provider)
    }

    fun stop() {
        recordingTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        recordingTimeoutRunnable = null
        dualVideoRecorder?.stop {}
        dualVideoRecorder = null
        currentRecording?.stop()
        currentRecording = null
        pendingRecordingCallback = null
        cameraProvider?.unbindAll()
        isRunning = false
    }

    /** Existing views without any side effects (used by frame-copy previews). */
    val currentPrimaryPreviewView: PreviewView? get() = primaryPreviewView
    val currentFrontPreviewView: PreviewView? get() = frontPreviewView

    fun getPrimaryPreviewView(ctx: Context): PreviewView {
        primaryPreviewView?.let { return it }
        val view = PreviewView(ctx).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        primaryPreviewView = view
        val existingPreview = primaryPreviewUseCase
        if (isRunning && existingPreview != null) {
            existingPreview.setSurfaceProvider(view.surfaceProvider)
        } else {
            start()
        }
        return view
    }

    fun getFrontPreviewView(ctx: Context): PreviewView {
        frontPreviewView?.let { return it }
        val view = PreviewView(ctx).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        frontPreviewView = view
        val existingFrontPreview = frontPreviewUseCase
        if (isRunning && isMultiCamSupported && isDualCamModeEnabled && existingFrontPreview != null) {
            existingFrontPreview.setSurfaceProvider(view.surfaceProvider)
        } else {
            start()
        }
        return view
    }

    fun switchCamera(callback: (Result<Double>) -> Unit) {
        isUltraWideLensSelected = false

        // In concurrent dual mode both cameras are already live; swapping the PiP is
        // a UI + compositor swap, so do NOT rebind (rebinding would restart both cameras).
        if (isMultiCamSupported && isDualCamModeEnabled && secondaryCamera != null) {
            isPipSwapped = !isPipSwapped
            callback(Result.success(getMaxZoom()))
            return
        }

        currentLensFacing = if (currentLensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        start()
        callback(Result.success(getMaxZoom()))
    }

    fun hasUltraWideCamera(): Boolean {
        if (currentLensFacing != CameraSelector.LENS_FACING_BACK) return false
        val minRatio = primaryCamera?.cameraInfo?.zoomState?.value?.minZoomRatio?.toDouble() ?: 1.0
        if (minRatio <= 0.6) return true

        try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as? android.hardware.camera2.CameraManager
            if (cm != null) {
                val chars = cm.getCameraCharacteristics("0")
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                    val physicalIds = chars.physicalCameraIds
                    for (pId in physicalIds) {
                        val pChars = cm.getCameraCharacteristics(pId)
                        val focals = pChars.get(android.hardware.camera2.CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                        if (focals != null && focals.any { it < 3.0f }) {
                            return true
                        }
                    }
                }
                for (id in cm.cameraIdList) {
                    val characteristics = cm.getCameraCharacteristics(id)
                    val facing = characteristics.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                    val focalLengths = characteristics.get(android.hardware.camera2.CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                    if (facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK &&
                        focalLengths != null && focalLengths.any { it < 3.0f }) {
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun getUltraWideCameraSelector(provider: ProcessCameraProvider): CameraSelector? {
        val backCameras = provider.availableCameraInfos.filter { it.lensFacing == CameraSelector.LENS_FACING_BACK }
        val ultraWideInfo = backCameras.firstOrNull { info ->
            try {
                val characteristics = androidx.camera.camera2.interop.Camera2CameraInfo.from(info)
                val focalLengths = characteristics.getCameraCharacteristic(
                    android.hardware.camera2.CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS
                )
                focalLengths != null && focalLengths.any { it < 3.0f }
            } catch (e: Exception) {
                false
            }
        }
        if (ultraWideInfo != null) {
            return CameraSelector.Builder()
                .addCameraFilter { cameras ->
                    if (cameras.contains(ultraWideInfo)) listOf(ultraWideInfo) else cameras
                }
                .build()
        }
        return null
    }

    fun getMinZoom(): Double {
        val cam = activeCamera
        val isBack = if (isMultiCamSupported && isDualCamModeEnabled) !isPipSwapped else (currentLensFacing == CameraSelector.LENS_FACING_BACK)
        if (isBack) {
            val minRatio = cam?.cameraInfo?.zoomState?.value?.minZoomRatio?.toDouble() ?: 1.0
            if (minRatio <= 0.6) return 0.5
            if (hasUltraWideCamera()) return 0.5
            return 1.0
        } else {
            val minRatio = cam?.cameraInfo?.zoomState?.value?.minZoomRatio?.toDouble() ?: 1.0
            if (minRatio <= 0.6) return minRatio
            return 1.0
        }
    }

    fun getMaxZoom(): Double {
        return activeCamera?.cameraInfo?.zoomState?.value?.maxZoomRatio?.toDouble() ?: 5.0
    }

    fun setZoom(factor: Double) {
        val cam = activeCamera ?: return
        val minRatio = cam.cameraInfo.zoomState.value?.minZoomRatio ?: 1.0f
        val maxRatio = cam.cameraInfo.zoomState.value?.maxZoomRatio ?: 5.0f

        if (factor < 0.9) {
            if (minRatio <= 0.6f) {
                val target = factor.toFloat().coerceAtLeast(minRatio)
                cam.cameraControl.setZoomRatio(target)
            } else if (hasUltraWideCamera() && currentLensFacing == CameraSelector.LENS_FACING_BACK) {
                try {
                    val c2Control = androidx.camera.camera2.interop.Camera2CameraControl.from(cam.cameraControl)
                    val options = androidx.camera.camera2.interop.CaptureRequestOptions.Builder()
                        .setCaptureRequestOption(android.hardware.camera2.CaptureRequest.CONTROL_ZOOM_RATIO, factor.toFloat())
                        .build()
                    c2Control.setCaptureRequestOptions(options)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        } else {
            try {
                val c2Control = androidx.camera.camera2.interop.Camera2CameraControl.from(cam.cameraControl)
                val options = androidx.camera.camera2.interop.CaptureRequestOptions.Builder()
                    .clearCaptureRequestOption(android.hardware.camera2.CaptureRequest.CONTROL_ZOOM_RATIO)
                    .build()
                c2Control.setCaptureRequestOptions(options)
            } catch (e: Exception) {
                // Ignore
            }
            val target = factor.toFloat().coerceIn(minRatio, maxRatio)
            cam.cameraControl.setZoomRatio(target)
        }
    }

    fun setWideAngleMode(enabled: Boolean) {
        isWideAngleModeEnabled = enabled
    }

    fun toggleTorch(enabled: Boolean) {
        primaryCamera?.cameraControl?.enableTorch(enabled)
    }

    fun setExposureBias(bias: Double) {
        activeCamera?.cameraControl?.setExposureCompensationIndex(bias.roundToInt())
    }

    fun setFocusPoint(x: Double, y: Double) {
        val preview = if (isMultiCamSupported && isDualCamModeEnabled && isPipSwapped) {
            frontPreviewView ?: primaryPreviewView
        } else {
            primaryPreviewView
        } ?: return
        val factory = preview.meteringPointFactory
        val point = factory.createPoint(x.toFloat() * preview.width, y.toFloat() * preview.height)
        val action = FocusMeteringAction.Builder(point).build()
        activeCamera?.cameraControl?.startFocusAndMetering(action)
    }

    fun setHDR(enabled: Boolean) {
        // HDR on Android CameraX is handled through CameraExtensions or exposure compensation
    }

    fun setResolution(width: Int, height: Int, fps: Int) {
        currentCaptureWidth = width
        currentCaptureHeight = height
        currentFPS = fps
    }

    fun getAvailableResolutions(): List<Map<String, Any>> {
        return listOf(
            mapOf("width" to 1920, "height" to 1080, "fps" to 30, "label" to "1080p 30 FPS"),
            mapOf("width" to 1280, "height" to 720, "fps" to 30, "label" to "720p 30 FPS"),
            mapOf("width" to 3840, "height" to 2160, "fps" to 30, "label" to "4K 30 FPS")
        )
    }

    fun startRecording() {
        val hasAudio = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        // 1. In Dual Cam mode, record composited video (main camera + rounded-corner PiP camera)
        if (isMultiCamSupported && isDualCamModeEnabled) {
            dualVideoRecorder?.stop {}
            val outputFile = File(context.cacheDir, "video_dual_" + UUID.randomUUID().toString() + ".mp4")
            currentVideoFile = outputFile

            val recorder = DualVideoRecorder(
                outputFile = outputFile,
                enableAudio = hasAudio,
                frameRenderer = { canvas, width, height ->
                    renderDualVideoFrame(canvas, width, height)
                }
            )
            if (recorder.start()) {
                dualVideoRecorder = recorder
                return
            } else {
                dualVideoRecorder = null
            }
        }

        // 2. In Wide Angle mode, record BOTH 9:16 vertical and 16:9 center-cropped horizontal video simultaneously
        if (isWideAngleModeEnabled) {
            dualVideoRecorder?.stop {}
            val vertFile = File(context.cacheDir, "video_vert_" + UUID.randomUUID().toString() + ".mp4")
            val horizFile = File(context.cacheDir, "video_horiz_" + UUID.randomUUID().toString() + ".mp4")
            currentVideoFile = vertFile

            val recorder = DualVideoRecorder(
                outputFile = vertFile,
                enableAudio = hasAudio,
                horizontalOutputFile = horizFile,
                framePrePass = {
                    captureSingleCameraBuffer()
                },
                horizontalFrameRenderer = { canvas, width, height ->
                    renderSingleCameraFrame(canvas, width, height, copyTexture = false)
                },
                frameRenderer = { canvas, width, height ->
                    renderSingleCameraFrame(canvas, width, height, copyTexture = false)
                }
            )
            if (recorder.start()) {
                dualVideoRecorder = recorder
                return
            } else {
                dualVideoRecorder = null
            }
        }

        val vc = videoCapture
        if (vc == null) {
            currentVideoFile = null
            return
        }
        val outputFile = File(context.cacheDir, "video_" + UUID.randomUUID().toString() + ".mp4")
        currentVideoFile = outputFile

        val outputOptions = FileOutputOptions.Builder(outputFile).build()

        val pendingRecording = vc.output.prepareRecording(context, outputOptions)
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            pendingRecording.withAudioEnabled()
        }

        currentRecording = pendingRecording.start(ContextCompat.getMainExecutor(context)) { event ->
            if (event is VideoRecordEvent.Finalize) {
                recordingTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingTimeoutRunnable = null

                val cb = pendingRecordingCallback
                pendingRecordingCallback = null
                currentRecording = null

                if (!event.hasError()) {
                    val path = currentVideoFile?.absolutePath
                    if (path != null && File(path).exists() && File(path).length() > 0) {
                        cb?.invoke(Result.success(listOf(path)))
                    } else {
                        cb?.invoke(Result.failure(Exception("Recorded video file is missing or empty")))
                    }
                } else {
                    cb?.invoke(Result.failure(Exception("Video recording failed: ${event.error}")))
                }
            }
        }
    }

    fun stopRecording(callback: (Result<List<String>>) -> Unit) {
        val dualRec = dualVideoRecorder
        if (dualRec != null) {
            dualVideoRecorder = null
            dualRec.stop(callback)
            return
        }

        val rec = currentRecording
        if (rec == null) {
            val path = currentVideoFile?.absolutePath
            if (path != null && File(path).exists() && File(path).length() > 0) {
                callback(Result.success(listOf(path)))
            } else {
                callback(Result.failure(Exception("No active recording")))
            }
            return
        }

        pendingRecordingCallback = callback
        rec.stop()

        // 5-second safety timeout in case CameraX finalize event is delayed
        val timeoutRunnable = Runnable {
            val cb = pendingRecordingCallback
            if (cb != null) {
                pendingRecordingCallback = null
                currentRecording = null
                val path = currentVideoFile?.absolutePath
                if (path != null && File(path).exists() && File(path).length() > 0) {
                    cb.invoke(Result.success(listOf(path)))
                } else {
                    cb.invoke(Result.failure(Exception("Recording finalize timeout")))
                }
            }
        }
        recordingTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, 5000)
    }

    private fun captureSingleCameraBuffer(): Boolean {
        val mainView = primaryPreviewView ?: return false
        val mainTv = findTextureView(mainView) ?: return false
        if (!mainTv.isAvailable) return false
        mainTv.getBitmap(videoMainBuffer)
        return true
    }

    private fun renderSingleCameraFrame(
        canvas: Canvas,
        width: Int,
        height: Int,
        copyTexture: Boolean = true
    ): Boolean {
        val mainView = primaryPreviewView ?: return false
        val mainTv = findTextureView(mainView) ?: return false
        if (!mainTv.isAvailable) return false

        canvas.drawColor(Color.BLACK)
        renderMainDstRect.set(0f, 0f, width.toFloat(), height.toFloat())
        drawTextureViewToCanvas(mainView, mainTv, videoMainBuffer, canvas, renderMainDstRect, copyTexture)
        return true
    }

    private fun renderDualVideoFrame(canvas: Canvas, width: Int, height: Int): Boolean {
        val mainView = if (isPipSwapped) frontPreviewView else primaryPreviewView
        val pipView = if (isPipSwapped) primaryPreviewView else frontPreviewView

        val mainTv = findTextureView(mainView) ?: return false
        if (!mainTv.isAvailable || mainView == null) return false

        canvas.drawColor(Color.BLACK)

        renderMainDstRect.set(0f, 0f, width.toFloat(), height.toFloat())
        drawTextureViewToCanvas(mainView, mainTv, videoMainBuffer, canvas, renderMainDstRect, copyTexture = true)

        val pipTv = findTextureView(pipView)
        if (pipView != null && pipTv != null && pipTv.isAvailable) {
            val scaleFactor = width / 1080f
            val pipW = width * 0.3f
            val pipH = height * 0.3f
            val padding = 40f * scaleFactor
            val cornerRadius = 24f * scaleFactor

            val left = if (pipCornerIndex == 0 || pipCornerIndex == 2) padding else (width - pipW - padding)
            val top = if (pipCornerIndex == 0 || pipCornerIndex == 1) padding else (height - pipH - padding)
            renderPipDstRect.set(left, top, left + pipW, top + pipH)

            pipClipPath.reset()
            pipClipPath.addRoundRect(renderPipDstRect, cornerRadius, cornerRadius, Path.Direction.CW)

            canvas.save()
            canvas.clipPath(pipClipPath)
            drawTextureViewToCanvas(pipView, pipTv, videoPipBuffer, canvas, renderPipDstRect, copyTexture = true)
            canvas.restore()
        }

        return true
    }

    internal fun drawTextureViewToCanvas(
        previewView: PreviewView,
        textureView: TextureView,
        buffer: Bitmap,
        canvas: Canvas,
        dstRect: RectF,
        copyTexture: Boolean = true
    ) {
        if (copyTexture) {
            textureView.getBitmap(buffer)
        }
        val tvW = textureView.width
        val tvH = textureView.height
        val pvW = previewView.width
        val pvH = previewView.height

        if (tvW <= 0 || tvH <= 0 || pvW <= 0 || pvH <= 0) {
            canvas.drawBitmap(buffer, null, dstRect, videoBitmapPaint)
            return
        }

        val matrix = renderDrawMatrix
        matrix.reset()
        // 1. Map buffer coordinates -> TextureView layout coordinates (mResolution)
        matrix.setScale(
            tvW.toFloat() / buffer.width.toFloat(),
            tvH.toFloat() / buffer.height.toFloat()
        )
        // 2. Apply CameraX's TextureView orientation correction matrix
        val correction = renderCorrectionMatrix
        correction.reset()
        textureView.getTransform(correction)
        matrix.postConcat(correction)
        // 3. Apply CameraX's FILL_CENTER scale & translation into PreviewView space (0..pvW, 0..pvH)
        matrix.postScale(textureView.scaleX, textureView.scaleY)
        matrix.postTranslate(textureView.translationX, textureView.translationY)
        // 4. Center-crop PreviewView space (0..pvW, 0..pvH) into dstRect
        val scaleToDst = maxOf(
            dstRect.width() / pvW.toFloat(),
            dstRect.height() / pvH.toFloat()
        )
        val dx = dstRect.left + (dstRect.width() - pvW * scaleToDst) / 2f
        val dy = dstRect.top + (dstRect.height() - pvH * scaleToDst) / 2f
        matrix.postScale(scaleToDst, scaleToDst)
        matrix.postTranslate(dx, dy)

        canvas.drawBitmap(buffer, matrix, videoBitmapPaint)
    }

    internal fun findTextureView(view: View?): TextureView? {
        if (view is TextureView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = findTextureView(view.getChildAt(i))
                if (child != null) return child
            }
        }
        return null
    }

    private fun capturePreviewBitmapOnUiThread(previewView: PreviewView?): Bitmap? {
        if (previewView == null) return null
        try {
            val bmp = previewView.bitmap
            if (bmp != null && bmp.width > 0 && bmp.height > 0) {
                return bmp
            }
        } catch (_: Exception) {}

        val tv = findTextureView(previewView) ?: return null
        if (!tv.isAvailable) return null
        val outW = if (previewView.width > 0) previewView.width else 1080
        val outH = if (previewView.height > 0) previewView.height else 1920
        val raw = tv.getBitmap(minOf(outW, 1080), minOf(outH, 1920)) ?: return null
        val output = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        drawTextureViewToCanvas(previewView, tv, raw, canvas, RectF(0f, 0f, outW.toFloat(), outH.toFloat()))
        raw.recycle()
        return output
    }

    fun takePhoto(callback: (Result<List<String>>) -> Unit) {
        // In Dual Cam mode, capture both live PreviewViews on the UI thread and composite them on cameraExecutor
        if (isMultiCamSupported && isDualCamModeEnabled) {
            mainHandler.post {
                val mainView = if (isPipSwapped) frontPreviewView else primaryPreviewView
                val pipView = if (isPipSwapped) primaryPreviewView else frontPreviewView

                val mainBitmap = capturePreviewBitmapOnUiThread(mainView)
                val pipBitmap = capturePreviewBitmapOnUiThread(pipView)

                if (mainBitmap == null) {
                    callback(Result.failure(Exception("Failed to capture dual camera preview frame")))
                    return@post
                }

                cameraExecutor.execute {
                    try {
                        val composited = if (pipBitmap != null) {
                            createPipComposite(mainBitmap, pipBitmap)
                        } else {
                            mainBitmap
                        }

                        val finalFile = File(context.cacheDir, "photo_dual_" + UUID.randomUUID().toString() + ".jpg")
                        FileOutputStream(finalFile).use { out ->
                            composited.compress(Bitmap.CompressFormat.JPEG, 95, out)
                        }

                        mainHandler.post {
                            callback(Result.success(listOf(finalFile.absolutePath)))
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            callback(Result.failure(e))
                        }
                    }
                }
            }
            return
        }

        val capture = primaryImageCapture
        if (capture == null) {
            callback(Result.failure(Exception("ImageCapture is null")))
            return
        }

        val primaryFile = File(context.cacheDir, "photo_" + UUID.randomUUID().toString() + ".jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(primaryFile).build()

        capture.takePicture(
            outputOptions,
            cameraExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    handleSinglePhotoSaved(primaryFile, callback)
                }

                override fun onError(exception: ImageCaptureException) {
                    callback(Result.failure(exception))
                }
            }
        )
    }

    private fun createPipComposite(main: Bitmap, pip: Bitmap): Bitmap {
        val outW = maxOf(main.width, 1080)
        val outH = if (main.width > 0 && main.height > 0) {
            (outW.toFloat() * main.height.toFloat() / main.width.toFloat()).roundToInt()
        } else {
            1920
        }

        val result = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        canvas.drawBitmap(main, null, RectF(0f, 0f, outW.toFloat(), outH.toFloat()), videoBitmapPaint)

        val scaleFactor = outW / 1080f
        val pipWidth = (outW * 0.3f).roundToInt()
        val pipHeight = (outH * 0.3f).roundToInt()
        val padding = 40f * scaleFactor
        val cornerRadius = 24f * scaleFactor

        val left = if (pipCornerIndex == 0 || pipCornerIndex == 2) padding else (outW - pipWidth - padding)
        val top = if (pipCornerIndex == 0 || pipCornerIndex == 1) padding else (outH - pipHeight - padding)

        val roundedPip = getRoundedCornerBitmap(pip, cornerRadius, pipWidth, pipHeight)
        canvas.drawBitmap(roundedPip, left, top, videoBitmapPaint)

        return result
    }

    private fun getRoundedCornerBitmap(
        bitmap: Bitmap,
        cornerRadius: Float,
        targetWidth: Int,
        targetHeight: Int
    ): Bitmap {
        val output = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        paint.color = -0x1
        val rect = Rect(0, 0, targetWidth, targetHeight)
        val rectF = RectF(rect)

        canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)

        // Center-crop the source bitmap into (targetWidth, targetHeight) so it never stretches
        val scale = maxOf(
            targetWidth.toFloat() / bitmap.width.toFloat(),
            targetHeight.toFloat() / bitmap.height.toFloat()
        )
        val scaledW = bitmap.width * scale
        val scaledH = bitmap.height * scale
        val dx = (targetWidth - scaledW) / 2f
        val dy = (targetHeight - scaledH) / 2f
        val dstRect = RectF(dx, dy, dx + scaledW, dy + scaledH)

        canvas.drawBitmap(bitmap, null, dstRect, paint)

        return output
    }

    private fun decodeBitmapWithExif(path: String): Bitmap? {
        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOptions)
        var sampleSize = 1
        val maxDim = maxOf(boundsOptions.outWidth, boundsOptions.outHeight)
        while (maxDim / sampleSize > 2560) {
            sampleSize *= 2
        }
        val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val raw = BitmapFactory.decodeFile(path, decodeOptions) ?: return null
        return try {
            val exif = ExifInterface(path)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                else -> return raw
            }
            Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
        } catch (_: Exception) {
            raw
        }
    }

    private fun handleSinglePhotoSaved(primaryFile: File, callback: (Result<List<String>>) -> Unit) {
        val results = mutableListOf(primaryFile.absolutePath)

        if (isWideAngleModeEnabled) {
            try {
                val original = decodeBitmapWithExif(primaryFile.absolutePath)
                if (original != null) {
                    val width = original.width
                    val height = (width * (9.0 / 16.0)).roundToInt().coerceAtMost(original.height)
                    val yOffset = ((original.height - height) / 2).coerceAtLeast(0)

                    val cropped = Bitmap.createBitmap(original, 0, yOffset, width, height)
                    val horizFile = File(context.cacheDir, "photo_horiz_" + UUID.randomUUID().toString() + ".jpg")
                    FileOutputStream(horizFile).use { out ->
                        cropped.compress(Bitmap.CompressFormat.JPEG, 95, out)
                    }
                    results.add(horizFile.absolutePath)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        ContextCompat.getMainExecutor(context).execute {
            callback(Result.success(results))
        }
    }
}
