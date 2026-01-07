//
//  SpeechHelper.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI
import Combine
import AVFoundation // 👈 语音功能必须引入这个

/// 语音助手：提供语音提示和指导
// 关键修改：必须继承 NSObject，才能处理语音播放完成的回调
class SpeechHelper: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // MARK: - 发布属性
    @Published var isSpeaking = false
    @Published var isVoiceEnabled = true
    
    // MARK: - 私有属性
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage = ""
    private var lastSpokenTime = Date.distantPast
    private let minInterval: TimeInterval = 3.0 // 最小语音间隔时间
    
    // MARK: - 初始化
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - 语音提示
    func speak(_ text: String, force: Bool = false) {
        guard isVoiceEnabled else { return }
        
        // 检查是否与上次消息相同且时间间隔太短
        let now = Date()
        if !force && text == lastSpokenMessage && now.timeIntervalSince(lastSpokenTime) < minInterval {
            return
        }
        
        // 停止当前语音
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // 创建语音内容
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") // 使用中文语音
        utterance.rate = 0.5 // 语速适中
        utterance.pitchMultiplier = 1.0 // 音调正常
        utterance.volume = 1.0 // 音量最大
        
        // 开始语音
        synthesizer.speak(utterance)
        
        // 更新记录
        lastSpokenMessage = text
        lastSpokenTime = now
        isSpeaking = true
    }
    
    // MARK: - 根据姿势状态提供语音指导
    func speakGuidance(for poseStatus: PoseStatus, detailedMessage: String? = nil) {
        guard isVoiceEnabled else { return }
        
        var message = ""
        
        switch poseStatus {
        case .perfect:
            message = "姿势完美，可以拍摄证件照"
        case .good:
            message = "姿势良好，可以微调"
        case .needsAdjustment:
            if let detailed = detailedMessage, !detailed.isEmpty {
                message = detailed
            } else {
                message = "请调整姿势，将脸部对准中心框"
            }
        case .noFace:
            message = "未检测到人脸，请将脸部对准框内"
        }
        
        speak(message)
    }
    
    // MARK: - 拍摄相关语音
    func speakCaptureCountdown(_ count: Int) {
        guard isVoiceEnabled else { return }
        
        if count > 0 {
            speak("\(count)")
        } else {
            speak("拍照")
        }
    }
    
    func speakCaptureSuccess() {
        guard isVoiceEnabled else { return }
        speak("拍照成功，请查看照片")
    }
    
    func speakCaptureFailed() {
        guard isVoiceEnabled else { return }
        speak("拍照失败，请重试")
    }
    
    // MARK: - 功能提示语音
    func speakFlashToggle(_ isOn: Bool) {
        guard isVoiceEnabled else { return }
        speak(isOn ? "闪光灯已开启" : "闪光灯已关闭")
    }
    
    func speakCameraSwitch(_ isFront: Bool) {
        guard isVoiceEnabled else { return }
        speak(isFront ? "已切换至前置摄像头" : "已切换至后置摄像头")
    }
    
    // MARK: - 停止语音
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
    
    // MARK: - 切换语音开关
    func toggleVoice() {
        isVoiceEnabled.toggle()
        if !isVoiceEnabled && synthesizer.isSpeaking {
            stopSpeaking()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate 实现
extension SpeechHelper {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

// MARK: - 语音控制视图
struct VoiceControlView: View {
    @ObservedObject var speechHelper: SpeechHelper
    
    var body: some View {
        HStack {
            Button(action: {
                speechHelper.toggleVoice()
            }) {
                Image(systemName: speechHelper.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title2)
                    .foregroundColor(speechHelper.isVoiceEnabled ? .blue : .gray)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            if speechHelper.isSpeaking {
                // 语音活动指示器
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 4, height: 20)
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.1),
                                value: speechHelper.isSpeaking
                            )
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal)
    }
}
