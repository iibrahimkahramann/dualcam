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
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    init(frame: CGRect, cameraManager: DualCameraManager) {
        self.imageView = UIImageView(frame: frame)
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        super.init()
        
        // Listen to photo outputs or video outputs directly. 
        // We can use an observer pattern on DualCameraManager.
        cameraManager.addPreviewObserver(self)
    }
    
    func view() -> UIView {
        return imageView
    }
    
    deinit {
        // Assume manager cleans up or we remove observer
    }
}

extension CameraHorizontalPreviewView: CameraHorizontalPreviewObserver {
    func didOutputCroppedFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        
        DispatchQueue.main.async { [weak self] in
            self?.imageView.image = image
        }
    }
}
