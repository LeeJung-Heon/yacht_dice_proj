import Testing
import CoreGraphics
import RealityKit
import simd
import DiceTrajectory
@testable import YachtDice

/// 주사위 눈이 화면에 제대로 나오는지를 지키는 이음매 테스트.
///
/// 여기가 조용히 썩었던 자리다. 예전 구현은 `generateBox`가 6면을 가로로 이어붙인
/// 아틀라스를 기대한다고 가정했는데, 실제로는 텍스처 한 장이 6면 각각에 통째로
/// 매핑된다. 결과는 눈이 하나도 안 보이는 줄무늬 주사위였고, 컴파일도 되고
/// 테스트도 다 통과했기 때문에 스무 번의 리뷰를 그대로 통과했다.
///
/// 그래서 이 테스트는 코드가 아니라 **메시가 실제로 뭘 주는지**를 확인한다.
@Suite("주사위 눈 텍스처")
@MainActor
struct DiePipTextureTests {

    private func parts() -> [MeshResource.Part] {
        DiceSceneBuilder.makeDieMesh().contents.models.flatMap { Array($0.parts) }
    }

    @Test("메시가 면마다 하나씩, 6개 파트로 쪼개진다")
    func 면_분리() {
        #expect(parts().count == 6, "면이 6개로 안 쪼개졌다 — splitFaces: true가 빠졌다")
        #expect(DiceSceneBuilder.makeDieMaterials().count == 6,
                "머티리얼이 6개가 아니면 파트마다 다른 눈을 붙일 수 없다")
    }

    @Test("머티리얼 인덱스 순서가 DieFace의 축 배치와 정확히 맞는다")
    func 인덱스_축_배치() throws {
        for part in parts() {
            let index = part.materialIndex
            let normals = try #require(part.normals?.elements, "파트에 법선이 없다")
            var sum = SIMD3<Float>.zero
            for normal in normals { sum += normal }
            let axis = simd_normalize(sum)

            let declared = DiePipTexture.faceNormalsByMaterialIndex[index]
            #expect(simd_length(axis - declared) < 0.02,
                    "머티리얼 인덱스 \(index)는 \(declared) 면인 줄 알았는데 실제 법선은 \(axis)다")

            // 그 축에 DieFace가 배정한 눈과 우리가 그 인덱스에 그리는 눈이 같아야 한다
            let value = DiePipTexture.faceValuesByMaterialIndex[index]
            #expect(simd_length(DieFace.normal(of: value) - declared) < 1e-5,
                    "인덱스 \(index)에 \(value)를 그리는데 DieFace는 그 눈을 \(DieFace.normal(of: value)) 면에 둔다")
        }
    }

    @Test("파트마다 UV가 그 면 하나를 [0,1]로 덮는다")
    func uv_범위() throws {
        for part in parts() {
            let uvs = try #require(part.textureCoordinates?.elements, "파트에 UV가 없다")
            let us = uvs.map(\.x), vs = uvs.map(\.y)
            #expect(us.min()! < 0.01 && us.max()! > 0.99,
                    "u가 [\(us.min()!), \(us.max()!)] — 면 하나가 텍스처 전체를 쓰지 않는다")
            #expect(vs.min()! < 0.01 && vs.max()! > 0.99,
                    "v가 [\(vs.min()!), \(vs.max()!)]")
        }
    }

    @Test("마주 보는 면의 합이 7이다")
    func 반대면_합() {
        let values = DiePipTexture.faceValuesByMaterialIndex
        // 인덱스 배치상 (0,2)=(+Z,-Z), (1,3)=(+Y,-Y), (4,5)=(+X,-X)
        #expect(values[0] + values[2] == 7)
        #expect(values[1] + values[3] == 7)
        #expect(values[4] + values[5] == 7)
        #expect(Set(values) == Set(1...6), "1~6이 한 번씩 나오지 않는다: \(values)")
    }

    @Test("각 면 텍스처에 눈 개수만큼 점이 찍힌다", arguments: 1...6)
    func 눈_개수(value: Int) throws {
        #expect(DiePipTexture.pipLayout(for: value).count == value)

        let image = try #require(DiePipTexture.makeFace(value: value, size: 64))
        #expect(image.width == 64 && image.height == 64, "면 텍스처는 정사각이어야 한다")

        // 실제로 어두운 픽셀이 찍혔는지 — 눈 수에 비례해야 한다
        let dark = darkPixelRatio(image)
        #expect(dark > 0.004 * Double(value), "\(value)면에 점이 거의 안 찍혔다 (어두운 픽셀 \(dark))")
        #expect(dark < 0.05 * Double(value) + 0.01, "\(value)면이 지나치게 검다 (\(dark))")
    }

    private func darkPixelRatio(_ image: CGImage) -> Double {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let count = CFDataGetLength(data)
        var dark = 0
        for offset in stride(from: 0, to: count - 3, by: 4) where bytes[offset] < 80 { dark += 1 }
        return Double(dark) / Double(count / 4)
    }
}
