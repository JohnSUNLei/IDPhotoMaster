//
//  PoseDetector.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI  // 👈 必须加！它包含了 Color, View, ObservableObject 等定义
import Combine  // 👈 必须加！它包含了 @Published 的功能
import Vision
import UIKit

/// 姿势检测状态
enum PoseStatus {
    case perfect      // 姿势完美
    case good         // 姿势良好
    case needsAdjustment // 需要调整
    case noFace       // 未检测到人脸
}

/// 姿势检测器：使用 Vision 框架检测人脸和姿势
class PoseDetector: NSObject, ObservableObject {
    // MARK: - 发布属性
    @Published var poseStatus: PoseStatus = .noFace
    @Published var guidanceMessage: String = "请将脸部对准框内"
    @Published var faceBoundingBox: CGRect = .zero
    @Published var faceAngle: Double = 0.0
    
    // MARK: - 私有属性
    private let faceDetectionRequest = VNDetectFaceRectanglesRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    
    // MARK: - 检测姿势
    func detectPose(in image: CIImage) {
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        
        // 执行人脸检测
        do {
            try handler.perform([faceDetectionRequest, faceLandmarksRequest])
            
            // 删掉 "as? [VNFaceObservation]" - Vision 框架知道返回的类型
            guard let results = faceDetectionRequest.results,
                  let face = results.first else {
                updateStatus(.noFace, message: "未检测到人脸，请将脸部对准框内")
                return
            }
            
            // 获取人脸边界框
            let boundingBox = face.boundingBox
            faceBoundingBox = boundingBox
            
            // 分析姿势
            // Vision 框架知道返回的类型，不需要强制转换
            analyzeFacePose(face: face, landmarks: faceLandmarksRequest.results?.first)
            
        } catch {
            print("姿势检测失败: \(error.localizedDescription)")
            updateStatus(.noFace, message: "检测失败，请重试")
        }
    }
    
    // MARK: - 分析人脸姿势
    private func analyzeFacePose(face: VNFaceObservation, landmarks: VNFaceObservation?) {
        // 检查人脸是否在中心区域（理想位置）
        let boundingBox = face.boundingBox
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        
        // 理想中心区域（屏幕中心 ± 10%）
        let idealCenterRangeX = 0.4...0.6
        let idealCenterRangeY = 0.4...0.6
        
        // 检查头部倾斜角度
        if let roll = face.roll?.doubleValue {
            faceAngle = roll * 180 / .pi // 转换为角度
            
            // 检查各项指标
            let isCentered = idealCenterRangeX.contains(centerX) && idealCenterRangeY.contains(centerY)
            let isUpright = abs(faceAngle) < 5.0 // 倾斜角度小于5度
            let isGoodSize = boundingBox.width > 0.2 && boundingBox.width < 0.5 // 人脸大小适中
            
            if isCentered && isUpright && isGoodSize {
                updateStatus(.perfect, message: "姿势完美！可以拍摄")
            } else if isCentered && abs(faceAngle) < 10.0 {
                updateStatus(.good, message: "姿势良好，可以微调")
            } else {
                // 提供具体指导
                var guidance = "请调整姿势："
                
                if !isCentered {
                    if centerX < 0.4 {
                        guidance += " 向右移动"
                    } else if centerX > 0.6 {
                        guidance += " 向左移动"
                    }
                    if centerY < 0.4 {
                        guidance += " 向下移动"
                    } else if centerY > 0.6 {
                        guidance += " 向上移动"
                    }
                }
                
                if abs(faceAngle) >= 10.0 {
                    if faceAngle > 0 {
                        guidance += " 头部向左转正"
                    } else {
                        guidance += " 头部向右转正"
                    }
                }
                
                if boundingBox.width <= 0.2 {
                    guidance += " 请靠近摄像头"
                } else if boundingBox.width >= 0.5 {
                    guidance += " 请远离摄像头"
                }
                
                updateStatus(.needsAdjustment, message: guidance)
            }
        } else {
            updateStatus(.needsAdjustment, message: "请保持头部直立")
        }
    }
    
    // MARK: - 更新状态
    private func updateStatus(_ status: PoseStatus, message: String) {
        DispatchQueue.main.async {
            self.poseStatus = status
            self.guidanceMessage = message
        }
    }
    
    // MARK: - 获取姿势指导颜色
    func getStatusColor() -> Color {
        switch poseStatus {
        case .perfect:
            return .green
        case .good:
            return .yellow
        case .needsAdjustment:
            return .orange
        case .noFace:
            return .red
        }
    }
    
    // MARK: - 重置检测
    func reset() {
        poseStatus = .noFace
        guidanceMessage = "请将脸部对准框内"
        faceBoundingBox = .zero
        faceAngle = 0.0
    }
}

// MARK: - 姿势引导视图
struct PoseGuidanceView: View {
    @ObservedObject var poseDetector: PoseDetector
    
    var body: some View {
        VStack(spacing: 12) {
            // 姿势状态指示器
            HStack {
                Circle()
                    .fill(poseDetector.getStatusColor())
                    .frame(width: 12, height: 12)
                
                Text(poseDetector.guidanceMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
            }
            
            // 姿势详细指导
            if poseDetector.poseStatus == .needsAdjustment {
                Text(getDetailedGuidance())
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
            }
        }
        .padding()
    }
    
    private func getDetailedGuidance() -> String {
        let angle = poseDetector.faceAngle
        
        if abs(angle) > 10 {
            return angle > 0 ? "头部向左倾斜 \(String(format: "%.1f", abs(angle)))°，请向右转正" : 
                               "头部向右倾斜 \(String(format: "%.1f", abs(angle)))°，请向左转正"
        }
        
        return "请将脸部对准中心框，保持头部直立"
    }
}
