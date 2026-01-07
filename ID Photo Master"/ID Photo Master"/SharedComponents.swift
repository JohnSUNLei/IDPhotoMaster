//
//  SharedComponents.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine
import AVFoundation  // 👈 添加这一行，解决 position 和 front 找不到的问题

// MARK: - 共享的顶部控制栏（用于 MainView.swift）
struct MainViewTopControlBar: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var speechHelper: SpeechHelper
    @Binding var showAboutPage: Bool
    @Binding var showSettings: Bool
    
    var body: some View {
        HStack {
            // 关于按钮
            Button(action: {
                showAboutPage = true
            }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // 语音控制
            VoiceControlView(speechHelper: speechHelper)
            
            Spacer()
            
            // 设置按钮
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 共享的底部控制栏（用于 MainView.swift）
struct MainViewBottomControlBar: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var poseDetector: PoseDetector
    @ObservedObject var speechHelper: SpeechHelper
    @ObservedObject var backgroundProcessor: BackgroundProcessor
    @Binding var isCaptureCountdown: Bool
    @Binding var countdownValue: Int
    @Binding var showPreview: Bool
    
    var body: some View {
        HStack(spacing: 40) {
            // 闪光灯按钮
            Button(action: {
                cameraManager.toggleFlash()
                speechHelper.speakFlashToggle(cameraManager.isFlashOn)
            }) {
                Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(15)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            // 拍照按钮
            Button(action: {
                if poseDetector.poseStatus == .perfect || poseDetector.poseStatus == .good {
                    startCaptureCountdown()
                } else {
                    speechHelper.speak("请先调整好姿势再拍照", force: true)
                }
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 3)
                    )
            }
            
            // 切换摄像头按钮
            Button(action: {
                cameraManager.switchCamera()
                speechHelper.speakCameraSwitch(cameraManager.currentCamera?.position == .front)
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(15)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 30)
    }
    
    private func startCaptureCountdown() {
        countdownValue = 3
        isCaptureCountdown = true
    }
}

// MARK: - 姿势引导框覆盖层
struct PoseGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width * 0.85  // 使用屏幕宽度的 85%
            let frameHeight = frameWidth * 1.4  // 保持 3:4 比例
            let topSpace = (geometry.size.height - frameHeight) / 2
            
            ZStack {
                // 半透明蒙版
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                                .frame(height: topSpace)
                            
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: (geometry.size.width - frameWidth) / 2)
                                
                                // 中心引导框（透明区域）
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: frameWidth, height: frameHeight)
                                
                                Rectangle()
                                    .frame(width: (geometry.size.width - frameWidth) / 2)
                            }
                            .frame(height: frameHeight)
                            
                            Rectangle()
                                .frame(height: geometry.size.height - topSpace - frameHeight)
                        }
                    )
                
                // 引导框边框
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: frameWidth, height: frameHeight)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // 引导文字
                VStack {
                    Spacer()
                        .frame(height: topSpace + frameHeight + 20)
                    
                    Text("请将脸部对准框内，保持头部直立")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - 倒计时覆盖层
struct CountdownOverlay: View {
    @Binding var countdownValue: Int
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            Text("\(countdownValue)")
                .font(.system(size: 100, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 相机权限提示视图（用于 MainView）
struct CameraPermissionView: View {
    var cameraManager: CameraManager? = nil
    var cameraViewModel: CameraViewModel? = nil
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "camera.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("需要相机权限")
                .font(.title)
                .fontWeight(.bold)
            
            Text("证件照大师需要访问您的相机来拍摄照片。\n请前往设置中开启相机权限。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("检查权限") {
                if let manager = cameraManager {
                    manager.checkCameraPermission()
                } else if let viewModel = cameraViewModel {
                    viewModel.checkCameraPermission()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 20)
            
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - 顶部控制栏（用于 EnhancedMainView）
struct TopControlBar: View {
    var body: some View {
        HStack {
            // 关于按钮
            Button(action: {
                // 暂时空实现
            }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // 设置按钮
            Button(action: {
                // 暂时空实现
            }) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 底部控制栏（用于 EnhancedMainView）
struct BottomControlBar: View {
    @ObservedObject var cameraViewModel: CameraViewModel
    @ObservedObject var poseGuidanceManager: PoseGuidanceManager
    let onCapturePhoto: () -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            // 闪光灯按钮
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
            
            // 拍照按钮（总是可以点击）
            Button(action: {
                onCapturePhoto()
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 3)
                    )
            }
            
            // 切换摄像头按钮
            Button(action: {
                cameraViewModel.switchCamera()
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(15)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 30)
    }
}
