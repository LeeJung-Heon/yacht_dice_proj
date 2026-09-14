import RealityKit
import UIKit
import GameCore

/// 규칙 좌표를 실제 입체 장면으로 옮긴다. 물리는 승패에 관여하지 않는다.
@MainActor
final class CupPongScene {
    let root = Entity()
    let camera = Entity()
    private var cups: [Entity] = []
    private var photos: [ModelEntity] = []
    private let ball = ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [material(.white, roughness: 0.3)])
    private var appliedRevision = -1
    private var appliedStore: ObjectIdentifier?

    init() {
        root.name = "cupPongStage"
        var cameraComponent = PerspectiveCameraComponent()
        cameraComponent.fieldOfViewInDegrees = 43
        camera.components.set(cameraComponent)
        camera.look(at: [0, 0, -0.59], from: [0, 1.13, 0.91], relativeTo: nil)
        let wood = SceneMaterials.walnut(along: .v, tone: 0.9)
        box("tableFrame", size: [0.86, 0.065, 1.30], at: [0, -0.042, -0.6], material: wood, radius: 0.018)
        box("felt", size: [0.80, 0.018, 1.20], at: [0, -0.009, -0.6],
            material: Self.material(UIColor(red: 0.035, green: 0.24, blue: 0.21, alpha: 1), roughness: 0.9), radius: 0.008)
        let ivory = Self.material(UIColor(white: 0.85, alpha: 1), roughness: 0.65)
        for x: Float in [-0.383, 0.383] {
            box("sideline", size: [0.003, 0.001, 1.165], at: [x, 0.0006, -0.6], material: ivory)
        }
        for z: Float in [-0.02, -0.6, -1.18] {
            box("baseline", size: [0.766, 0.001, 0.003], at: [0, 0.0006, z], material: ivory)
        }
        let metal = Self.material(UIColor(white: 0.12, alpha: 1), roughness: 0.35, metallic: 0.75)
        for x: Float in [-0.32, 0.32] {
            for z: Float in [-0.12, -1.08] {
                box("leg", size: [0.032, 0.32, 0.032], at: [x, -0.23, z], material: metal, radius: 0.004)
            }
        }
        box("floor", size: [20, 0.015, 20], at: [0, -0.4, 0],
            material: Self.material(UIColor(red: 0.045, green: 0.065, blue: 0.065, alpha: 1), roughness: 1))
        let red = Self.material(UIColor(red: 0.70, green: 0.035, blue: 0.075, alpha: 1), roughness: 0.26)
        // 외벽 → 입구 두께 → 내벽. 구멍 위를 막는 원판은 없다.
        let shellMesh = Self.lathe(profile: [(0.032, 0), (0.048, 0.085), (0.043, 0.085), (0.027, 0.007)])
        let rimProfile: [(Float, Float)] = (0...12).map { step in
            let a = Float(step) / 12 * 2 * .pi
            return (0.0455 + cos(a) * 0.0032, 0.085 + sin(a) * 0.0032)
        }
        let rimMesh = Self.lathe(profile: rimProfile)
        let photoMesh = Self.lathe(profile: [(0.0353, 0.015), (0.0455, 0.069)], start: -0.95, end: 0.95)
        for (index, center) in CupPong.cupCenters.enumerated() {
            let cup = Entity()
            cup.name = "cup.\(index)"
            cup.position = Self.position(x: center.x, y: center.y)
            cup.addChild(ModelEntity(mesh: shellMesh, materials: [red]))
            cup.addChild(ModelEntity(mesh: rimMesh, materials: [Self.material(.white, roughness: 0.23)]))
            let inside = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.030),
                                     materials: [Self.material(UIColor(red: 0.19, green: 0.018, blue: 0.03, alpha: 1), roughness: 0.15)])
            inside.position.y = 0.024
            cup.addChild(inside)
            let photo = ModelEntity(mesh: photoMesh, materials: [Self.material(.white, roughness: 0.45)])
            photo.name = "photo.\(index)"
            photo.isEnabled = false
            cup.addChild(photo)
            photos.append(photo)
            root.addChild(cup)
            cups.append(cup)
        }
        ball.name = "ball"
        ball.isEnabled = false
        root.addChild(ball)
        let rig = SceneLighting.makeRig()
        if let key = rig.findEntity(named: "keyLight") {
            key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 0.5))
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
            camera.look(at: p + [0, 0.042, 0], from: p + [0, 0.16, 0.28], relativeTo: nil)
        } else {
            camera.look(at: [0, 0, -0.59], from: [0, 1.13, 0.91], relativeTo: nil)
        }
    }

    static func position(x: Int, y: Int) -> SIMD3<Float> { [Float(x) * 0.0004, 0, -Float(y) * 0.0004] }

    func update(cups remaining: [Bool], ball frame: (x: Int, y: Int, height: CGFloat)?, vanishing: Int?,
                customization: CupPongCustomizationStore) {
        for index in cups.indices { cups[index].isEnabled = remaining.indices.contains(index) && remaining[index] && index != vanishing }
        ball.isEnabled = frame != nil
        if let frame {
            ball.position = Self.position(x: frame.x, y: frame.y)
            ball.position.y = 0.10 + Float(frame.height) * 0.40
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
            var material = Self.material(.white, roughness: 0.5)
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

    private static func material(_ color: UIColor, roughness: Float, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.clearcoat = .init(floatLiteral: 0.18)
        return material
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
