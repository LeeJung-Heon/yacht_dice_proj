import Testing
import Foundation
import RealityKit
import simd
import DiceTrajectory
import YachtCore
@testable import YachtDice

/// 실제 카메라로 투영해서 "화면에 보이는가"를 검사한다.
///
/// 예전의 접근성 감사 테스트 네 개는 완전히 망가진 UI에서도 통과했다 —
/// enum raw value의 유일성, 프로퍼티 왕복, 문자열 길이, total < 1000을 봤을 뿐이다.
/// 그동안 keep한 주사위는 ndcY ≈ 1.15, 즉 화면 밖 허공에 세워지고 있었다.
/// 그래서 이 테스트는 씬의 좌표를 카메라 행렬에 그대로 통과시켜 확인한다.
@Suite("무대 투영 — 화면에 실제로 보이는가")
@MainActor
struct StageProjectionTests {

    /// 세로 화면에서 DiceStageView가 차지하는 비율(0.42)로 계산한 뷰포트 가로세로비.
    /// iPhone 17 Pro Max(가장 좁음)에서 iPhone SE(가장 넓음)까지를 덮는다.
    private static let aspects: [Float] = [1.20, 1.24, 1.30, 1.38, 1.45]

    private struct Projector {
        let view: simd_float4x4
        let tanHalfFOV: Float
        let aspect: Float

        @MainActor init(camera: Entity, aspect: Float) {
            view = camera.transformMatrix(relativeTo: nil).inverse
            let fov = camera.components[PerspectiveCameraComponent.self]!.fieldOfViewInDegrees
            tanHalfFOV = tan(fov * .pi / 180 / 2)
            self.aspect = aspect
        }

        /// RealityKit 카메라는 로컬 -Z를 본다.
        func ndc(_ point: SIMD3<Float>) -> SIMD2<Float> {
            let v = view * SIMD4<Float>(point, 1)
            return SIMD2((v.x / -v.z) / (tanHalfFOV * aspect), (v.y / -v.z) / tanHalfFOV)
        }

        func corners(of center: SIMD3<Float>) -> [SIMD2<Float>] {
            let h = TrayGeometry.dieSize / 2
            return [-h, h].flatMap { dx in [-h, h].flatMap { dy in [-h, h].map { dz in
                ndc(center + SIMD3(dx, dy, dz))
            } } }
        }
    }

    private func restingCenters() throws -> [SIMD3<Float>] {
        try TrajectoryLibrary.bundled().all.flatMap { $0.frames[$0.frameCount - 1].map(\.position) }
    }

    private func shelfCenters() -> [SIMD3<Float>] {
        let spacing = TrayGeometry.dieSize * 1.9
        return (0..<YachtCore.diceCount).map { order in
            SIMD3((Float(order) - Float(YachtCore.diceCount - 1) / 2) * spacing,
                  TrayGeometry.shelfDieY, TrayGeometry.shelfDieZ)
        }
    }

    @Test("구운 궤적이 멈추는 모든 자리가 화면 안이다")
    func 정지_위치_전부_화면_안() throws {
        let camera = DiceSceneBuilder.makeCamera()
        let centers = try restingCenters()
        #expect(centers.count > 1_000, "정지 위치 표본이 너무 적다: \(centers.count)")

        for aspect in Self.aspects {
            let projector = Projector(camera: camera, aspect: aspect)
            var worst = SIMD2<Float>.zero
            for center in centers {
                for corner in projector.corners(of: center) {
                    worst = simd_max(worst, abs(corner))
                }
            }
            #expect(worst.x <= 0.99 && worst.y <= 0.99,
                    "가로세로비 \(aspect)에서 멈춘 주사위가 화면 밖으로 나간다: NDC \(worst)")
        }
    }

    @Test("keep 선반 위의 주사위가 화면 안이고, 바닥의 주사위와 확실히 갈라져 보인다")
    func 선반_화면_안() throws {
        let camera = DiceSceneBuilder.makeCamera()
        let restingCenters = try restingCenters()

        for aspect in Self.aspects {
            let projector = Projector(camera: camera, aspect: aspect)

            var shelfLow = Float.infinity
            for center in shelfCenters() {
                for corner in projector.corners(of: center) {
                    #expect(abs(corner.x) <= 0.97 && abs(corner.y) <= 0.97,
                            "선반 위 주사위가 화면 밖이다 (가로세로비 \(aspect)): NDC \(corner)")
                    shelfLow = min(shelfLow, corner.y)
                }
            }

            var floorHigh = -Float.infinity
            for center in restingCenters {
                for corner in projector.corners(of: center) { floorHigh = max(floorHigh, corner.y) }
            }
            #expect(shelfLow > floorHigh,
                    "선반(아래 끝 \(shelfLow))과 바닥에 멈춘 주사위(위 끝 \(floorHigh))가 화면에서 겹친다")
        }
    }

    @Test("주사위가 화면 높이의 5% 이상을 차지한다")
    func 주사위_크기() {
        let camera = DiceSceneBuilder.makeCamera()
        let projector = Projector(camera: camera, aspect: 1.24)
        let half = TrayGeometry.dieSize / 2
        // 트레이 한가운데 바닥에 놓인 주사위의 가로 폭
        let left = projector.ndc(SIMD3(-half, half, 0))
        let right = projector.ndc(SIMD3(half, half, 0))
        let widthOfFrameHeight = abs(right.x - left.x) / 2 * projector.aspect
        #expect(widthOfFrameHeight > 0.05,
                "주사위가 화면 높이의 \(widthOfFrameHeight * 100)%뿐이다 — 눈을 읽을 수 없다")
    }

    @Test("트레이 벽이 정지한 주사위의 윗면을 가리지 않는다")
    func 앞벽_가림_없음() throws {
        let camera = DiceSceneBuilder.makeCamera()
        let eye = camera.position(relativeTo: nil)
        let wallTop = TrayGeometry.visualWallHeight
        let wallZ = TrayGeometry.trayInner.z / 2      // 앞벽 안쪽 면

        for center in try restingCenters() {
            let topFace = SIMD3(center.x, center.y + TrayGeometry.dieSize / 2, center.z)
            guard topFace.z < wallZ else { continue }
            // 눈에서 윗면으로 가는 시선이 앞벽 안쪽 면을 지날 때의 높이
            let t = (wallZ - eye.z) / (topFace.z - eye.z)
            let heightAtWall = eye.y + t * (topFace.y - eye.y)
            #expect(heightAtWall > wallTop,
                    "z=\(center.z)에 멈춘 주사위의 윗면이 앞벽(높이 \(wallTop))에 가린다")
        }
    }
}
