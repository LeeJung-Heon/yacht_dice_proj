import Testing
import Foundation
import CoreGraphics
@testable import YachtDice

@Suite("표면 질감")
struct SurfaceTexturesTests {
    @Test("세 질감이 만들어지고 정사각이며, 알파가 전부 같지 않다(결이 있다)",
          arguments: [SurfaceTextures.Kind.paper, .leather, .wood])
    func 질감(kind: SurfaceTextures.Kind) throws {
        let image = try #require(SurfaceTextures.makeGrain(kind: kind, size: 64))
        #expect(image.width == 64 && image.height == 64)
        let data = try #require(image.dataProvider?.data as Data?)
        // 나무·가죽은 색이, 종이는 알파가 흔들려야 한다. 어느 쪽이든 픽셀이 다양해야 결이다.
        let pixels = Set(stride(from: 0, to: data.count, by: 4).map { data[$0..<$0 + 4].map { $0 } })
        #expect(pixels.count > 16, "\(kind) 결이 평평하다")
    }
}
