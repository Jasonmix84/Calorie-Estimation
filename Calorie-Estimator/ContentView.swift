import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var apiManager = SegmentationAPIManager()
    @State private var showResults = false
    @State private var capturedRGBImage: UIImage?
    @State private var capturedDepthImage: UIImage?
   
    var body: some View {
        ZStack {
            if showResults {
                ResultsView(
                    apiManager: apiManager,
                    rgbImage: capturedRGBImage,
                    onClose: {
                        showResults = false
                        capturedRGBImage = nil
                        capturedDepthImage = nil
                    }
                )
            } else {
                cameraView
            }
           
            // Processing overlay
            if apiManager.isProcessing {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
               
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Processing image...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
           
            // Error overlay
            if let error = apiManager.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                }
            }
        }
    }
   
    var cameraView: some View {
        ZStack {
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
           
            VStack {
                Spacer()
               
                HStack(spacing: 30) {
                    // Toggle depth view
                    Button(action: {
                        cameraManager.showDepth.toggle()
                    }) {
                        Image(systemName: cameraManager.showDepth ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                   
                    // Capture button
                    Button(action: {
                        captureAndProcess()
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                            )
                    }
                   
                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 60, height: 60)
                }
                .padding(.bottom, 40)
            }
           
            // Status overlay
            if let message = cameraManager.statusMessage {
                VStack {
                    Text(message)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.top, 50)
                    Spacer()
                }
            }
        }
    }
   
    func captureAndProcess() {
        cameraManager.capturePhotoWithCallback { rgbImage, depthImage in
            self.capturedRGBImage = rgbImage
            self.capturedDepthImage = depthImage
           
            // Send to API for processing
            Task {
                await apiManager.processImage(
                    rgbImage: rgbImage,
                    depthMap: depthImage
                )
               
                // Show results when done
                DispatchQueue.main.async {
                    self.showResults = true
                }
            }
        }
    }
}

struct ResultsView: View {
    @ObservedObject var apiManager: SegmentationAPIManager
    let rgbImage: UIImage?
    let onClose: () -> Void
   
    // Calculate total calories
    var totalCalories: Double {
        apiManager.detections.compactMap { $0.caloriesKcal }.reduce(0, +)
    }
   
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Original image
                    if let image = rgbImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                    }
                   
                    // Total calories card
                    if totalCalories > 0 {
                        TotalCaloriesCard(totalCalories: totalCalories)
                    }
                   
                    // Detections list
                    ForEach(Array(apiManager.detections.enumerated()), id: \.offset) { index, detection in
                        DetectionCard(detection: detection, index: index)
                    }
                }
                .padding()
            }
            .navigationTitle("Food Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onClose()
                    }
                }
            }
        }
    }
}

struct TotalCaloriesCard: View {
    let totalCalories: Double
   
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
               
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Calories")
                        .font(.headline)
                        .foregroundColor(.secondary)
                   
                    Text(String(format: "%.0f kcal", totalCalories))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                }
               
                Spacer()
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.1), Color.red.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8)
    }
}

struct DetectionCard: View {
    let detection: FoodDetection
    let index: Int
   
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\(index + 1). \(detection.name.capitalized)")
                    .font(.headline)
               
                Spacer()
               
                Text("\(Int(detection.confidence * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
           
            // Mask visualization
            Image(uiImage: detection.mask)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .cornerRadius(8)
           
            // Nutrition info
            VStack(spacing: 8) {
                // Volume
                if let volume = detection.estimatedVolume {
                    InfoRow(
                        icon: "cube.fill",
                        label: "Volume",
                        value: String(format: "%.1f cm³", volume),
                        color: .blue
                    )
                }
               
                // Mass
                if let mass = detection.massGrams {
                    InfoRow(
                        icon: "scalemass.fill",
                        label: "Mass",
                        value: String(format: "%.1f g", mass),
                        color: .green
                    )
                }
               
                // Calories
                if let calories = detection.caloriesKcal {
                    InfoRow(
                        icon: "flame.fill",
                        label: "Calories",
                        value: String(format: "%.0f kcal", calories),
                        color: .orange
                    )
                } else if let error = detection.nutritionError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5)
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
   
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text("\(label):")
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
