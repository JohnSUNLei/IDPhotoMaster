//
//  AboutView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI

/// 关于页面：显示应用信息和开发者信息
struct AboutView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // 应用图标和名称
                    VStack(spacing: 15) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("证件照大师")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("ID Photo Master")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("版本 1.0.0")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    
                    // 开发者信息
                    VStack(alignment: .leading, spacing: 20) {
                        Text("开发者信息")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        DeveloperInfoRow(
                            icon: "person.fill",
                            title: "开发者",
                            value: "神龙大侠 (Dragon Warrior)"
                        )
                        
                        DeveloperInfoRow(
                            icon: "envelope.fill",
                            title: "联系方式",
                            value: "dragon.warrior@example.com"
                        )
                        
                        DeveloperInfoRow(
                            icon: "globe",
                            title: "官方网站",
                            value: "https://idphotomaste.example.com"
                        )
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 应用介绍
                    VStack(alignment: .leading, spacing: 15) {
                        Text("应用介绍")
                            .font(.headline)
                        
                        Text("""
                        「证件照大师」是一款专业的证件照拍摄应用，帮助您轻松拍摄符合标准的证件照片。
                        
                        主要功能：
                        • 实时姿势引导，确保拍摄角度正确
                        • 语音提示，指导您调整姿势
                        • 智能背景替换，支持多种背景颜色
                        • 多种证件照规格选择
                        • 高清照片保存和分享
                        
                        让证件照拍摄变得简单、专业！
                        """)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(5)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 版权信息
                    VStack(spacing: 10) {
                        Text("© 2026 神龙大侠 版权所有")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("本应用完全免费，无广告")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { }
                }
            }
        }
    }
}

/// 开发者信息行组件
struct DeveloperInfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.body)
            }
            
            Spacer()
            
            if icon == "globe" {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 预览
#Preview {
    AboutView()
}
