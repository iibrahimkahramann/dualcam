import Foundation
import AVFoundation
import CoreImage

protocol DualCameraManagerDelegate: AnyObject {
    func didOutput(videoSampleBuffer: CMSampleBuffer, from position: AVCaptureDevice.Position)
    func didOutput(audioSampleBuffer: CMSampleBuffer)
    func cameraError(_ error: Error)
}

protocol CameraHorizontalPreviewObserver: AnyObject {
    func didOutputCroppedFrame(_ pixelBuffer: CVPixelBuffer)
}

protocol CameraFrontPreviewObserver: AnyObject {
    func didOutputFrontFrame(_ pixelBuffer: CVPixelBuffer)
}

class DualCameraManager: NSObject {
    
    weak var delegate: DualCameraManagerDelegate?
    private var previewObservers = [CameraHorizontalPreviewObserver]()
    private var frontPreviewObservers = [CameraFrontPreviewObserver]()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var pixelBufferPool: CVPixelBufferPool?
    
    let isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
    lazy var captureSession: AVCaptureSession = {
        if isMultiCamSupported {
            return AVCaptureMultiCamSession()
        } else {
            return AVCaptureSession()
        }
    }()
    
    private let sessionQueue = DispatchQueue(label: "com.two_camera.sessionQueue")
    private let captureQueue = DispatchQueue(label: "com.two_camera.captureQueue", qos: .userInteractive)
    
    private var backVideoOutput: AVCaptureVideoDataOutput?
    private var frontVideoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    static let shared = DualCameraManager()
    
    var currentCameraPosition: AVCaptureDevice.Position = .back
    
    var isDualCamModeEnabled: Bool = true
    var isWideAngleModeEnabled: Bool = false
    
    var activeDevice: AVCaptureDevice? {
        if isMultiCamSupported {
            return getCamera(with: currentCameraPosition)
        }
        return (captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput)?.device
    }
    
    var currentCaptureWidth = 1080
    var currentCaptureHeight = 1920
    var currentFPS = 30
    
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
        if !isMultiCamSupported, captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        if isMultiCamSupported {
            guard let backCamera = getCamera(with: .back),
                  let frontCamera = getCamera(with: .front),
                  let backInput = try? AVCaptureDeviceInput(device: backCamera),
                  let frontInput = try? AVCaptureDeviceInput(device: frontCamera) else {
                notifyError(NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get multi-camera inputs"]))
                return
            }
            
            if captureSession.canAddInput(backInput) {
                captureSession.addInput(backInput)
            }
            if captureSession.canAddInput(frontInput) {
                captureSession.addInput(frontInput)
            }
            
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
            
            let bOutput = AVCaptureVideoDataOutput()
            bOutput.setSampleBufferDelegate(self, queue: captureQueue)
            bOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            bOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(bOutput) {
                captureSession.addOutput(bOutput)
                self.backVideoOutput = bOutput
                if let conn = bOutput.connection(with: .video) {
                    if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                }
            }
            
            let fOutput = AVCaptureVideoDataOutput()
            fOutput.setSampleBufferDelegate(self, queue: captureQueue)
            fOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            fOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(fOutput) {
                captureSession.addOutput(fOutput)
                self.frontVideoOutput = fOutput
                if let conn = fOutput.connection(with: .video) {
                    if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                    if conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
                }
            }
            
            let aOutput = AVCaptureAudioDataOutput()
            aOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if captureSession.canAddOutput(aOutput) {
                captureSession.addOutput(aOutput)
                self.audioOutput = aOutput
            }
            
        } else {
            let initialPosition = self.currentCameraPosition
            guard let camera = getCamera(with: initialPosition),
                  let videoInput = try? AVCaptureDeviceInput(device: camera) else {
                notifyError(NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get camera input"]))
                return
            }
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
            
            let vOutput = AVCaptureVideoDataOutput()
            vOutput.setSampleBufferDelegate(self, queue: captureQueue)
            vOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            vOutput.alwaysDiscardsLateVideoFrames = true
            
            if captureSession.canAddOutput(vOutput) {
                captureSession.addOutput(vOutput)
                self.backVideoOutput = vOutput
                
                if let connection = vOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if initialPosition == .front && connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
            }
            
            let aOutput = AVCaptureAudioDataOutput()
            aOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if captureSession.canAddOutput(aOutput) {
                captureSession.addOutput(aOutput)
                self.audioOutput = aOutput
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    private func notifyError(_ error: Error) {
        DispatchQueue.main.async {
            self.delegate?.cameraError(error)
        }
    }
    
    private func getCamera(with position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if isMultiCamSupported {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        }
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return nil
    }
    
    func getAvailableResolutions() -> [[String: Any]] {
        guard let device = activeDevice else { return [] }
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
        if isMultiCamSupported {
            if let backCamera = getCamera(with: .back), let frontCamera = getCamera(with: .front) {
                try applyResolution(to: backCamera, width: width, height: height, fps: fps)
                try applyResolution(to: frontCamera, width: width, height: height, fps: fps)
            }
        } else {
            guard let videoInput = captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else { return }
            try applyResolution(to: videoInput.device, width: width, height: height, fps: fps)
        }
        currentCaptureWidth = height
        currentCaptureHeight = width
    }
    
    private func applyResolution(to device: AVCaptureDevice, width: Int, height: Int, fps: Int) throws {
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
    
    func getMinZoom() -> Double {
        guard let device = activeDevice else { return 1.0 }
        let minZoom = device.minAvailableVideoZoomFactor
        return Double(minZoom)
    }

    func getMaxZoom() -> Double {
        guard let device = activeDevice else { return 1.0 }
        let maxZoom = device.activeFormat.videoMaxZoomFactor
        return min(Double(maxZoom), 5.0)
    }
    
    func setZoom(factor: CGFloat) throws {
        guard let device = activeDevice else { return }
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
        let safeFactor = max(minZoom, min(factor, maxZoom))
        try device.lockForConfiguration()
        device.videoZoomFactor = safeFactor
        device.unlockForConfiguration()
    }
    
    func switchCamera(completion: @escaping (Result<Double, Error>) -> Void) {
        if isMultiCamSupported {
            self.currentCameraPosition = (self.currentCameraPosition == .back) ? .front : .back
            let newMaxZoom = self.getMaxZoom()
            DispatchQueue.main.async { completion(.success(newMaxZoom)) }
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            if let currentInput = self.captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            
            self.currentCameraPosition = (self.currentCameraPosition == .back) ? .front : .back
            
            do {
                guard let newCamera = self.getCamera(with: self.currentCameraPosition) else {
                    throw NSError(domain: "Camera", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target camera not found"])
                }
                let newInput = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    
                    if let connection = self.backVideoOutput?.connection(with: .video) {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                        if connection.isVideoMirroringSupported {
                            connection.isVideoMirrored = (self.currentCameraPosition == .front)
                        }
                    }
                    self.captureSession.commitConfiguration()
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

    func addFrontPreviewObserver(_ observer: CameraFrontPreviewObserver) {
        if !frontPreviewObservers.contains(where: { $0 === observer }) {
            frontPreviewObservers.append(observer)
        }
    }
    
    func removeFrontPreviewObserver(_ observer: CameraFrontPreviewObserver) {
        frontPreviewObservers.removeAll(where: { $0 === observer })
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == backVideoOutput {
            let pos: AVCaptureDevice.Position = isMultiCamSupported ? .back : .unspecified
            delegate?.didOutput(videoSampleBuffer: sampleBuffer, from: pos)
            
            if !previewObservers.isEmpty {
                if !isMultiCamSupported {
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        processHorizontalPreview(pixelBuffer)
                    }
                } else if isWideAngleModeEnabled && currentCameraPosition == .back {
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        processHorizontalPreview(pixelBuffer)
                    }
                }
            }
            
        } else if output == frontVideoOutput {
            delegate?.didOutput(videoSampleBuffer: sampleBuffer, from: .front)
            
            if !frontPreviewObservers.isEmpty {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    for observer in frontPreviewObservers {
                        observer.didOutputFrontFrame(pixelBuffer)
                    }
                }
            }
            
            if !previewObservers.isEmpty {
                if isDualCamModeEnabled {
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        for observer in previewObservers {
                            observer.didOutputCroppedFrame(pixelBuffer)
                        }
                    }
                } else if isWideAngleModeEnabled && currentCameraPosition == .front {
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        processHorizontalPreview(pixelBuffer)
                    }
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
