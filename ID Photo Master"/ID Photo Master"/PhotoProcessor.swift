//
//  PhotoProcessor.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine
import UIKit
import Vision
import CoreImage                  // 👈 核心图像处理
import CoreImage.CIFilterBuiltins // 👈 关键！必须加这个才能用 CIFilter 的各种滤镜

/// 背景颜色选项
enum PhotoBackgroundColor: String, CaseIterable {
    case white = "白色"
    case blue = "蓝色"
    case red = "红色"
    
    var uiColor: UIColor {
        switch self {
        case .white: return .white
        case .blue: return UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        case .red: return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        }
    }
    
    var ciColor: CIColor {
        return CIColor(color: uiColor)
    }
}

/// 证件照规格
struct PhotoSpecification: Equatable {
    let name: String
    let sizeInMM: CGSize // 毫米
    let dpi: Int
    let aspectRatio: CGFloat
    
    var pixelSize: CGSize {
        let inchesWidth = sizeInMM.width / 25.4
        let inchesHeight = sizeInMM.height / 25.4
        return CGSize(
            width: CGFloat(dpi) * inchesWidth,
            height: CGFloat(dpi) * inchesHeight
        )
    }
    
    // 常见证件照规格
    static let oneInch = PhotoSpecification(
        name: "一寸",
        sizeInMM: CGSize(width: 25, height: 35),
        dpi: 300,
        aspectRatio: 25.0/35.0
    )
    
    static let twoInch = PhotoSpecification(
        name: "二寸",
        sizeInMM: CGSize(width: 35, height: 49),
        dpi: 300,
        aspectRatio: 35.0/49.0
    )
    
    static let smallTwoInch = PhotoSpecification(
        name: "小二寸",
        sizeInMM: CGSize(width: 33, height: 48),
        dpi: 300,
        aspectRatio: 33.0/48.0
    )
    
    static let passport = PhotoSpecification(
        name: "护照",
        sizeInMM: CGSize(width: 33, height: 48),
        dpi: 300,
        aspectRatio: 33.0/48.0
    )
    
    static let visa = PhotoSpecification(
        name: "签证",
        sizeInMM: CGSize(width: 35, height: 45),
        dpi: 300,
        aspectRatio: 35.0/45.0
    )
    
    static let driverLicense = PhotoSpecification(
        name: "驾照",
        sizeInMM: CGSize(width: 22, height: 32),
        dpi: 300,
        aspectRatio: 22.0/32.0
    )
    
    static let idCard = PhotoSpecification(
        name: "身份证",
        sizeInMM: CGSize(width: 26, height: 32),
        dpi: 300,
        aspectRatio: 26.0/32.0
    )
    
    static let graduation = PhotoSpecification(
        name: "毕业照",
        sizeInMM: CGSize(width: 40, height: 60),
        dpi: 300,
        aspectRatio: 40.0/60.0
    )
    
    static let allSpecs: [PhotoSpecification] = [
        oneInch, twoInch, smallTwoInch, passport, visa, 
        driverLicense, idCard, graduation
    ]
}

/// 照片处理器：处理人像分割、背景替换和证件照裁剪
class PhotoProcessor: ObservableObject {
    // MARK: - 发布属性
    @Published var isProcessing = false
    @Published var processedImage: UIImage?
    @Published var selectedBackground: PhotoBackgroundColor = .white
    @Published var selectedSpec: PhotoSpecification = .twoInch  // 默认使用二寸
    
    // MARK: - 处理照片
    func processPhoto(_ image: UIImage, completion: @escaping (UIImage?) -> Void) {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 0. WYSIWYG 裁剪 - 确保"所见即所得"
            guard let croppedToScreen = self.cropToScreenAspectRatio(image) else {
                print("⚠️ WYSIWYG 裁剪失败，使用原图")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(image)
                }
                return
            }
            
            print("✅ WYSIWYG 裁剪成功，裁剪后尺寸: \(croppedToScreen.size)")
            
            // 1. 人像分割（使用裁剪后的图片）
            guard let segmentedMask = self.segmentPerson(from: croppedToScreen) else {
                print("⚠️ 人像分割失败，返回裁剪后的图")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(croppedToScreen)
                }
                return
            }
            
            print("✅ 人像分割成功")
            
            // 2. 背景替换（使用裁剪后的图片）
            guard let backgroundReplaced = self.replaceBackground(
                image: croppedToScreen,
                mask: segmentedMask,
                backgroundColor: self.selectedBackground
            ) else {
                print("⚠️ 背景替换失败，返回裁剪后的图")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(croppedToScreen)
                }
                return
            }
            
            print("✅ 背景替换成功")
            
            // 3. 裁剪为证件照规格
            guard let croppedImage = self.cropToSpecification(
                backgroundReplaced,
                specification: self.selectedSpec
            ) else {
                print("⚠️ 裁剪失败，返回未裁剪版本")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(backgroundReplaced) // 返回未裁剪的版本
                }
                return
            }
            
            print("✅ 裁剪成功")
            
            DispatchQueue.main.async {
                self.processedImage = croppedImage
                self.isProcessing = false
                completion(croppedImage)
            }
        }
    }
    
    // MARK: - WYSIWYG 裁剪（所见即所得）
    private func cropToScreenAspectRatio(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // 获取屏幕宽高比
        let screenBounds = UIScreen.main.bounds
        let screenAspectRatio = screenBounds.width / screenBounds.height
        
        // 获取图片尺寸
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageAspectRatio = imageWidth / imageHeight
        
        print("📱 屏幕比例: \(screenAspectRatio), 图片比例: \(imageAspectRatio)")
        
        // 计算裁剪区域（Center Crop）
        var cropRect: CGRect
        
        if imageAspectRatio > screenAspectRatio {
            // 图片更宽，裁剪宽度
            let targetWidth = imageHeight * screenAspectRatio
            let xOffset = (imageWidth - targetWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: targetWidth, height: imageHeight)
        } else {
            // 图片更高（通常是这种情况：4:3 vs 屏幕的 19.5:9）
            // 裁剪高度，保持宽度
            let targetHeight = imageWidth / screenAspectRatio
            let yOffset = (imageHeight - targetHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageWidth, height: targetHeight)
        }
        
        print("✂️ 裁剪区域: \(cropRect)")
        
        // 执行裁剪
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        // 转换回 UIImage，保持原始 scale 和 orientation
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - 人像分割
    private func segmentPerson(from image: UIImage) -> CIImage? {
        // 图片方向已经在 CameraViewModel 中修正，直接使用
        guard let ciImage = CIImage(image: image) else { return nil }
        
        // 创建人像分割请求
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                return nil
            }
            
            // 获取像素缓冲区（在某些 iOS 版本中不是可选类型）
            let maskPixelBuffer = result.pixelBuffer
            
            // 将像素缓冲区转换为 CIImage
            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            
            // 调整掩码大小以匹配原始图像
            let scaleX = ciImage.extent.width / maskImage.extent.width
            let scaleY = ciImage.extent.height / maskImage.extent.height
            let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            // 应用高斯模糊使边缘更自然
            guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
                return scaledMask
            }
            blurFilter.setValue(scaledMask, forKey: kCIInputImageKey)
            blurFilter.setValue(2.0, forKey: kCIInputRadiusKey)  // 减小模糊半径
            
            guard let blurredMask = blurFilter.outputImage else {
                return scaledMask
            }
            
            // 裁剪模糊后的遮罩以匹配原始图像范围
            return blurredMask.cropped(to: ciImage.extent)
            
        } catch {
            print("人像分割失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 背景替换
    private func replaceBackground(image: UIImage, mask: CIImage, 
                                 backgroundColor: PhotoBackgroundColor) -> UIImage? {
        // 图片方向已经在 CameraViewModel 中修正，直接使用
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let context = CIContext()
        
        // 1. 创建纯色背景
        guard let backgroundFilter = CIFilter(name: "CIConstantColorGenerator") else {
            return nil
        }
        backgroundFilter.setValue(backgroundColor.ciColor, forKey: kCIInputColorKey)
        
        guard let backgroundImage = backgroundFilter.outputImage else {
            return nil
        }
        
        // 2. 裁剪背景以匹配原始图像
        let scaledBackground = backgroundImage.cropped(to: ciImage.extent)
        
        // 3. 使用混合滤镜合成图像
        // CIBlendWithMask: inputImage(前景) + backgroundImage(背景) + maskImage(遮罩)
        // 遮罩白色部分显示前景，黑色部分显示背景
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }
        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)  // 前景：原始人像
        blendFilter.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)  // 背景：纯色
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)  // 遮罩：人像分割结果
        
        guard let outputCIImage = blendFilter.outputImage else {
            return nil
        }
        
        // 4. 转换为 UIImage
        guard let cgImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - 裁剪为证件照规格
    private func cropToSpecification(_ image: UIImage, 
                                   specification: PhotoSpecification) -> UIImage? {
        let targetAspectRatio = specification.aspectRatio
        
        // 计算裁剪区域（保持脸部在中心上方）
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        var cropRect: CGRect
        
        if imageAspectRatio > targetAspectRatio {
            // 图像更宽，裁剪宽度
            let cropWidth = imageSize.height * targetAspectRatio
            let xOffset = (imageSize.width - cropWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: cropWidth, height: imageSize.height)
        } else {
            // 图像更高，裁剪高度
            // 证件照通常需要头部在上方1/3处，所以从顶部开始裁剪
            let cropHeight = imageSize.width / targetAspectRatio
            let yOffset = max(0, (imageSize.height - cropHeight) * 0.2) // 从上方20%开始
            cropRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: cropHeight)
        }
        
        // 确保裁剪区域在图像范围内
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        
        // 执行裁剪（需要转换坐标系）
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        // CGImage 的坐标系是左下角为原点，需要转换
        let scale = image.scale
        let scaledCropRect = CGRect(
            x: cropRect.origin.x * scale,
            y: (imageSize.height - cropRect.origin.y - cropRect.height) * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: scaledCropRect) else {
            return nil
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: image.imageOrientation)
        
        // 不调整尺寸，保持原始分辨率用于预览
        // 只在保存时才调整到目标尺寸
        return croppedImage
    }
    
    // MARK: - 调整图像尺寸
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - 添加水印
    private func addWatermark(to image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // 绘制原始图像
            image.draw(at: .zero)
            
            // 添加水印文本
            let watermarkText = "App by 神龙大侠"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.white.withAlphaComponent(0.3),
                .backgroundColor: UIColor.black.withAlphaComponent(0.1)
            ]
            
            let textSize = watermarkText.size(withAttributes: attributes)
            let textRect = CGRect(
                x: image.size.width - textSize.width - 10,
                y: image.size.height - textSize.height - 10,
                width: textSize.width,
                height: textSize.height
            )
            
            watermarkText.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    // MARK: - 修正图片方向
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // 如果图片已经是正确方向，直接返回
        if image.imageOrientation == .up {
            return image
        }
        
        // 创建正确方向的图片
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? image
    }
    
    // MARK: - 保存到相册
    func saveToPhotoAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        // 也可以保存到应用的文档目录
        saveToDocuments(image)
    }
    
    // MARK: - 保存到文档目录
    private func saveToDocuments(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        
        let fileName = "IDPhoto_\(Date().timeIntervalSince1970).jpg"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileURL = documentsURL?.appendingPathComponent(fileName)
        
        if let fileURL = fileURL {
            try? data.write(to: fileURL)
        }
    }
    
    // MARK: - 快速背景切换（不重新处理分割）
    func quickBackgroundSwitch(for image: UIImage, to newBackground: PhotoBackgroundColor) -> UIImage? {
        guard let ciImage = CIImage(image: image),
              let mask = segmentPerson(from: image) else {
            return nil
        }
        
        return replaceBackground(image: image, mask: mask, backgroundColor: newBackground)
    }
}

// MARK: - 照片规格选择视图
struct PhotoSpecSelectorView: View {
    @Binding var selectedSpec: PhotoSpecification
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("证件照规格")
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PhotoSpecification.allSpecs, id: \.name) { spec in
                        Button(action: {
                            selectedSpec = spec
                        }) {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSpec.name == spec.name ? Color.blue : Color.gray.opacity(0.2))
                                    .frame(width: 60, height: 80)
                                    .overlay(
                                        Text(spec.name)
                                            .font(.caption)
                                            .foregroundColor(selectedSpec.name == spec.name ? .white : .primary)
                                    )
                                
                                Text("\(Int(spec.sizeInMM.width))×\(Int(spec.sizeInMM.height))mm")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 背景颜色选择视图
struct BackgroundColorSelectorView: View {
    @Binding var selectedColor: PhotoBackgroundColor
    @State private var showColorPicker = false
    @State private var customColor: Color = .gray
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("背景颜色")
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    // 预设颜色
                    ForEach(PhotoBackgroundColor.allCases, id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                        }) {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color(color.uiColor))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                
                                Text(color.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    // 自定义颜色按钮
                    Button(action: {
                        showColorPicker = true
                    }) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.red, .yellow, .green, .blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 50, height: 50)
                                
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                            
                            Text("自定义")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showColorPicker) {
            ColorPickerSheet(selectedColor: $customColor, onConfirm: {
                // TODO: 应用自定义颜色
                showColorPicker = false
            })
        }
    }
}

// MARK: - 自定义颜色选择器
struct ColorPickerSheet: View {
    @Binding var selectedColor: Color
    let onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("选择自定义背景颜色")
                    .font(.title2)
                    .fontWeight(.bold)
                
                ColorPicker("选择颜色", selection: $selectedColor, supportsOpacity: false)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                
                // 预览
                VStack(spacing: 10) {
                    Text("预览")
                        .font(.headline)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedColor)
                        .frame(height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
