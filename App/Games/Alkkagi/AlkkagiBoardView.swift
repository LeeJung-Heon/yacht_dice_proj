import SwiftUI
import GameCore

/// 넓은 17줄 판. 잘린 모서리와 중앙 범퍼는 물리 규칙과 같은 치수로 그린다.
struct AlkkagiBoardView: View {
    let stones: [[Alkkagi.Point?]]
    var flipped = false
    /// 그릴 당김. `clamped`면 최대까지 당긴 것이라 선이 더 자라지 않는다.
    var pull: (from: Alkkagi.Point, to: Alkkagi.Point, clamped: Bool)?
    var preview: [Alkkagi.Point] = []
    var highlight: Int?
    var highlightSeat = 0
    /// 지금 놓는 좌석의 진영. 그 y 띠를 옅게 칠해 어디에 놓을 수 있는지 보인다.
    var homeShade: ClosedRange<Int>?
    /// 배치 중에 끌고 있는 돌. 배치의 자리가 아니라 손끝에 그린다.
    var dragging: (seat: Int, stone: Int, at: Alkkagi.Point)?
    var map: Alkkagi.Map = .classic
    private static let brass = Color(red: 0.72, green: 0.53, blue: 0.17)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let margin = AlkkagiGeometry.margin
            let limit = Alkkagi.boardMax
            let cut = Alkkagi.cornerCut + margin
            let surface: Path
            if map == .cutCorners {
                let outline: [Alkkagi.Point] = [
                    .init(x: cut, y: -margin), .init(x: limit - cut, y: -margin),
                    .init(x: limit + margin, y: cut), .init(x: limit + margin, y: limit - cut),
                    .init(x: limit - cut, y: limit + margin), .init(x: cut, y: limit + margin),
                    .init(x: -margin, y: limit - cut), .init(x: -margin, y: cut)
                ]
                surface = Path { path in
                    for (index, point) in outline.enumerated() {
                        let p = AlkkagiGeometry.project(point, in: size, flipped: flipped)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                }
            } else {
                surface = Path(CGRect(origin: origin, size: CGSize(width: side, height: side)))
            }
            context.fill(surface, with: .linearGradient(Gradient(colors: [
                Color(red: 0.91, green: 0.76, blue: 0.51), Color(red: 0.76, green: 0.56, blue: 0.31)
            ]), startPoint: origin, endPoint: CGPoint(x: origin.x + side, y: origin.y + side)))
            context.stroke(surface, with: .color(Color(red: 0.33, green: 0.20, blue: 0.10)), lineWidth: 3)
            context.clip(to: surface)
            if let homeShade {
                // 진영은 줄에서 여백 반 칸만큼 더 나가 판 가장자리에 닿는다.
                let m = AlkkagiGeometry.unit(in: size) * CGFloat(AlkkagiGeometry.margin)
                let near = AlkkagiGeometry.project(.init(x: 0, y: homeShade.lowerBound), in: size, flipped: flipped)
                let far = AlkkagiGeometry.project(.init(x: Alkkagi.boardMax, y: homeShade.upperBound), in: size, flipped: flipped)
                let band = CGRect(x: min(near.x, far.x) - m, y: min(near.y, far.y) - m,
                                  width: abs(far.x - near.x) + m * 2, height: abs(far.y - near.y) + m * 2)
                context.fill(Path(band), with: .color(Self.brass.opacity(0.22)))
            }
            var grid = Path()
            for i in 0..<Alkkagi.lines {
                let v = i * Alkkagi.spacing
                grid.move(to: AlkkagiGeometry.project(.init(x: v, y: 0), in: size, flipped: flipped))
                grid.addLine(to: AlkkagiGeometry.project(.init(x: v, y: Alkkagi.boardMax), in: size, flipped: flipped))
                grid.move(to: AlkkagiGeometry.project(.init(x: 0, y: v), in: size, flipped: flipped))
                grid.addLine(to: AlkkagiGeometry.project(.init(x: Alkkagi.boardMax, y: v), in: size, flipped: flipped))
            }
            context.stroke(grid, with: .color(.black.opacity(0.65)), lineWidth: 1)
            for (x, y) in [(4, 4), (4, 12), (12, 4), (12, 12), (8, 8)] {
                let p = AlkkagiGeometry.project(.init(x: x * Alkkagi.spacing, y: y * Alkkagi.spacing), in: size, flipped: flipped)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.black.opacity(0.7)))
            }
            if map == .centerBumper {
                let center = AlkkagiGeometry.project(.init(x: limit / 2, y: limit / 2), in: size, flipped: flipped)
                let radius = CGFloat(Alkkagi.bumperRadius) * AlkkagiGeometry.unit(in: size)
                let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: circle.offsetBy(dx: 1, dy: 3)), with: .color(.black.opacity(0.4)))
                context.fill(Path(ellipseIn: circle), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.48, green: 0.56, blue: 0.54), Color(red: 0.14, green: 0.23, blue: 0.22)]),
                    center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.5))
                context.stroke(Path(ellipseIn: circle.insetBy(dx: 2, dy: 2)), with: .color(Self.brass.opacity(0.9)), lineWidth: 2)
                context.draw(Text("범퍼").font(.system(size: max(10, radius * 0.36), weight: .semibold)).foregroundColor(.white.opacity(0.9)), at: center)
            }
            if preview.count > 1, let first = preview.first, let last = preview.last {
                var path = Path()
                for (i, p) in preview.enumerated() {
                    let s = AlkkagiGeometry.project(p, in: size, flipped: flipped)
                    i == 0 ? path.move(to: s) : path.addLine(to: s)
                }
                context.stroke(path, with: .linearGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                     .init(color: .white.opacity(0.45), location: 0.5),
                                     .init(color: .clear, location: 1)]),
                    startPoint: AlkkagiGeometry.project(first, in: size, flipped: flipped),
                    endPoint: AlkkagiGeometry.project(last, in: size, flipped: flipped)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
            }
            let r = AlkkagiGeometry.stoneRadius(in: size)
            func drawStone(_ p: Alkkagi.Point, seat: Int, stone: Int) {
                let c = AlkkagiGeometry.project(p, in: size, flipped: flipped)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.25)))
                let black = seat == 0
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: black ? [Color(white: 0.35), .black] : [.white, Color(white: 0.78)]),
                    center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
                if highlight == stone && highlightSeat == seat {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(Self.brass), lineWidth: 2)
                }
            }
            for seat in stones.indices {
                for (i, p) in stones[seat].enumerated() {
                    guard let p, !(dragging?.seat == seat && dragging?.stone == i) else { continue }
                    drawStone(p, seat: seat, stone: i)
                }
            }
            // 끌리는 돌은 맨 위에 그린다 — 지나가는 돌에 가려지면 손끝을 놓친다.
            if let dragging { drawStone(dragging.at, seat: dragging.seat, stone: dragging.stone) }
            if let pull {
                let from = AlkkagiGeometry.project(pull.from, in: size, flipped: flipped)
                let to = AlkkagiGeometry.project(pull.to, in: size, flipped: flipped)
                var line = Path(); line.move(to: from); line.addLine(to: to)
                // 최대까지 당기면 선이 황동으로 물들어, 더 끌어도 힘이 늘지 않는다고 알린다.
                context.stroke(line, with: .color(pull.clamped ? Self.brass : .white.opacity(0.9)), lineWidth: 2)
                // 화살표: 돌에서 당김 반대 방향으로
                let dx = from.x - to.x, dy = from.y - to.y
                let len = max(1, (dx * dx + dy * dy).squareRoot())
                let tip = CGPoint(x: from.x + dx / len * r * 2.2, y: from.y + dy / len * r * 2.2)
                var arrow = Path(); arrow.move(to: from); arrow.addLine(to: tip)
                context.stroke(arrow, with: .color(Self.brass), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityIdentifier("alkkagi.board")
        .accessibilityLabel("17줄 \(map.title) 판, 흑 \(stones[0].compactMap { $0 }.count) · 백 \(stones[1].compactMap { $0 }.count)")
    }
}
