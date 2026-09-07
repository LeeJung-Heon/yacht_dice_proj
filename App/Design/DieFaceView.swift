import SwiftUI

/// 상아색 주사위 면. 3D 주사위와 같은 눈 배치(`DiePipTexture.pipLayout`)를 쓴다.
/// value 0이면 굴리기 전의 빈 면.
struct DieFaceView: View {
    @Environment(\.theme) private var theme
    let value: Int
    var isHeld: Bool = false
    var size: CGFloat = 48

    static func pipPoints(for value: Int) -> [CGPoint] {
        (1...6).contains(value) ? DiePipTexture.pipLayout(for: value) : []
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(LinearGradient(colors: [theme.ivory, theme.ivory.opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: isHeld ? 5 : 2, y: isHeld ? 4 : 1)
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(isHeld ? theme.brass : Color.black.opacity(0.12), lineWidth: isHeld ? 2.5 : 1)
            GeometryReader { geo in
                ForEach(Array(Self.pipPoints(for: value).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(theme.pip)
                        .frame(width: size * 0.17, height: size * 0.17)
                        .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(value == 0 ? 0.55 : 1)
        .offset(y: isHeld ? -3 : 0)
    }
}
