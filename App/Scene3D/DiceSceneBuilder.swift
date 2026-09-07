import Foundation
import RealityKit
import simd
import DiceTrajectory

/// 트레이·테이블·주사위 엔티티를 조립한다. 재질은 `SceneMaterials`, 조명은 `SceneLighting`이 맡는다.
/// 물리 컴포넌트를 붙이지 않는다 — 재생은 키프레임 구동이고, 물리는 베이커에만 있다.
///
/// 치수는 전부 `TrayGeometry`에서 온다. 눈에 보이는 모양(모서리 라운드, 선반 인레이)은
/// 바꿔도 되지만, 주사위가 닿는 면의 위치는 구운 궤적과 맞물려 있으니 건드리면 안 된다.
@MainActor
enum DiceSceneBuilder {

    static func makeRoot() -> Entity {
        let root = Entity()
        root.addChild(makeTable())
        root.addChild(makeTray())
        for die in makeDice() { root.addChild(die) }

        let lighting = SceneLighting.makeRig()
        root.addChild(lighting)
        // IBL은 광원 엔티티(ibl)에 붙이고, 수신은 비출 대상(table/tray/dice)의
        // 공통 조상인 root에 붙여 광원 엔티티를 가리키게 한다. 둘 다 같은 leaf
        // 엔티티에 붙이면 광원이 자기 자신만 비추고 눈에 보이는 지오메트리는
        // 아무것도 이 IBL을 받지 못한다 (리뷰에서 지적됨).
        if let ibl = lighting.findEntity(named: "ibl") {
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        }
        return root
    }

    static func dice(in root: Entity) -> [ModelEntity] {
        (0..<5).compactMap { root.findEntity(named: "die\($0)") as? ModelEntity }
    }

    /// 탭 히트테스트가 돌려준 엔티티에서 주사위 슬롯을 찾는다. 주사위가 아니면 nil.
    static func slot(of entity: Entity) -> Int? {
        guard entity.name.hasPrefix("die"), let slot = Int(entity.name.dropFirst(3)),
              (0..<5).contains(slot) else { return nil }
        return slot
    }

    static func makeCamera() -> Entity {
        let camera = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = 34
        camera.components.set(component)
        // 레퍼런스와 같은 약 55도 부감. 트레이 테두리가 네 변 모두 화면 안에 들어오면서도
        // 주사위가 화면 높이의 5% 이상을 차지하도록 잡았다 — StageProjectionTests가
        // 구운 궤적 593개의 정지 위치 전부와 keep 선반을 이 카메라로 투영해 확인한다.
        camera.look(at: [0, 0, -0.005], from: [0, 0.372, 0.262], relativeTo: nil)
        return camera
    }

    // MARK: - 구성 요소

    /// 아직 굴리기 전 다섯 개가 놓이는 자리. DiceStage.reset()도 같은 배치를 쓴다.
    static func restingPosition(slot: Int) -> SIMD3<Float> {
        [Float(slot - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
    }

    private static func makeTable() -> Entity {
        let entity = ModelEntity(mesh: .generatePlane(width: 1.2, depth: 1.2),
                                 materials: [SceneMaterials.walnut(along: .u, tone: 0.55, tiling: 5)])
        entity.name = "table"
        entity.position = [0, -TrayGeometry.wallThickness, 0]
        return entity
    }

    /// 가죽 바닥 + 호두나무 테두리 4면 + keep 선반.
    private static func makeTray() -> Entity {
        let tray = Entity()
        tray.name = "tray"
        let t = TrayGeometry.wallThickness
        let inner = TrayGeometry.trayInner
        let h = TrayGeometry.visualWallHeight

        let floor = ModelEntity(mesh: .generateBox(size: [inner.x, t, inner.z]),
                                materials: [SceneMaterials.leather(vignette: true)])
        floor.name = "floor"
        floor.position = [0, -t / 2, 0]
        tray.addChild(floor)

        // 벽은 물리 높이(inner.y)가 아니라 눈에 보이는 테두리 높이로 그린다 — 이유는
        // TrayGeometry.visualWallHeight 주석 참고. 물리 궤적은 여전히 0.12 상자에서 구웠다.
        // 벽 바깥 면은 테이블 아래(-t)까지 내려 트레이가 통짜 나무 상자로 보이게 한다.
        let wallHeight = h + t
        let wallY = (h - t) / 2
        // generateBox의 UV는 어느 면이든 u가 그 면의 가로 방향이다. 벽의 보이는 면은 안쪽 면이고,
        // 그 면의 가로 방향이 곧 벽의 길이 방향이라 결은 항상 u를 따라 흐르면 된다.
        let wood = SceneMaterials.walnut(along: .u)
        let walls: [(size: SIMD3<Float>, offset: SIMD3<Float>)] = [
            ([inner.x + 2 * t, wallHeight, t], [0, wallY,  (inner.z + t) / 2]),
            ([inner.x + 2 * t, wallHeight, t], [0, wallY, -(inner.z + t) / 2]),
            ([t, wallHeight, inner.z], [ (inner.x + t) / 2, wallY, 0]),
            ([t, wallHeight, inner.z], [-(inner.x + t) / 2, wallY, 0]),
        ]
        for wall in walls {
            let entity = ModelEntity(mesh: .generateBox(size: wall.size, cornerRadius: t * 0.28),
                                     materials: [wood])
            entity.name = "wall"
            entity.position = wall.offset
            tray.addChild(entity)
        }

        tray.addChild(makeShelf())
        return tray
    }

    /// keep한 주사위가 올라앉는 선반. 트레이 뒤쪽 벽에 붙은 호두나무 턱 위에 가죽 패드를 깔았다.
    /// 굴러간 주사위가 절대 멈추지 않는 띠 위에 놓으므로 둘이 겹칠 일이 없다
    /// (TrayGeometry.shelfFrontZ 주석 참고). 가죽 패드 윗면이 정확히 `shelfTop`이라
    /// 주사위는 `shelfDieY`에 앉으면 패드에 닿는다.
    private static func makeShelf() -> Entity {
        let depth = TrayGeometry.shelfFrontZ - TrayGeometry.shelfBackZ
        let padThickness: Float = 0.0025
        let inset: Float = 0.004

        let shelf = Entity()
        shelf.name = "shelf"

        let ledgeHeight = TrayGeometry.shelfTop - padThickness * 0.6
        let ledge = ModelEntity(
            mesh: .generateBox(size: [TrayGeometry.trayInner.x, ledgeHeight, depth], cornerRadius: 0.002),
            materials: [SceneMaterials.walnut(along: .u)])
        ledge.name = "ledge"
        ledge.position = [0, ledgeHeight / 2, TrayGeometry.shelfDieZ]
        shelf.addChild(ledge)

        // 패드는 가로가 세로의 6배쯤 되는 띠라, 세로 UV를 그만큼 줄여 결 알갱이를 정사각으로 맞춘다.
        let padWidth = TrayGeometry.trayInner.x - 2 * inset
        let padDepth = depth - 2 * inset
        let pad = ModelEntity(
            mesh: .generateBox(size: [padWidth, padThickness, padDepth], cornerRadius: 0.001),
            materials: [SceneMaterials.leather(vignette: false, tiling: [1, padDepth / padWidth])])
        pad.name = "pad"
        pad.position = [0, TrayGeometry.shelfTop - padThickness / 2, TrayGeometry.shelfDieZ]
        shelf.addChild(pad)
        return shelf
    }

    /// 주사위 하나의 메시. 면을 6개 파트로 쪼개서 파트마다 다른 눈 텍스처를 붙일 수 있게 한다.
    /// `splitFaces: false`로는 텍스처 한 장이 6면 전부에 그대로 매핑돼 눈을 구분할 수 없다.
    static func makeDieMesh() -> MeshResource {
        let size = TrayGeometry.dieSize
        return .generateBox(width: size, height: size, depth: size,
                            cornerRadius: size * 0.12, splitFaces: true)
    }

    /// 머티리얼 인덱스 순서대로 6장.
    static func makeDieMaterials() -> [PhysicallyBasedMaterial] {
        SceneMaterials.dice()
    }

    private static func makeDice() -> [ModelEntity] {
        let mesh = makeDieMesh()
        let materials = makeDieMaterials()
        return (0..<5).map { index in
            let entity = ModelEntity(mesh: mesh, materials: materials)
            entity.name = "die\(index)"
            entity.position = restingPosition(slot: index)
            // 바닥과 닿는 자리에 부드러운 접촉 그림자. 이게 없으면 주사위가 바닥 위에 떠 보인다.
            entity.components.set(GroundingShadowComponent(castsShadow: true))
            // 탭으로 keep하기 위한 히트테스트. 물리가 아니라 입력용 충돌 형상이다.
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(
                shapes: [.generateBox(size: SIMD3(repeating: TrayGeometry.dieSize))]))
            return entity
        }
    }
}
