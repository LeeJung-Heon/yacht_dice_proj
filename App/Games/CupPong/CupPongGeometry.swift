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

    /// 착지까지 직선으로 가며 높이는 `4p(1-p)` 포물선의 산이다(연출).
    static func ballPath(to landing: CupPong.Landing, progress: CGFloat) -> (x: Int, y: Int, height: CGFloat) {
        let p = max(0, min(1, progress))
        let x = Int((CGFloat(landing.x) * p).rounded())
        let y = Int((CGFloat(landing.y) * p).rounded())
        return (x, y, 4 * p * (1 - p))
    }
}
