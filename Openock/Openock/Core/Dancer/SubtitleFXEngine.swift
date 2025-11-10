import Foundation
import SwiftUI
import Combine

public struct SubtitleStyle: Equatable {
    public var extraSize: CGFloat   // base 폰트에 더할 pt
    public var color: Color?        // nil이면 기본색 유지
    public static let neutral = SubtitleStyle(extraSize: 0, color: nil)
}

public struct SubtitleFXRules {
    // 임계값
    public var stepStart: Double = 60      // 단계적 확대 시작 dB
    public var stepEnd:   Double = 75      // 단계적 확대 끝 dB
    public var colorStart: Double = 80     // 색 보간 시작
    public var colorEnd:   Double = 90     // 색 보간 끝

    // 30~75dB: 9dB당 +4pt, 최대 +20pt
    public var stepWidthDB: Double = 9
    public var perStepPoints: CGFloat = 4
    public var stepMaxPoints: CGFloat = 20

    // 75~90dB: 색 보간 구간에서 추가 크기, 최대 +8pt
    public var colorExtraMax: CGFloat = 8

    // 방송 자막 톤의 진한 노랑 (#FFD500 근처)
    public var strongYellow: Color = Color(.sRGB, red: 1.0, green: 0.835, blue: 0.0, opacity: 1.0)

    public init() {}
}

public final class SubtitleFXEngine: ObservableObject {
    @Published public private(set) var style: SubtitleStyle = .neutral
    private var rules = SubtitleFXRules()

    public init() {}
    public func configure(_ rules: SubtitleFXRules) { self.rules = rules }

    /// dB에 따른 크기/색 계산.
    /// - 0~30: 기본(검정)
    /// - 30~75: +0 → +20pt (계단형, 색은 검정 유지)
    /// - 75~90: +20 → +28pt (선형) & **검정→노랑** 보간
    /// - 90+: +28pt & **완전 노랑** 고정
    public func update(dB: Double, baseColor: Color = .black) {
        var extra: CGFloat = 0
        var color: Color? = nil

        if dB >= rules.stepStart {
            let clamped = min(dB, rules.stepEnd)
            let steps = max(0, floor((clamped - rules.stepStart) / rules.stepWidthDB))
            extra += min(CGFloat(steps) * rules.perStepPoints, rules.stepMaxPoints) // 최대 +20
        }

        if dB >= rules.colorStart && dB < rules.colorEnd {
            let t = CGFloat((dB - rules.colorStart) / (rules.colorEnd - rules.colorStart)) // 0~1
            color = baseColor.interpolate(to: rules.strongYellow, t: t) // 검정→노랑
            extra += t * rules.colorExtraMax                           // +0 → +8
        } else if dB >= rules.colorEnd {
            color = rules.strongYellow
            extra += rules.colorExtraMax                                // +8 고정
        }

        let newStyle = SubtitleStyle(extraSize: extra, color: color)
        if newStyle != style { DispatchQueue.main.async { self.style = newStyle } }
    }
}

// MARK: - Color lerp helpers
private extension Color {
    func interpolate(to: Color, t: CGFloat) -> Color {
        let tt = max(0, min(1, t))
        let (r1, g1, b1, a1) = self.rgba()
        let (r2, g2, b2, a2) = to.rgba()
        return Color(
            .sRGB,
            red:     Double(r1 + (r2 - r1) * tt),
            green:   Double(g1 + (g2 - g1) * tt),
            blue:    Double(b1 + (b2 - b1) * tt),
            opacity: Double(a1 + (a2 - a1) * tt)
        )
    }

    func rgba() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        #if os(macOS)
        let ns = NSColor(self)
        guard let c = ns.usingColorSpace(.sRGB) else { return (1,1,1,1) }
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #endif
    }
}
