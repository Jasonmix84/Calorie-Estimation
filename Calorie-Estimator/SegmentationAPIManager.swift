import Foundation
import UIKit
import CoreImage

// MARK: - API Response Models
struct SegmentationResponse: Codable {
    let masks: [String]
    let food_names: [String]
    let boxes: [[Double]]
    let confidences: [Double]
   
    enum CodingKeys: String, CodingKey {
        case masks
        case food_names
        case boxes
        case confidences
    }
}

// MARK: - Food Detection Result
struct FoodDetection {
    let name: String
    let mask: UIImage
    let boundingBox: CGRect
    let confidence: Double
    let estimatedVolume: Double?  // in cubic centimeters
}

// MARK: - API Manager
@MainActor
class SegmentationAPIManager: ObservableObject {
    @Published var detections: [FoodDetection] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?
   
    // Replace with your ngrok URL from Colab
    private let baseURL = "https://ruthfully-waterlocked-james.ngrok-free.dev"  // e.g., "https://abc123.ngrok.io"
   
    func processImage(rgbImage: UIImage, depthMap: UIImage) async {
        print("\n🚀 [Processing] Starting image processing...")
       
        self.isProcessing = true
        self.errorMessage = nil
        self.detections = []
       
        do {
            // Step 1: Get segmentation masks from API
            print("📡 [Processing] Step 1: Sending image to API...")
            let response = try await sendImageToAPI(image: rgbImage)
            print("✅ [Processing] Step 1 complete: Received \(response.masks.count) detections")
           
            // Step 2: Process each detection and calculate volume
            print("🧮 [Processing] Step 2: Calculating volumes...")
            var newDetections: [FoodDetection] = []
           
            for i in 0..<response.masks.count {
                print("   Processing detection \(i + 1)/\(response.masks.count): \(response.food_names[i])")
               
                // Decode mask from base64
                guard let maskData = Data(base64Encoded: response.masks[i]),
                      let maskImage = UIImage(data: maskData) else {
                    print("   ⚠️ Failed to decode mask for \(response.food_names[i])")
                    continue
                }
               
                print("   ✓ Decoded mask (\(maskImage.size.width)x\(maskImage.size.height))")
               
                // Create bounding box
                let box = response.boxes[i]
                let boundingBox = CGRect(
                    x: box[0],
                    y: box[1],
                    width: box[2] - box[0],
                    height: box[3] - box[1]
                )
               
                print("   ✓ Bounding box: \(boundingBox)")
               
                // Calculate volume using depth map
                let volume = calculateVolume(
                    mask: maskImage,
                    depthMap: depthMap,
                    boundingBox: boundingBox
                )
               
                if let volume = volume {
                    print("   ✓ Calculated volume: \(String(format: "%.2f", volume)) cm³")
                } else {
                    print("   ⚠️ Volume calculation failed")
                }
               
                let detection = FoodDetection(
                    name: response.food_names[i],
                    mask: maskImage,
                    boundingBox: boundingBox,
                    confidence: response.confidences[i],
                    estimatedVolume: volume
                )
               
                newDetections.append(detection)
            }
           
            print("✅ [Processing] Step 2 complete: Processed \(newDetections.count) detections")
            print("🎉 [Processing] All done!\n")
           
            self.detections = newDetections
            self.isProcessing = false
           
        } catch {
            print("❌ [Processing] Error occurred: \(error)")
            print("❌ [Processing] Error details: \(error.localizedDescription)")
            self.errorMessage = "Error: \(error.localizedDescription)"
            self.isProcessing = false
        }
    }
   
    private func sendImageToAPI(image: UIImage) async throws -> SegmentationResponse {
        print("🌐 [API] Sending request to: \(baseURL)/segment")
       
        guard let url = URL(string: "\(baseURL)/segment") else {
            print("❌ [API] Invalid URL: \(baseURL)")
            throw URLError(.badURL)
        }
       
        // Convert image to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ [API] Failed to convert image to JPEG")
            throw NSError(domain: "ImageConversion", code: -1, userInfo: nil)
        }
       
        print("📷 [API] Image size: \(image.size)")
        print("📦 [API] Image data size: \(imageData.count / 1024) KB")
       
        // Create multipart form data
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0  // 30 second timeout
       
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
       
        var body = Data()
       
        // Add image file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
       
        request.httpBody = body
       
        print("📤 [API] Sending request...")
       
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
       
        print("📥 [API] Received response")
       
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [API] Invalid response type")
            throw URLError(.badServerResponse)
        }
       
        print("📊 [API] Status code: \(httpResponse.statusCode)")
       
        // Print raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📄 [API] Raw response:")
            print(responseString)
        }
       
        guard httpResponse.statusCode == 200 else {
            print("❌ [API] Bad status code: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ [API] Error message: \(errorString)")
            }
            throw URLError(.badServerResponse)
        }
       
        // Decode response
        let decoder = JSONDecoder()
        do {
            let decodedResponse = try decoder.decode(SegmentationResponse.self, from: data)
           
            // Print decoded response details
            print("✅ [API] Successfully decoded response")
            print("🍽️ [API] Found \(decodedResponse.masks.count) food items:")
            for (index, name) in decodedResponse.food_names.enumerated() {
                print("   \(index + 1). \(name) (confidence: \(String(format: "%.2f", decodedResponse.confidences[index] * 100))%)")
                print("      Box: \(decodedResponse.boxes[index])")
                print("      Mask size: \(decodedResponse.masks[index].count) characters (base64)")
            }
           
            return decodedResponse
        } catch {
            print("❌ [API] Decoding error: \(error)")
            print("❌ [API] Decoding error details: \(error.localizedDescription)")
            throw error
        }
    }
   
    private func calculateVolume(
            mask: UIImage,
            depthMap: UIImage,
            boundingBox: CGRect
        ) -> Double? {
            guard let maskCG = mask.cgImage else {
                return nil
            }
           
            // --- FIX STARTS HERE ---
            // 1. Determine the target size based on the high-res mask
            let targetSize = CGSize(width: maskCG.width, height: maskCG.height)
           
            // 2. Resize the depth map to match the mask dimensions
            //    This prevents the "Index out of range" error when iterating
            var depthImageToProcess = depthMap
            if depthMap.size.width != CGFloat(maskCG.width) || depthMap.size.height != CGFloat(maskCG.height) {
                UIGraphicsBeginImageContext(targetSize)
                depthMap.draw(in: CGRect(origin: .zero, size: targetSize))
                if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                    depthImageToProcess = resized
                }
                UIGraphicsEndImageContext()
            }
           
            guard let depthCG = depthImageToProcess.cgImage else {
                return nil
            }
            // --- FIX ENDS HERE ---
           
            let width = maskCG.width
            let height = maskCG.height
           
            // Create pixel buffers
            guard let maskData = createPixelData(from: maskCG),
                  let depthData = createPixelData(from: depthCG) else { // Uses the resized depthCG
                return nil
            }
           
            // Step 1: Find the reference plane (table/plate surface)
            // This is typically the most common depth value in the mask region
            var depthValues: [Double] = []
           
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                   
                    // Safety check (optional, but good practice)
                    if index + 3 >= maskData.count || index + 3 >= depthData.count {
                        continue
                    }
                   
                    let maskValue = maskData[index]
                   
                    if maskValue > 128 {
                        let depthValue = Double(depthData[index])
                        depthValues.append(depthValue)
                    }
                }
            }
           
            guard !depthValues.isEmpty else { return nil }
           
            // Find the maximum depth (furthest point = likely the base/plate)
            let referencePlaneDepth = depthValues.max() ?? 0
           
            // Step 2: Calculate volume using LiDAR depth
            var totalVolume: Double = 0.0
            var pixelCount = 0
            var totalDepth: Double = 0.0
           
            // LiDAR gives depth in normalized 0-255 range
            // We need to estimate the pixel size at the food's distance
           
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                   
                    // Safety check
                    if index >= maskData.count || index >= depthData.count { continue }

                    let maskValue = maskData[index]
                   
                    if maskValue > 128 {
                        let depthValue = Double(depthData[index])
                       
                        // Calculate height above reference plane
                        // Lower depth value = closer to camera = higher on food
                        let heightAbovePlane = referencePlaneDepth - depthValue
                       
                        // Only count positive heights (above the plane)
                        if heightAbovePlane > 0 {
                            totalDepth += heightAbovePlane
                            pixelCount += 1
                        }
                    }
                }
            }
           
            guard pixelCount > 0 else { return nil }
           
            // Average depth (height) in normalized units (0-255)
            let avgHeight = totalDepth / Double(pixelCount)
           
            // Estimate distance to food from depth map
            // This is a simplified estimation - real implementation would use camera intrinsics
            let estimatedDistance = 400.0  // mm (40cm - typical distance)
           
            // Calculate pixel size at this distance
            // iPhone 15 Pro wide camera: ~77° horizontal FOV, 4032 pixels wide
            let fovRadians = 77.0 * .pi / 180.0
            let sensorWidthMm = 2.0 * estimatedDistance * tan(fovRadians / 2.0)
            let pixelSizeMm = sensorWidthMm / Double(width)
           
            // Convert normalized height (0-255) to real height in mm
            // Assuming depth range of ~5m, each unit ≈ 20mm
            let heightMm = (avgHeight / 255.0) * 5000.0 * 0.05  // Scale factor for food height
           
            // Calculate area of the food in mm²
            let areaMm2 = Double(pixelCount) * pixelSizeMm * pixelSizeMm
           
            // Calculate volume (area × average height)
            let volumeMm3 = areaMm2 * heightMm
           
            // Convert mm³ to cm³
            let volumeCm3 = volumeMm3 / 1000.0
           
            // Apply a correction factor based on empirical testing
            // You can adjust this multiplier based on testing with known volumes
            let correctedVolume = volumeCm3 * 0.8  // Correction factor
           
            return max(correctedVolume, 1.0)  // Minimum 1 cm³
        }
   
    private func createPixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
       
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
       
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
       
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
       
        return pixelData
    }
}

// MARK: - Helper Extensions
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
