//
//  SettingsView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI

/// 设置页面：应用设置和配置
struct SettingsView: View {
    @ObservedObject var speechHelper: SpeechHelper
    @ObservedObject var backgroundProcessor: BackgroundProcessor
    
    @State private var isVoiceEnabled: Bool
    @State private var selectedBackground: BackgroundColor
    @State private var showResetConfirmation = false
    
    init(speechHelper: SpeechHelper, backgroundProcessor: BackgroundProcessor) {
        self.speechHelper = speechHelper
        self.backgroundProcessor = backgroundProcessor
        _isVoiceEnabled = State(initialValue: speechHelper.isVoiceEnabled)
        _selectedBackground = State(initialValue: backgroundProcessor.selectedBackground)
    }
    
    var body: some View {
        NavigationView {
            List {
                // 语音设置
                Section(header: Text("语音设置")) {
                    Toggle("启用语音提示", isOn: $isVoiceEnabled)
                        .onChange(of: isVoiceEnabled) { oldValue, newValue in
                            speechHelper.isVoiceEnabled = newValue
                            if !newValue {
                                speechHelper.stopSpeaking()
                            }
                        }
                    
                    if isVoiceEnabled {
                        HStack {
                            Text("语音状态")
                            Spacer()
                            if speechHelper.isSpeaking {
                                Text("正在播放")
                                    .foregroundColor(.green)
                            } else {
                                Text("待机")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                // 背景设置
                Section(header: Text("背景设置")) {
                    Picker("默认背景颜色", selection: $selectedBackground) {
                        ForEach(BackgroundColor.allCases, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(Color(color.color))
                                    .frame(width: 20, height: 20)
                                Text(color.rawValue)
                            }
                            .tag(color)
                        }
                    }
                    .onChange(of: selectedBackground) { oldValue, newValue in
                        backgroundProcessor.selectedBackground = newValue
                    }
                    
                    Text("拍摄后可在预览页面更改背景颜色")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // 应用信息
                Section(header: Text("应用信息")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("开发者")
                        Spacer()
                        Text("神龙大侠")
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        if let url = URL(string: "https://idphotomaste.example.com") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("官方网站")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // 重置和帮助
                Section {
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置所有设置")
                            Spacer()
                        }
                        .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        // 显示使用指南
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("使用指南")
                            Spacer()
                        }
                    }
                    
                    Button(action: {
                        // 显示隐私政策
                    }) {
                        HStack {
                            Image(systemName: "hand.raised")
                            Text("隐私政策")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { }
                }
            }
            .alert("重置设置", isPresented: $showResetConfirmation) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("确定要重置所有设置吗？这将恢复默认设置。")
            }
        }
    }
    
    private func resetSettings() {
        // 重置语音设置
        isVoiceEnabled = true
        speechHelper.isVoiceEnabled = true
        
        // 重置背景设置
        selectedBackground = .white
        backgroundProcessor.selectedBackground = .white
        
        // 停止当前语音
        speechHelper.stopSpeaking()
    }
}

// MARK: - 预览
#Preview {
    SettingsView(
        speechHelper: SpeechHelper(),
        backgroundProcessor: BackgroundProcessor()
    )
}
