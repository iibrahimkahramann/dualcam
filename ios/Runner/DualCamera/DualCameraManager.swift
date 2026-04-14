import Foundation
import AVFoundation

protocol DualCameraManagerDelegate: AnyObject {
    func didOutput(videoSampleBuffer: CMSampleBuffer)
    func didOutput(audioSampleBuffer: CMSampleBuffer)
    func cameraError(_ error: Error)
}

/// Manages AVCaptureSession and its outputs.
protocol CameraHorizontalPreviewObserver: AnyObject {
    func didOutputCroppedFrame(_ pixelBuffer: CVPixelBuffer)
}

class DualCameraManager: NSObject {
    weak var delegate: DualCameraManagerDelegate?
    private var previewObservers = [CameraHorizontalPreviewObserver]()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var pixelBufferPool: CVPixelBufferPool?
    
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.two_camera.sessionQueue")
    private let captureQueue = DispatchQueue(label: "com.two_camera.captureQueue", qos: .userInteractive)
    
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    var currentCameraPosition: AVCaptureDevice.Position = .back
    
    var activeDevice: AVCaptureDevice? {
        return (captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput)?.device
    }
    
    var currentCaptureWidth = 1080
    var currentCaptureHeight = 1920
    
    var isRunning: Bool {
        return captureSession.isRunning
    }
    
    override init() {
        super.init()
    }
    
    func checkPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            checkAudioPermissions(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.checkAudioPermissions(completion: completion)
                } else {
                    completion(false)
                }
            }
        default:
            completion(false)
        }
    }
    
    private func checkAudioPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }
    
    func start() {
        sessionQueue.async {
            self.configureSession()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    private func configureSession() {
        captureSession.beginConfiguration()
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high // Or .hd4K3840x2160 depending on requirements
        }
        // Setup Video Input
        let initialPosition = self.currentCameraPosition
        guard let camera = getCamera(with: initialPosition),
              let videoInput = try? AVCaptureDeviceInput(device: camera) else {
            notifyError(NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get camera input"]))
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // Setup Audio Input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        }
        
        // Setup Video Output
        let vOutput = AVCaptureVideoDataOutput()
        vOutput.setSampleBufferDelegate(self, queue: captureQueue)
        vOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        vOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(vOutput) {
            captureSession.addOutput(vOutput)
            self.videoOutput = vOutput
            
            if let connection = vOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait // Base recorded view is Portrait
                }
                if initialPosition == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }
        
        // Setup Audio Output
        let aOutput = AVCaptureAudioDataOutput()
        aOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if captureSession.canAddOutput(aOutput) {
            captureSession.addOutput(aOutput)
            self.audioOutput = aOutput
        }
        
        captureSession.commitConfiguration()
    }
    
    private func notifyError(_ error: Error) {
        DispatchQueue.main.async {
            self.delegate?.cameraError(error)
        }
    }
    
    // Helper to fetch camera device based on position
    private func getCamera(with position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return nil
    }
    
    // MARK: - Advanced Features
    
    func getAvailableResolutions() -> [[String: Any]] {
        guard let device = activeDevice ?? getCamera(with: currentCameraPosition) else { return [] }
        var resolutions: [[String: Any]] = []
        var uniqueKeys = Set<String>()
        
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            if width < 1280 { continue }
            
            for range in format.videoSupportedFrameRateRanges {
                let maxFPS = Int(range.maxFrameRate)
                if [24, 30, 60].contains(maxFPS) {
                    let key = "\(width)x\(height)@\(maxFPS)"
                    if !uniqueKeys.contains(key) {
                        uniqueKeys.insert(key)
                        let label: String
                        if width >= 3840 {
                            label = "4K • \(maxFPS)"
                        } else if width >= 1920 {
                            label = "HD • \(maxFPS)"
                        } else {
                            label = "720p • \(maxFPS)"
                        }
                        resolutions.append([
                            "width": width, 
                            "height": height, 
                            "fps": maxFPS,
                            "label": label
                        ])
                    }
                }
            }
        }
        
        return resolutions.sorted {
            let w0 = $0["width"] as? Int ?? 0
            let w1 = $1["width"] as? Int ?? 0
            if w0 != w1 { return w0 > w1 }
            let f0 = $0["fps"] as? Int ?? 0
            let f1 = $1["fps"] as? Int ?? 0
            return f0 > f1
        }
    }
    
    func setResolution(width: Int, height: Int, fps: Int) throws {
        guard let videoInput = captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else { return }
        let device = videoInput.device
        
        var bestFormat: AVCaptureDevice.Format?
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if Int(dimensions.width) == width && Int(dimensions.height) == height {
                for range in format.videoSupportedFrameRateRanges {
                    if Int(range.maxFrameRate) == fps {
                        bestFormat = format
                        break
                    }
                }
                if bestFormat != nil { break }
            }
        }
        
        if let format = bestFormat {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
            
            currentCaptureWidth = height
            currentCaptureHeight = width
        } else {
            throw NSError(domain: "CameraManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Resolution/FPS not supported"])
        }
    }
    
    func setHDR(enabled: Bool) throws {
        guard let device = activeDevice else { return }
        try device.lockForConfiguration()
        device.automaticallyAdjustsVideoHDREnabled = false
        if device.activeFormat.isVideoHDRSupported {
            device.isVideoHDREnabled = enabled
        }
        device.unlockForConfiguration()
    }
    
    func setExposureBias(bias: Float) throws {
        guard let device = activeDevice else { return }
        try device.lockForConfiguration()
        let actualBias = Swift.max(device.minExposureTargetBias, Swift.min(device.maxExposureTargetBias, bias))
        device.setExposureTargetBias(actualBias, completionHandler: nil)
        device.unlockForConfiguration()
    }
    
    func setFocusPoint(x: CGFloat, y: CGFloat) throws {
        guard let device = activeDevice else { return }
        try device.lockForConfiguration()
        let point = CGPoint(x: x, y: y)
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
        device.unlockForConfiguration()
    }
    
    // MARK: - Zoom Features
    
    func getMaxZoom() -> Double {
        guard let device = activeDevice else { return 1.0 }
        let maxZoom = device.activeFormat.videoMaxZoomFactor
        return min(Double(maxZoom), 5.0) // Caps maximum reasonable digital zoom before quality decays severely
    }
    
    func setZoom(factor: CGFloat) throws {
        guard let device = activeDevice else { return }
        
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
        let safeFactor = max(1.0, min(factor, maxZoom))
        
        try device.lockForConfiguration()
        device.videoZoomFactor = safeFactor
        device.unlockForConfiguration()
    }
    
    // MARK: - Toggle Features
    
    func switchCamera(completion: @escaping (Result<Double, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // Remove old input
            if let currentInput = self.captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            // Toggle position
            self.currentCameraPosition = (self.currentCameraPosition == .back) ? .front : .back
            
            // Re-add new input
            do {
                guard let newCamera = self.getCamera(with: self.currentCameraPosition) else {
                    throw NSError(domain: "Camera", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target camera not found"])
                }
                let newInput = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    
                    // Reset orientation and mirror front camera securely
                    if let connection = self.videoOutput?.connection(with: .video) {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                        if connection.isVideoMirroringSupported {
                            connection.isVideoMirrored = (self.currentCameraPosition == .front)
                        }
                    }
                    
                    self.captureSession.commitConfiguration()
                    
                    // Get new max zoom safely
                    let newMaxZoom = self.getMaxZoom()
                    DispatchQueue.main.async { completion(.success(newMaxZoom)) }
                } else {
                    throw NSError(domain: "Camera", code: 405, userInfo: [NSLocalizedDescriptionKey: "Could not add new camera input"])
                }
            } catch {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
    
    func toggleTorch(enabled: Bool) throws {
        guard let device = activeDevice else { return }
        if !device.hasTorch || !device.isTorchAvailable { return }
        
        try device.lockForConfiguration()
        if enabled {
            try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        } else {
            device.torchMode = .off
        }
        device.unlockForConfiguration()
    }
}

extension DualCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func addPreviewObserver(_ observer: CameraHorizontalPreviewObserver) {
        if !previewObservers.contains(where: { $0 === observer }) {
            previewObservers.append(observer)
        }
    }
    
    func removePreviewObserver(_ observer: CameraHorizontalPreviewObserver) {
        previewObservers.removeAll(where: { $0 === observer })
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            delegate?.didOutput(videoSampleBuffer: sampleBuffer)
            
            // Generate horizontal cropped buffer if anyone is observing
            if !previewObservers.isEmpty {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    processHorizontalPreview(pixelBuffer)
                }
            }
        } else if output == audioOutput {
            delegate?.didOutput(audioSampleBuffer: sampleBuffer)
        }
    }
    
    private func processHorizontalPreview(_ input: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        let originalHHeight = Int(Double(width) * (9.0 / 16.0))
        let yOffset = (height - originalHHeight) / 2
        
        // Target size for PiP (Higher resolution to prevent blurriness on larger UI)
        let pipWidth = 480
        let pipHeight = 270
        
        if pixelBufferPool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pipWidth,
                kCVPixelBufferHeightKey as String: pipHeight
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
        }
        
        guard let pool = pixelBufferPool else { return }
        var croppedBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &croppedBuffer)
        
        if let output = croppedBuffer {
            let inputImage = CIImage(cvPixelBuffer: input)
            let cropRect = CGRect(x: 0, y: yOffset, width: width, height: originalHHeight)
            let croppedImage = inputImage.cropped(to: cropRect)
            
            let scaleY = CGFloat(pipHeight) / CGFloat(originalHHeight)
            let scaleX = CGFloat(pipWidth) / CGFloat(width)
            
            let transformedImage = croppedImage
                .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(-yOffset)))
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            ciContext.render(transformedImage, to: output)
            
            for observer in previewObservers {
                observer.didOutputCroppedFrame(output)
            }
        }
    }
}
