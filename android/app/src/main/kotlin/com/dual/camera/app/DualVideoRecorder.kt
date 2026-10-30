package com.dual.camera.app

import android.annotation.SuppressLint
import android.graphics.Canvas
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Hardware-accelerated real-time video + audio recorder for Android.
 * Supports:
 * 1) Dual Camera PiP composited recording (main camera + rounded-corner PiP in any of the 4 corners)
 * 2) Simultaneous Vertical (9:16) + Horizontal (16:9) recording in Wide Angle mode
 */
class DualVideoRecorder(
    private val outputFile: File,
    private val enableAudio: Boolean,
    private val horizontalOutputFile: File? = null,
    private val framePrePass: (() -> Boolean)? = null,
    private val horizontalFrameRenderer: ((Canvas, Int, Int) -> Boolean)? = null,
    private val frameRenderer: (Canvas, Int, Int) -> Boolean
) {
    companion object {
        private const val TAG = "DualVideoRecorder"
        private const val VIDEO_MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val AUDIO_MIME = MediaFormat.MIMETYPE_AUDIO_AAC
        private const val SAMPLE_RATE = 44100
        private const val AUDIO_BITRATE = 64000
        private const val FPS = 30
    }

    private class PendingSample(
        val isVideo: Boolean,
        val data: ByteBuffer,
        val flags: Int,
        val presentationTimeUs: Long
    )

    private var videoWidth = 1080
    private var videoHeight = 1920

    private var videoEncoder: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var mediaMuxer: MediaMuxer? = null
    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerStarted = false
    private val pendingSamples = mutableListOf<PendingSample>()

    // Optional second encoder/muxer for simultaneous 16:9 horizontal video in Wide Angle mode
    private var horizWidth = 1280
    private var horizHeight = 720
    private var horizVideoEncoder: MediaCodec? = null
    private var horizInputSurface: Surface? = null
    private var horizMediaMuxer: MediaMuxer? = null
    private var horizVideoTrackIndex = -1
    private var horizAudioTrackIndex = -1
    private var horizMuxerStarted = false
    private val horizPendingSamples = mutableListOf<PendingSample>()

    private var audioEncoder: MediaCodec? = null
    private var audioRecord: AudioRecord? = null
    private var cachedAudioOutputFormat: MediaFormat? = null

    private val muxerLock = Any()
    private var audioActive = false

    private var startNanoTime = 0L
    private var lastVideoPtsUs = 0L
    private var lastHorizVideoPtsUs = 0L
    private var lastAudioPtsUs = 0L

    private val isRecording = AtomicBoolean(false)
    private var videoThread: HandlerThread? = null
    private var videoHandler: Handler? = null
    private var audioThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun start(): Boolean {
        if (isRecording.getAndSet(true)) return false

        return try {
            videoThread = HandlerThread("DualVideoRecorderThread", Process.THREAD_PRIORITY_DISPLAY).apply {
                start()
            }
            val handler = Handler(videoThread!!.looper)
            videoHandler = handler

            // Initialize hardware MediaCodec encoders, AudioRecord, and MediaMuxer on the background
            // recorder thread so the main/UI thread never stutters when tapping Record.
            handler.post {
                if (!isRecording.get()) return@post
                if (!initializeEncodersOnRecorderThread()) {
                    isRecording.set(false)
                    releaseResources()
                    return@post
                }
                if (isRecording.get()) {
                    handler.post(frameLoopRunnable)
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting DualVideoRecorder", e)
            isRecording.set(false)
            releaseResources()
            false
        }
    }

    private fun initializeEncodersOnRecorderThread(): Boolean {
        return try {
            if (!setupVideoEncoder(1080, 1920, 8_000_000)) {
                if (!setupVideoEncoder(720, 1280, 5_000_000)) {
                    Log.e(TAG, "Failed to initialize video encoder")
                    return false
                }
            }

            if (horizontalOutputFile != null && horizontalFrameRenderer != null) {
                if (setupHorizontalVideoEncoder(1280, 720, 5_000_000)) {
                    horizMediaMuxer = MediaMuxer(
                        horizontalOutputFile.absolutePath,
                        MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
                    )
                }
            }

            audioActive = if (enableAudio) setupAudio() else false

            mediaMuxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            startNanoTime = System.nanoTime()
            lastVideoPtsUs = 0L
            lastHorizVideoPtsUs = 0L
            lastAudioPtsUs = 0L

            if (audioActive) {
                startAudioLoop()
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing encoders on recorder thread", e)
            false
        }
    }

    private fun setupVideoEncoder(width: Int, height: Int, bitrate: Int): Boolean {
        return try {
            val format = MediaFormat.createVideoFormat(VIDEO_MIME, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            val encoder = MediaCodec.createEncoderByType(VIDEO_MIME)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = encoder.createInputSurface()
            encoder.start()

            videoWidth = width
            videoHeight = height
            videoEncoder = encoder
            inputSurface = surface
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to configure video encoder ${width}x${height}: ${e.message}")
            try {
                videoEncoder?.release()
            } catch (_: Exception) {}
            videoEncoder = null
            inputSurface = null
            false
        }
    }

    private fun setupHorizontalVideoEncoder(width: Int, height: Int, bitrate: Int): Boolean {
        return try {
            val format = MediaFormat.createVideoFormat(VIDEO_MIME, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            val encoder = MediaCodec.createEncoderByType(VIDEO_MIME)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = encoder.createInputSurface()
            encoder.start()

            horizWidth = width
            horizHeight = height
            horizVideoEncoder = encoder
            horizInputSurface = surface
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to configure horizontal encoder: ${e.message}")
            try {
                horizVideoEncoder?.release()
            } catch (_: Exception) {}
            horizVideoEncoder = null
            horizInputSurface = null
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun setupAudio(): Boolean {
        return try {
            val minBufferSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBufferSize <= 0) return false

            val bufferSize = maxOf(minBufferSize * 2, 8192)
            val record = AudioRecord(
                MediaRecorder.AudioSource.CAMCORDER,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                return false
            }

            val audioFormat = MediaFormat.createAudioFormat(AUDIO_MIME, SAMPLE_RATE, 1).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BITRATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }
            val encoder = MediaCodec.createEncoderByType(AUDIO_MIME)
            encoder.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            record.startRecording()

            audioRecord = record
            audioEncoder = encoder
            true
        } catch (e: Exception) {
            Log.w(TAG, "Audio setup failed, falling back to video-only: ${e.message}")
            try {
                audioRecord?.release()
            } catch (_: Exception) {}
            try {
                audioEncoder?.release()
            } catch (_: Exception) {}
            audioRecord = null
            audioEncoder = null
            false
        }
    }

    private val frameLoopRunnable = object : Runnable {
        override fun run() {
            if (!isRecording.get()) return
            val frameStartMs = System.currentTimeMillis()
            try {
                renderAndDrainVideoFrame()
            } catch (e: Exception) {
                Log.w(TAG, "Error rendering video frame: ${e.message}")
            }
            if (isRecording.get()) {
                val elapsedMs = System.currentTimeMillis() - frameStartMs
                val delayMs = (33L - elapsedMs).coerceAtLeast(5L)
                videoHandler?.postDelayed(this, delayMs)
            }
        }
    }

    private fun renderAndDrainVideoFrame() {
        val surface = inputSurface ?: return
        if (framePrePass != null && !framePrePass.invoke()) {
            return
        }

        val canvas = try {
            surface.lockHardwareCanvas()
        } catch (_: Exception) {
            try {
                surface.lockCanvas(null)
            } catch (_: Exception) {
                null
            }
        } ?: return

        var rendered = false
        try {
            rendered = frameRenderer(canvas, videoWidth, videoHeight)
        } finally {
            try {
                surface.unlockCanvasAndPost(canvas)
            } catch (_: Exception) {}
        }

        if (rendered) {
            drainVideoEncoder(endOfStream = false)
        }

        val hSurface = horizInputSurface
        val hRenderer = horizontalFrameRenderer
        if (hSurface != null && hRenderer != null) {
            val hCanvas = try {
                hSurface.lockHardwareCanvas()
            } catch (_: Exception) {
                try {
                    hSurface.lockCanvas(null)
                } catch (_: Exception) {
                    null
                }
            }
            if (hCanvas != null) {
                var hRendered = false
                try {
                    hRendered = hRenderer(hCanvas, horizWidth, horizHeight)
                } finally {
                    try {
                        hSurface.unlockCanvasAndPost(hCanvas)
                    } catch (_: Exception) {}
                }
                if (hRendered) {
                    drainHorizontalVideoEncoder(endOfStream = false)
                }
            }
        }
    }

    private fun startAudioLoop() {
        audioThread = Thread({
            try {
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            } catch (_: Exception) {}
            val record = audioRecord ?: return@Thread
            val encoder = audioEncoder ?: return@Thread
            val readBuffer = ByteArray(4096)

            try {
                while (isRecording.get()) {
                    val readBytes = record.read(readBuffer, 0, readBuffer.size)
                    if (readBytes > 0) {
                        val inputIndex = encoder.dequeueInputBuffer(10_000)
                        if (inputIndex >= 0) {
                            val inputBuffer = encoder.getInputBuffer(inputIndex)
                            if (inputBuffer != null) {
                                inputBuffer.clear()
                                val bytesToWrite = minOf(readBytes, inputBuffer.remaining())
                                inputBuffer.put(readBuffer, 0, bytesToWrite)
                                val ptsUs = getMonotonicPtsUs(streamType = 2)
                                encoder.queueInputBuffer(inputIndex, 0, bytesToWrite, ptsUs, 0)
                            }
                        }
                        drainAudioEncoder(endOfStream = false)
                    }
                }

                // Send EOS to audio encoder
                val inputIndex = encoder.dequeueInputBuffer(10_000)
                if (inputIndex >= 0) {
                    val ptsUs = getMonotonicPtsUs(streamType = 2)
                    encoder.queueInputBuffer(
                        inputIndex,
                        0,
                        0,
                        ptsUs,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                    )
                }
                drainAudioEncoder(endOfStream = true)
            } catch (e: Exception) {
                Log.w(TAG, "Audio loop error: ${e.message}")
            }
        }, "DualAudioRecorderThread").apply { start() }
    }

    private fun getMonotonicPtsUs(streamType: Int): Long {
        synchronized(muxerLock) {
            val rawUs = (System.nanoTime() - startNanoTime) / 1000L
            return when (streamType) {
                0 -> {
                    val pts = if (rawUs <= lastVideoPtsUs) lastVideoPtsUs + 1000L else rawUs
                    lastVideoPtsUs = pts
                    pts
                }
                1 -> {
                    val pts = if (rawUs <= lastHorizVideoPtsUs) lastHorizVideoPtsUs + 1000L else rawUs
                    lastHorizVideoPtsUs = pts
                    pts
                }
                else -> {
                    val pts = if (rawUs <= lastAudioPtsUs) lastAudioPtsUs + 1000L else rawUs
                    lastAudioPtsUs = pts
                    pts
                }
            }
        }
    }

    private fun drainVideoEncoder(endOfStream: Boolean) {
        val encoder = videoEncoder ?: return
        if (endOfStream) {
            try {
                encoder.signalEndOfInputStream()
            } catch (_: Exception) {}
        }

        val bufferInfo = MediaCodec.BufferInfo()
        var loops = 0
        while (loops < 60) {
            loops++
            val status = try {
                encoder.dequeueOutputBuffer(bufferInfo, if (endOfStream) 10_000L else 0L)
            } catch (_: Exception) {
                break
            }

            if (status == MediaCodec.INFO_TRY_AGAIN_LATER) {
                break
            } else if (status == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxerLock) {
                    if (!muxerStarted && videoTrackIndex < 0) {
                        videoTrackIndex = mediaMuxer?.addTrack(encoder.outputFormat) ?: -1
                        tryStartMuxersLocked()
                    }
                }
            } else if (status >= 0) {
                val encodedData = encoder.getOutputBuffer(status)
                if (encodedData != null && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && bufferInfo.size > 0) {
                    bufferInfo.presentationTimeUs = getMonotonicPtsUs(streamType = 0)
                    writeOrQueueVerticalSample(isVideo = true, encodedData, bufferInfo)
                }
                encoder.releaseOutputBuffer(status, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    break
                }
            }
        }
    }

    private fun drainHorizontalVideoEncoder(endOfStream: Boolean) {
        val encoder = horizVideoEncoder ?: return
        if (endOfStream) {
            try {
                encoder.signalEndOfInputStream()
            } catch (_: Exception) {}
        }

        val bufferInfo = MediaCodec.BufferInfo()
        var loops = 0
        while (loops < 60) {
            loops++
            val status = try {
                encoder.dequeueOutputBuffer(bufferInfo, if (endOfStream) 10_000L else 0L)
            } catch (_: Exception) {
                break
            }

            if (status == MediaCodec.INFO_TRY_AGAIN_LATER) {
                break
            } else if (status == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxerLock) {
                    if (!horizMuxerStarted && horizVideoTrackIndex < 0) {
                        horizVideoTrackIndex = horizMediaMuxer?.addTrack(encoder.outputFormat) ?: -1
                        tryStartMuxersLocked()
                    }
                }
            } else if (status >= 0) {
                val encodedData = encoder.getOutputBuffer(status)
                if (encodedData != null && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && bufferInfo.size > 0) {
                    bufferInfo.presentationTimeUs = getMonotonicPtsUs(streamType = 1)
                    writeOrQueueHorizontalSample(isVideo = true, encodedData, bufferInfo)
                }
                encoder.releaseOutputBuffer(status, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    break
                }
            }
        }
    }

    private fun drainAudioEncoder(endOfStream: Boolean) {
        val encoder = audioEncoder ?: return
        val bufferInfo = MediaCodec.BufferInfo()
        var loops = 0
        while (loops < 60) {
            loops++
            val status = try {
                encoder.dequeueOutputBuffer(bufferInfo, if (endOfStream) 10_000L else 0L)
            } catch (_: Exception) {
                break
            }

            if (status == MediaCodec.INFO_TRY_AGAIN_LATER) {
                break
            } else if (status == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxerLock) {
                    cachedAudioOutputFormat = encoder.outputFormat
                    if (!muxerStarted && audioTrackIndex < 0) {
                        audioTrackIndex = mediaMuxer?.addTrack(encoder.outputFormat) ?: -1
                    }
                    if (!horizMuxerStarted && horizAudioTrackIndex < 0 && horizMediaMuxer != null) {
                        horizAudioTrackIndex = horizMediaMuxer?.addTrack(encoder.outputFormat) ?: -1
                    }
                    tryStartMuxersLocked()
                }
            } else if (status >= 0) {
                val encodedData = encoder.getOutputBuffer(status)
                if (encodedData != null && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && bufferInfo.size > 0) {
                    writeOrQueueVerticalSample(isVideo = false, encodedData, bufferInfo)
                    if (horizMediaMuxer != null) {
                        writeOrQueueHorizontalSample(isVideo = false, encodedData, bufferInfo)
                    }
                }
                encoder.releaseOutputBuffer(status, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    break
                }
            }
        }
    }

    private fun tryStartMuxersLocked() {
        val elapsedMs = (System.nanoTime() - startNanoTime) / 1_000_000L

        if (audioActive && audioTrackIndex < 0 && elapsedMs > 500L) {
            audioActive = false
        }

        if (!muxerStarted) {
            val muxer = mediaMuxer
            if (muxer != null && videoTrackIndex >= 0 && (!audioActive || audioTrackIndex >= 0)) {
                muxer.start()
                muxerStarted = true

                val info = MediaCodec.BufferInfo()
                for (sample in pendingSamples) {
                    val track = if (sample.isVideo) videoTrackIndex else audioTrackIndex
                    if (track >= 0) {
                        info.set(0, sample.data.remaining(), sample.presentationTimeUs, sample.flags)
                        muxer.writeSampleData(track, sample.data, info)
                    }
                }
                pendingSamples.clear()
            }
        }

        if (!horizMuxerStarted && horizMediaMuxer != null) {
            val hMuxer = horizMediaMuxer
            if (horizAudioTrackIndex < 0 && cachedAudioOutputFormat != null) {
                horizAudioTrackIndex = hMuxer?.addTrack(cachedAudioOutputFormat!!) ?: -1
            }
            if (hMuxer != null && horizVideoTrackIndex >= 0 && (!audioActive || horizAudioTrackIndex >= 0)) {
                hMuxer.start()
                horizMuxerStarted = true

                val info = MediaCodec.BufferInfo()
                for (sample in horizPendingSamples) {
                    val track = if (sample.isVideo) horizVideoTrackIndex else horizAudioTrackIndex
                    if (track >= 0) {
                        info.set(0, sample.data.remaining(), sample.presentationTimeUs, sample.flags)
                        hMuxer.writeSampleData(track, sample.data, info)
                    }
                }
                horizPendingSamples.clear()
            }
        }
    }

    private fun writeOrQueueVerticalSample(
        isVideo: Boolean,
        buffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        synchronized(muxerLock) {
            if (!muxerStarted) {
                tryStartMuxersLocked()
            }
            if (muxerStarted) {
                val track = if (isVideo) videoTrackIndex else audioTrackIndex
                if (track >= 0) {
                    buffer.position(bufferInfo.offset)
                    buffer.limit(bufferInfo.offset + bufferInfo.size)
                    try {
                        mediaMuxer?.writeSampleData(track, buffer, bufferInfo)
                    } catch (e: Exception) {
                        Log.w(TAG, "writeSampleData error: ${e.message}")
                    }
                }
            } else if (pendingSamples.size < 45) {
                buffer.position(bufferInfo.offset)
                buffer.limit(bufferInfo.offset + bufferInfo.size)
                val copy = ByteBuffer.allocateDirect(bufferInfo.size)
                copy.put(buffer)
                copy.flip()
                pendingSamples.add(
                    PendingSample(
                        isVideo = isVideo,
                        data = copy,
                        flags = bufferInfo.flags,
                        presentationTimeUs = bufferInfo.presentationTimeUs
                    )
                )
            }
        }
    }

    private fun writeOrQueueHorizontalSample(
        isVideo: Boolean,
        buffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo
    ) {
        synchronized(muxerLock) {
            if (!horizMuxerStarted) {
                tryStartMuxersLocked()
            }
            if (horizMuxerStarted) {
                val track = if (isVideo) horizVideoTrackIndex else horizAudioTrackIndex
                if (track >= 0) {
                    buffer.position(bufferInfo.offset)
                    buffer.limit(bufferInfo.offset + bufferInfo.size)
                    try {
                        horizMediaMuxer?.writeSampleData(track, buffer, bufferInfo)
                    } catch (e: Exception) {
                        Log.w(TAG, "horiz writeSampleData error: ${e.message}")
                    }
                }
            } else if (horizPendingSamples.size < 45) {
                buffer.position(bufferInfo.offset)
                buffer.limit(bufferInfo.offset + bufferInfo.size)
                val copy = ByteBuffer.allocateDirect(bufferInfo.size)
                copy.put(buffer)
                copy.flip()
                horizPendingSamples.add(
                    PendingSample(
                        isVideo = isVideo,
                        data = copy,
                        flags = bufferInfo.flags,
                        presentationTimeUs = bufferInfo.presentationTimeUs
                    )
                )
            }
        }
    }

    fun stop(callback: (Result<List<String>>) -> Unit) {
        if (!isRecording.getAndSet(false)) {
            val paths = collectValidOutputPaths()
            if (paths.isNotEmpty()) {
                mainHandler.post { callback(Result.success(paths)) }
            } else {
                mainHandler.post { callback(Result.failure(Exception("No active recording"))) }
            }
            return
        }

        val handler = videoHandler
        if (handler != null) {
            handler.removeCallbacksAndMessages(null)
            handler.post {
                finishAndRelease(callback)
            }
        } else {
            Thread { finishAndRelease(callback) }.start()
        }
    }

    private fun collectValidOutputPaths(): List<String> {
        val paths = mutableListOf<String>()
        if (outputFile.exists() && outputFile.length() > 0) {
            paths.add(outputFile.absolutePath)
        }
        if (horizontalOutputFile != null && horizontalOutputFile.exists() && horizontalOutputFile.length() > 0) {
            paths.add(horizontalOutputFile.absolutePath)
        }
        return paths
    }

    private fun finishAndRelease(callback: (Result<List<String>>) -> Unit) {
        try {
            try {
                audioThread?.join(1500)
            } catch (_: Exception) {}

            try {
                drainVideoEncoder(endOfStream = true)
            } catch (_: Exception) {}

            try {
                drainHorizontalVideoEncoder(endOfStream = true)
            } catch (_: Exception) {}

            releaseResources()

            try {
                videoThread?.quitSafely()
            } catch (_: Exception) {}
            videoThread = null
            videoHandler = null

            val paths = collectValidOutputPaths()
            if (paths.isNotEmpty()) {
                mainHandler.post {
                    callback(Result.success(paths))
                }
            } else {
                mainHandler.post {
                    callback(Result.failure(Exception("Recorded video file is empty")))
                }
            }
        } catch (e: Exception) {
            mainHandler.post {
                callback(Result.failure(e))
            }
        }
    }

    private fun releaseResources() {
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        try {
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null

        try {
            audioEncoder?.stop()
        } catch (_: Exception) {}
        try {
            audioEncoder?.release()
        } catch (_: Exception) {}
        audioEncoder = null

        try {
            videoEncoder?.stop()
        } catch (_: Exception) {}
        try {
            videoEncoder?.release()
        } catch (_: Exception) {}
        videoEncoder = null

        try {
            inputSurface?.release()
        } catch (_: Exception) {}
        inputSurface = null

        try {
            horizVideoEncoder?.stop()
        } catch (_: Exception) {}
        try {
            horizVideoEncoder?.release()
        } catch (_: Exception) {}
        horizVideoEncoder = null

        try {
            horizInputSurface?.release()
        } catch (_: Exception) {}
        horizInputSurface = null

        synchronized(muxerLock) {
            if (muxerStarted) {
                try {
                    mediaMuxer?.stop()
                } catch (_: Exception) {}
            }
            try {
                mediaMuxer?.release()
            } catch (_: Exception) {}
            mediaMuxer = null
            muxerStarted = false
            pendingSamples.clear()

            if (horizMuxerStarted) {
                try {
                    horizMediaMuxer?.stop()
                } catch (_: Exception) {}
            }
            try {
                horizMediaMuxer?.release()
            } catch (_: Exception) {}
            horizMediaMuxer = null
            horizMuxerStarted = false
            horizPendingSamples.clear()
        }
    }
}
