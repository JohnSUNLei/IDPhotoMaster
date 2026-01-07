//
//  CameraManager.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine  // 👈 加上这一行，这堆报错就会消失
import AVFoundation

/// 相机管理器：处理相机权限、会话和照片拍摄
class CameraManager: NSObject, ObservableObject {
    // MARK: - 发布属性
    @Published var session = AVCaptureSession()
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var isCameraAuthorized = false
    @Published var capturedImage: UIImage?
    @Published var isFlashOn = false
    
    // MARK: - 发布属性
    @Published var currentCamera: AVCaptureDevice?
    
    // MARK: - 初始化
    override init() {
        super.init()
        checkCameraPermission()
    }
    
    // MARK: - 相机权限检查
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
            isCameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                        self?.isCameraAuthorized = true
                    }
                }
            }
        default:
            isCameraAuthorized = false
        }
    }
    
    // MARK: - 相机设置
    func setupCamera() {
        // 在后台线程配置相机，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                self.session.beginConfiguration()
                
                // 配置输入设备（后置摄像头）
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    print("无法获取后置摄像头")
                    return
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                self.currentCamera = device
                
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                
                // 配置输出
                if self.session.canAddOutput(self.output) {
                    self.session.addOutput(self.output)
                }
                
                self.session.commitConfiguration()
                
                // 在后台线程启动相机会话
                self.session.startRunning()
                
            } catch {
                print("相机设置失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 拍摄照片
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = isFlashOn ? .on : .off
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - 切换闪光灯
    func toggleFlash() {
        isFlashOn.toggle()
    }
    
    // MARK: - 切换摄像头
    func switchCamera() {
        session.beginConfiguration()
        
        // 移除当前输入
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        
        // 切换摄像头位置
        let newPosition: AVCaptureDevice.Position = currentCamera?.position == .back ? .front : .back
        
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                print("无法获取摄像头")
                return
            }
            
            let input = try AVCaptureDeviceInput(device: device)
            currentCamera = device
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            session.commitConfiguration()
            
        } catch {
            print("切换摄像头失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 停止会话
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    // MARK: - 重新开始会话
    func restartSession() {
        if !session.isRunning {
            session.startRunning()
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate 扩展
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            print("照片处理错误: \(error!.localizedDescription)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("无法获取图片数据")
            return
        }
        
        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }
}

// MARK: - 相机预览视图
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black // 设置黑色背景，避免闪烁
        
        cameraManager.preview = AVCaptureVideoPreviewLayer(session: cameraManager.session)
        cameraManager.preview.videoGravity = .resizeAspectFill
        cameraManager.preview.frame = view.bounds
        
        view.layer.addSublayer(cameraManager.preview)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 更新预览层大小以匹配视图
        DispatchQueue.main.async {
            self.cameraManager.preview?.frame = uiView.bounds
        }
    }
}
