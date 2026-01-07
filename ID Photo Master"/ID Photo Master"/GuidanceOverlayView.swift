//
//  GuidanceOverlayView.swift
//  ID Photo Master
//
//  Created by 神龙大侠 (Dragon Warrior) on 2026-01-06.
//

import SwiftUI

/// 引导弧段状态
enum ArcSegmentState {
    case inactive      // 未激活
    case active        // 激活（提示需要调整）
    case perfect       // 完美状态
    case warning       // 警告状态（闪烁）
}

/// 引导覆盖层视图：显示证件照轮廓和动态弧形光圈
struct GuidanceOverlayView: View {
    // MARK: - 参数
    let faceBoundingBox: CGRect?
    let yawAngle: Double?      // 左右偏转角度（弧度）
    let rollAngle: Double?     // 歪头角度（弧度）
    let pitchAngle: Double?    // 抬头/低头角度（估算）
    
    // MARK: - 状态
    @State private var arcAnimationProgress: Double = 0
    @State private var warningBlinkOpacity: Double = 1
    @State private var perfectGlowRadius: CGFloat = 5
    
    // MARK: - 常量
    private let arcWidth: CGFloat = 8
    private let arcSegmentLength: CGFloat = .pi / 3 // 60度弧段
    
    // MARK: - 计算属性
    private func guideFrame(in size: CGSize) -> CGRect {
        // 使用屏幕宽度的 85% 作为框的宽度，让用户更容易对准
        let frameWidth = size.width * 0.85
        // 保持 3:4 的纵横比（标准证件照比例）
        let frameHeight = frameWidth * 1.4
        
        return CGRect(
            x: (size.width - frameWidth) / 2,
            y: (size.height - frameHeight) / 2,
            width: frameWidth,
            height: frameHeight
        )
    }
    
    private var guideFrameSize: CGSize {
        // 动态计算，不再使用固定值
        return CGSize(width: 300, height: 420)
    }
    
    private var arcRadius: CGFloat {
        // 弧形半径也相应增大
        return 200
    }
    
    private func arcCenter(in size: CGSize) -> CGPoint {
        let frame = guideFrame(in: size)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    // MARK: - 弧段状态计算
    private var topArcState: ArcSegmentState {
        guard let pitch = pitchAngle else { return .inactive }
        let pitchDegrees = abs(pitch * 180 / .pi)
        
        if pitchDegrees < 3 { return .perfect }
        if pitch < 0 { return .warning } // 低头，上方需要警告
        return .active
    }
    
    private var bottomArcState: ArcSegmentState {
        guard let pitch = pitchAngle else { return .inactive }
        let pitchDegrees = abs(pitch * 180 / .pi)
        
        if pitchDegrees < 3 { return .perfect }
        if pitch > 0 { return .warning } // 抬头，下方需要警告
        return .active
    }
    
    private var leftArcState: ArcSegmentState {
        guard let yaw = yawAngle else { return .inactive }
        let yawDegrees = abs(yaw * 180 / .pi)
        
        if yawDegrees < 3 { return .perfect }
        if yaw > 0 { return .warning } // 脸向右偏，左侧需要警告
        return .active
    }
    
    private var rightArcState: ArcSegmentState {
        guard let yaw = yawAngle else { return .inactive }
        let yawDegrees = abs(yaw * 180 / .pi)
        
        if yawDegrees < 3 { return .perfect }
        if yaw < 0 { return .warning } // 脸向左偏，右侧需要警告
        return .active
    }
    
    // MARK: - 身体
    var body: some View {
        GeometryReader { geometry in
            let frame = guideFrame(in: geometry.size)
            let center = arcCenter(in: geometry.size)
            
            ZStack {
                // 半透明蒙版
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                                .frame(height: frame.minY)
                            
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: frame.minX)
                                
                                // 中心透明区域（证件照轮廓）
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: frame.width, height: frame.height)
                                
                                Rectangle()
                                    .frame(width: frame.minX)
                            }
                            .frame(height: frame.height)
                            
                            Rectangle()
                                .frame(height: geometry.size.height - frame.maxY)
                        }
                    )
            
                // 证件照轮廓（使用动态尺寸）
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(0.8), lineWidth: 4)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                
                // 头部和肩部轮廓
                HeadAndShouldersShape()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: frame.width * 0.7, height: frame.height * 0.8)
                    .position(x: frame.midX, y: frame.midY)
                
                // 动态弧形光圈
                ArcSegment(center: center, radius: arcRadius, 
                          startAngle: .degrees(60), endAngle: .degrees(120),
                          state: topArcState, animationProgress: arcAnimationProgress)
                    .stroke(lineWidth: arcWidth)
                
                ArcSegment(center: center, radius: arcRadius,
                          startAngle: .degrees(120), endAngle: .degrees(180),
                          state: leftArcState, animationProgress: arcAnimationProgress)
                    .stroke(lineWidth: arcWidth)
                
                ArcSegment(center: center, radius: arcRadius,
                          startAngle: .degrees(240), endAngle: .degrees(300),
                          state: bottomArcState, animationProgress: arcAnimationProgress)
                    .stroke(lineWidth: arcWidth)
                
                ArcSegment(center: center, radius: arcRadius,
                          startAngle: .degrees(300), endAngle: .degrees(360),
                          state: rightArcState, animationProgress: arcAnimationProgress)
                    .stroke(lineWidth: arcWidth)
                
                // 人脸边界框（如果检测到）
                if let faceBox = faceBoundingBox {
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: faceBox.width, height: faceBox.height)
                        .position(x: faceBox.midX, y: faceBox.midY)
                }
                
                // 角度指示器
                VStack {
                    Spacer()
                        .frame(height: frame.maxY + 20)
                
                HStack(spacing: 30) {
                    AngleIndicator(angle: yawAngle, label: "左右偏转", 
                                  perfectRange: -3...3, unit: "度")
                    AngleIndicator(angle: rollAngle, label: "头部倾斜",
                                  perfectRange: -3...3, unit: "度")
                    AngleIndicator(angle: pitchAngle, label: "抬头低头",
                                  perfectRange: -3...3, unit: "度")
                    }
                    .padding(.horizontal)
                }
            }
            .onAppear {
                // 启动弧段动画
                withAnimation(Animation.easeInOut(duration: 2).repeatForever()) {
                    arcAnimationProgress = 1
                }
                
                // 启动警告闪烁动画
                withAnimation(Animation.easeInOut(duration: 0.5).repeatForever()) {
                    warningBlinkOpacity = warningBlinkOpacity == 1 ? 0.3 : 1
                }
                
                // 启动完美状态光晕动画
                withAnimation(Animation.easeInOut(duration: 1).repeatForever()) {
                    perfectGlowRadius = 15
                }
            }
        }
    }
}

// MARK: - 头部和肩部形状
struct HeadAndShouldersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 头部（椭圆形）
        let headRect = CGRect(x: rect.width * 0.2, y: rect.height * 0.1,
                            width: rect.width * 0.6, height: rect.height * 0.5)
        path.addEllipse(in: headRect)
        
        // 肩部（梯形）
        let shoulderTopY = headRect.maxY
        let shoulderBottomY = rect.maxY
        let shoulderTopWidth = rect.width * 0.4
        let shoulderBottomWidth = rect.width * 0.8
        
        path.move(to: CGPoint(x: rect.midX - shoulderTopWidth/2, y: shoulderTopY))
        path.addLine(to: CGPoint(x: rect.midX - shoulderBottomWidth/2, y: shoulderBottomY))
        path.addLine(to: CGPoint(x: rect.midX + shoulderBottomWidth/2, y: shoulderBottomY))
        path.addLine(to: CGPoint(x: rect.midX + shoulderTopWidth/2, y: shoulderTopY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - 弧段形状
struct ArcSegment: Shape {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: Angle
    let endAngle: Angle
    let state: ArcSegmentState
    var animationProgress: Double
    
    var animatableData: Double {
        get { animationProgress }
        set { animationProgress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 根据动画进度计算实际结束角度
        let actualEndAngle = startAngle + Angle(degrees: (endAngle.degrees - startAngle.degrees) * animationProgress)
        
        path.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: actualEndAngle,
                   clockwise: false)
        
        return path
    }
}

// MARK: - 弧段视图（添加样式）
extension ArcSegment {
    func stroke(lineWidth: CGFloat) -> some View {
        self.stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .foregroundColor(colorForState())
            .shadow(color: glowColorForState(), radius: glowRadiusForState())
            .opacity(opacityForState())
    }
    
    private func colorForState() -> Color {
        switch state {
        case .inactive:
            return .gray.opacity(0.5)
        case .active:
            return .blue
        case .perfect:
            return .green
        case .warning:
            return .orange
        }
    }
    
    private func glowColorForState() -> Color {
        switch state {
        case .perfect:
            return .green
        case .warning:
            return .orange
        default:
            return .clear
        }
    }
    
    private func glowRadiusForState() -> CGFloat {
        switch state {
        case .perfect:
            return 10
        case .warning:
            return 5
        default:
            return 0
        }
    }
    
    private func opacityForState() -> Double {
        switch state {
        case .warning:
            return 0.8 // 闪烁效果通过外部动画控制
        default:
            return 1.0
        }
    }
}

// MARK: - 角度指示器
struct AngleIndicator: View {
    let angle: Double?
    let label: String
    let perfectRange: ClosedRange<Double>
    let unit: String
    
    private var angleDegrees: Double? {
        guard let angle = angle else { return nil }
        return angle * 180 / .pi
    }
    
    private var isPerfect: Bool {
        guard let degrees = angleDegrees else { return false }
        return perfectRange.contains(degrees)
    }
    
    private var color: Color {
        guard let degrees = angleDegrees else { return .gray }
        
        if isPerfect {
            return .green
        } else if abs(degrees) < 10 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white)
            
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 50, height: 50)
                
                if let degrees = angleDegrees {
                    Text(String(format: "%.1f%@", abs(degrees), unit))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                    
                    // 角度指针
                    Rectangle()
                        .fill(color)
                        .frame(width: 2, height: 20)
                        .offset(y: -10)
                        .rotationEffect(.degrees(degrees))
                } else {
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - 预览
#Preview {
    GuidanceOverlayView(
        faceBoundingBox: CGRect(x: 100, y: 100, width: 200, height: 250),
        yawAngle: 0.1,  // 约5.7度
        rollAngle: 0.05, // 约2.9度
        pitchAngle: -0.2 // 约-11.5度（低头）
    )
    .background(Color.gray)
}
