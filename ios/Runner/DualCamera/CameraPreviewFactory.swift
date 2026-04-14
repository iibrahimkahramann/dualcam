import Flutter
import UIKit
import AVFoundation

class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private var cameraManager: DualCameraManager
    
    init(cameraManager: DualCameraManager) {
        self.cameraManager = cameraManager
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraPreviewView(frame: frame, cameraManager: cameraManager)
    }
}

class CameraPreviewView: NSObject, FlutterPlatformView {
    private let uiView: UIView
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    init(frame: CGRect, cameraManager: DualCameraManager) {
        let container = PreviewContainerView(frame: frame)
        self.uiView = container
        super.init()
        
        let session = cameraManager.captureSession
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        container.layer.addSublayer(layer)
        container.previewLayer = layer
        self.previewLayer = layer
    }
    
    func view() -> UIView {
        return uiView
    }

    // We need viewDidLayoutSubviews equivalent. For UIView, overidding layoutSubviews is better.
    // However, since we are just attaching a layer, we can make a custom UIView class.
}

class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

