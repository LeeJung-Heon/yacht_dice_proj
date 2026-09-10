import SwiftUI
import GameCore

/// 판 위 교차점 ↔ 화면 좌표. 판은 정사각형이고 바깥 여백은 칸 하나의 절반이다.
enum OmokGeometry {
    static let n = Omok.size
    static func cell(_ size: CGSize) -> CGFloat { min(size.width, size.height) / CGFloat(n) }
    static func point(of move: Omok.Move, in size: CGSize) -> CGPoint {
        let c = cell(size)
        return CGPoint(x: c * (CGFloat(move.x) + 0.5), y: c * (CGFloat(move.y) + 0.5))
    }
    static func move(at point: CGPoint, in size: CGSize) -> Omok.Move? {
        let c = cell(size)
        let x = Int((point.x / c).rounded(.down)), y = Int((point.y / c).rounded(.down))
        guard (0..<n).contains(x), (0..<n).contains(y) else { return nil }
        return Omok.Move(x: x, y: y)
    }
}

/// 나무 판·격자·화점·돌·미리보기·마지막 수 표식. 상태만 받아 그린다.
struct OmokBoardView: View {
    let state: Omok.State
    var preview: Omok.Move?
    var previewSeat: Int = 0
    /// 원격 수가 도착해 잠깐 크게 그려 두는 자리. 로그에 더해지기 전이라 판은 아직 비어 있다.
    var animating: Omok.Move?
    var onTap: (Omok.Move) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let size = CGSize(width: side, height: side)
            Canvas { context, _ in
                let c = OmokGeometry.cell(size)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.86, green: 0.70, blue: 0.44)))
                var grid = Path()
                for i in 0..<OmokGeometry.n {
                    let p = c * (CGFloat(i) + 0.5)
                    grid.move(to: CGPoint(x: c / 2, y: p)); grid.addLine(to: CGPoint(x: size.width - c / 2, y: p))
                    grid.move(to: CGPoint(x: p, y: c / 2)); grid.addLine(to: CGPoint(x: p, y: size.height - c / 2))
                }
                context.stroke(grid, with: .color(.black.opacity(0.65)), lineWidth: 1)
                for (x, y) in [(3, 3), (3, 11), (11, 3), (11, 11), (7, 7)] {
                    let p = OmokGeometry.point(of: Omok.Move(x: x, y: y), in: size)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.black.opacity(0.7)))
                }
                for y in 0..<OmokGeometry.n {
                    for x in 0..<OmokGeometry.n {
                        let stone = state.stone(x: x, y: y)
                        guard stone != 0 else { continue }
                        let move = Omok.Move(x: x, y: y)
                        let scale: CGFloat = animating == move ? 1.25 : 1
                        drawStone(context, at: OmokGeometry.point(of: move, in: size), radius: c * 0.45 * scale, black: stone == 1, alpha: 1)
                    }
                }
                // 아직 로그에 없는 원격 수. 지금 둘 좌석의 색으로 그린다.
                if let animating, state.stone(x: animating.x, y: animating.y) == 0 {
                    drawStone(context, at: OmokGeometry.point(of: animating, in: size), radius: c * 0.45 * 1.25,
                              black: Omok.currentSeat(state) == 0, alpha: 1)
                }
                if let preview, state.stone(x: preview.x, y: preview.y) == 0 {
                    drawStone(context, at: OmokGeometry.point(of: preview, in: size), radius: c * 0.45, black: previewSeat == 0, alpha: 0.45)
                }
                if let last = state.lastMove {
                    let p = OmokGeometry.point(of: last, in: size)
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                                   with: .color(state.stone(x: last.x, y: last.y) == 1 ? .white : .black), lineWidth: 1.5)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let move = OmokGeometry.move(at: location, in: size) { onTap(move) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityIdentifier("omok.board")
        .accessibilityLabel("오목판, 흑 \(state.cells.filter { $0 == 1 }.count)개, 백 \(state.cells.filter { $0 == 2 }.count)개")
    }

    /// `GraphicsContext`는 값 형식이라 사본을 받아 `opacity`를 바꾼다.
    private func drawStone(_ context: GraphicsContext, at p: CGPoint, radius: CGFloat, black: Bool, alpha: Double) {
        var context = context
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        let shading: GraphicsContext.Shading = .radialGradient(
            Gradient(colors: black ? [Color(white: 0.35), .black] : [.white, Color(white: 0.78)]),
            center: CGPoint(x: p.x - radius * 0.35, y: p.y - radius * 0.35), startRadius: 0, endRadius: radius * 1.4)
        context.opacity = alpha
        context.fill(Path(ellipseIn: rect.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.25 * alpha)))
        context.fill(Path(ellipseIn: rect), with: shading)
    }
}
