import Foundation
import AVFoundation
import CoreImage
import Photos
import UIKit

class PhotoCaptureManager {
    static let shared = PhotoCaptureManager()
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isCapturing = false
    private var captureCompletion: ((Result<[String], Error>) -> Void)?
    
    private var latestFrontPixelBuffer: CVPixelBuffer?
    
    func takePhoto(completion: @escaping (Result<[String], Error>) -> Void) {
        if isCapturing {
            completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already capturing"])))
            return
        }
        isCapturing = true
        captureCompletion = completion
    }
    
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer, from position: AVCaptureDevice.Position) {
        let isDualCam = AVCaptureMultiCamSession.isMultiCamSupported && DualCameraManager.shared.isDualCamModeEnabled
        let isWideAngle = DualCameraManager.shared.isWideAngleModeEnabled
        
        if isDualCam {
            if position != DualCameraManager.shared.currentCameraPosition {
                if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    latestFrontPixelBuffer = pb
                }
                return
            }
            
            guard isCapturing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let completion = captureCompletion else { return }
            isCapturing = false
            captureCompletion = nil
            
            let backCI = CIImage(cvPixelBuffer: pixelBuffer)
            
            var frontCI: CIImage?
            if let frontPB = latestFrontPixelBuffer {
                frontCI = CIImage(cvPixelBuffer: frontPB)
            }
            
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
            var finalCI = backCI
            
            if let frontCI = frontCI {
                let pipWidth = CGFloat(width) * 0.3
                let pipHeight = CGFloat(height) * 0.3
                
                let scaleX = pipWidth / frontCI.extent.width
                let scaleY = pipHeight / frontCI.extent.height
                
                let padding: CGFloat = 40
                let tx = CGFloat(width) - pipWidth - padding
                let ty = CGFloat(height) - pipHeight - padding
                
                let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))
                    
                let scaledFront = frontCI.transformed(by: transform)
                finalCI = scaledFront.composited(over: backCI)
            }
            
            guard let finalCG = ciContext.createCGImage(finalCI, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
                completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to render composited photo"])))
                return
            }
            let finalImage = UIImage(cgImage: finalCG, scale: 1.0, orientation: .up)
            saveImages(vertical: finalImage, horizontal: nil, completion: completion)
            
        } else {
            if position != DualCameraManager.shared.currentCameraPosition {
                return
            }
            
            guard isCapturing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let completion = captureCompletion else { return }
            isCapturing = false
            captureCompletion = nil
            
            let backCI = CIImage(cvPixelBuffer: pixelBuffer)
            
            guard let verticalCG = ciContext.createCGImage(backCI, from: backCI.extent) else {
                completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to render vertical"])))
                return
            }
            let verticalImage = UIImage(cgImage: verticalCG, scale: 1.0, orientation: .up)
            
            var horizontalImage: UIImage? = nil
            
            if isWideAngle {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                
                let hWidth = width
                var hHeight = Int(Double(width) * (9.0 / 16.0))
                if hHeight % 2 != 0 { hHeight += 1 }
                
                let yOffset = (height - hHeight) / 2
                let cropRect = CGRect(x: 0, y: yOffset, width: hWidth, height: hHeight)
                let croppedCI = backCI.cropped(to: cropRect)
                
                if let horizontalCG = ciContext.createCGImage(croppedCI, from: croppedCI.extent) {
                    horizontalImage = UIImage(cgImage: horizontalCG, scale: 1.0, orientation: .up)
                }
            }
            
            saveImages(vertical: verticalImage, horizontal: horizontalImage, completion: completion)
        }
    }
    
    private func saveImages(vertical: UIImage, horizontal: UIImage?, completion: @escaping (Result<[String], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var urls: [String] = []
            do {
                if let data = vertical.jpegData(compressionQuality: 0.95) {
                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photo_\(UUID().uuidString).jpg")
                    try data.write(to: tempUrl)
                    urls.append(tempUrl.path)
                }
                
                if let horizontal = horizontal, let data = horizontal.jpegData(compressionQuality: 0.95) {
                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photo_\(UUID().uuidString)_horiz.jpg")
                    try data.write(to: tempUrl)
                    urls.append(tempUrl.path)
                }
                
                DispatchQueue.main.async {
                    completion(.success(urls))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
