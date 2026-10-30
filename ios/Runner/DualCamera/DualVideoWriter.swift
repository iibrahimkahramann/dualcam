import Foundation
import AVFoundation
import CoreImage
import Photos

class DualVideoWriter {
    private var verticalWriter: AVAssetWriter?
    private var verticalVideoInput: AVAssetWriterInput?
    private var verticalAudioInput: AVAssetWriterInput?
    
    private var horizontalWriter: AVAssetWriter?
    private var horizontalVideoInput: AVAssetWriterInput?
    private var horizontalAudioInput: AVAssetWriterInput?
    
    private var verticalPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var horizontalPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])
    private var pixelBufferPool: CVPixelBufferPool?
    private var compositeBufferPool: CVPixelBufferPool?
    
    private(set) var isRecording = false
    private var hasStartedWriting = false
    private let writerQueue = DispatchQueue(label: "com.two_camera.writerQueue", qos: .userInitiated)
    private let frameGuardLock = NSLock()
    private var isProcessingVideoFrame = false
    
    private var verticalUrl: URL
    private var horizontalUrl: URL
    
    private var latestFrontPixelBuffer: CVPixelBuffer?
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory
        verticalUrl = tempDir.appendingPathComponent("vertical_video_\(UUID().uuidString).mp4")
        horizontalUrl = tempDir.appendingPathComponent("horizontal_video_\(UUID().uuidString).mp4")
    }
    
    func prepare(width: Int = 1080, height: Int = 1920) throws {
        writerQueue.async {
            try? self.prepareOnQueue(width: width, height: height)
        }
    }

    private func prepareOnQueue(width: Int = 1080, height: Int = 1920) throws {
        if verticalWriter?.status == .writing {
            verticalWriter?.cancelWriting()
        }
        if horizontalWriter?.status == .writing {
            horizontalWriter?.cancelWriting()
        }
        verticalWriter = nil
        horizontalWriter = nil
        compositeBufferPool = nil
        pixelBufferPool = nil

        let tempDir = FileManager.default.temporaryDirectory
        verticalUrl = tempDir.appendingPathComponent("vertical_video_\(UUID().uuidString).mp4")
        horizontalUrl = tempDir.appendingPathComponent("horizontal_video_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: verticalUrl)
        try? FileManager.default.removeItem(at: horizontalUrl)
        
        verticalWriter = try AVAssetWriter(url: verticalUrl, fileType: .mp4)
        
        let vVideoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        verticalVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vVideoSettings)
        verticalVideoInput?.expectsMediaDataInRealTime = true
        
        let vSourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        verticalPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: verticalVideoInput!,
            sourcePixelBufferAttributes: vSourcePixelBufferAttributes
        )
        
        if verticalWriter!.canAdd(verticalVideoInput!) {
            verticalWriter!.add(verticalVideoInput!)
        }
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000
        ]
        verticalAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        verticalAudioInput?.expectsMediaDataInRealTime = true
        if verticalWriter!.canAdd(verticalAudioInput!) {
            verticalWriter!.add(verticalAudioInput!)
        }
        
        let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
        let isWideAngle = DualCameraManager.shared.isWideAngleModeEnabled
        
        if isDualCam {
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, vSourcePixelBufferAttributes as CFDictionary, &compositeBufferPool)
        } else if isWideAngle {
            let hWidth = width
            var hHeight = Int(Double(width) * (9.0 / 16.0))
            if hHeight % 2 != 0 { hHeight += 1 }
            
            horizontalWriter = try AVAssetWriter(url: horizontalUrl, fileType: .mp4)
            let hVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: hWidth,
                AVVideoHeightKey: hHeight
            ]
            horizontalVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: hVideoSettings)
            horizontalVideoInput?.expectsMediaDataInRealTime = true
            
            let hSourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: hWidth,
                kCVPixelBufferHeightKey as String: hHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            horizontalPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: horizontalVideoInput!,
                sourcePixelBufferAttributes: hSourcePixelBufferAttributes
            )
            if horizontalWriter!.canAdd(horizontalVideoInput!) {
                horizontalWriter!.add(horizontalVideoInput!)
            }
            
            horizontalAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            horizontalAudioInput?.expectsMediaDataInRealTime = true
            if horizontalWriter!.canAdd(horizontalAudioInput!) {
                horizontalWriter!.add(horizontalAudioInput!)
            }
            
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, hSourcePixelBufferAttributes as CFDictionary, &pixelBufferPool)
        }
        
        // Pre-start AVAssetWriter so hardware VideoToolbox H.264 encoder and IOSurface pools
        // are initialized BEFORE the user taps Record (eliminates first-frame recording stutter).
        verticalWriter?.startWriting()
        if !isDualCam && isWideAngle {
            horizontalWriter?.startWriting()
        }

        // Pre-warm CIContext Metal shaders and pixel buffer pool
        if let pool = verticalPixelBufferAdaptor?.pixelBufferPool ?? compositeBufferPool {
            var warmupBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &warmupBuffer)
            if let warmupBuffer = warmupBuffer {
                let dummy = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
                ciContext.render(dummy, to: warmupBuffer)
            }
        }
        
        hasStartedWriting = false
    }
    
    func startRecording() {
        writerQueue.async {
            self.hasStartedWriting = false
            self.isRecording = true
        }
    }

    func cacheSecondaryFrameIfNeeded(sampleBuffer: CMSampleBuffer, from position: AVCaptureDevice.Position) {
        let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
        guard isDualCam, position != DualCameraManager.shared.currentCameraPosition else { return }
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
            writerQueue.async {
                self.latestFrontPixelBuffer = pb
            }
        }
    }
    
    func writeVideo(sampleBuffer: CMSampleBuffer, from position: AVCaptureDevice.Position) {
        let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
        if isDualCam && position != DualCameraManager.shared.currentCameraPosition {
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                writerQueue.async {
                    self.latestFrontPixelBuffer = pb
                }
            }
            return
        }

        // Avoid queueing multiple primary camera CMSampleBuffers on writerQueue, which would
        // starve AVCaptureVideoDataOutput's buffer pool and freeze the live preview.
        frameGuardLock.lock()
        if isProcessingVideoFrame {
            frameGuardLock.unlock()
            return
        }
        isProcessingVideoFrame = true
        frameGuardLock.unlock()

        writerQueue.async {
            defer {
                self.frameGuardLock.lock()
                self.isProcessingVideoFrame = false
                self.frameGuardLock.unlock()
            }
            guard self.isRecording else { return }
            
            let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
            let isWideAngle = DualCameraManager.shared.isWideAngleModeEnabled
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if isDualCam {
                if position != DualCameraManager.shared.currentCameraPosition {
                    if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        self.latestFrontPixelBuffer = pb
                    }
                    return
                }
                
                if !self.hasStartedWriting {
                    if self.verticalWriter?.status == .unknown {
                        self.verticalWriter?.startWriting()
                    }
                    self.verticalWriter?.startSession(atSourceTime: timestamp)
                    self.hasStartedWriting = true
                }
                
                guard let backPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                var finalBufferToAppend = backPixelBuffer
                let activePool = self.verticalPixelBufferAdaptor?.pixelBufferPool ?? self.compositeBufferPool
                if let frontPixelBuffer = self.latestFrontPixelBuffer, let pool = activePool {
                    var compositeBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &compositeBuffer)
                    if let compositeBuffer = compositeBuffer {
                        self.compositePiP(back: backPixelBuffer, front: frontPixelBuffer, output: compositeBuffer)
                        finalBufferToAppend = compositeBuffer
                    }
                }
                
                if self.verticalVideoInput?.isReadyForMoreMediaData == true {
                    self.verticalPixelBufferAdaptor?.append(finalBufferToAppend, withPresentationTime: timestamp)
                }
            } else {
                if position != DualCameraManager.shared.currentCameraPosition {
                    return
                }
                
                if !self.hasStartedWriting {
                    if self.verticalWriter?.status == .unknown {
                        self.verticalWriter?.startWriting()
                    }
                    self.verticalWriter?.startSession(atSourceTime: timestamp)
                    
                    if isWideAngle {
                        if self.horizontalWriter?.status == .unknown {
                            self.horizontalWriter?.startWriting()
                        }
                        self.horizontalWriter?.startSession(atSourceTime: timestamp)
                    }
                    
                    self.hasStartedWriting = true
                }
                
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                
                if self.verticalVideoInput?.isReadyForMoreMediaData == true {
                    self.verticalVideoInput?.append(sampleBuffer)
                }
                
                if isWideAngle {
                    if self.horizontalVideoInput?.isReadyForMoreMediaData == true, let pool = self.pixelBufferPool {
                        var croppedBuffer: CVPixelBuffer?
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &croppedBuffer)
                        if let croppedBuffer = croppedBuffer {
                            self.cropToHorizontal(input: pixelBuffer, output: croppedBuffer)
                            self.horizontalPixelBufferAdaptor?.append(croppedBuffer, withPresentationTime: timestamp)
                        }
                    }
                }
            }
        }
    }
    
    func writeAudio(sampleBuffer: CMSampleBuffer) {
        writerQueue.async {
            guard self.isRecording, self.hasStartedWriting else { return }
            
            if self.verticalAudioInput?.isReadyForMoreMediaData == true {
                self.verticalAudioInput?.append(sampleBuffer)
            }
            
            let isWideAngle = DualCameraManager.shared.isWideAngleModeEnabled
            
            if isWideAngle {
                if self.horizontalAudioInput?.isReadyForMoreMediaData == true {
                    self.horizontalAudioInput?.append(sampleBuffer)
                }
            }
        }
    }
    
    func stopRecording(completion: @escaping (Result<[String], Error>) -> Void) {
        writerQueue.async {
            self.isRecording = false
            self.hasStartedWriting = false
            
            let group = DispatchGroup()
            var returnError: Error?
            
            if let vWriter = self.verticalWriter, vWriter.status == .writing {
                self.verticalVideoInput?.markAsFinished()
                self.verticalAudioInput?.markAsFinished()
                group.enter()
                vWriter.finishWriting {
                    if let err = vWriter.error { returnError = err }
                    group.leave()
                }
            }
            
            let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
            let isWideAngle = DualCameraManager.shared.isWideAngleModeEnabled
            
            if !isDualCam && isWideAngle {
                if let hWriter = self.horizontalWriter, hWriter.status == .writing {
                    self.horizontalVideoInput?.markAsFinished()
                    self.horizontalAudioInput?.markAsFinished()
                    group.enter()
                    hWriter.finishWriting {
                        if let err = hWriter.error { returnError = err }
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                if let err = returnError {
                    completion(.failure(err))
                } else {
                    var urls = [self.verticalUrl.path]
                    if !isDualCam && isWideAngle {
                        if FileManager.default.fileExists(atPath: self.horizontalUrl.path) {
                            urls.append(self.horizontalUrl.path)
                        }
                    }
                    completion(.success(urls))
                }
            }
        }
    }
    
    private func compositePiP(back: CVPixelBuffer, front: CVPixelBuffer, output: CVPixelBuffer) {
        let backImage = CIImage(cvPixelBuffer: back)
        let frontImage = CIImage(cvPixelBuffer: front)
        
        let width = CVPixelBufferGetWidth(back)
        let height = CVPixelBufferGetHeight(back)
        
        let pipWidth = CGFloat(width) * 0.3
        let pipHeight = CGFloat(height) * 0.3
        
        let scaleX = pipWidth / CGFloat(CVPixelBufferGetWidth(front))
        let scaleY = pipHeight / CGFloat(CVPixelBufferGetHeight(front))
        
        let padding: CGFloat = 40
        let corner = DualCameraManager.shared.pipCornerIndex
        let tx: CGFloat = (corner == 0 || corner == 2) ? padding : (CGFloat(width) - pipWidth - padding)
        let ty: CGFloat = (corner == 2 || corner == 3) ? padding : (CGFloat(height) - pipHeight - padding)
        
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
            
        let scaledFront = frontImage.transformed(by: transform)
        let composited = scaledFront.composited(over: backImage)
        
        ciContext.render(composited, to: output)
    }
    
    private func cropToHorizontal(input: CVPixelBuffer, output: CVPixelBuffer) {
        let inputImage = CIImage(cvPixelBuffer: input)
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        let hWidth = width
        var hHeight = Int(Double(width) * (9.0 / 16.0))
        if hHeight % 2 != 0 { hHeight += 1 }
        
        let yOffset = (height - hHeight) / 2
        let cropRect = CGRect(x: 0, y: yOffset, width: hWidth, height: hHeight)
        let croppedImage = inputImage.cropped(to: cropRect)
        
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(-yOffset)))
        ciContext.render(translatedImage, to: output)
    }
}
