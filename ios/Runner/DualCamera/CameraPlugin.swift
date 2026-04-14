import Flutter
import UIKit
import AVFoundation

public class CameraPlugin: NSObject, FlutterPlugin, DualCameraManagerDelegate {
    
    private let channel: FlutterMethodChannel
    private let cameraManager: DualCameraManager
    private let videoWriter: DualVideoWriter
    
    public init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
        self.channel = channel
        self.cameraManager = DualCameraManager()
        self.videoWriter = DualVideoWriter()
        super.init()
        
        self.cameraManager.delegate = self
        
        let factory = CameraPreviewFactory(cameraManager: self.cameraManager)
        registrar.register(factory, withId: "two_camera/preview")
        
        let horizontalFactory = CameraHorizontalPreviewFactory(cameraManager: self.cameraManager)
        registrar.register(horizontalFactory, withId: "two_camera/horizontal_preview")
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.two_camera/channel", binaryMessenger: registrar.messenger())
        let instance = CameraPlugin(channel: channel, registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            cameraManager.checkPermissions { [weak self] granted in
                if granted {
                    self?.cameraManager.start()
                    do {
                        try self?.videoWriter.prepare(
                            width: self?.cameraManager.currentCaptureWidth ?? 1080,
                            height: self?.cameraManager.currentCaptureHeight ?? 1920
                        )
                        result(true)
                    } catch {
                        result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
                    }
                } else {
                    result(FlutterError(code: "NO_PERMISSION", message: "Camera or Microphone permission denied", details: nil))
                }
            }
            
        case "startRecording":
            if cameraManager.isRunning {
                videoWriter.startRecording()
                result(true)
            } else {
                result(FlutterError(code: "NOT_RUNNING", message: "Camera is not running", details: nil))
            }
            
        case "stopRecording":
            videoWriter.stopRecording { res in
                switch res {
                case .success(let paths):
                    result(paths) // Returns ["path/to/vertical", "path/to/horizontal"]
                    // Re-prepare for next recording instantly
                    try? self.videoWriter.prepare(
                        width: self.cameraManager.currentCaptureWidth,
                        height: self.cameraManager.currentCaptureHeight
                    )
                case .failure(let error):
                    result(FlutterError(code: "STOP_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "takePhoto":
            PhotoCaptureManager.shared.takePhoto { res in
                switch res {
                case .success(let paths):
                    result(paths)
                case .failure(let error):
                    result(FlutterError(code: "PHOTO_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "dispose":
            cameraManager.stop()
            result(true)
            
        case "getAvailableResolutions":
            let res = cameraManager.getAvailableResolutions()
            result(res)
            
        case "setResolution":
            if let args = call.arguments as? [String: Any],
               let width = args["width"] as? Int,
               let height = args["height"] as? Int,
               let fps = args["fps"] as? Int {
                do {
                    try cameraManager.setResolution(width: width, height: height, fps: fps)
                    // Must optionally re-prepare video writer with new size so it doesn't crash on start
                    try videoWriter.prepare(
                        width: cameraManager.currentCaptureWidth,
                        height: cameraManager.currentCaptureHeight
                    )
                    result(true)
                } catch {
                    result(FlutterError(code: "RES_FAILED", message: error.localizedDescription, details: nil))
                }
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Width, Height and FPS required", details: nil))
            }
            
        case "setHDR":
            if let enabled = call.arguments as? Bool {
                do {
                    try cameraManager.setHDR(enabled: enabled)
                    result(true)
                } catch {
                    result(FlutterError(code: "HDR_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "setExposure":
            if let bias = call.arguments as? Double {
                do {
                    try cameraManager.setExposureBias(bias: Float(bias))
                    result(true)
                } catch {
                    result(FlutterError(code: "EXP_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "setFocusPoint":
            if let args = call.arguments as? [String: Any],
               let x = args["x"] as? Double,
               let y = args["y"] as? Double {
                do {
                    try cameraManager.setFocusPoint(x: CGFloat(x), y: CGFloat(y))
                    result(true)
                } catch {
                    result(FlutterError(code: "FOCUS_FAILED", message: error.localizedDescription, details: nil))
                }
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "X and Y required", details: nil))
            }
            
        case "getMaxZoom":
            let maxZoom = cameraManager.getMaxZoom()
            result(maxZoom)
            
        case "setZoom":
            if let factor = call.arguments as? Double {
                do {
                    try cameraManager.setZoom(factor: CGFloat(factor))
                    result(true)
                } catch {
                    result(FlutterError(code: "ZOOM_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "switchCamera":
            cameraManager.switchCamera { res in
                switch res {
                case .success(let newMaxZoom):
                    result(newMaxZoom)
                case .failure(let error):
                    result(FlutterError(code: "SWITCH_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "toggleTorch":
            if let enabled = call.arguments as? Bool {
                do {
                    try cameraManager.toggleTorch(enabled: enabled)
                    result(true)
                } catch {
                    result(FlutterError(code: "TORCH_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            
        case "getScreenBrightness":
            DispatchQueue.main.async {
                result(Double(UIScreen.main.brightness))
            }
            
        case "setScreenBrightness":
            if let brightness = call.arguments as? Double {
                DispatchQueue.main.async {
                    UIScreen.main.brightness = CGFloat(brightness)
                    result(true)
                }
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - DualCameraManagerDelegate
    
    public func didOutput(videoSampleBuffer: CMSampleBuffer) {
        if videoWriter.isRecording {
            videoWriter.writeVideo(sampleBuffer: videoSampleBuffer)
        }
        PhotoCaptureManager.shared.processVideoFrame(videoSampleBuffer)
    }
    
    public func didOutput(audioSampleBuffer: CMSampleBuffer) {
        if videoWriter.isRecording {
            videoWriter.writeAudio(sampleBuffer: audioSampleBuffer)
        }
    }
    
    func cameraError(_ error: Error) {
        channel.invokeMethod("onError", arguments: error.localizedDescription)
    }
}
