import AVFoundation
import UIKit
import Photos

class CameraManager: NSObject, ObservableObject {
    @Published var showDepth = false
    @Published var statusMessage: String?
    
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    private var currentDepthPixelBuffer: CVPixelBuffer?
    private var capturedPhotoData: Data?
    private var capturedDepthData: AVDepthData?
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupCamera()
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.statusMessage = "Camera access denied"
            }
        }
    }
    
    func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Try to find LiDAR camera first (Pro models)
        var device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
        
        // If no LiDAR, try TrueDepth front camera (all iPhones with Face ID)
        if device == nil {
            device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        }
        
        // If no depth camera at all, try dual camera
        if device == nil {
            device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
        }
        
        // Last resort: wide angle back camera
        if device == nil {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        
        guard let device = device else {
            statusMessage = "No compatible camera found"
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            }
            
            // Depth output
            if session.canAddOutput(depthDataOutput) {
                session.addOutput(depthDataOutput)
                depthDataOutput.isFilteringEnabled = false
            }
            
            // Video output for preview
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            }
            
            // Configure depth-photo connection
            if let connection = photoOutput.connection(with: .video) {
                if connection.isCameraIntrinsicMatrixDeliverySupported {
                    connection.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
            }
            
            session.commitConfiguration()
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
            
        } catch {
            statusMessage = "Camera setup failed: \(error.localizedDescription)"
            session.commitConfiguration()
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = true
        
        photoOutput.capturePhoto(with: settings, delegate: self)
        
        DispatchQueue.main.async {
            self.statusMessage = "Capturing..."
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.statusMessage = "Capture failed: \(error.localizedDescription)"
            }
            return
        }
        
        capturedPhotoData = photo.fileDataRepresentation()
        capturedDepthData = photo.depthData
        
        // Save both images
        saveImages()
    }
    
    func saveImages() {
        guard let photoData = capturedPhotoData,
              let depthData = capturedDepthData else {
            DispatchQueue.main.async {
                self.statusMessage = "Missing data"
            }
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.statusMessage = "Photos access denied"
                }
                return
            }
            
            // Save RGB image
            if let rgbImage = UIImage(data: photoData) {
                UIImageWriteToSavedPhotosAlbum(rgbImage, nil, nil, nil)
            }
            
            // Convert and save depth map
            let depthMap = depthData.depthDataMap
            if let depthImage = self.depthMapToGrayscaleImage(depthMap: depthMap) {
                UIImageWriteToSavedPhotosAlbum(depthImage, nil, nil, nil)
            }
            
            DispatchQueue.main.async {
                self.statusMessage = "✓ Saved RGB + Depth"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.statusMessage = nil
                }
            }
        }
    }
    
    func depthMapToGrayscaleImage(depthMap: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        let context = CIContext()
        
        // Normalize depth values to 0-1 range
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(1.0, forKey: kCIInputContrastKey)
        
        guard let outputImage = filter?.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Extract depth data for preview if available
        if output == depthDataOutput {
            // Get the pixel buffer from the sample buffer
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                currentDepthPixelBuffer = pixelBuffer
            }
        }
    }
}
