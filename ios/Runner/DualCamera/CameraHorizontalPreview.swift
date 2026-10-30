import Flutter
import UIKit
import AVFoundation

class CameraHorizontalPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private var cameraManager: DualCameraManager
    
    init(cameraManager: DualCameraManager) {
        self.cameraManager = cameraManager
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraHorizontalPreviewView(frame: frame, cameraManager: cameraManager)
    }
}

class CameraHorizontalPreviewView: NSObject, FlutterPlatformView {
    private let imageView: UIImageView
    private weak var cameraManager: DualCameraManager?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let renderLock = NSLock()
    private var isRenderingFrame = false
    
    init(frame: CGRect, cameraManager: DualCameraManager) {
        self.imageView = UIImageView(frame: frame)
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.cameraManager = cameraManager
        super.init()
        
        cameraManager.addPreviewObserver(self)
    }
    
    func view() -> UIView {
        return imageView
    }
    
    deinit {
        cameraManager?.removePreviewObserver(self)
    }
}

extension CameraHorizontalPreviewView: CameraHorizontalPreviewObserver {
    func didOutputCroppedFrame(_ pixelBuffer: CVPixelBuffer) {
        renderLock.lock()
        if isRenderingFrame {
            renderLock.unlock()
            return
        }
        isRenderingFrame = true
        renderLock.unlock()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            renderLock.lock()
            isRenderingFrame = false
            renderLock.unlock()
            return
        }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imageView.image = image
            self.renderLock.lock()
            self.isRenderingFrame = false
            self.renderLock.unlock()
        }
    }
}

class CameraFrontPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private var cameraManager: DualCameraManager
    
    init(cameraManager: DualCameraManager) {
        self.cameraManager = cameraManager
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraFrontPreviewView(frame: frame, cameraManager: cameraManager)
    }
}

class CameraFrontPreviewView: NSObject, FlutterPlatformView {
    private let imageView: UIImageView
    private weak var cameraManager: DualCameraManager?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let renderLock = NSLock()
    private var isRenderingFrame = false
    
    init(frame: CGRect, cameraManager: DualCameraManager) {
        self.imageView = UIImageView(frame: frame)
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.cameraManager = cameraManager
        super.init()
        
        cameraManager.addFrontPreviewObserver(self)
    }
    
    func view() -> UIView {
        return imageView
    }
    
    deinit {
        cameraManager?.removeFrontPreviewObserver(self)
    }
}

extension CameraFrontPreviewView: CameraFrontPreviewObserver {
    func didOutputFrontFrame(_ pixelBuffer: CVPixelBuffer) {
        renderLock.lock()
        if isRenderingFrame {
            renderLock.unlock()
            return
        }
        isRenderingFrame = true
        renderLock.unlock()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            renderLock.lock()
            isRenderingFrame = false
            renderLock.unlock()
            return
        }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imageView.image = image
            self.renderLock.lock()
            self.isRenderingFrame = false
            self.renderLock.unlock()
        }
    }
}
