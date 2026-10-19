package com.dual.camera.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class CameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var cameraManager: DualCameraManager? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var platformViewsRegistered = false

    private var pendingPermissionCallback: ((Boolean) -> Unit)? = null
    private val PERMISSION_REQUEST_CODE = 9911

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, "com.two_camera/channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        val act = binding.activity
        if (act is androidx.lifecycle.LifecycleOwner) {
            if (cameraManager == null) {
                cameraManager = DualCameraManager(act, act)
            }
            if (!platformViewsRegistered) {
                flutterPluginBinding?.let {
                    registerPlatformViews(it, cameraManager!!)
                    platformViewsRegistered = true
                }
            }
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        cameraManager?.stop()
        cameraManager = null
    }

    private fun registerPlatformViews(binding: FlutterPlugin.FlutterPluginBinding, manager: DualCameraManager) {
        val registry = binding.platformViewRegistry
        registry.registerViewFactory("two_camera/preview", CameraPreviewFactory(manager))
        registry.registerViewFactory("two_camera/horizontal_preview", CameraHorizontalPreviewFactory(manager))
        registry.registerViewFactory("two_camera/front_preview", CameraFrontPreviewFactory(manager))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val act = activity
            if (act != null) {
                val cameraGranted = ContextCompat.checkSelfPermission(
                    act,
                    Manifest.permission.CAMERA
                ) == PackageManager.PERMISSION_GRANTED
                pendingPermissionCallback?.invoke(cameraGranted)
            } else {
                pendingPermissionCallback?.invoke(false)
            }
            pendingPermissionCallback = null
            return true
        }
        return false
    }

    private fun ensurePermissions(callback: (Boolean) -> Unit) {
        val act = activity
        if (act == null) {
            callback(false)
            return
        }

        val cameraGranted = ContextCompat.checkSelfPermission(
            act,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        val audioGranted = ContextCompat.checkSelfPermission(
            act,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (cameraGranted) {
            if (!audioGranted) {
                // Request audio permission in background if not yet granted
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(Manifest.permission.RECORD_AUDIO),
                    PERMISSION_REQUEST_CODE + 1
                )
            }
            callback(true)
            return
        }

        pendingPermissionCallback = callback
        val permissionsToRequest = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        ActivityCompat.requestPermissions(act, permissionsToRequest, PERMISSION_REQUEST_CODE)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val manager = cameraManager
        if (manager == null) {
            result.error("NOT_INITIALIZED", "Camera manager is not initialized", null)
            return
        }

        when (call.method) {
            "initialize" -> {
                ensurePermissions { granted ->
                    if (granted) {
                        manager.initialize { success ->
                            if (success) {
                                result.success(true)
                            } else {
                                result.error("INIT_FAILED", "Failed to initialize camera", null)
                            }
                        }
                    } else {
                        result.error("NO_PERMISSION", "Camera permission denied", null)
                    }
                }
            }

            "isMultiCamSupported" -> {
                result.success(manager.isMultiCamSupported)
            }

            "startRecording" -> {
                if (manager.isRunning) {
                    manager.startRecording()
                    result.success(true)
                } else {
                    result.error("NOT_RUNNING", "Camera is not running", null)
                }
            }

            "stopRecording" -> {
                manager.stopRecording { res ->
                    res.onSuccess { paths ->
                        result.success(paths)
                    }.onFailure { err ->
                        result.error("STOP_FAILED", err.localizedMessage, null)
                    }
                }
            }

            "takePhoto" -> {
                manager.takePhoto { res ->
                    res.onSuccess { paths ->
                        result.success(paths)
                    }.onFailure { err ->
                        result.error("PHOTO_FAILED", err.localizedMessage, null)
                    }
                }
            }

            "dispose" -> {
                manager.stop()
                result.success(true)
            }

            "getAvailableResolutions" -> {
                result.success(manager.getAvailableResolutions())
            }

            "setDualCamModeEnabled" -> {
                val enabled = call.arguments as? Boolean ?: true
                manager.isDualCamModeEnabled = enabled
                manager.start()
                result.success(true)
            }

            "setWideAngleMode" -> {
                val enabled = call.arguments as? Boolean ?: false
                manager.setWideAngleMode(enabled)
                result.success(true)
            }

            "setResolution" -> {
                val width = call.argument<Int>("width") ?: 1080
                val height = call.argument<Int>("height") ?: 1920
                val fps = call.argument<Int>("fps") ?: 30
                manager.setResolution(width, height, fps)
                result.success(true)
            }

            "setHDR" -> {
                val enabled = call.arguments as? Boolean ?: false
                manager.setHDR(enabled)
                result.success(true)
            }

            "setExposure" -> {
                val bias = call.arguments as? Double ?: 0.0
                manager.setExposureBias(bias)
                result.success(true)
            }

            "setFocusPoint" -> {
                val x = call.argument<Double>("x") ?: 0.5
                val y = call.argument<Double>("y") ?: 0.5
                manager.setFocusPoint(x, y)
                result.success(true)
            }

            "getMinZoom" -> {
                result.success(manager.getMinZoom())
            }

            "getMaxZoom" -> {
                result.success(manager.getMaxZoom())
            }

            "setZoom" -> {
                val factor = call.arguments as? Double ?: 1.0
                manager.setZoom(factor)
                result.success(true)
            }

            "switchCamera" -> {
                manager.switchCamera { res ->
                    res.onSuccess { maxZoom ->
                        result.success(maxZoom)
                    }.onFailure { err ->
                        result.error("SWITCH_FAILED", err.localizedMessage, null)
                    }
                }
            }

            "toggleTorch" -> {
                val enabled = call.arguments as? Boolean ?: false
                manager.toggleTorch(enabled)
                result.success(true)
            }

            "getScreenBrightness" -> {
                val act = activity
                if (act != null) {
                    val lp = act.window.attributes
                    val brightness = if (lp.screenBrightness < 0) {
                        try {
                            Settings.System.getInt(act.contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
                        } catch (e: Exception) {
                            0.5
                        }
                    } else {
                        lp.screenBrightness.toDouble()
                    }
                    result.success(brightness)
                } else {
                    result.success(0.5)
                }
            }

            "setScreenBrightness" -> {
                val brightness = call.arguments as? Double ?: 1.0
                activity?.let { act ->
                    act.runOnUiThread {
                        val lp = act.window.attributes
                        lp.screenBrightness = brightness.toFloat().coerceIn(0.01f, 1.0f)
                        act.window.attributes = lp
                    }
                }
                result.success(true)
            }

            else -> {
                result.notImplemented()
            }
        }
    }
}
