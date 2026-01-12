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
    
    // 提示语防抖动（增强版）
    private var lastGuidanceUpdateTime = Date.distantPast
    private var pendingGuidanceText: String = ""
    private var pendingGuidanceState: PoseState = .noFaceDetected
    private let guidanceUpdateThreshold: TimeInterval = 3.0  // 提示语更新最小间隔（3秒）
    private let guidanceStableThreshold: TimeInterval = 1.0  // 状态稳定时间（1秒）
    private var stateStableStartTime: Date?
    private var lastStableState: PoseState = .noFaceDetected
    
    // 错误优先级（用于只播报最关键的问题）
    private enum ErrorPriority: Int {
        case noFace = 0
        case tooFar = 1
        case tooClose = 2
        case positionWrong = 3
        case angleWrong = 4
        case shoulderCut = 5  // 最低优先级
    }
    
    // ICAO 国际证件照标准阈值（放宽以匹配UI引导框）
    // A. 头部大小（Face Size / Zoom Level）- 放宽阈值
    private let minScreenFaceHeightRatio: Double = 0.45  // 45% 屏幕可见高度（放宽）
    private let maxScreenFaceHeightRatio: Double = 0.75  // 75% 屏幕可见高度（放宽）
    private let idealMinFaceHeightRatio: Double = 0.50   // 50% 理想最小
    private let idealMaxFaceHeightRatio: Double = 0.70   // 70% 理想最大
    
    // B. 头顶留白（Headroom / Top Margin）- 放宽
    private let minHeadroomRatio: Double = 0.05    // 5% 最小留白（放宽）
    private let maxHeadroomRatio: Double = 0.25    // 25% 最大留白（放宽）
    private let idealHeadroomMin: Double = 0.08    // 8% 理想最小
    private let idealHeadroomMax: Double = 0.18    // 18% 理想最大
    
    // C. 水平居中（Horizontal Centering）- 放宽
    private let horizontalCenterTolerance: Double = 0.08  // 8% 容差（放宽）
    
    // D. 肩膀可视区（已禁用）
    // 前置摄像头视野有限，不再强制要求肩膀完全可见
    
    // 角度阈值（放宽标准）
    private let yawThreshold: Double = 5.0      // 左右偏转（放宽）
    private let rollThreshold: Double = 3.0     // 头部倾斜（放宽）
    private let pitchThreshold: Double = 8.0    // 抬头低头（放宽）
    
    // MARK: - 初始化
    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }
    
    // MARK: - 更新姿势状态（ICAO标准）
    func updatePose(yaw: Double?, roll: Double?, pitch: Double?, faceDetected: Bool, faceBoundingBox: CGRect? = nil, faceLandmarks: VNFaceLandmarks2D? = nil) {
        guard faceDetected, let faceBox = faceBoundingBox else {
            setPoseState(.noFaceDetected, text: "请将脸部对准框内")
            return
        }
        
        // 转换角度为度
        let yawDegrees = abs((yaw ?? 0) * 180 / .pi)
        let rollDegrees = abs((roll ?? 0) * 180 / .pi)
        let pitchDegrees = abs((pitch ?? 0) * 180 / .pi)
        
        // ICAO 国际证件照标准校验（只报告最关键的一个问题）
        var criticalError: (priority: ErrorPriority, message: String)? = nil
        
        // ===== 核心构图标准 (Composition Standards) =====
        
        // A. 头部大小（Face Size / Zoom Level）- 最高优先级
        let visibleHeightFactor = calculateVisibleHeightFactor()
        let screenFaceHeightRatio = faceBox.height / visibleHeightFactor
        
        if screenFaceHeightRatio < minScreenFaceHeightRatio {
            criticalError = (.tooFar, "太远了，请靠近一点")
        } else if screenFaceHeightRatio > maxScreenFaceHeightRatio {
            criticalError = (.tooClose, "太近了，请离远一点")
        }
        
        // 如果距离有问题，其他问题都不重要了
        if criticalError == nil {
            // B. 头顶留白（Headroom / Top Margin）
            let headroom = 1.0 - faceBox.maxY
            if headroom < minHeadroomRatio {
                criticalError = (.positionWrong, "头顶太高，请下移")
            } else if headroom > maxHeadroomRatio {
                criticalError = (.positionWrong, "头顶太低，请上移")
            }
        }
        
        // C. 水平居中（Horizontal Centering）
        if criticalError == nil {
            let horizontalCenter = faceBox.midX
            let horizontalDeviation = abs(horizontalCenter - 0.5)
            if horizontalDeviation > horizontalCenterTolerance * 1.5 {  // 放宽容差
                if horizontalCenter < 0.5 {
                    criticalError = (.positionWrong, "请向右移")
                } else {
                    criticalError = (.positionWrong, "请向左移")
                }
            }
        }
        
        // D. 肩膀可视区（放宽要求，仅作为软警告）
        // 不再阻止拍照，只在其他条件都满足时才提示
        // 已注释掉，不再检查肩膀
        
        // ===== 角度标准（仅在位置正确后检查）=====
        if criticalError == nil {
            // 检查角度（放宽标准）
            let isYawPerfect = yawDegrees <= yawThreshold * 1.5
            let isRollPerfect = rollDegrees <= rollThreshold * 1.5
            let isPitchPerfect = pitchDegrees <= pitchThreshold * 1.2
            
            if !isYawPerfect {
                criticalError = (.angleWrong, "请正对镜头")
            } else if !isRollPerfect {
                criticalError = (.angleWrong, "请保持头部直立")
            } else if !isPitchPerfect {
                criticalError = (.angleWrong, "请平视镜头")
            }
        }
        
        // 5. 综合判断（只报告最关键的一个问题）
        if let error = criticalError {
            // 需要调整 - 只播报最关键的问题
            handleAdjustmentNeeded(yawDegrees: yawDegrees, rollDegrees: rollDegrees, 
                                 pitchDegrees: pitchDegrees, yaw: yaw, pitch: pitch, 
                                 faceBoundingBox: faceBoundingBox, customGuidance: error.message)
        } else {
            // 完美姿势
            handlePerfectPose()
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
    
    // MARK: - 检查并提供语音指导（强制3秒间隔）
    private func checkAndProvideSpeechGuidance(guidance: String) {
        let now = Date()
        
        // 强制最小间隔检查（3秒）
        let timeSinceLastSpoken = now.timeIntervalSince(lastGuidanceUpdateTime)
        if timeSinceLastSpoken < guidanceUpdateThreshold {
            // 还在冷却期，不播报
            return
        }
        
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
        let now = Date()
        
        // 防抖动逻辑
        // 1. 检查状态是否稳定
        if state != lastStableState {
            // 状态改变，重置稳定计时器
            lastStableState = state
            stateStableStartTime = now
            pendingGuidanceState = state
            pendingGuidanceText = text
            return
        }
        
        // 2. 状态稳定，检查是否达到稳定时间阈值
        guard let stableStart = stateStableStartTime else {
            stateStableStartTime = now
            return
        }
        
        let stableDuration = now.timeIntervalSince(stableStart)
        
        // 3. 检查是否可以更新UI
        let timeSinceLastUpdate = now.timeIntervalSince(lastGuidanceUpdateTime)
        
        // 只有当状态稳定超过阈值，且距离上次更新超过最小间隔时，才更新UI
        if stableDuration >= guidanceStableThreshold && timeSinceLastUpdate >= guidanceUpdateThreshold {
            DispatchQueue.main.async {
                self.currentPoseState = state
                self.guidanceText = text
            }
            lastGuidanceUpdateTime = now
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
    
    // MARK: - 计算可见高度因子（Visible Height Factor）
    /// 计算屏幕可见区域相对于完整传感器图像的高度比例
    /// 用于修正 resizeAspectFill 导致的坐标映射误差
    private func calculateVisibleHeightFactor() -> Double {
        // 获取屏幕尺寸
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height
        let screenAspectRatio = screenWidth / screenHeight
        
        // 相机传感器通常是 4:3 (1.33)
        let sensorAspectRatio: CGFloat = 4.0 / 3.0
        
        // 计算可见高度因子
        // 当使用 resizeAspectFill 时：
        // - 如果屏幕更窄（screenAspectRatio < sensorAspectRatio），图片宽度填满，高度超出
        // - 如果屏幕更宽（screenAspectRatio > sensorAspectRatio），图片高度填满，宽度超出（少见）
        
        let visibleHeightFactor: CGFloat
        
        if screenAspectRatio < sensorAspectRatio {
            // 竖屏情况（常见）：图片宽度填满屏幕，高度被裁剪
            // 可见高度 = 屏幕宽度 / 传感器宽高比
            // 可见高度占完整图像高度的比例 = (屏幕宽度 / 传感器宽高比) / 屏幕高度
            visibleHeightFactor = (screenWidth / sensorAspectRatio) / screenHeight
        } else {
            // 横屏或方屏情况（少见）：图片高度填满屏幕
            visibleHeightFactor = 1.0
        }
        
        return Double(visibleHeightFactor)
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
