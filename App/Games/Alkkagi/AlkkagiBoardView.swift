import SwiftUI
import GameCore

/// 나무 판, 13×13 격자, 화점, 흑백 돌, 당김 선과 화살표, 예상 궤적 점선. 배치만 받아 그린다.
struct AlkkagiBoardView: View {
    let stones: [[Alkkagi.Point?]]
    var flipped = false
    var pull: (from: Alkkagi.Point, to: Alkkagi.Point)?
    var preview: [Alkkagi.Point] = []
    var highlight: Int?
    var highlightSeat = 0

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.fill(Path(CGRect(origin: origin, size: CGSize(width: side, height: side))),
                         with: .color(Color(red: 0.86, green: 0.70, blue: 0.44)))
            var grid = Path()
            for i in 0..<Alkkagi.lines {
                let v = i * Alkkagi.spacing
                grid.move(to: AlkkagiGeometry.project(.init(x: v, y: 0), in: size, flipped: flipped))
                grid.addLine(to: AlkkagiGeometry.project(.init(x: v, y: Alkkagi.boardMax), in: size, flipped: flipped))
                grid.move(to: AlkkagiGeometry.project(.init(x: 0, y: v), in: size, flipped: flipped))
                grid.addLine(to: AlkkagiGeometry.project(.init(x: Alkkagi.boardMax, y: v), in: size, flipped: flipped))
            }
            context.stroke(grid, with: .color(.black.opacity(0.65)), lineWidth: 1)
            for (x, y) in [(3, 3), (3, 9), (9, 3), (9, 9), (6, 6)] {
                let p = AlkkagiGeometry.project(.init(x: x * Alkkagi.spacing, y: y * Alkkagi.spacing), in: size, flipped: flipped)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.black.opacity(0.7)))
            }
            if preview.count > 1 {
                var path = Path()
                for (i, p) in preview.enumerated() {
                    let s = AlkkagiGeometry.project(p, in: size, flipped: flipped)
                    i == 0 ? path.move(to: s) : path.addLine(to: s)
                }
                context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
            }
            let r = AlkkagiGeometry.stoneRadius(in: size)
            for seat in stones.indices {
                for (i, p) in stones[seat].enumerated() {
                    guard let p else { continue }
                    let c = AlkkagiGeometry.project(p, in: size, flipped: flipped)
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.25)))
                    let black = seat == 0
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: black ? [Color(white: 0.35), .black] : [.white, Color(white: 0.78)]),
                        center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
                    if highlight == i && highlightSeat == seat {
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(Color(red: 0.72, green: 0.53, blue: 0.17)), lineWidth: 2)
                    }
                }
            }
            if let pull {
                let from = AlkkagiGeometry.project(pull.from, in: size, flipped: flipped)
                let to = AlkkagiGeometry.project(pull.to, in: size, flipped: flipped)
                var line = Path(); line.move(to: from); line.addLine(to: to)
                context.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 2)
                // 화살표: 돌에서 당김 반대 방향으로
                let dx = from.x - to.x, dy = from.y - to.y
                let len = max(1, (dx * dx + dy * dy).squareRoot())
                let tip = CGPoint(x: from.x + dx / len * r * 2.2, y: from.y + dy / len * r * 2.2)
                var arrow = Path(); arrow.move(to: from); arrow.addLine(to: tip)
                context.stroke(arrow, with: .color(Color(red: 0.72, green: 0.53, blue: 0.17)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityIdentifier("alkkagi.board")
        .accessibilityLabel("흑 \(stones[0].compactMap { $0 }.count) · 백 \(stones[1].compactMap { $0 }.count)")
    }
}
