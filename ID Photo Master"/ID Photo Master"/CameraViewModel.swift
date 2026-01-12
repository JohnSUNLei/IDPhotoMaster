//
//  CameraViewModel.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import AVFoundation
import Vision
import SwiftUI
import Combine

/// 面部检测数据模型
struct FaceDetectionData {
    let boundingBox: CGRect              // 屏幕坐标（用于UI显示）
    let normalizedBoundingBox: CGRect    // 归一化坐标（0.0~1.0，用于ICAO校验）
    let yaw: Double?                     // 左右偏转角度（弧度）
    let roll: Double?                    // 歪头角度（弧度）
    let pitch: Double?                   // 抬头/低头角度（估算）
    let faceLandmarks: VNFaceLandmarks2D?
}

/// 相机视图模型：处理相机、实时人脸检测和帧处理
class CameraViewModel: NSObject, ObservableObject {
    // MARK: - 发布属性
    @Published var session = AVCaptureSession()
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var currentFrame: CGImage?
    @Published var faceDetectionData: FaceDetectionData?
    @Published var isCameraAuthorized = false
    @Published var errorMessage: String?
    @Published var isFlashOn = false
    
    // MARK: - 私有属性
    private let sessionQueue = DispatchQueue(label: "com.idphotomaste.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.idphotomaste.camera.video")
    private var currentDevice: AVCaptureDevice?
    private var currentCameraPosition: AVCaptureDevice.Position = .front  // 跟踪当前摄像头位置
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    
    // Vision 请求
    private let faceDetectionRequest = VNDetectFaceRectanglesRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let faceLandmarks2DRequest = VNDetectFaceLandmarksRequest()
    
    // 帧处理
    private var lastProcessedTime = Date()
    private let processingInterval: TimeInterval = 0.1 // 每100ms处理一帧
    
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
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                        self?.isCameraAuthorized = true
                    } else {
                        self?.errorMessage = "需要相机权限来拍摄证件照"
                    }
                }
            }
        default:
            errorMessage = "请在设置中启用相机权限"
            isCameraAuthorized = false
        }
    }
    
    // MARK: - 相机设置
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            // 配置输入设备（前置摄像头）
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                           for: .video,
                                                           position: .front) else {
                DispatchQueue.main.async {
                    self.errorMessage = "无法获取前置摄像头"
                }
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                self.currentDevice = videoDevice
                self.currentCameraPosition = videoDevice.position  // 记录当前摄像头位置
                
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }
                
                // 配置视频输出（用于实时检测）
                self.videoOutput = AVCaptureVideoDataOutput()
                self.videoOutput?.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                self.videoOutput?.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                
                if let videoOutput = self.videoOutput, self.session.canAddOutput(videoOutput) {
                    self.session.addOutput(videoOutput)
                    // 不设置视频输出方向，让系统自动处理
                    // 预览方向由设备方向自动适配
                }
                
                // 配置照片输出（用于拍摄）
                self.photoOutput = AVCapturePhotoOutput()
                if let photoOutput = self.photoOutput, self.session.canAddOutput(photoOutput) {
                    self.session.addOutput(photoOutput)
                }
                
                self.session.commitConfiguration()
                self.session.startRunning()
                
                // 配置预览层
                DispatchQueue.main.async {
                    self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                    self.previewLayer?.videoGravity = .resizeAspectFill
                    
                    // 设置预览层方向为竖屏
                    if let connection = self.previewLayer?.connection, connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "相机设置失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - 拍摄照片
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        
        photoOutput.capturePhoto(with: settings, delegate: self)
        
        // 临时存储完成回调
        photoCaptureCompletion = completion
    }
    
    // MARK: - 停止/开始会话
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    // MARK: - 切换闪光灯
    func toggleFlash() {
        isFlashOn.toggle()
    }
    
    // MARK: - 切换摄像头
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            // 移除当前输入
            if let currentInput = self.session.inputs.first as? AVCaptureDeviceInput {
                self.session.removeInput(currentInput)
            }
            
            // 切换摄像头位置
            let newPosition: AVCaptureDevice.Position = self.currentDevice?.position == .back ? .front : .back
            
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                    print("无法获取摄像头")
                    return
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                self.currentDevice = device
                self.currentCameraPosition = device.position  // 更新当前摄像头位置
                
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                
                self.session.commitConfiguration()
                
            } catch {
                print("切换摄像头失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 私有属性（用于照片捕获）
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                     didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
        // 控制处理频率
        let now = Date()
        
        // 在 nonisolated 上下文中提取 pixelBuffer，避免在 Task 中捕获 sampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task { @MainActor in
            guard now.timeIntervalSince(self.lastProcessedTime) >= self.processingInterval else { return }
            self.lastProcessedTime = now
            
            // 创建 Vision 请求处理图像
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                      orientation: .leftMirrored,
                                                      options: [:])
            
            // 执行人脸检测
            do {
                try requestHandler.perform([self.faceDetectionRequest, self.faceLandmarks2DRequest])
                
                // 处理检测结果
                self.processDetectionResults(pixelBuffer: pixelBuffer)
                
            } catch {
                print("人脸检测失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 处理检测结果
    private func processDetectionResults(pixelBuffer: CVPixelBuffer) {
        // Vision 框架知道返回的类型，不需要强制转换
        guard let faceObservations = faceDetectionRequest.results,
              let face = faceObservations.first else {
            // 未检测到人脸
            DispatchQueue.main.async {
                self.faceDetectionData = nil
            }
            return
        }
        
        // 获取面部特征点
        let landmarks = faceLandmarks2DRequest.results?.first as? VNFaceObservation
        
        // 计算角度
        let yaw = face.yaw?.doubleValue
        let roll = face.roll?.doubleValue
        let pitch = calculatePitch(from: landmarks)
        
        // 重构更大的边界框（基于特征点）
        let expandedBoundingBox = reconstructBoundingBox(from: face, landmarks: landmarks)
        
        // 转换边界框到屏幕坐标
        let screenBoundingBox = convertBoundingBox(expandedBoundingBox)
        
        // 创建检测数据（同时保存归一化坐标）
        let detectionData = FaceDetectionData(
            boundingBox: screenBoundingBox,
            normalizedBoundingBox: expandedBoundingBox,  // 使用扩展后的归一化坐标
            yaw: yaw,
            roll: roll,
            pitch: pitch,
            faceLandmarks: landmarks?.landmarks
        )
        
        // 更新到主线程
        DispatchQueue.main.async {
            self.faceDetectionData = detectionData
        }
        
        // 更新当前帧（用于预览）
        updateCurrentFrame(from: pixelBuffer)
    }
    
    // MARK: - 计算抬头/低头角度（通过特征点比例估算）
    private func calculatePitch(from faceObservation: VNFaceObservation?) -> Double? {
        guard let landmarks = faceObservation?.landmarks else { return nil }
        
        // 获取关键特征点
        guard let nosePoints = landmarks.nose?.normalizedPoints,
              let leftEyePoints = landmarks.leftEye?.normalizedPoints,
              let rightEyePoints = landmarks.rightEye?.normalizedPoints,
              let outerLipsPoints = landmarks.outerLips?.normalizedPoints,
              nosePoints.count > 0,
              leftEyePoints.count > 0,
              rightEyePoints.count > 0,
              outerLipsPoints.count > 0 else {
            return nil
        }
        
        // 计算眼睛中心点
        let leftEyeCenter = leftEyePoints.reduce(CGPoint.zero, { $0 + $1 }) / CGFloat(leftEyePoints.count)
        let rightEyeCenter = rightEyePoints.reduce(CGPoint.zero, { $0 + $1 }) / CGFloat(rightEyePoints.count)
        let eyesCenter = (leftEyeCenter + rightEyeCenter) / 2
        
        // 计算鼻子中心点
        let noseCenter = nosePoints.reduce(CGPoint.zero, { $0 + $1 }) / CGFloat(nosePoints.count)
        
        // 计算嘴唇中心点
        let lipsCenter = outerLipsPoints.reduce(CGPoint.zero, { $0 + $1 }) / CGFloat(outerLipsPoints.count)
        
        // 计算眼睛到鼻子的距离
        let eyesToNoseDistance = distanceBetween(eyesCenter, noseCenter)
        
        // 计算鼻子到嘴唇的距离
        let noseToLipsDistance = distanceBetween(noseCenter, lipsCenter)
        
        // 计算比例（用于估算抬头/低头）
        let ratio = eyesToNoseDistance / (noseToLipsDistance + 0.0001) // 避免除零
        
        // 将比例转换为角度估算（经验值）
        // 正常比例约为 0.8-1.2，对应 0度
        let pitch = (ratio - 1.0) * 45.0 // 简单线性转换
        
        return pitch
    }
    
    // MARK: - 重构边界框（基于特征点扩展）
    /// 利用面部特征点重新构建一个更大、更准确的边界框
    private func reconstructBoundingBox(from face: VNFaceObservation, landmarks: VNFaceObservation?) -> CGRect {
        var minX = face.boundingBox.minX
        var maxX = face.boundingBox.maxX
        var minY = face.boundingBox.minY
        var maxY = face.boundingBox.maxY
        
        // 如果有特征点，使用特征点来扩展边界框
        if let faceLandmarks = landmarks?.landmarks {
            // 获取所有可用的特征点
            var allPoints: [CGPoint] = []
            
            // 添加各种特征点
            if let leftEye = faceLandmarks.leftEye {
                allPoints.append(contentsOf: leftEye.normalizedPoints)
            }
            if let rightEye = faceLandmarks.rightEye {
                allPoints.append(contentsOf: rightEye.normalizedPoints)
            }
            if let nose = faceLandmarks.nose {
                allPoints.append(contentsOf: nose.normalizedPoints)
            }
            if let outerLips = faceLandmarks.outerLips {
                allPoints.append(contentsOf: outerLips.normalizedPoints)
            }
            if let leftEyebrow = faceLandmarks.leftEyebrow {
                allPoints.append(contentsOf: leftEyebrow.normalizedPoints)
            }
            if let rightEyebrow = faceLandmarks.rightEyebrow {
                allPoints.append(contentsOf: rightEyebrow.normalizedPoints)
            }
            if let faceContour = faceLandmarks.faceContour {
                allPoints.append(contentsOf: faceContour.normalizedPoints)
            }
            
            // 找到所有特征点的极值
            if !allPoints.isEmpty {
                let pointMinX = allPoints.map { $0.x }.min() ?? minX
                let pointMaxX = allPoints.map { $0.x }.max() ?? maxX
                let pointMinY = allPoints.map { $0.y }.min() ?? minY
                let pointMaxY = allPoints.map { $0.y }.max() ?? maxY
                
                // 扩展边界框（添加15%的边距）
                let expandMargin: CGFloat = 0.15
                let width = pointMaxX - pointMinX
                let height = pointMaxY - pointMinY
                
                minX = max(0, pointMinX - width * expandMargin)
                maxX = min(1, pointMaxX + width * expandMargin)
                minY = max(0, pointMinY - height * expandMargin)
                maxY = min(1, pointMaxY + height * expandMargin)
            }
        } else {
            // 如果没有特征点，至少扩展原始边界框20%
            let expandFactor: CGFloat = 0.20
            let width = face.boundingBox.width
            let height = face.boundingBox.height
            
            minX = max(0, face.boundingBox.minX - width * expandFactor)
            maxX = min(1, face.boundingBox.maxX + width * expandFactor)
            minY = max(0, face.boundingBox.minY - height * expandFactor)
            maxY = min(1, face.boundingBox.maxY + height * expandFactor)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - 转换边界框到屏幕坐标（考虑 resizeAspectFill 裁剪）
    private func convertBoundingBox(_ boundingBox: CGRect) -> CGRect {
        guard let previewLayer = previewLayer else { return boundingBox }
        
        // 获取预览层尺寸
        let layerWidth = previewLayer.bounds.width
        let layerHeight = previewLayer.bounds.height
        let layerAspectRatio = layerWidth / layerHeight
        
        // 相机传感器通常是 4:3 (1.33)
        let sensorAspectRatio: CGFloat = 4.0 / 3.0
        
        // 计算 resizeAspectFill 的缩放和偏移
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0.0
        var offsetY: CGFloat = 0.0
        
        if layerAspectRatio > sensorAspectRatio {
            // 屏幕更宽（如 19.5:9），图片高度填满，宽度超出
            scaleY = layerHeight
            scaleX = layerHeight * sensorAspectRatio
            offsetX = (layerWidth - scaleX) / 2
        } else {
            // 屏幕更窄（少见），图片宽度填满，高度超出
            scaleX = layerWidth
            scaleY = layerWidth / sensorAspectRatio
            offsetY = (layerHeight - scaleY) / 2
        }
        
        // Vision 坐标系：原点在左下角，需要翻转 Y 轴
        let x = boundingBox.minX * scaleX + offsetX
        let y = (1.0 - boundingBox.maxY) * scaleY + offsetY
        let width = boundingBox.width * scaleX
        let height = boundingBox.height * scaleY
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - 更新当前帧
    private func updateCurrentFrame(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        DispatchQueue.main.async {
            self.currentFrame = cgImage
        }
    }
    
    // MARK: - 辅助函数
    private func distanceBetween(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        return sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                    didFinishProcessingPhoto photo: AVCapturePhoto,
                    error: Error?) {
        if let error = error {
            print("照片处理错误: \(error.localizedDescription)")
            photoCaptureCompletion?(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            photoCaptureCompletion?(nil)
            return
        }
        
        // 修正照片方向
        // 需要将照片转换为正确的方向（竖直向上）
        let correctedImage = self.fixImageOrientation(image)
        
        photoCaptureCompletion?(correctedImage)
        photoCaptureCompletion = nil
    }
    
    // MARK: - 修正图片方向
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // 如果图片已经是正立的且是后置摄像头，直接返回
        if image.imageOrientation == .up && currentCameraPosition == .back {
            return image
        }
        
        // 使用 UIImage 的 draw 方法自动处理 EXIF 方向
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        
        // 直接绘制图片，UIImage 会自动根据 imageOrientation 调整
        image.draw(in: CGRect(origin: .zero, size: size))
        
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let result = normalizedImage else { return image }
        
        // 前置摄像头需要水平镜像
        if currentCameraPosition == .front {
            guard let cgImage = result.cgImage else { return result }
            
            UIGraphicsBeginImageContextWithOptions(size, false, result.scale)
            guard let context = UIGraphicsGetCurrentContext() else { return result }
            
            // 先翻转Y轴（因为Core Graphics坐标系原点在左下角）
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1.0, y: -1.0)
            
            // 再进行水平镜像
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1.0, y: 1.0)
            
            // 绘制镜像后的图片
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            
            let mirroredImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return mirroredImage ?? result
        }
        
        return result
    }
}

// MARK: - CGPoint 运算符重载
extension CGPoint {
    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x + right.x, y: left.y + right.y)
    }
    
    static func / (point: CGPoint, scalar: CGFloat) -> CGPoint {
        return CGPoint(x: point.x / scalar, y: point.y / scalar)
    }
}

