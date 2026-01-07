//
//  PhotoResultView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI

/// 照片结果视图：显示处理后的照片并提供编辑和保存功能
struct PhotoResultView: View {
    // MARK: - 参数
    let originalImage: UIImage
    @ObservedObject var photoProcessor: PhotoProcessor
    @Binding var isPresented: Bool
    
    // MARK: - 状态
    @State private var processedImage: UIImage?
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorText = ""
    @State private var isProcessing = false
    @State private var brightness: Double = 0.0  // 亮度调节 (-1.0 到 1.0)
    @State private var showSizeSelector = false  // 显示尺寸选择器
    
    // MARK: - 身体
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 照片预览区域 - 占据大部分空间
                    PhotoPreviewArea(
                        originalImage: originalImage,
                        processedImage: processedImage,
                        isProcessing: isProcessing
                    )
                    .frame(height: geometry.size.height * 0.7) // 占70%高度
                    
                    // 控制面板 - 紧凑布局
                    ScrollView {
                        CompactControlPanel(
                            photoProcessor: photoProcessor,
                            processedImage: $processedImage,
                            originalImage: originalImage,
                            isProcessing: $isProcessing,
                            isSaving: $isSaving,
                            brightness: $brightness,
                            onSave: savePhoto,
                            onRetake: { isPresented = false }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .frame(height: geometry.size.height * 0.3) // 占30%高度
                    .background(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                }
            }
            .navigationTitle("照片预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        isPresented = false
                    }
                }
            }
            .alert("保存成功", isPresented: $showSaveSuccess) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("证件照已保存到相册")
            }
            .alert("保存失败", isPresented: $showSaveError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(saveErrorText)
            }
            .onAppear {
                // 首次加载时处理照片
                processPhoto()
            }
            .onChange(of: photoProcessor.selectedBackground) { oldValue, newValue in
                // 背景颜色变化时重新处理
                processPhoto()
            }
            .onChange(of: photoProcessor.selectedSpec) { oldValue, newValue in
                // 规格变化时重新处理
                processPhoto()
            }
            .onChange(of: brightness) { oldValue, newValue in
                // 亮度变化时重新处理
                processPhoto()
            }
        }
    }
    
    // MARK: - 处理照片
    private func processPhoto() {
        isProcessing = true
        
        photoProcessor.processPhoto(originalImage) { image in
            self.isProcessing = false
            // 应用亮度调节
            if let image = image, self.brightness != 0.0 {
                self.processedImage = self.adjustBrightness(image: image, value: self.brightness)
            } else {
                self.processedImage = image
            }
        }
    }
    
    // MARK: - 调整亮度
    private func adjustBrightness(image: UIImage, value: Double) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(value, forKey: kCIInputBrightnessKey)
        
        guard let outputImage = filter?.outputImage else { return image }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return image }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - 保存照片
    private func savePhoto() {
        let imageToSave = processedImage ?? originalImage
        
        isSaving = true
        
        // 保存到相册
        photoProcessor.saveToPhotoAlbum(imageToSave)
        
        // 模拟保存过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
            showSaveSuccess = true
        }
    }
}

// MARK: - 照片预览区域
struct PhotoPreviewArea: View {
    let originalImage: UIImage
    let processedImage: UIImage?
    let isProcessing: Bool
    
    var body: some View {
        ZStack {
            // 背景
            Color(.systemGray6)
            
            // 照片显示 - 尽可能大
            if let processedImage = processedImage {
                Image(uiImage: processedImage)
                    .resizable()
                    .scaledToFit()
                    .padding(10) // 最小边距
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            } else {
                Image(uiImage: originalImage)
                    .resizable()
                    .scaledToFit()
                    .padding(10) // 最小边距
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            
            // 处理中指示器
            if isProcessing {
                ProcessingOverlay()
            }
        }
    }
}

// MARK: - 处理中覆盖层
struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("正在处理照片...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("人像分割和背景替换中")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - 紧凑控制面板
struct CompactControlPanel: View {
    @ObservedObject var photoProcessor: PhotoProcessor
    @Binding var processedImage: UIImage?
    let originalImage: UIImage
    @Binding var isProcessing: Bool
    @Binding var isSaving: Bool
    @Binding var brightness: Double
    
    let onSave: () -> Void
    let onRetake: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // 操作按钮行
            HStack(spacing: 12) {
                Button(action: onRetake) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重拍")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray)
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button(action: onSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isSaving ? "保存中..." : "保存")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isSaving)
            }
            
            // 亮度调节 - 紧凑版
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $brightness, in: -0.5...0.5, step: 0.05)
                    .accentColor(.blue)
                Text("\(Int(brightness * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            
            // 背景颜色选择 - 紧凑版
            HStack(spacing: 8) {
                Text("背景")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(PhotoBackgroundColor.allCases, id: \.self) { color in
                    Button(action: {
                        photoProcessor.selectedBackground = color
                    }) {
                        Circle()
                            .fill(Color(color.uiColor))
                            .frame(width: 35, height: 35)
                            .overlay(
                                Circle()
                                    .stroke(Color.blue, lineWidth: photoProcessor.selectedBackground == color ? 2 : 0)
                            )
                    }
                }
            }
            
            // 尺寸选择 - 紧凑版
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("尺寸")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(PhotoSpecification.allSpecs, id: \.name) { spec in
                        Button(action: {
                            photoProcessor.selectedSpec = spec
                        }) {
                            Text(spec.name)
                                .font(.caption)
                                .foregroundColor(photoProcessor.selectedSpec.name == spec.name ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(photoProcessor.selectedSpec.name == spec.name ? Color.blue : Color(.secondarySystemBackground))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 控制面板（旧版，保留兼容）
struct ControlPanel: View {
    @ObservedObject var photoProcessor: PhotoProcessor
    @Binding var processedImage: UIImage?
    let originalImage: UIImage
    @Binding var isProcessing: Bool
    @Binding var isSaving: Bool
    @Binding var brightness: Double
    
    let onSave: () -> Void
    let onRetake: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            // 亮度调节
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.secondary)
                    Text("亮度调节")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(brightness * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $brightness, in: -0.5...0.5, step: 0.05)
                    .accentColor(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            // 证件照规格选择
            PhotoSpecSelectorView(selectedSpec: $photoProcessor.selectedSpec)
            
            // 背景颜色选择
            BackgroundColorSelectorView(selectedColor: $photoProcessor.selectedBackground)
            
            // 操作按钮
            HStack(spacing: 15) {
                // 重拍按钮
                ActionButton(
                    title: "重拍",
                    icon: "arrow.counterclockwise",
                    backgroundColor: .gray,
                    action: onRetake
                )
                
                // 保存按钮
                ActionButton(
                    title: isSaving ? "保存中..." : "保存",
                    icon: isSaving ? "" : "square.and.arrow.down",
                    backgroundColor: .blue,
                    isLoading: isSaving,
                    action: onSave
                )
                .disabled(isSaving)
            }
        }
    }
}

// MARK: - 快速背景切换按钮
struct QuickBackgroundButtons: View {
    @ObservedObject var photoProcessor: PhotoProcessor
    let originalImage: UIImage
    @Binding var processedImage: UIImage?
    @Binding var isProcessing: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(PhotoBackgroundColor.allCases, id: \.self) { color in
                Button(action: {
                    quickSwitchBackground(to: color)
                }) {
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: photoProcessor.selectedBackground == color ? 3 : 0)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                }
            }
        }
    }
    
    private func quickSwitchBackground(to color: PhotoBackgroundColor) {
        guard photoProcessor.selectedBackground != color else { return }
        
        isProcessing = true
        photoProcessor.selectedBackground = color
        
        // 使用快速背景切换
        let currentImage = processedImage ?? originalImage
        if let newImage = photoProcessor.quickBackgroundSwitch(for: currentImage, to: color) {
            processedImage = newImage
            isProcessing = false
        } else {
            // 如果快速切换失败，重新处理
            photoProcessor.processPhoto(originalImage) { image in
                isProcessing = false
                processedImage = image
            }
        }
    }
}

// MARK: - 操作按钮
struct ActionButton: View {
    let title: String
    let icon: String
    let backgroundColor: Color
    var isLoading = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: backgroundColor.opacity(0.3), radius: 5, x: 0, y: 3)
        }
    }
}

// MARK: - 预览
#Preview {
    PhotoResultView(
        originalImage: UIImage(systemName: "photo")!,
        photoProcessor: PhotoProcessor(),
        isPresented: .constant(true)
    )
}
