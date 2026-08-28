import Foundation
import CoreGraphics
import RealityKit
import simd
import DiceTrajectory

/// 트레이·테이블·주사위 엔티티를 만든다.
/// 물리 컴포넌트를 붙이지 않는다 — 재생은 키프레임 구동이고, 물리는 베이커에만 있다.
enum DiceSceneBuilder {

    static func makeRoot() -> Entity {
        let root = Entity()
        root.addChild(makeTable())
        root.addChild(makeTray())
        for die in makeDice() { root.addChild(die) }
        root.addChild(makeLighting())
        return root
    }

    static func dice(in root: Entity) -> [ModelEntity] {
        (0..<5).compactMap { root.findEntity(named: "die\($0)") as? ModelEntity }
    }

    static func makeCamera() -> Entity {
        let camera = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = 42
        camera.components.set(component)
        // 레퍼런스와 같은 약 55도 부감
        camera.look(at: [0, 0, 0], from: [0, 0.42, 0.30], relativeTo: nil)
        return camera
    }

    // MARK: - 구성 요소

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

        let walls: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([inner.x + 2 * t, inner.y, t], [0, inner.y / 2,  (inner.z + t) / 2]),
            ([inner.x + 2 * t, inner.y, t], [0, inner.y / 2, -(inner.z + t) / 2]),
            ([t, inner.y, inner.z], [ (inner.x + t) / 2, inner.y / 2, 0]),
            ([t, inner.y, inner.z], [-(inner.x + t) / 2, inner.y / 2, 0]),
        ]
        for (size, offset) in walls {
            let wall = ModelEntity(mesh: .generateBox(size: size), materials: [rim])
            wall.position = offset
            tray.addChild(wall)
        }
        return tray
    }

    private static func makeDice() -> [ModelEntity] {
        var ceramic = PhysicallyBasedMaterial()
        ceramic.baseColor = .init(tint: .init(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        ceramic.roughness = .init(floatLiteral: 0.35)
        ceramic.metallic = .init(floatLiteral: 0)
        ceramic.clearcoat = .init(floatLiteral: 0.4)
        ceramic.clearcoatRoughness = .init(floatLiteral: 0.2)

        if let atlas = DiePipTexture.makeAtlas(),
           let texture = try? TextureResource(image: atlas, options: .init(semantic: .color)) {
            ceramic.baseColor = .init(tint: .white, texture: .init(texture))
        }

        return (0..<5).map { index in
            let size = TrayGeometry.dieSize
            let entity = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: size * 0.10),
                materials: [ceramic])
            entity.name = "die\(index)"
            entity.position = [Float(index - 2) * size * 1.6, size / 2, 0]
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
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: entity))
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
