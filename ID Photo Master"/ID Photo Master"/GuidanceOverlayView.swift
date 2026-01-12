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
                
                // 静态参考轮廓（完全固定，不随人脸移动）
                StaticReferenceSilhouette()
                    .stroke(
                        Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [10, 5])
                    )
                    .frame(width: geometry.size.width * 0.60, height: geometry.size.width * 0.60 * 1.35)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * 0.15 + (geometry.size.width * 0.60 * 1.35) / 2
                    )
                
                // 🧹 已移除：动态弧形光圈（调试用）
                // 🧹 已移除：人脸边界框（调试用）
                // 🧹 已移除：角度指示器（调试用）
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

// MARK: - 静态参考轮廓（完全固定，不接受任何检测输入）
struct StaticReferenceSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        
        // 固定的标准证件照比例（基于屏幕坐标系）
        let headTop = h * 0.08           // 头顶位置
        let headWidth = w * 0.52         // 头部宽度
        let headHeight = h * 0.42        // 头部高度
        
        // 颈部
        let neckTop = headTop + headHeight
        let neckWidth = w * 0.22
        let neckHeight = h * 0.10
        
        // 肩膀
        let shoulderTop = neckTop + neckHeight
        let shoulderWidth = w * 0.70
        let shoulderHeight = h * 0.15
        
        // 绘制头部椭圆
        let headRect = CGRect(
            x: cx - headWidth/2,
            y: headTop,
            width: headWidth,
            height: headHeight
        )
        path.addEllipse(in: headRect)
        
        // 绘制颈部和肩膀（开放式）
        // 左肩
        path.move(to: CGPoint(x: cx - shoulderWidth/2, y: shoulderTop + shoulderHeight))
        
        // 左肩到左颈
        path.addQuadCurve(
            to: CGPoint(x: cx - neckWidth/2, y: neckTop),
            control: CGPoint(x: cx - shoulderWidth * 0.38, y: shoulderTop + shoulderHeight * 0.5)
        )
        
        // 左颈（短直线）
        path.addLine(to: CGPoint(x: cx - neckWidth/2, y: neckTop - neckHeight * 0.2))
        
        // 右颈（对称）
        path.move(to: CGPoint(x: cx + neckWidth/2, y: neckTop - neckHeight * 0.2))
        path.addLine(to: CGPoint(x: cx + neckWidth/2, y: neckTop))
        
        // 右颈到右肩
        path.addQuadCurve(
            to: CGPoint(x: cx + shoulderWidth/2, y: shoulderTop + shoulderHeight),
            control: CGPoint(x: cx + shoulderWidth * 0.38, y: shoulderTop + shoulderHeight * 0.5)
        )
        
        return path
    }
}

// MARK: - ICAO 标准引导框（符合国际证件照标准）
struct ICAOGuidanceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        
        // ICAO 标准比例：
        // - 轮廓高度占屏幕 55%
        // - 头顶距离顶端 12%
        // - 头部是椭圆形
        // - 底部开放式，暗示需要露出肩膀
        
        // 头部椭圆参数
        let headTop = h * 0.12           // 头顶留白12%
        let headWidth = w * 0.50         // 头部宽度
        let headHeight = h * 0.42        // 头部高度（椭圆）
        
        // 耳朵标记位置
        let earY = headTop + headHeight * 0.45  // 耳朵在头部中间偏上
        let earRadius = w * 0.025        // 耳朵标记半径
        
        // 颈部和肩膀
        let neckTop = headTop + headHeight
        let neckWidth = w * 0.22
        let shoulderTop = neckTop + h * 0.08
        let shoulderWidth = w * 0.70
        
        // 绘制头部椭圆
        let headRect = CGRect(
            x: cx - headWidth/2,
            y: headTop,
            width: headWidth,
            height: headHeight
        )
        path.addEllipse(in: headRect)
        
        // 绘制左耳标记（小半圆）
        path.addArc(
            center: CGPoint(x: cx - headWidth/2, y: earY),
            radius: earRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(270),
            clockwise: false
        )
        
        // 绘制右耳标记（小半圆）
        path.addArc(
            center: CGPoint(x: cx + headWidth/2, y: earY),
            radius: earRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // 绘制颈部和肩膀轮廓（开放式倒U形）
        // 从左肩开始
        path.move(to: CGPoint(x: cx - shoulderWidth/2, y: shoulderTop + h * 0.15))
        
        // 左肩到左颈
        path.addQuadCurve(
            to: CGPoint(x: cx - neckWidth/2, y: neckTop),
            control: CGPoint(x: cx - shoulderWidth * 0.35, y: shoulderTop)
        )
        
        // 左颈（短直线）
        path.addLine(to: CGPoint(x: cx - neckWidth/2, y: neckTop - h * 0.02))
        
        // 右颈（对称）
        path.move(to: CGPoint(x: cx + neckWidth/2, y: neckTop - h * 0.02))
        path.addLine(to: CGPoint(x: cx + neckWidth/2, y: neckTop))
        
        // 右颈到右肩
        path.addQuadCurve(
            to: CGPoint(x: cx + shoulderWidth/2, y: shoulderTop + h * 0.15),
            control: CGPoint(x: cx + shoulderWidth * 0.35, y: shoulderTop)
        )
        
        return path
    }
}

// MARK: - 原有的头部和肩部形状（保留作为备用）
struct HeadAndShouldersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        
        // 参考图的关键点位置（精确测量）
        // 从左肩开始，逆时针绘制完整轮廓
        
        // 左肩起点
        path.move(to: CGPoint(x: cx - w * 0.47, y: h * 0.88))
        
        // 左肩到左颈（大弧线）
        path.addCurve(
            to: CGPoint(x: cx - w * 0.13, y: h * 0.62),
            control1: CGPoint(x: cx - w * 0.42, y: h * 0.78),
            control2: CGPoint(x: cx - w * 0.20, y: h * 0.68)
        )
        
        // 左颈（直线）
        path.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.53))
        
        // 左下巴（圆润过渡）
        path.addCurve(
            to: CGPoint(x: cx, y: h * 0.545),
            control1: CGPoint(x: cx - w * 0.10, y: h * 0.535),
            control2: CGPoint(x: cx - w * 0.05, y: h * 0.545)
        )
        
        // 右下巴（对称）
        path.addCurve(
            to: CGPoint(x: cx + w * 0.13, y: h * 0.53),
            control1: CGPoint(x: cx + w * 0.05, y: h * 0.545),
            control2: CGPoint(x: cx + w * 0.10, y: h * 0.535)
        )
        
        // 右颈（直线）
        path.addLine(to: CGPoint(x: cx + w * 0.13, y: h * 0.62))
        
        // 右颈到右肩（大弧线）
        path.addCurve(
            to: CGPoint(x: cx + w * 0.47, y: h * 0.88),
            control1: CGPoint(x: cx + w * 0.20, y: h * 0.68),
            control2: CGPoint(x: cx + w * 0.42, y: h * 0.78)
        )
        
        // 头部轮廓（新路径，从右下巴开始）
        path.move(to: CGPoint(x: cx + w * 0.13, y: h * 0.53))
        
        // 右脸颊（平滑曲线）
        path.addCurve(
            to: CGPoint(x: cx + w * 0.24, y: h * 0.38),
            control1: CGPoint(x: cx + w * 0.20, y: h * 0.47),
            control2: CGPoint(x: cx + w * 0.24, y: h * 0.42)
        )
        
        // 右耳朵（小凸起）
        path.addCurve(
            to: CGPoint(x: cx + w * 0.27, y: h * 0.32),
            control1: CGPoint(x: cx + w * 0.26, y: h * 0.36),
            control2: CGPoint(x: cx + w * 0.27, y: h * 0.34)
        )
        
        path.addCurve(
            to: CGPoint(x: cx + w * 0.24, y: h * 0.26),
            control1: CGPoint(x: cx + w * 0.27, y: h * 0.30),
            control2: CGPoint(x: cx + w * 0.26, y: h * 0.28)
        )
        
        // 右侧头部（从耳朵到头顶）
        path.addCurve(
            to: CGPoint(x: cx, y: h * 0.08),
            control1: CGPoint(x: cx + w * 0.24, y: h * 0.18),
            control2: CGPoint(x: cx + w * 0.15, y: h * 0.08)
        )
        
        // 左侧头部（从头顶到耳朵，对称）
        path.addCurve(
            to: CGPoint(x: cx - w * 0.24, y: h * 0.26),
            control1: CGPoint(x: cx - w * 0.15, y: h * 0.08),
            control2: CGPoint(x: cx - w * 0.24, y: h * 0.18)
        )
        
        // 左耳朵（对称）
        path.addCurve(
            to: CGPoint(x: cx - w * 0.27, y: h * 0.32),
            control1: CGPoint(x: cx - w * 0.26, y: h * 0.28),
            control2: CGPoint(x: cx - w * 0.27, y: h * 0.30)
        )
        
        path.addCurve(
            to: CGPoint(x: cx - w * 0.24, y: h * 0.38),
            control1: CGPoint(x: cx - w * 0.27, y: h * 0.34),
            control2: CGPoint(x: cx - w * 0.26, y: h * 0.36)
        )
        
        // 左脸颊（平滑曲线）
        path.addCurve(
            to: CGPoint(x: cx - w * 0.13, y: h * 0.53),
            control1: CGPoint(x: cx - w * 0.24, y: h * 0.42),
            control2: CGPoint(x: cx - w * 0.20, y: h * 0.47)
        )
        
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
