import SwiftUI
import GameCore

/// 나무 바닥, 초록 테이블, 중앙선, 먼 쪽의 빨간 컵, 예상 착지 점선, 날아가는 공. 상태만 받아 그린다.
struct CupPongTableView: View {
    let cups: [Bool]
    /// 먼 쪽 삼각형이 누구 것인지("내 컵"·"상대 컵"). 상대 차례에는 저 컵이 내 것이라 라벨이 뒤집힌다.
    var owner: String = "상대 컵"
    var aim: CupPong.Landing?
    var ball: (x: Int, y: Int, height: CGFloat)?
    var vanishing: Int?

    /// 공·조준선이 뜬 높이를 화면에서 얼마나 들어 올려 그릴지(화면 높이 비율).
    private static let heightLift: CGFloat = 0.18

    var body: some View {
        Canvas { context, size in
            drawTable(context, size)
            if let aim { drawAim(context, size, aim) }
            // cupCenters는 먼 쪽(인덱스 0)부터 가까운 쪽 순이다. 그 순서 그대로 그려야
            // 가까운 컵이 먼 컵 위에 덧그려진다.
            for i in CupPong.cupCenters.indices where cups[i] || vanishing == i {
                drawCup(context, size, index: i, fading: vanishing == i)
            }
            if let ball { drawBall(context, size, ball) }
        }
        .accessibilityElement()
        .accessibilityIdentifier("cuppong.table")
        .accessibilityLabel("\(owner) \(cups.filter { $0 }.count)개 남음")
    }

    private func drawTable(_ context: GraphicsContext, _ size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.80, green: 0.66, blue: 0.45)))
        var table = Path()
        table.move(to: CupPongGeometry.project(x: -1000, y: 0, in: size))
        table.addLine(to: CupPongGeometry.project(x: 1000, y: 0, in: size))
        table.addLine(to: CupPongGeometry.project(x: 1000, y: 3000, in: size))
        table.addLine(to: CupPongGeometry.project(x: -1000, y: 3000, in: size))
        table.closeSubpath()
        context.fill(table, with: .color(Color(red: 0.16, green: 0.55, blue: 0.34)))
        context.stroke(table, with: .color(.white.opacity(0.9)), lineWidth: 3)
        var center = Path()
        center.move(to: CupPongGeometry.project(x: 0, y: 0, in: size))
        center.addLine(to: CupPongGeometry.project(x: 0, y: 3000, in: size))
        context.stroke(center, with: .color(.white.opacity(0.9)), lineWidth: 2)
    }

    private func drawCup(_ context: GraphicsContext, _ size: CGSize, index: Int, fading: Bool) {
        let c = CupPong.cupCenters[index]
        let p = CupPongGeometry.project(x: c.x, y: c.y, in: size)
        let s = CupPongGeometry.scale(y: c.y, in: size)
        let w = size.width * 0.075 * s, h = w * 1.35
        var ctx = context
        ctx.opacity = fading ? 0.35 : 1
        let body = Path(roundedRect: CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h), cornerRadius: w * 0.18)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 0.92, green: 0.15, blue: 0.16), Color(red: 0.65, green: 0.05, blue: 0.08)]),
                                             startPoint: CGPoint(x: p.x - w / 2, y: p.y), endPoint: CGPoint(x: p.x + w / 2, y: p.y)))
        let rim = Path(ellipseIn: CGRect(x: p.x - w / 2, y: p.y - h - w * 0.18, width: w, height: w * 0.36))
        ctx.fill(rim, with: .color(.white))
        ctx.fill(Path(ellipseIn: rim.boundingRect.insetBy(dx: w * 0.08, dy: w * 0.05)), with: .color(Color(red: 0.55, green: 0.04, blue: 0.06)))
    }

    private func drawAim(_ context: GraphicsContext, _ size: CGSize, _ aim: CupPong.Landing) {
        var path = Path()
        for step in 0...12 {
            let pt = CupPongGeometry.ballPath(to: aim, progress: CGFloat(step) / 12)
            var p = CupPongGeometry.project(x: pt.x, y: pt.y, in: size)
            p.y -= pt.height * size.height * Self.heightLift
            step == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
        let end = CupPongGeometry.project(x: aim.x, y: aim.y, in: size)
        context.stroke(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 3, width: 12, height: 6)), with: .color(.white), lineWidth: 1.5)
    }

    private func drawBall(_ context: GraphicsContext, _ size: CGSize, _ ball: (x: Int, y: Int, height: CGFloat)) {
        var p = CupPongGeometry.project(x: ball.x, y: ball.y, in: size)
        let shadow = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 3, width: 14, height: 6))
        context.fill(shadow, with: .color(.black.opacity(0.25)))
        p.y -= ball.height * size.height * Self.heightLift
        let r = 9 * CupPongGeometry.scale(y: ball.y, in: size) * (1 + ball.height * 0.4)
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [.white, Color(white: 0.75)]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.5))
    }
}
