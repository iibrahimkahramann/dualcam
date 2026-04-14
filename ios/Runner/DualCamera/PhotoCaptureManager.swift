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
    
    func takePhoto(completion: @escaping (Result<[String], Error>) -> Void) {
        if isCapturing {
            completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already capturing"])))
            return
        }
        isCapturing = true
        captureCompletion = completion
    }
    
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isCapturing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let completion = captureCompletion else { return }
        isCapturing = false
        captureCompletion = nil
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 1. Process Vertical Image (Original 9:16)
        guard let verticalCG = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to render vertical"])))
            return
        }
        let verticalImage = UIImage(cgImage: verticalCG, scale: 1.0, orientation: .up) // AVCaptureVideoDataOutput typically yields landscape images rotated 90 deg. .right matches portrait.
        
        // 2. Process Horizontal (Crop to 16:9)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Wait, if it's portrait the width is 1080, height is 1920.
        // If the sampleBuffer natively comes as 1920x1080 (landscape left/right) 
        // we should crop accordingly. 
        // Let's rely on the output size.
        let hWidth = width
        let hHeight = Int(Double(width) * (9.0 / 16.0))
        let yOffset = (height - hHeight) / 2
        let cropRect = CGRect(x: 0, y: yOffset, width: hWidth, height: hHeight)
        let croppedCI = ciImage.cropped(to: cropRect)
        
        guard let horizontalCG = ciContext.createCGImage(croppedCI, from: croppedCI.extent) else {
             completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to render horizontal"])))
             return
        }
        let horizontalImage = UIImage(cgImage: horizontalCG, scale: 1.0, orientation: .up)
        
        saveImages(vertical: verticalImage, horizontal: horizontalImage, completion: completion)
    }
    
    private func saveImages(vertical: UIImage, horizontal: UIImage, completion: @escaping (Result<[String], Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            let isAuthorized: Bool
            if #available(iOS 14, *) {
                isAuthorized = (status == .authorized || status == .limited)
            } else {
                isAuthorized = (status == .authorized)
            }
            
            guard isAuthorized else {
                completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo Library access denied"])))
                return
            }
            
            var verticalId = ""
            var horizontalId = ""
            
            PHPhotoLibrary.shared().performChanges({
                let req1 = PHAssetChangeRequest.creationRequestForAsset(from: vertical)
                verticalId = req1.placeholderForCreatedAsset?.localIdentifier ?? ""
                
                let req2 = PHAssetChangeRequest.creationRequestForAsset(from: horizontal)
                horizontalId = req2.placeholderForCreatedAsset?.localIdentifier ?? ""
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(["Saved Vertical: \(verticalId)", "Saved Horizontal: \(horizontalId)"]))
                    } else if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.failure(NSError(domain: "Photo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error saving"])))
                    }
                }
            }
        }
    }
}
