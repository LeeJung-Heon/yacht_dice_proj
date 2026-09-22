import RealityKit
import UIKit
import GameCore

/// 물리 엔진의 좌표를 같은 축척으로 그린다. 컵과 공의 실제 접촉면도 규칙 치수를 따른다.
@MainActor
final class CupPongScene {
    let root = Entity()
    let camera = Entity()
    private var cups: [Entity] = []
    private var photos: [ModelEntity] = []
    private let ball = ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [CupPongMaterials.ball])
    private let ballShadow = ModelEntity(mesh: .generatePlane(width: 0.055, depth: 0.055), materials: [CupPongMaterials.contactShadow])
    private var appliedRevision = -1
    private var appliedStore: ObjectIdentifier?

    init() {
        root.name = "cupPongStage"
        var cameraComponent = PerspectiveCameraComponent()
        cameraComponent.fieldOfViewInDegrees = 47
        camera.components.set(cameraComponent)
        setPlayCamera()
        buildTable()
        buildCups()
        ball.name = "ball"
        ball.isEnabled = false
        root.addChild(ball)
        ballShadow.name = "ballShadow"
        ballShadow.isEnabled = false
        root.addChild(ballShadow)
        let rig = SceneLighting.makeRig()
        if let key = rig.findEntity(named: "keyLight") {
            key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 2.5, depthBias: 1.5))
        }
        root.addChild(rig)
        if let ibl = rig.findEntity(named: "ibl") {
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        }
    }

    func focus(on cup: Int?) {
        if let cup, CupPong.cupCenters.indices.contains(cup) {
            let center = CupPong.cupCenters[cup]
            let p = Self.position(x: center.x, y: center.y)
            camera.look(at: p + [0, 0.042, 0], from: p + [0.015, 0.15, 0.24], relativeTo: nil)
        } else {
            setPlayCamera()
        }
    }

    private func setPlayCamera() {
        camera.look(at: [0, 0.005, -0.62], from: [0, 1.15, 0.40], relativeTo: nil)
    }

    private func buildTable() {
        let wood = SceneMaterials.walnut(along: .v, tone: 1.08)
        box("tableFrame", size: [0.855, 0.068, 1.255], at: [0, -0.043, -0.6], material: wood, radius: 0.012)
        box("tableInlay", size: [0.81, 0.014, 1.21], at: [0, -0.009, -0.6], material: CupPongMaterials.brass, radius: 0.005)
        box("playingSurface", size: [0.80, 0.012, 1.20], at: [0, -0.006, -0.6], material: CupPongMaterials.tabletop, radius: 0.004)
        let ink = CupPongMaterials.base(UIColor(red: 0.77, green: 0.77, blue: 0.64, alpha: 1), roughness: 0.75)
        for x: Float in [-0.383, 0.383] {
            box("sideline", size: [0.002, 0.0004, 1.165], at: [x, 0.0003, -0.6], material: ink)
        }
        for z: Float in [-0.02, -1.18] {
            box("baseline", size: [0.766, 0.0004, 0.002], at: [0, 0.0003, z], material: ink)
        }
        box("centerLine", size: [0.766, 0.0004, 0.001], at: [0, 0.0003, -0.55], material: ink)
        // 상판 위 인쇄. 플레이 영역을 가리지 않는 작고 낮은 대비의 표시다.
        let lettering = ModelEntity(mesh: .generateText("CUP  /  PONG", extrusionDepth: 0.0001,
            font: .systemFont(ofSize: 0.024, weight: .medium)), materials: [ink])
        let width = lettering.visualBounds(relativeTo: nil).extents.x
        lettering.position = [-width / 2, 0.0006, -0.49]
        lettering.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        root.addChild(lettering)
        for x: Float in [-0.32, 0.32] {
            for z: Float in [-0.12, -1.08] {
                box("leg", size: [0.028, 0.33, 0.028], at: [x, -0.23, z], material: CupPongMaterials.metal, radius: 0.003)
                let bolt = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: 0.0025), materials: [CupPongMaterials.brass])
                bolt.position = [x > 0 ? 0.414 : -0.414, -0.008, z]
                root.addChild(bolt)
            }
        }
        box("floor", size: [20, 0.015, 20], at: [0, -0.4, 0],
            material: CupPongMaterials.base(UIColor(red: 0.033, green: 0.047, blue: 0.042, alpha: 1), roughness: 0.95))
    }

    private func buildCups() {
        // 외벽, 흰 내벽, 말린 테두리를 각각 모델링해 구멍의 깊이와 얇은 플라스틱 두께를 남긴다.
        let height = Float(CupPong.cupHeight) * 0.0004
        let radius = Float(CupPong.cupRadius) * 0.0004
        let innerRadius = Float(CupPong.cupInnerRadius) * 0.0004
        let shell = Self.lathe(profile: [(0.032, 0.002), (0.033, 0.011), (0.035, 0.025),
            (0.039, 0.043), (0.0455, 0.071), (radius, height)])
        let interior = Self.lathe(profile: [(innerRadius, height), (0.027, 0.006), (0.001, 0.006)])
        let rim = Self.ring(radius: (radius + innerRadius) / 2, tube: Float(CupPong.rimRadius) * 0.0004, height: height)
        let photoMesh = Self.lathe(profile: [(0.0359, 0.028), (0.0459, 0.069)], start: -0.92, end: 0.92)
        let shadowMesh = MeshResource.generatePlane(width: 0.12, depth: 0.12)
        for (index, center) in CupPong.cupCenters.enumerated() {
            let cup = Entity()
            cup.name = "cup.\(index)"
            cup.position = Self.position(x: center.x, y: center.y)
            cup.addChild(ModelEntity(mesh: shell, materials: [CupPongMaterials.redPlastic]))
            cup.addChild(ModelEntity(mesh: interior, materials: [CupPongMaterials.innerPlastic]))
            cup.addChild(ModelEntity(mesh: rim, materials: [CupPongMaterials.rim]))
            for h: Float in [0.009, 0.015, 0.020] {
                let rib = ModelEntity(mesh: Self.ring(radius: 0.032 + h * 0.15, tube: 0.00065, height: h), materials: [CupPongMaterials.redPlastic])
                cup.addChild(rib)
            }
            let liquid = ModelEntity(mesh: .generateCylinder(height: 0.0006, radius: 0.0315), materials: [CupPongMaterials.water])
            liquid.name = "liquid.\(index)"
            liquid.position.y = Float(CupPong.liquidHeight) * 0.0004
            cup.addChild(liquid)
            let meniscus = ModelEntity(mesh: Self.ring(radius: 0.0314, tube: 0.0006, height: Float(CupPong.liquidHeight) * 0.0004 + 0.0003), materials: [CupPongMaterials.water])
            cup.addChild(meniscus)
            let shadow = ModelEntity(mesh: shadowMesh, materials: [CupPongMaterials.contactShadow])
            shadow.position.y = 0.0005
            cup.addChild(shadow)
            let photo = ModelEntity(mesh: photoMesh, materials: [CupPongMaterials.base(.white, roughness: 0.45)])
            photo.name = "photo.\(index)"
            photo.isEnabled = false
            cup.addChild(photo)
            photos.append(photo)
            root.addChild(cup)
            cups.append(cup)
        }
    }

    private static func ring(radius: Float, tube: Float, height: Float) -> MeshResource {
        lathe(profile: (0...12).map { index in
            let angle = Float(index) / 12 * 2 * .pi
            return (radius + cos(angle) * tube, height + sin(angle) * tube)
        })
    }

    static func position(x: Int, y: Int) -> SIMD3<Float> { [Float(x) * 0.0004, 0, -Float(y) * 0.0004] }

    func update(cups remaining: [Bool], ball frame: (x: Int, y: Int, height: CGFloat)?, vanishing: Int?,
                customization: CupPongCustomizationStore) {
        for index in cups.indices { cups[index].isEnabled = remaining.indices.contains(index) && remaining[index] && index != vanishing }
        ball.isEnabled = frame != nil
        ballShadow.isEnabled = frame != nil
        if let frame {
            ball.position = Self.position(x: frame.x, y: frame.y)
            ball.position.y = Float(frame.height) * 0.0004
            ball.orientation = simd_quatf(angle: Float(frame.y) * 0.016, axis: normalize(SIMD3<Float>(1, 0, 0.25)))
            ballShadow.position = Self.position(x: frame.x, y: frame.y) + [0, 0.001, 0]
            let spread = 1 + max(0, Float(frame.height)) / 550
            ballShadow.scale = [spread, 1, spread]
            ballShadow.isEnabled = abs(frame.x) <= CupPong.tableHalfWidth && (0...CupPong.tableLength).contains(frame.y) && frame.height >= 0
        }
        guard appliedRevision != customization.revision || appliedStore != ObjectIdentifier(customization) else { return }
        appliedRevision = customization.revision
        appliedStore = ObjectIdentifier(customization)
        for index in photos.indices {
            guard let image = customization.image(for: index)?.cgImage,
                  let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else {
                photos[index].isEnabled = false
                continue
            }
            var material = CupPongMaterials.base(.white, roughness: 0.42)
            material.baseColor = .init(texture: .init(texture))
            photos[index].model?.materials = [material]
            photos[index].isEnabled = true
        }
    }

    private func box(_ name: String, size: SIMD3<Float>, at position: SIMD3<Float>,
                     material: PhysicallyBasedMaterial, radius: Float = 0) {
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material])
        entity.name = name
        entity.position = position
        root.addChild(entity)
    }

    /// 사진 패치도 같은 곡면을 사용해 컵 벽에 붙는다.
    private static func lathe(profile: [(Float, Float)], start: Float = -.pi, end: Float = .pi) -> MeshResource {
        let segments = 64
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var triangles: [UInt32] = []
        for strip in 0..<(profile.count - 1) {
            let lower = profile[strip], upper = profile[strip + 1]
            let offset = UInt32(positions.count)
            for row in 0...1 {
                let point = row == 0 ? lower : upper
                for segment in 0...segments {
                    let u = Float(segment) / Float(segments)
                    let angle = start + (end - start) * u
                    positions.append([sin(angle) * point.0, point.1, cos(angle) * point.0])
                    normals.append(normalize(SIMD3(sin(angle) * (upper.1 - lower.1), lower.0 - upper.0,
                                                   cos(angle) * (upper.1 - lower.1))))
                    uv.append([u, Float(row)])
                }
            }
            for segment in 0..<segments {
                let a = offset + UInt32(segment), b = a + 1, c = a + UInt32(segments + 1), d = c + 1
                triangles += [a, b, c, b, d, c]
            }
        }
        var descriptor = MeshDescriptor(name: "cupSurface")
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.textureCoordinates = .init(uv)
        descriptor.primitives = .triangles(triangles)
        do { return try MeshResource.generate(from: [descriptor]) }
        catch { preconditionFailure("컵 메시 생성 실패: \(error)") }
    }
}
