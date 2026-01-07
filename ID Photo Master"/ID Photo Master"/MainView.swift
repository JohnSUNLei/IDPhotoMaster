//
//  MainView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine  // 👈 加上这一行，这堆报错就会消失

/// 应用主视图：整合相机、姿势检测、语音提示和背景替换功能
struct MainView: View {
    // MARK: - 状态管理器
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseDetector = PoseDetector()
    @StateObject private var speechHelper = SpeechHelper()
    @StateObject private var backgroundProcessor = BackgroundProcessor()
    
    // MARK: - 视图状态
    @State private var isShowingPreview = false
    @State private var isShowingSettings = false
    @State private var isCaptureCountdown = false
    @State private var countdownValue = 3
    @State private var showAboutPage = false
    
    // MARK: - 定时器
    private let poseDetectionTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 相机预览层
            if cameraManager.isCameraAuthorized {
                CameraPreview(cameraManager: cameraManager)
                    .edgesIgnoringSafeArea(.all)
                
                // 姿势引导框
                PoseGuideOverlay()
                
                // 顶部控制栏
                VStack {
                    MainViewTopControlBar(
                        cameraManager: cameraManager,
                        speechHelper: speechHelper,
                        showAboutPage: $showAboutPage,
                        showSettings: $isShowingSettings
                    )
                    .padding(.top, 50)
                    
                    Spacer()
                    
                    // 姿势指导信息
                    PoseGuidanceView(poseDetector: poseDetector)
                        .padding(.bottom, 100)
                    
                    // 底部控制栏
                    MainViewBottomControlBar(
                        cameraManager: cameraManager,
                        poseDetector: poseDetector,
                        speechHelper: speechHelper,
                        backgroundProcessor: backgroundProcessor,
                        isCaptureCountdown: $isCaptureCountdown,
                        countdownValue: $countdownValue,
                        showPreview: $isShowingPreview
                    )
                    .padding(.bottom, 30)
                }
            } else {
                // 相机权限提示
                CameraPermissionView(cameraManager: cameraManager)
            }
            
            // 倒计时覆盖层
            if isCaptureCountdown {
                CountdownOverlay(countdownValue: $countdownValue)
            }
        }
        .onReceive(poseDetectionTimer) { _ in
            // 定期检测姿势
            detectPoseFromCamera()
        }
        .onReceive(countdownTimer) { _ in
            // 处理倒计时
            handleCountdown()
        }
        .onChange(of: poseDetector.poseStatus) { oldStatus, newStatus in
            // 根据姿势状态提供语音指导
            speechHelper.speakGuidance(for: newStatus, detailedMessage: poseDetector.guidanceMessage)
        }
        .sheet(isPresented: $isShowingPreview) {
            // 照片预览界面
            PhotoPreviewView(
                image: cameraManager.capturedImage,
                backgroundProcessor: backgroundProcessor,
                isPresented: $isShowingPreview
            )
        }
        .sheet(isPresented: $showAboutPage) {
            // 关于页面
            AboutView()
        }
        .sheet(isPresented: $isShowingSettings) {
            // 设置页面
            SettingsView(
                speechHelper: speechHelper,
                backgroundProcessor: backgroundProcessor
            )
        }
        .onAppear {
            // 应用启动时欢迎语音
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                speechHelper.speak("欢迎使用证件照大师，请将脸部对准框内")
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
    
    // MARK: - 从相机检测姿势
    private func detectPoseFromCamera() {
        guard cameraManager.isCameraAuthorized else {
            return
        }
        
        // 在实际应用中，这里应该从相机获取当前帧进行姿势检测
        // 由于时间关系，这里使用模拟检测
        // 实际实现应该使用 AVCaptureVideoDataOutput 获取视频帧
        
        // 模拟姿势检测（用于演示）
        // 在实际应用中，这里应该处理真实的像素缓冲区
    }
    
    // MARK: - 处理倒计时
    private func handleCountdown() {
        guard isCaptureCountdown else { return }
        
        if countdownValue > 0 {
            speechHelper.speakCaptureCountdown(countdownValue)
            countdownValue -= 1
        } else {
            isCaptureCountdown = false
            capturePhoto()
        }
    }
    
    // MARK: - 拍摄照片
    private func capturePhoto() {
        cameraManager.capturePhoto()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if cameraManager.capturedImage != nil {
                speechHelper.speakCaptureSuccess()
                isShowingPreview = true
            } else {
                speechHelper.speakCaptureFailed()
            }
        }
    }
}


// MARK: - 预览
#Preview {
    MainView()
}
