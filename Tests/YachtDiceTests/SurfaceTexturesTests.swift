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
        let alphas = Set(stride(from: 3, to: data.count, by: 4).map { data[$0] })
        #expect(alphas.count > 4, "\(kind) 결이 평평하다")
    }
}
