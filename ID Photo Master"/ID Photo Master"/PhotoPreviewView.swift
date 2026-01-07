//
//  PhotoPreviewView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI

/// 照片预览视图：显示拍摄的照片并提供编辑功能
struct PhotoPreviewView: View {
    let image: UIImage?
    @ObservedObject var backgroundProcessor: BackgroundProcessor
    @Binding var isPresented: Bool
    
    @State private var selectedSpecIndex = 0
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let image = image {
                    // 照片预览
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding()
                    
                    // 背景选择器
                    BackgroundSelectorView(processor: backgroundProcessor)
                        .padding(.horizontal)
                    
                    // 证件照规格选择
                    VStack(alignment: .leading, spacing: 12) {
                        Text("证件照规格")
                            .font(.headline)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<BackgroundProcessor.commonSpecs.count, id: \.self) { index in
                                    Button(action: {
                                        selectedSpecIndex = index
                                    }) {
                                        Text(BackgroundProcessor.commonSpecs[index].name)
                                            .font(.subheadline)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedSpecIndex == index ? Color.blue : Color.gray.opacity(0.2)
                                            )
                                            .foregroundColor(selectedSpecIndex == index ? .white : .primary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // 操作按钮
                    HStack(spacing: 20) {
                        // 重新拍摄按钮
                        Button(action: {
                            isPresented = false
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重拍")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                        
                        // 保存按钮
                        Button(action: {
                            savePhoto()
                        }) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("保存")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                } else {
                    // 无照片提示
                    VStack(spacing: 20) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("暂无照片")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Button("返回拍摄") {
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("照片预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        isPresented = false
                    }
                }
            }
            .alert("保存成功", isPresented: $showSaveSuccess) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("照片已保存到相册")
            }
        }
        .onAppear {
            // 显示照片时自动处理背景
            if let image = image {
                backgroundProcessor.replaceBackground(of: image, with: backgroundProcessor.selectedBackground)
            }
        }
    }
    
    private func savePhoto() {
        guard let originalImage = image else { return }
        
        isSaving = true
        
        // 1. 处理背景
        let processedImage = backgroundProcessor.processedImage ?? originalImage
        
        // 2. 裁剪为选定规格
        let selectedSpec = BackgroundProcessor.commonSpecs[selectedSpecIndex]
        if let finalImage = backgroundProcessor.cropToSpec(processedImage, spec: selectedSpec) {
            // 3. 保存到相册
            backgroundProcessor.saveToPhotoAlbum(finalImage)
        } else {
            // 如果裁剪失败，保存原图
            backgroundProcessor.saveToPhotoAlbum(processedImage)
        }
        
        // 显示保存成功提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
            showSaveSuccess = true
        }
    }
}
