package com.dual.camera.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import androidx.camera.core.Camera
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.ConcurrentCamera
import androidx.camera.core.ConcurrentCamera.SingleCameraConfig
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.VideoRecordEvent
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
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

    private var primaryImageCapture: ImageCapture? = null
    private var secondaryImageCapture: ImageCapture? = null

    private var videoCapture: VideoCapture<Recorder>? = null
    private var currentRecording: Recording? = null
    private var currentVideoFile: File? = null
    private var pendingRecordingCallback: ((Result<List<String>>) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recordingTimeoutRunnable: Runnable? = null

    private val cameraExecutor = Executors.newSingleThreadExecutor()

    var isRunning: Boolean = false
        private set

    var isMultiCamSupported: Boolean = false
        private set

    var isDualCamModeEnabled: Boolean = false
    var isWideAngleModeEnabled: Boolean = false
    var currentLensFacing: Int = CameraSelector.LENS_FACING_BACK
    private var isUltraWideLensSelected: Boolean = false

    init {
        detectMultiCamSupport()
    }

    var currentCaptureWidth = 1080
    var currentCaptureHeight = 1920
    var currentFPS = 30

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
     * Binds back + front cameras concurrently.
     *
     * Concurrent camera hardware only guarantees a limited number of streams per camera,
     * so we try progressively lighter use-case combinations. The last attempt is
     * Preview + Preview, which every concurrent-capable device must support — this
     * guarantees both previews are live (back in primaryPreviewView, front in frontPreviewView).
     */
    private fun startConcurrentCameras(provider: ProcessCameraProvider) {
        // attempt index -> (back has ImageCapture, back has VideoCapture, front has ImageCapture)
        val attempts = listOf(
            Triple(true, true, true),
            Triple(false, true, true),
            Triple(true, false, true),
            Triple(false, true, false),
            Triple(true, false, false),
            Triple(false, false, false)
        )

        for ((backImage, backVideo, frontImage) in attempts) {
            try {
                provider.unbindAll()

                val backPreview = Preview.Builder().build()
                val frontPreview = Preview.Builder().build()
                primaryPreviewView?.let { backPreview.setSurfaceProvider(it.surfaceProvider) }
                frontPreviewView?.let { frontPreview.setSurfaceProvider(it.surfaceProvider) }

                val backImageCapture = if (backImage) ImageCapture.Builder().build() else null
                val frontImageCapture = if (frontImage) ImageCapture.Builder().build() else null
                val backVideoCapture = if (backVideo) {
                    VideoCapture.withOutput(
                        Recorder.Builder()
                            .setQualitySelector(QualitySelector.from(Quality.HD))
                            .build()
                    )
                } else null

                val backGroup = UseCaseGroup.Builder().addUseCase(backPreview).apply {
                    backImageCapture?.let { addUseCase(it) }
                    backVideoCapture?.let { addUseCase(it) }
                }.build()

                val frontGroup = UseCaseGroup.Builder().addUseCase(frontPreview).apply {
                    frontImageCapture?.let { addUseCase(it) }
                }.build()

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
                primaryImageCapture = backImageCapture
                secondaryImageCapture = frontImageCapture
                videoCapture = backVideoCapture

                android.util.Log.d(
                    "DualCamDebug",
                    "Concurrent bind OK (backImage=$backImage, backVideo=$backVideo, frontImage=$frontImage)"
                )
                return
            } catch (e: Exception) {
                android.util.Log.w(
                    "DualCamDebug",
                    "Concurrent bind failed (backImage=$backImage, backVideo=$backVideo, frontImage=$frontImage): ${e.message}"
                )
            }
        }

        // Even Preview + Preview failed: device does not really support concurrent cameras.
        try { provider.unbindAll() } catch (_: Exception) {}
        secondaryCamera = null
        secondaryImageCapture = null
        isMultiCamSupported = false
        startSingleCamera(provider)
    }

    fun stop() {
        recordingTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        recordingTimeoutRunnable = null
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
        start()
        return view
    }

    fun getFrontPreviewView(ctx: Context): PreviewView {
        frontPreviewView?.let { return it }
        val view = PreviewView(ctx).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        frontPreviewView = view
        start()
        return view
    }

    fun switchCamera(callback: (Result<Double>) -> Unit) {
        isUltraWideLensSelected = false

        // In concurrent dual mode both cameras are already live; swapping the PiP is
        // purely a UI change, so do NOT rebind (rebinding would restart both cameras).
        if (isMultiCamSupported && isDualCamModeEnabled && secondaryCamera != null) {
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
                    android.util.Log.d("DualCamDebug", "Camera 0 physicalIds: $physicalIds")
                    for (pId in physicalIds) {
                        val pChars = cm.getCameraCharacteristics(pId)
                        val focals = pChars.get(android.hardware.camera2.CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                        android.util.Log.d("DualCamDebug", "Physical camera $pId focals: ${focals?.toList()}")
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
        if (currentLensFacing == CameraSelector.LENS_FACING_BACK) {
            val minRatio = primaryCamera?.cameraInfo?.zoomState?.value?.minZoomRatio?.toDouble() ?: 1.0
            if (minRatio <= 0.6) return 0.5
            if (hasUltraWideCamera()) return 0.5
            return 1.0
        } else {
            val minRatio = primaryCamera?.cameraInfo?.zoomState?.value?.minZoomRatio?.toDouble() ?: 1.0
            if (minRatio <= 0.6) return minRatio
            return 1.0
        }
    }

    fun getMaxZoom(): Double {
        return primaryCamera?.cameraInfo?.zoomState?.value?.maxZoomRatio?.toDouble() ?: 5.0
    }

    fun setZoom(factor: Double) {
        val minRatio = primaryCamera?.cameraInfo?.zoomState?.value?.minZoomRatio ?: 1.0f
        val maxRatio = primaryCamera?.cameraInfo?.zoomState?.value?.maxZoomRatio ?: 5.0f

        if (factor < 0.9) {
            if (minRatio <= 0.6f) {
                val target = factor.toFloat().coerceAtLeast(minRatio)
                primaryCamera?.cameraControl?.setZoomRatio(target)
            } else if (hasUltraWideCamera() && currentLensFacing == CameraSelector.LENS_FACING_BACK) {
                try {
                    val c2Control = androidx.camera.camera2.interop.Camera2CameraControl.from(primaryCamera!!.cameraControl)
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
                val c2Control = androidx.camera.camera2.interop.Camera2CameraControl.from(primaryCamera!!.cameraControl)
                val options = androidx.camera.camera2.interop.CaptureRequestOptions.Builder()
                    .clearCaptureRequestOption(android.hardware.camera2.CaptureRequest.CONTROL_ZOOM_RATIO)
                    .build()
                c2Control.setCaptureRequestOptions(options)
            } catch (e: Exception) {
                // Ignore
            }
            val target = factor.toFloat().coerceIn(minRatio, maxRatio)
            primaryCamera?.cameraControl?.setZoomRatio(target)
        }
    }

    fun setWideAngleMode(enabled: Boolean) {
        isWideAngleModeEnabled = enabled
    }

    fun toggleTorch(enabled: Boolean) {
        primaryCamera?.cameraControl?.enableTorch(enabled)
    }

    fun setExposureBias(bias: Double) {
        primaryCamera?.cameraControl?.setExposureCompensationIndex(bias.roundToInt())
    }

    fun setFocusPoint(x: Double, y: Double) {
        val preview = primaryPreviewView ?: return
        val factory = preview.meteringPointFactory
        val point = factory.createPoint(x.toFloat() * preview.width, y.toFloat() * preview.height)
        val action = FocusMeteringAction.Builder(point).build()
        primaryCamera?.cameraControl?.startFocusAndMetering(action)
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
        val vc = videoCapture
        if (vc == null) {
            currentVideoFile = null
            return
        }
        val outputFile = File(context.cacheDir, "video_" + java.util.UUID.randomUUID().toString() + ".mp4")
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

    fun takePhoto(callback: (Result<List<String>>) -> Unit) {
        val capture = primaryImageCapture
        if (capture == null) {
            callback(Result.failure(Exception("ImageCapture is null")))
            return
        }

        val primaryFile = File(context.cacheDir, "photo_" + java.util.UUID.randomUUID().toString() + ".jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(primaryFile).build()

        capture.takePicture(
            outputOptions,
            cameraExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    if (isMultiCamSupported && isDualCamModeEnabled && secondaryImageCapture != null) {
                        captureSecondaryAndComposite(primaryFile, callback)
                    } else {
                        handleSinglePhotoSaved(primaryFile, callback)
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    callback(Result.failure(exception))
                }
            }
        )
    }

    private fun captureSecondaryAndComposite(
        primaryFile: File,
        callback: (Result<List<String>>) -> Unit
    ) {
        val secondaryFile = File(context.cacheDir, "temp_front_" + java.util.UUID.randomUUID().toString() + ".jpg")
        val options = ImageCapture.OutputFileOptions.Builder(secondaryFile).build()

        secondaryImageCapture?.takePicture(
            options,
            cameraExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    try {
                        val backBitmap = BitmapFactory.decodeFile(primaryFile.absolutePath)
                        val frontBitmap = BitmapFactory.decodeFile(secondaryFile.absolutePath)

                        val composited = createPipComposite(backBitmap, frontBitmap)

                        val finalFile = File(context.cacheDir, "photo_dual_" + java.util.UUID.randomUUID().toString() + ".jpg")
                        FileOutputStream(finalFile).use { out ->
                            composited.compress(Bitmap.CompressFormat.JPEG, 95, out)
                        }

                        // Cleanup temp files
                        primaryFile.delete()
                        secondaryFile.delete()

                        ContextCompat.getMainExecutor(context).execute {
                            callback(Result.success(listOf(finalFile.absolutePath)))
                        }
                    } catch (e: Exception) {
                        handleSinglePhotoSaved(primaryFile, callback)
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    handleSinglePhotoSaved(primaryFile, callback)
                }
            }
        ) ?: handleSinglePhotoSaved(primaryFile, callback)
    }

    private fun createPipComposite(back: Bitmap, front: Bitmap): Bitmap {
        val result = back.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(result)

        val pipWidth = (back.width * 0.3f).roundToInt()
        val pipHeight = (back.height * 0.3f).roundToInt()
        val padding = 40f

        val left = back.width - pipWidth - padding
        val top = padding
        val right = left + pipWidth
        val bottom = top + pipHeight

        val roundedFront = getRoundedCornerBitmap(front, 24f, pipWidth, pipHeight)
        canvas.drawBitmap(roundedFront, left, top, null)

        return result
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadius: Float, targetWidth: Int, targetHeight: Int): Bitmap {
        val scaled = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
        val output = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        val paint = Paint().apply {
            isAntiAlias = true
            color = -0x1
        }
        val rect = Rect(0, 0, targetWidth, targetHeight)
        val rectF = RectF(rect)

        canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(scaled, rect, rect, paint)

        return output
    }

    private fun handleSinglePhotoSaved(primaryFile: File, callback: (Result<List<String>>) -> Unit) {
        val results = mutableListOf(primaryFile.absolutePath)

        if (isWideAngleModeEnabled) {
            try {
                val original = BitmapFactory.decodeFile(primaryFile.absolutePath)
                val width = original.width
                val height = (width * (9.0 / 16.0)).roundToInt()
                val yOffset = (original.height - height) / 2

                val cropped = Bitmap.createBitmap(original, 0, yOffset, width, height)
                val horizFile = File(context.cacheDir, "photo_horiz_" + java.util.UUID.randomUUID().toString() + ".jpg")
                FileOutputStream(horizFile).use { out ->
                    cropped.compress(Bitmap.CompressFormat.JPEG, 95, out)
                }
                results.add(horizFile.absolutePath)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        ContextCompat.getMainExecutor(context).execute {
            callback(Result.success(results))
        }
    }
}
