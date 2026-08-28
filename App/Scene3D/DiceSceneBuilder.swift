import Foundation
import CoreGraphics
import RealityKit
import simd
import DiceTrajectory

/// 트레이·테이블·주사위 엔티티를 만든다.
/// 물리 컴포넌트를 붙이지 않는다 — 재생은 키프레임 구동이고, 물리는 베이커에만 있다.
@MainActor
enum DiceSceneBuilder {

    static func makeRoot() -> Entity {
        let root = Entity()
        root.addChild(makeTable())
        root.addChild(makeTray())
        for die in makeDice() { root.addChild(die) }

        let lighting = makeLighting()
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

    static func makeCamera() -> Entity {
        let camera = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = 32
        camera.components.set(component)
        // 레퍼런스와 같은 약 55도 부감. 거리와 화각은 트레이 안쪽이 화면을 채우도록 좁혔다 —
        // 예전 값(0.42/0.30, 42도)은 바깥 벽과 테이블까지 담느라 주사위가 화면 높이의
        // 4%밖에 안 됐다. 지금 값에서는 6.3%다.
        //
        // 구운 궤적 593개의 정지 위치 전부를 이 카메라로 투영해 확인했다:
        // NDC |x| ≤ 0.95, |y| ≤ 0.90 (세로 화면 비율 1.20~1.40 전 구간). keep 선반은 y ≈ 0.71,
        // 가장 뒤에서 멈춘 주사위는 y ≈ 0.44라 선반과 바닥이 확실히 갈라져 보인다.
        camera.look(at: [0, 0, 0], from: [0, 0.369, 0.258], relativeTo: nil)
        return camera
    }

    // MARK: - 구성 요소

    /// 아직 굴리기 전 다섯 개가 놓이는 자리. DiceStage.reset()도 같은 배치를 쓴다.
    static func restingPosition(slot: Int) -> SIMD3<Float> {
        [Float(slot - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
    }

    private static func makeTable() -> Entity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.45, green: 0.29, blue: 0.16, alpha: 1))
        material.roughness = .init(floatLiteral: 0.55)
        material.metallic = .init(floatLiteral: 0)
        let entity = ModelEntity(mesh: .generatePlane(width: 2, depth: 2), materials: [material])
        entity.name = "table"
        entity.position = [0, -TrayGeometry.wallThickness, 0]
        return entity
    }

    private static func makeTray() -> Entity {
        var leather = PhysicallyBasedMaterial()
        leather.baseColor = .init(tint: .init(red: 0.52, green: 0.11, blue: 0.11, alpha: 1))
        leather.roughness = .init(floatLiteral: 0.85)
        leather.metallic = .init(floatLiteral: 0)

        var rim = PhysicallyBasedMaterial()
        rim.baseColor = .init(tint: .init(red: 0.72, green: 0.72, blue: 0.74, alpha: 1))
        rim.roughness = .init(floatLiteral: 0.35)
        rim.metallic = .init(floatLiteral: 0.9)

        let tray = Entity()
        tray.name = "tray"
        let t = TrayGeometry.wallThickness
        let inner = TrayGeometry.trayInner

        let floor = ModelEntity(mesh: .generateBox(size: [inner.x, t, inner.z]), materials: [leather])
        floor.position = [0, -t / 2, 0]
        tray.addChild(floor)

        // 벽은 물리 높이(inner.y)가 아니라 눈에 보이는 테두리 높이로 그린다 — 이유는
        // TrayGeometry.visualWallHeight 주석 참고. 물리 궤적은 여전히 0.12 상자에서 구웠다.
        let h = TrayGeometry.visualWallHeight
        let walls: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([inner.x + 2 * t, h, t], [0, h / 2,  (inner.z + t) / 2]),
            ([inner.x + 2 * t, h, t], [0, h / 2, -(inner.z + t) / 2]),
            ([t, h, inner.z], [ (inner.x + t) / 2, h / 2, 0]),
            ([t, h, inner.z], [-(inner.x + t) / 2, h / 2, 0]),
        ]
        for (size, offset) in walls {
            let wall = ModelEntity(mesh: .generateBox(size: size), materials: [rim])
            wall.position = offset
            tray.addChild(wall)
        }

        tray.addChild(makeShelf(material: rim))
        return tray
    }

    /// keep한 주사위가 올라앉는 선반. 트레이 뒤쪽 벽에 붙은 턱이다.
    /// 굴러간 주사위가 절대 멈추지 않는 띠 위에 놓으므로 둘이 겹칠 일이 없다
    /// (TrayGeometry.shelfFrontZ 주석 참고).
    private static func makeShelf(material: PhysicallyBasedMaterial) -> ModelEntity {
        let depth = TrayGeometry.shelfFrontZ - TrayGeometry.shelfBackZ
        let shelf = ModelEntity(
            mesh: .generateBox(size: [TrayGeometry.trayInner.x, TrayGeometry.shelfTop, depth],
                               cornerRadius: 0.001),
            materials: [material])
        shelf.name = "shelf"
        shelf.position = [0, TrayGeometry.shelfTop / 2, TrayGeometry.shelfDieZ]
        return shelf
    }

    /// 주사위 하나의 메시. 면을 6개 파트로 쪼개서 파트마다 다른 눈 텍스처를 붙일 수 있게 한다.
    /// `splitFaces: false`로는 텍스처 한 장이 6면 전부에 그대로 매핑돼 눈을 구분할 수 없다.
    static func makeDieMesh() -> MeshResource {
        let size = TrayGeometry.dieSize
        return .generateBox(width: size, height: size, depth: size,
                            cornerRadius: size * 0.10, splitFaces: true)
    }

    /// 머티리얼 인덱스 순서대로 6장. 텍스처를 못 만들면 눈 없는 흰 주사위 하나를 돌려준다 —
    /// 게임이 시작조차 못 하는 것보다는 낫다.
    static func makeDieMaterials() -> [PhysicallyBasedMaterial] {
        var ceramic = PhysicallyBasedMaterial()
        ceramic.baseColor = .init(tint: .init(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        ceramic.roughness = .init(floatLiteral: 0.35)
        ceramic.metallic = .init(floatLiteral: 0)
        ceramic.clearcoat = .init(floatLiteral: 0.4)
        ceramic.clearcoatRoughness = .init(floatLiteral: 0.2)

        guard let faces = DiePipTexture.makeFaceTextures() else { return [ceramic] }
        return faces.map { image in
            var material = ceramic
            if let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
            return material
        }
    }

    private static func makeDice() -> [ModelEntity] {
        let mesh = makeDieMesh()
        let materials = makeDieMaterials()
        return (0..<5).map { index in
            let entity = ModelEntity(mesh: mesh, materials: materials)
            entity.name = "die\(index)"
            entity.position = restingPosition(slot: index)
            return entity
        }
    }

    /// 방향광은 그림자를 만들고, IBL이 재질의 질감을 만든다.
    /// 스펙 §7.5: 레퍼런스의 "따뜻한 실내 조명에 놓인 실물" 느낌은 대부분 IBL에서 온다.
    /// 방향광만 쓰면 주사위가 플라스틱처럼 납작해 보인다.
    private static func makeLighting() -> Entity {
        let rig = Entity()
        rig.name = "lighting"

        let key = Entity()
        key.name = "keyLight"
        var directional = DirectionalLightComponent(color: .white, intensity: 2_400)
        directional.isRealWorldProxy = false
        key.components.set(directional)
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 1.0, depthBias: 1.0))
        key.look(at: [0, 0, 0], from: [0.3, 0.6, 0.25], relativeTo: nil)
        rig.addChild(key)

        if let ibl = makeImageBasedLight() { rig.addChild(ibl) }
        return rig
    }

    /// 스튜디오 환경광. 외부 HDR 파일 없이 코드로 그러데이션 큐브맵을 만든다 (스펙 §13).
    private static func makeImageBasedLight() -> Entity? {
        guard let image = makeStudioEnvironmentImage(),
              let resource = try? EnvironmentResource(equirectangular: image, withName: "studio")
        else { return nil }

        let entity = Entity()
        entity.name = "ibl"
        var component = ImageBasedLightComponent(source: .single(resource), intensityExponent: 1.0)
        component.inheritsRotation = true
        entity.components.set(component)
        // 수신 컴포넌트는 여기 붙이지 않는다 — 비출 대상의 조상(root)에 붙는다 (makeRoot 참고).
        return entity
    }

    /// 위는 따뜻한 흰색, 아래는 어두운 갈색으로 이어지는 등장방형 이미지.
    /// 실내 테이블 위라는 상황을 최소 비용으로 흉내낸다.
    private static func makeStudioEnvironmentImage() -> CGImage? {
        let width = 256, height = 128
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let top = CGColor(red: 1.00, green: 0.96, blue: 0.90, alpha: 1)
        let bottom = CGColor(red: 0.20, green: 0.14, blue: 0.10, alpha: 1)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [top, bottom] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: 0, y: 0),
                                   options: [])
        return context.makeImage()
    }
}
