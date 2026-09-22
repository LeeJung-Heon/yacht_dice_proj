import Foundation
import GameCore

/// 스와이프를 던지는 힘으로 바꾸고 실제 공의 재생 위치를 구한다. 3D 배치는 CupPongScene이 맡는다.
enum CupPongGeometry {
    /// 끈 길이가 세기를 정하고 `speed`(놓기 직전 구간의 초당 이동 거리)는 거기에 최대 15%만 얹는다.
    /// `screenHeight`에 화면 높이를 주면 손을 멈춘 채 200~280pt쯤 끄는 끌기가 컵 자리에 떨어진다.
    static func shot(dx: CGFloat, dy: CGFloat, speed: CGFloat, screenHeight: CGFloat) -> CupPong.Shot? {
        guard dy > 0 else { return nil }
        let length = (dx * dx + dy * dy).squareRoot()
        let speedFactor = min(1, speed / (screenHeight * 4))
        let power = length / screenHeight * 1400 * (1 + 0.15 * speedFactor)
        let side = dx / max(abs(dy), 1) * 1000
        return CupPong.Shot(dx: Int(max(-1000, min(1000, side.rounded()))),
                            power: Int(max(0, min(1000, power.rounded()))))
    }

    /// 실제 충돌 경로를 화면의 경과 시간에 맞춰 보간한다. 마지막 표본은 4스텝 간격이 아닐 수 있다.
    static func ballFrame(in frames: [CupPong.Frame], at seconds: TimeInterval) -> (x: Int, y: Int, height: CGFloat)? {
        guard let first = frames.first, let last = frames.last else { return nil }
        let step = max(0, seconds) * Double(CupPong.stepsPerSecond)
        guard step > Double(first.step) else { return (first.x, first.y, CGFloat(first.height)) }
        guard step < Double(last.step), let index = frames.firstIndex(where: { Double($0.step) >= step }) else {
            return (last.x, last.y, CGFloat(last.height))
        }
        let a = frames[index - 1], b = frames[index]
        let t = (step - Double(a.step)) / Double(max(1, b.step - a.step))
        return (Int((Double(a.x) + Double(b.x - a.x) * t).rounded()),
                Int((Double(a.y) + Double(b.y - a.y) * t).rounded()),
                CGFloat(Double(a.height) + Double(b.height - a.height) * t))
    }
}
