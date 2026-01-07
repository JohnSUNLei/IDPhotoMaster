//
//  EnhancedMainView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine
import AVFoundation
import AudioToolbox  // 用于播放拍照声音

/// 增强版主界面：集成所有新组件
struct EnhancedMainView: View {
    // MARK: - 视图模型
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var poseGuidanceManager = PoseGuidanceManager()
    @StateObject private var photoProcessor = PhotoProcessor()
    
    // MARK: - 视图状态
    @State private var isShowingResult = false
    @State private var capturedImage: UIImage?
    @State private var isCameraPreviewReady = false
    @State private var showCameraPermissionAlert = false
    @State private var lastCapturedImage: UIImage?  // 最后拍摄的照片（用于显示预览小图）
    
    // MARK: - 定时器
    private let poseUpdateTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 黑色背景，避免白屏
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 相机预览层
            if cameraViewModel.isCameraAuthorized {
                CameraPreviewLayer(cameraViewModel: cameraViewModel)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        isCameraPreviewReady = true
                        // 确保相机会话正在运行
                        cameraViewModel.startSession()
                    }
                
                // 引导覆盖层
                if isCameraPreviewReady {
                    GuidanceOverlayView(
                        faceBoundingBox: cameraViewModel.faceDetectionData?.boundingBox,
                        yawAngle: cameraViewModel.faceDetectionData?.yaw,
                        rollAngle: cameraViewModel.faceDetectionData?.roll,
                        pitchAngle: cameraViewModel.faceDetectionData?.pitch
                    )
                }
                
                // 顶部控制栏
                VStack {
                    TopControlBar()
                        .padding(.top, 50)
                    
                    Spacer()
                    
                    // 姿势指导状态
                    PoseStateView(poseManager: poseGuidanceManager)
                        .padding(.bottom, 120)
                    
                    // 底部控制栏（带预览小图）
                    HStack(spacing: 20) {
                        // 左侧：闪光灯按钮
                        Button(action: {
                            cameraViewModel.toggleFlash()
                        }) {
                            Image(systemName: cameraViewModel.isFlashOn ? "bolt.fill" : "bolt.slash")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(15)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // 中间：拍照按钮
                        Button(action: {
                            capturePhoto()
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 3)
                                )
                        }
                        
                        Spacer()
                        
                        // 右侧：预览小图或切换摄像头按钮
                        if let lastImage = lastCapturedImage {
                            Button(action: {
                                // 点击预览小图，打开编辑界面
                                capturedImage = lastImage
                                isShowingResult = true
                            }) {
                                Image(uiImage: lastImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        } else {
                            Button(action: {
                                cameraViewModel.switchCamera()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(15)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            } else {
                // 相机权限提示
                CameraPermissionView(cameraViewModel: cameraViewModel)
            }
        }
        .onReceive(poseUpdateTimer) { _ in
            // 只有在不显示预览界面时才更新姿势状态
            if !isShowingResult {
                updatePoseGuidance()
            }
        }
        .onChange(of: poseGuidanceManager.shouldCapturePhoto) { oldValue, newValue in
            if newValue {
                capturePhoto()
                poseGuidanceManager.resetCaptureFlag()
            }
        }
        .onChange(of: isShowingResult) { oldValue, newValue in
            if newValue {
                // 打开预览界面时，停止语音合成
                poseGuidanceManager.stopSpeaking()
            }
        }
        .sheet(isPresented: $isShowingResult) {
            if let image = capturedImage {
                PhotoResultView(
                    originalImage: image,
                    photoProcessor: photoProcessor,
                    isPresented: $isShowingResult
                )
            }
        }
        .alert("相机权限", isPresented: $showCameraPermissionAlert) {
            Button("设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("需要相机权限来拍摄证件照。请在设置中启用相机权限。")
        }
        .onAppear {
            // 检查相机权限
            if !cameraViewModel.isCameraAuthorized {
                showCameraPermissionAlert = true
            }
        }
        .onDisappear {
            cameraViewModel.stopSession()
        }
    }
    
    // MARK: - 更新姿势指导
    private func updatePoseGuidance() {
        guard let faceData = cameraViewModel.faceDetectionData else {
            poseGuidanceManager.updatePose(yaw: nil, roll: nil, pitch: nil, faceDetected: false, faceBoundingBox: nil, faceLandmarks: nil)
            return
        }
        
        let faceDetected = true
        poseGuidanceManager.updatePose(
            yaw: faceData.yaw,
            roll: faceData.roll,
            pitch: faceData.pitch,
            faceDetected: faceDetected,
            faceBoundingBox: faceData.boundingBox,
            faceLandmarks: faceData.faceLandmarks
        )
    }
    
    // MARK: - 拍摄照片
    private func capturePhoto() {
        // 播放系统拍照声音
        AudioServicesPlaySystemSound(1108)
        
        cameraViewModel.capturePhoto { image in
            if let image = image {
                // 保存为最后拍摄的照片（用于预览小图）
                self.lastCapturedImage = image
                
                // 自动打开编辑界面
                self.capturedImage = image
                self.isShowingResult = true
                
                // 重置姿势管理器
                self.poseGuidanceManager.reset()
            }
        }
    }
}

// MARK: - 相机预览层
struct CameraPreviewLayer: UIViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        
        // 延迟添加预览层
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previewLayer = self.cameraViewModel.previewLayer {
                view.videoPreviewLayer = previewLayer
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let previewLayer = cameraViewModel.previewLayer, uiView.videoPreviewLayer == nil {
            uiView.videoPreviewLayer = previewLayer
        }
    }
}

// MARK: - 预览视图
class PreviewView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            if let layer = videoPreviewLayer {
                layer.frame = bounds
                layer.videoGravity = .resizeAspectFill
                
                if layer.superlayer == nil {
                    self.layer.insertSublayer(layer, at: 0)
                }
                
                // 延迟设置方向，确保连接已经建立
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let connection = layer.connection, connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
        
        // 确保方向设置正确
        if let layer = videoPreviewLayer, let connection = layer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}


// MARK: - 预览
#Preview {
    EnhancedMainView()
}
