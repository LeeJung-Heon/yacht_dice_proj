import Foundation
import GameCore

/// 테이블 격자 ↔ 화면. 규칙은 정수 격자만 알고, 화면은 여기서만 원근을 붙인다.
enum CupPongGeometry {
    /// 먼 쪽 폭 / 가까운 쪽 폭.
    static let farRatio: CGFloat = 0.55
    /// 테이블이 차지하는 세로 범위(화면 높이 비율). 위 여백은 상대 명패, 아래는 공을 끄는 자리다.
    static let topInset: CGFloat = 0.12
    static let bottomInset: CGFloat = 0.22

    /// 먼 쪽일수록 작아지는 배율. `size`는 지금 쓰이지 않지만 화면 비율에 따라 원근을 달리 줄 자리로 남겨 둔다.
    static func scale(y: Int, in size: CGSize) -> CGFloat {
        let t = CGFloat(y) / CGFloat(CupPong.tableLength)
        return 1 - (1 - farRatio) * t
    }

    static func project(x: Int, y: Int, in size: CGSize) -> CGPoint {
        let t = CGFloat(y) / CGFloat(CupPong.tableLength)
        let top = size.height * topInset, bottom = size.height * (1 - bottomInset)
        let sy = bottom - (bottom - top) * t
        let halfWidth = size.width * 0.46 * scale(y: y, in: size)
        let sx = size.width / 2 + halfWidth * CGFloat(x) / CGFloat(CupPong.tableHalfWidth)
        return CGPoint(x: sx, y: sy)
    }

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
