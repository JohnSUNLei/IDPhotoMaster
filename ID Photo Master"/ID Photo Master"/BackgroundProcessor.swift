//
//  BackgroundProcessor.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine  // 👈 加上这一行，这堆报错就会消失
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 背景颜色选项
enum BackgroundColor: String, CaseIterable {
    case white = "白色"
    case blue = "蓝色"
    case red = "红色"
    case gray = "灰色"
    
    var color: UIColor {
        switch self {
        case .white: return .white
        case .blue: return UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        case .red: return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        case .gray: return .lightGray
        }
    }
    
    var ciColor: CIColor {
        return CIColor(color: color)
    }
}

/// 背景处理器：处理背景替换和证件照规格
class BackgroundProcessor: ObservableObject {
    // MARK: - 发布属性
    @Published var selectedBackground: BackgroundColor = .white
    @Published var processedImage: UIImage?
    @Published var isProcessing = false
    
    // MARK: - 证件照规格
    struct PhotoSpec {
        let name: String
        let size: CGSize // 单位：毫米
        let ratio: CGFloat // 宽高比
        let dpi: Int // 打印分辨率
        
        var pixelSize: CGSize {
            let inchesWidth = size.width / 25.4 // 毫米转英寸
            let inchesHeight = size.height / 25.4
            return CGSize(width: CGFloat(dpi) * inchesWidth, 
                         height: CGFloat(dpi) * inchesHeight)
        }
    }
    
    // 常见证件照规格
    static let commonSpecs: [PhotoSpec] = [
        PhotoSpec(name: "一寸", size: CGSize(width: 25, height: 35), ratio: 25/35, dpi: 300),
        PhotoSpec(name: "二寸", size: CGSize(width: 35, height: 49), ratio: 35/49, dpi: 300),
        PhotoSpec(name: "小一寸", size: CGSize(width: 22, height: 32), ratio: 22/32, dpi: 300),
        PhotoSpec(name: "大一寸", size: CGSize(width: 33, height: 48), ratio: 33/48, dpi: 300),
        PhotoSpec(name: "护照", size: CGSize(width: 33, height: 48), ratio: 33/48, dpi: 300),
        PhotoSpec(name: "签证", size: CGSize(width: 35, height: 45), ratio: 35/45, dpi: 300)
    ]
    
    // MARK: - 背景替换
    func replaceBackground(of image: UIImage, with color: BackgroundColor) {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let ciImage = CIImage(image: image) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            
            // 创建背景替换滤镜链
            let processedImage = self.processImage(ciImage, with: color)
            
            DispatchQueue.main.async {
                if let outputImage = processedImage {
                    self.processedImage = outputImage
                }
                self.isProcessing = false
            }
        }
    }
    
    // MARK: - 图像处理
    private func processImage(_ inputImage: CIImage, with color: BackgroundColor) -> UIImage? {
        let context = CIContext()
        
        // 1. 人脸检测和分割（简化版：使用颜色阈值）
        guard let segmentedMask = createFaceMask(from: inputImage) else {
            return nil
        }
        
        // 2. 创建纯色背景
        guard let backgroundFilter = CIFilter(name: "CIConstantColorGenerator") else {
            return nil
        }
        backgroundFilter.setValue(CIColor(color: color.color), forKey: kCIInputColorKey)
        
        guard let backgroundImage = backgroundFilter.outputImage else {
            return nil
        }
        
        // 3. 调整背景大小匹配原图
        let transform = CGAffineTransform(scaleX: inputImage.extent.width / backgroundImage.extent.width,
                                         y: inputImage.extent.height / backgroundImage.extent.height)
        let scaledBackground = backgroundImage.transformed(by: transform)
        
        // 4. 使用混合滤镜合成图像
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }
        blendFilter.setValue(scaledBackground, forKey: kCIInputImageKey)
        blendFilter.setValue(inputImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(segmentedMask, forKey: kCIInputMaskImageKey)
        
        guard let outputCIImage = blendFilter.outputImage else {
            return nil
        }
        
        // 5. 转换为 UIImage
        guard let cgImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - 创建人脸遮罩（简化版）
    private func createFaceMask(from image: CIImage) -> CIImage? {
        // 简化版：使用肤色检测
        // 在实际应用中，应该使用更精确的人像分割算法
        
        guard let colorFilter = CIFilter(name: "CIColorThreshold") else {
            // 如果 CIColorThreshold 不可用，返回一个全白遮罩
            guard let maskFilter = CIFilter(name: "CIConstantColorGenerator") else {
                return nil
            }
            maskFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: kCIInputColorKey)
            return maskFilter.outputImage?.cropped(to: image.extent)
        }
        colorFilter.setValue(image, forKey: kCIInputImageKey)
        
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return colorFilter.outputImage
        }
        blurFilter.setValue(colorFilter.outputImage, forKey: kCIInputImageKey)
        blurFilter.setValue(5.0, forKey: kCIInputRadiusKey)
        
        return blurFilter.outputImage
    }
    
    // MARK: - 裁剪为证件照规格
    func cropToSpec(_ image: UIImage, spec: PhotoSpec) -> UIImage? {
        let targetSize = spec.pixelSize
        
        // 计算裁剪区域（保持脸部在中心）
        let imageSize = image.size
        let targetRatio = targetSize.width / targetSize.height
        let imageRatio = imageSize.width / imageSize.height
        
        var cropRect: CGRect
        
        if imageRatio > targetRatio {
            // 图像更宽，裁剪宽度
            let cropWidth = imageSize.height * targetRatio
            let xOffset = (imageSize.width - cropWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: cropWidth, height: imageSize.height)
        } else {
            // 图像更高，裁剪高度
            let cropHeight = imageSize.width / targetRatio
            let yOffset = (imageSize.height - cropHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: cropHeight)
        }
        
        // 执行裁剪
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage)
        
        // 调整到目标尺寸
        return resizeImage(croppedImage, to: targetSize)
    }
    
    // MARK: - 调整图像尺寸
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - 保存图片到相册
    func saveToPhotoAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

// MARK: - 背景选择视图
struct BackgroundSelectorView: View {
    @ObservedObject var processor: BackgroundProcessor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("背景颜色")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                ForEach(BackgroundColor.allCases, id: \.self) { color in
                    Button(action: {
                        processor.selectedBackground = color
                    }) {
                        VStack {
                            Circle()
                                .fill(Color(color.color))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue, lineWidth: processor.selectedBackground == color ? 3 : 0)
                                )
                            
                            Text(color.rawValue)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            
            if processor.isProcessing {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    
                    Text("正在处理背景...")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
}
