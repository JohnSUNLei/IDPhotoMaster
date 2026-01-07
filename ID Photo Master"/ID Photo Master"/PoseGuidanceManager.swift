//
//  PoseGuidanceManager.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import AVFoundation
import Combine
import SwiftUI
import Vision  // 用于人脸特征点检测

/// 姿势状态
enum PoseState: Equatable {
    case noFaceDetected      // 未检测到人脸
    case needsAdjustment     // 需要调整
    case good                // 良好
    case perfect             // 完美
    case countdown           // 倒计时中
}

/// 姿势指导管理器：处理姿势评估、语音提示和自动拍照
class PoseGuidanceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // MARK: - 发布属性
    @Published var currentPoseState: PoseState = .noFaceDetected
    @Published var guidanceText: String = "请将脸部对准框内"
    @Published var countdownValue: Int = 3
    @Published var shouldCapturePhoto = false
    
    // MARK: - 私有属性
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpeechTime = Date.distantPast
    private let speechCooldown: TimeInterval = 8.0 // 语音冷却时间（8秒）
    private var errorStateStartTime: Date?
    private let errorThreshold: TimeInterval = 2.0 // 错误姿势持续时间阈值
    private var countdownTimer: Timer?
    private var perfectStateStartTime: Date?
    private let perfectThreshold: TimeInterval = 1.0 // 完美姿势持续时间阈值
    
    // 严格的证件照角度阈值（度）
    private let yawThreshold: Double = 3.0      // 左右偏转（严格：露出双耳）
    private let rollThreshold: Double = 2.0     // 头部倾斜（严格：头摆正）
    private let pitchThreshold: Double = 5.0    // 抬头低头
    
    // 人脸大小阈值（占屏幕比例）
    private let minFaceSize: Double = 0.30      // 最小30%
    private let maxFaceSize: Double = 0.50      // 最大50%
    
    // MARK: - 初始化
    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }
    
    // MARK: - 更新姿势状态
    func updatePose(yaw: Double?, roll: Double?, pitch: Double?, faceDetected: Bool, faceBoundingBox: CGRect? = nil, faceLandmarks: VNFaceLandmarks2D? = nil) {
        guard faceDetected else {
            setPoseState(.noFaceDetected, text: "请将脸部对准框内")
            return
        }
        
        // 转换角度为度
        let yawDegrees = abs((yaw ?? 0) * 180 / .pi)
        let rollDegrees = abs((roll ?? 0) * 180 / .pi)
        let pitchDegrees = abs((pitch ?? 0) * 180 / .pi)
        
        // 严格的证件照检测标准
        var validationErrors: [String] = []
        
        // 1. 检查人脸大小（距离）
        if let faceBox = faceBoundingBox {
            let faceArea = faceBox.width * faceBox.height
            if faceArea < minFaceSize {
                validationErrors.append("请靠近一点")
            } else if faceArea > maxFaceSize {
                validationErrors.append("请离远一点")
            }
        }
        
        // 2. 检查双眉可见性
        if let landmarks = faceLandmarks {
            if landmarks.leftEyebrow == nil || landmarks.rightEyebrow == nil {
                validationErrors.append("请露出眉毛")
            }
            
            // 3. 检查瞳孔注视（眼睛居中）
            if let leftPupil = landmarks.leftPupil, let rightPupil = landmarks.rightPupil,
               let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
                // 检查瞳孔是否在眼睛中心
                if !isPupilCentered(pupil: leftPupil, eye: leftEye) || !isPupilCentered(pupil: rightPupil, eye: rightEye) {
                    validationErrors.append("请注视摄像头")
                }
            }
        }
        
        // 4. 检查角度（严格标准）
        let isYawPerfect = yawDegrees <= yawThreshold
        let isRollPerfect = rollDegrees <= rollThreshold
        let isPitchPerfect = pitchDegrees <= pitchThreshold
        
        if !isYawPerfect {
            validationErrors.append("请正对镜头，露出双耳")
        }
        if !isRollPerfect {
            validationErrors.append("请保持头部直立")
        }
        if !isPitchPerfect {
            validationErrors.append("请平视镜头")
        }
        
        // 5. 综合判断
        if validationErrors.isEmpty {
            // 完美姿势
            handlePerfectPose()
        } else {
            // 需要调整
            let guidance = validationErrors.joined(separator: "，")
            handleAdjustmentNeeded(yawDegrees: yawDegrees, rollDegrees: rollDegrees, 
                                 pitchDegrees: pitchDegrees, yaw: yaw, pitch: pitch, faceBoundingBox: faceBoundingBox, customGuidance: guidance)
        }
    }
    
    // MARK: - 处理完美姿势
    private func handlePerfectPose() {
        if perfectStateStartTime == nil {
            perfectStateStartTime = Date()
            // 第一次检测到完美姿势时，立即播放提示（忽略冷却）
            speakGuidance("姿势完美！保持住", force: true)
        }
        
        let perfectDuration = Date().timeIntervalSince(perfectStateStartTime ?? Date())
        
        if perfectDuration >= perfectThreshold {
            // 保持完美姿势超过阈值，开始倒计时
            if currentPoseState != .countdown {
                startCountdown()
            }
            setPoseState(.countdown, text: "姿势完美！保持住")
        } else {
            // 刚刚进入完美姿势
            setPoseState(.perfect, text: "姿势完美！保持住")
        }
        
        // 重置错误状态计时器
        errorStateStartTime = nil
    }
    
    // MARK: - 检查瞳孔是否居中
    private func isPupilCentered(pupil: VNFaceLandmarkRegion2D, eye: VNFaceLandmarkRegion2D) -> Bool {
        guard let pupilPoints = pupil.normalizedPoints.first,
              eye.pointCount > 0 else {
            return true // 无法检测时假设正常
        }
        
        // 计算眼睛中心
        let eyePoints = eye.normalizedPoints
        let eyeCenter = eyePoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let avgEyeCenter = CGPoint(x: eyeCenter.x / CGFloat(eyePoints.count), y: eyeCenter.y / CGFloat(eyePoints.count))
        
        // 计算瞳孔到眼睛中心的距离
        let dx = pupilPoints.x - avgEyeCenter.x
        let dy = pupilPoints.y - avgEyeCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // 如果距离太大，说明没有注视摄像头
        return distance < 0.05 // 阈值可调整
    }
    
    // MARK: - 处理需要调整的姿势
    private func handleAdjustmentNeeded(yawDegrees: Double, rollDegrees: Double, 
                                      pitchDegrees: Double, yaw: Double?, pitch: Double?, faceBoundingBox: CGRect?, customGuidance: String? = nil) {
        // 重置完美状态计时器
        perfectStateStartTime = nil
        
        // 停止倒计时
        stopCountdown()
        
        // 使用自定义指导或生成指导文本
        let guidance: String
        if let customGuidance = customGuidance {
            guidance = customGuidance
        } else {
            guidance = generateGuidanceText(yawDegrees: yawDegrees, rollDegrees: rollDegrees,
                                          pitchDegrees: pitchDegrees, yaw: yaw, pitch: pitch, faceBoundingBox: faceBoundingBox)
        }
        
        setPoseState(.needsAdjustment, text: guidance)
        
        // 检查是否需要语音提示
        checkAndProvideSpeechGuidance(guidance: guidance)
    }
    
    // MARK: - 生成指导文本
    private func generateGuidanceText(yawDegrees: Double, rollDegrees: Double,
                                    pitchDegrees: Double, yaw: Double?, pitch: Double?, faceBoundingBox: CGRect?) -> String {
        var guidanceParts: [String] = []
        
        // 人脸位置检查（上下左右）
        if let faceBox = faceBoundingBox {
            let centerX = faceBox.midX
            let centerY = faceBox.midY
            
            // 检查水平位置（左右）
            // centerX 在 0.4-0.6 之间为居中
            if centerX < 0.35 {
                guidanceParts.append("请向右移动一点")
            } else if centerX > 0.65 {
                guidanceParts.append("请向左移动一点")
            }
            
            // 检查垂直位置（上下）
            // centerY 在 0.4-0.6 之间为居中
            if centerY < 0.35 {
                guidanceParts.append("请向下移动一点")
            } else if centerY > 0.65 {
                guidanceParts.append("请向上移动一点")
            }
        }
        
        // 左右偏转指导
        if yawDegrees > yawThreshold {
            if let yaw = yaw {
                if yaw > 0 {
                    guidanceParts.append("请向左转一点")
                } else {
                    guidanceParts.append("请向右转一点")
                }
            }
        }
        
        // 头部倾斜指导
        if rollDegrees > rollThreshold {
            guidanceParts.append("请保持头部直立")
        }
        
        // 抬头低头指导
        if pitchDegrees > pitchThreshold {
            if let pitch = pitch {
                if pitch > 0 {
                    guidanceParts.append("请抬头一点")
                } else {
                    guidanceParts.append("请低头一点")
                }
            }
        }
        
        // 如果没有任何指导，返回默认提示
        if guidanceParts.isEmpty {
            return "姿势很好"
        }
        
        return guidanceParts.joined(separator: "，")
    }
    
    // MARK: - 检查并提供语音指导
    private func checkAndProvideSpeechGuidance(guidance: String) {
        let now = Date()
        
        // 检查是否在错误状态
        if errorStateStartTime == nil {
            errorStateStartTime = now
        }
        
        let errorDuration = now.timeIntervalSince(errorStateStartTime ?? now)
        
        // 如果错误姿势持续超过阈值，播放语音（不强制，会受冷却限制）
        if errorDuration >= errorThreshold {
            speakGuidance(guidance, force: false)
        }
    }
    
    // MARK: - 语音指导
    private func speakGuidance(_ text: String, force: Bool = false) {
        // 如果不是强制播放，检查冷却时间
        if !force {
            let now = Date()
            let timeSinceLastSpeech = now.timeIntervalSince(lastSpeechTime)
            
            // 如果距离上次播放不到5秒，跳过
            if timeSinceLastSpeech < speechCooldown {
                return
            }
            
            // 更新上次播放时间
            lastSpeechTime = now
        }
        
        // 停止当前语音
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - 开始倒计时
    private func startCountdown() {
        stopCountdown() // 确保没有其他计时器在运行
        
        countdownValue = 3
        currentPoseState = .countdown
        
        // 播放开始倒计时语音（强制播放，忽略冷却）
        speakGuidance("3", force: true)
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.countdownValue > 1 {
                self.countdownValue -= 1
                // 倒计时语音强制播放
                self.speakGuidance("\(self.countdownValue)", force: true)
            } else {
                // 倒计时结束，触发拍照（强制播放）
                self.speakGuidance("拍照", force: true)
                self.shouldCapturePhoto = true
                self.stopCountdown()
                self.setPoseState(.perfect, text: "拍照完成！")
            }
        }
    }
    
    // MARK: - 停止倒计时
    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 3
    }
    
    // MARK: - 手动触发拍照
    func triggerManualCapture() {
        if currentPoseState == .perfect || currentPoseState == .good {
            // 手动拍照时强制播放语音
            speakGuidance("拍照", force: true)
            shouldCapturePhoto = true
        } else {
            // 错误提示也强制播放
            speakGuidance("请先调整好姿势", force: true)
        }
    }
    
    // MARK: - 重置拍照标志
    func resetCaptureFlag() {
        shouldCapturePhoto = false
    }
    
    // MARK: - 设置姿势状态
    private func setPoseState(_ state: PoseState, text: String) {
        DispatchQueue.main.async {
            self.currentPoseState = state
            self.guidanceText = text
        }
    }
    
    // MARK: - 重置状态
    func reset() {
        stopCountdown()
        currentPoseState = .noFaceDetected
        guidanceText = "请将脸部对准框内"
        errorStateStartTime = nil
        perfectStateStartTime = nil
        shouldCapturePhoto = false
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - 停止语音
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - 析构函数
    deinit {
        stopCountdown()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate 实现
extension PoseGuidanceManager {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // 语音播放完成
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // 语音被取消
    }
}

// MARK: - 姿势状态视图
struct PoseStateView: View {
    @ObservedObject var poseManager: PoseGuidanceManager
    
    var body: some View {
        VStack(spacing: 12) {
            // 姿势状态指示器
            HStack(spacing: 12) {
                // 状态指示灯
                Circle()
                    .fill(colorForState())
                    .frame(width: 12, height: 12)
                    .shadow(color: colorForState().opacity(0.5), radius: 4)
                
                // 指导文本
                Text(poseManager.guidanceText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .shadow(radius: 5)
            }
            
            // 倒计时显示
            if poseManager.currentPoseState == .countdown {
                CountdownView(countdownValue: poseManager.countdownValue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: poseManager.currentPoseState)
    }
    
    private func colorForState() -> Color {
        switch poseManager.currentPoseState {
        case .noFaceDetected:
            return .gray
        case .needsAdjustment:
            return .orange
        case .good:
            return .yellow
        case .perfect:
            return .green
        case .countdown:
            return .blue
        }
    }
}

// MARK: - 倒计时视图
struct CountdownView: View {
    let countdownValue: Int
    
    var body: some View {
        Text("\(countdownValue)")
            .font(.system(size: 60, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .blue, radius: 10)
            .scaleEffect(1.2)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: countdownValue)
    }
}
