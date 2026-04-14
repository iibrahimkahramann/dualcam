import Foundation
import AVFoundation
import CoreImage
import Photos

/// Manages dual video recording (Vertical 9:16 and Horizontal 16:9) simultaneously.
class DualVideoWriter {
    private var verticalWriter: AVAssetWriter?
    private var verticalVideoInput: AVAssetWriterInput?
    private var verticalAudioInput: AVAssetWriterInput?
    
    private var horizontalWriter: AVAssetWriter?
    private var horizontalVideoInput: AVAssetWriterInput?
    private var horizontalAudioInput: AVAssetWriterInput?
    
    private var verticalPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var horizontalPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false]) // GPU-accelerated
    private var pixelBufferPool: CVPixelBufferPool?
    
    // State
    private(set) var isRecording = false
    private var hasStartedWriting = false
    private let writerQueue = DispatchQueue(label: "com.two_camera.writerQueue")
    
    private var verticalUrl: URL
    private var horizontalUrl: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory
        verticalUrl = tempDir.appendingPathComponent("vertical_video_\(UUID().uuidString).mp4")
        horizontalUrl = tempDir.appendingPathComponent("horizontal_video_\(UUID().uuidString).mp4")
    }
    
    func prepare(width: Int = 1080, height: Int = 1920) throws {
        // Remove old files if they exist
        try? FileManager.default.removeItem(at: verticalUrl)
        try? FileManager.default.removeItem(at: horizontalUrl)
        
        // 1. Setup Vertical Writer (9:16) - e.g. 1080x1920
        verticalWriter = try AVAssetWriter(url: verticalUrl, fileType: .mp4)
        
        let vVideoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        verticalVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vVideoSettings)
        verticalVideoInput?.expectsMediaDataInRealTime = true
        
        // We use an adaptor since we have raw BGRA buffers
        let vSourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        verticalPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: verticalVideoInput!,
            sourcePixelBufferAttributes: vSourcePixelBufferAttributes
        )
        
        if verticalWriter!.canAdd(verticalVideoInput!) {
            verticalWriter!.add(verticalVideoInput!)
        }
        
        // Audio for Vertical
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
        
        // 2. Setup Horizontal Writer (16:9) - e.g. 1080x608 (if original is 1080x1920)
        let hWidth = width
        var hHeight = Int(Double(width) * (9.0 / 16.0))
        if hHeight % 2 != 0 { hHeight += 1 } // Ensure height is even for video encode
        
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
            kCVPixelBufferHeightKey as String: hHeight
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
        
        // Create PixelBufferPool for horizontal cropping
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, hSourcePixelBufferAttributes as CFDictionary, &pixelBufferPool)
        
        hasStartedWriting = false
    }
    
    func startRecording() {
        writerQueue.async {
            self.isRecording = true
        }
    }
    
    func writeVideo(sampleBuffer: CMSampleBuffer) {
        writerQueue.async {
            guard self.isRecording else { return }
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if !self.hasStartedWriting {
                self.verticalWriter?.startWriting()
                self.verticalWriter?.startSession(atSourceTime: timestamp)
                
                self.horizontalWriter?.startWriting()
                self.horizontalWriter?.startSession(atSourceTime: timestamp)
                
                self.hasStartedWriting = true
                print("[DualVideoWriter] startSession called with timestamp: \(timestamp.value)")
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            // 1. Write to Vertical (Original)
            if self.verticalVideoInput?.isReadyForMoreMediaData == true {
                self.verticalPixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
            }
            
            // 2. Write to Horizontal (Cropped)
            if self.horizontalVideoInput?.isReadyForMoreMediaData == true,
               let pool = self.pixelBufferPool {
                
                var croppedBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &croppedBuffer)
                
                if let croppedBuffer = croppedBuffer {
                    self.cropToHorizontal(input: pixelBuffer, output: croppedBuffer)
                    let success = self.horizontalPixelBufferAdaptor?.append(croppedBuffer, withPresentationTime: timestamp) ?? false
                    if !success {
                        print("[DualVideoWriter] Failed to append horizontal pixel buffer")
                    }
                } else {
                    print("[DualVideoWriter] CVPixelBufferPoolCreatePixelBuffer failed")
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
            
            if self.horizontalAudioInput?.isReadyForMoreMediaData == true {
                self.horizontalAudioInput?.append(sampleBuffer)
            }
        }
    }
    
    func stopRecording(completion: @escaping (Result<[String], Error>) -> Void) {
        print("[DualVideoWriter] stopRecording called from Flutter")
        writerQueue.async {
            print("[DualVideoWriter] stopRecording inside writerQueue")
            self.isRecording = false
            self.hasStartedWriting = false
            
            let group = DispatchGroup()
            var returnError: Error?
            
            print("[DualVideoWriter] checking verticalWriter status: \(String(describing: self.verticalWriter?.status.rawValue))")
            if let vWriter = self.verticalWriter, vWriter.status == .writing {
                print("[DualVideoWriter] marking vertical inputs as finished")
                self.verticalVideoInput?.markAsFinished()
                self.verticalAudioInput?.markAsFinished()
                group.enter()
                vWriter.finishWriting {
                    print("[DualVideoWriter] verticalWriter finishWriting block executed")
                    if let err = vWriter.error {
                        print("[DualVideoWriter] verticalWriter error: \(err)")
                        returnError = err
                    }
                    group.leave()
                }
            } else {
                print("[DualVideoWriter] verticalWriter not writing, status: \(String(describing: self.verticalWriter?.status.rawValue))")
                if let vWriter = self.verticalWriter, vWriter.status == .failed {
                    returnError = vWriter.error
                }
            }
            
            print("[DualVideoWriter] checking horizontalWriter status: \(String(describing: self.horizontalWriter?.status.rawValue))")
            if let hWriter = self.horizontalWriter, hWriter.status == .writing {
                print("[DualVideoWriter] marking horizontal inputs as finished")
                self.horizontalVideoInput?.markAsFinished()
                self.horizontalAudioInput?.markAsFinished()
                group.enter()
                hWriter.finishWriting {
                    print("[DualVideoWriter] horizontalWriter finishWriting block executed")
                    if let err = hWriter.error {
                        print("[DualVideoWriter] horizontalWriter error: \(err)")
                        returnError = err
                    }
                    group.leave()
                }
            } else {
                print("[DualVideoWriter] horizontalWriter not writing, status: \(String(describing: self.horizontalWriter?.status.rawValue))")
                if let hWriter = self.horizontalWriter, hWriter.status == .failed {
                    returnError = returnError ?? hWriter.error
                }
            }
            
            print("[DualVideoWriter] waiting on group.notify")
            group.notify(queue: .main) {
                print("[DualVideoWriter] group.notify fired")
                if let err = returnError {
                    print("[DualVideoWriter] completing with error: \(err)")
                    completion(.failure(err))
                } else {
                    print("[DualVideoWriter] requesting PhotoLibrary auth")
                    // Save to Photo Library
                    PHPhotoLibrary.requestAuthorization { status in
                        let isAuthorized: Bool
                        if #available(iOS 14, *) {
                            isAuthorized = (status == .authorized || status == .limited)
                        } else {
                            isAuthorized = (status == .authorized)
                        }
                        
                        guard isAuthorized else {
                            completion(.success([self.verticalUrl.path, self.horizontalUrl.path])) // Return paths even if it fails to save to gallery
                            return
                        }
                        
                        PHPhotoLibrary.shared().performChanges({
                            print("[DualVideoWriter] inserting assets to PhotoLibrary")
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.verticalUrl)
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.horizontalUrl)
                        }) { success, error in
                            DispatchQueue.main.async {
                                print("[DualVideoWriter] PhotoLibrary changes finished. Success: \(success), Error: \(String(describing: error))")
                                // Provide result. 
                                // To make sure flutter knows it succeeded or failed we can just return the local urls.
                                completion(.success([self.verticalUrl.path, self.horizontalUrl.path]))
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func cropToHorizontal(input: CVPixelBuffer, output: CVPixelBuffer) {
        let inputImage = CIImage(cvPixelBuffer: input)
        // inputImage is 1080x1920. We want 1080x607 centered.
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        let hWidth = width
        var hHeight = Int(Double(width) * (9.0 / 16.0))
        if hHeight % 2 != 0 { hHeight += 1 }
        
        let yOffset = (height - hHeight) / 2
        
        let cropRect = CGRect(x: 0, y: yOffset, width: hWidth, height: hHeight)
        let croppedImage = inputImage.cropped(to: cropRect)
        
        // Translate the cropped image down to origin (0,0)
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(-yOffset)))
        
        ciContext.render(translatedImage, to: output)
    }
}
