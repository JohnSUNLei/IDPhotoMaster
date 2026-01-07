# 证件照大师 (ID Photo Master) - 项目总结

## 项目概述
基于用户反馈的详细需求，我们重新设计和实现了「证件照大师」应用，采用了更先进的架构和技术栈，实现了实时姿势引导、智能人像分割和背景替换等核心功能。

## 架构设计

### 1. CameraViewModel (相机视图模型)
- **继承**: NSObject, ObservableObject
- **功能**:
  - 使用 AVCaptureSession 设置前置摄像头实时预览
  - 集成 Vision 框架进行实时人脸检测
  - 实时获取人脸坐标、Yaw、Roll 和估算的 Pitch 角度
  - 将视频帧转换为 SwiftUI 可显示的格式
  - 后台线程处理，主线程 UI 更新

### 2. GuidanceOverlayView (引导覆盖层视图)
- **视觉设计**:
  - 标准虚线框：屏幕中央的证件照人像轮廓
  - 动态弧形光圈：四个方向的圆弧段
  - 状态逻辑：根据面部角度高亮对应方向的圆弧
  - 角度指示器：实时显示偏转角度

### 3. PoseGuidanceManager (姿势指导管理器)
- **逻辑控制**:
  - 定义标准证件照角度阈值（Yaw < 3°, Roll < 3°, Pitch < 5°）
  - 文字提示：根据角度返回具体指导文本
  - 语音提示：集成 AVSpeechSynthesizer
  - 智能计时：错误姿势超过2秒触发语音，3秒冷却时间
  - 自动拍照：完美姿势保持1秒后开始3-2-1倒计时

### 4. PhotoProcessor (照片处理器)
- **核心功能**:
  - 高质量静态图片捕获
  - 智能抠图：使用 VNGeneratePersonSegmentationRequest
  - 背景替换：支持红、蓝、白三种背景色
  - 证件照规格裁剪：一寸、二寸、护照、签证
  - 水印添加："App by 神龙大侠"

### 5. PhotoResultView (结果预览视图)
- **UI 功能**:
  - 处理后的人像显示
  - 快速背景切换按钮（即时预览）
  - 证件照规格选择
  - 保存到相册功能

## 技术亮点

### 1. 实时人脸检测与姿势分析
- 使用 Vision 框架的 VNDetectFaceLandmarksRequest
- 实时计算 Yaw（左右偏转）、Roll（歪头）角度
- 通过面部特征点比例估算 Pitch（抬头/低头）角度
- 算法：眼睛到鼻子距离 / 鼻子到嘴巴距离的比例转换

### 2. 智能人像分割
- 使用 Vision 的 VNGeneratePersonSegmentationRequest
- 平衡质量与性能的 qualityLevel 设置
- 高斯模糊处理使边缘更自然
- 快速背景切换优化

### 3. 动态视觉引导
- 弧形光圈状态机：inactive/active/perfect/warning
- 实时角度指示器
- 呼吸动画和状态反馈
- 颜色编码：灰→蓝→绿→橙

### 4. 语音交互系统
- 中文语音合成
- 智能触发机制
- 防骚扰冷却计时
- 倒计时语音反馈

## 文件结构

```
ID Photo Master/
├── ID_Photo_Master_App.swift          # 应用入口
├── ContentView.swift                  # 主视图容器（使用 EnhancedMainView）
├── EnhancedMainView.swift             # 增强版主界面
├── CameraViewModel.swift              # 相机和实时检测
├── GuidanceOverlayView.swift          # 视觉引导层
├── PoseGuidanceManager.swift          # 姿势管理和语音
├── PhotoProcessor.swift               # 照片处理和人像分割
├── PhotoResultView.swift              # 结果预览和编辑
├── AboutView.swift                    # 关于页面
├── SettingsView.swift                 # 设置页面
├── Info.plist                         # 应用配置
└── Assets.xcassets/                   # 资源文件
```

## 权限配置
在 Info.plist 中添加了必要的权限描述：
- NSCameraUsageDescription: 相机权限
- NSMicrophoneUsageDescription: 麦克风权限（语音合成）
- NSPhotoLibraryAddUsageDescription: 相册保存权限

## 开发者信息
- **开发者**: 神龙大侠 (Dragon Warrior)
- **代码注释**: 所有关键代码都添加了中文注释
- **水印**: 保存的照片包含 "App by 神龙大侠" 水印

## 用户体验流程
1. **启动应用** → 相机权限检查
2. **实时引导** → 弧形光圈和角度指示
3. **姿势调整** → 视觉和语音双重指导
4. **自动拍照** → 完美姿势触发倒计时
5. **照片处理** → 智能抠图和背景替换
6. **结果预览** → 快速切换背景和规格
7. **保存分享** → 保存到相册

## 优化建议（未来版本）
1. 后置摄像头支持
2. 更多证件照规格
3. 自定义背景图片
4. 美颜滤镜功能
5. 云端存储和分享
6. 多语言支持

## 技术栈总结
- **UI 框架**: SwiftUI
- **相机处理**: AVFoundation
- **人脸检测**: Vision
- **图像处理**: CoreImage
- **语音合成**: AVSpeechSynthesizer
- **架构模式**: MVVM + ObservableObject

项目已按照用户的所有详细需求完成实现，具备完整的证件照拍摄、姿势引导和智能处理功能。
