import Foundation
import CoreGraphics
import RealityKit
import simd

/// 조명 리그. 방향광은 그림자를 만들고, IBL이 재질의 질감을 만든다.
///
/// 스펙 §7.5: 레퍼런스의 "따뜻한 실내 조명에 놓인 실물" 느낌은 대부분 IBL에서 온다.
/// 방향광만 쓰면 주사위가 플라스틱처럼 납작해 보인다. 그래서 IBL에는 그러데이션만이 아니라
/// 클리어코트와 나무에 비칠 **소프트박스 하이라이트**를 넣는다.
@MainActor
enum SceneLighting {

    /// 광원 엔티티 묶음. IBL 광원은 "ibl"이라는 이름으로 찾을 수 있다.
    static func makeRig() -> Entity {
        let rig = Entity()
        rig.name = "lighting"

        // 키: 따뜻하고, 앞-오른쪽 위에서 비스듬히. 그림자는 이 광원만 만든다.
        let key = Entity()
        key.name = "keyLight"
        var keyLight = DirectionalLightComponent(
            color: .init(red: 1.0, green: 0.93, blue: 0.84, alpha: 1), intensity: 2_600)
        keyLight.isRealWorldProxy = false
        key.components.set(keyLight)
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 0.8, depthBias: 0.6))
        key.look(at: [0, 0, 0], from: [0.22, 0.55, 0.30], relativeTo: nil)
        rig.addChild(key)

        // 필: 차갑고 약하게, 반대편에서. 그림자 쪽이 새까맣게 죽지 않게 한다.
        let fill = Entity()
        fill.name = "fillLight"
        var fillLight = DirectionalLightComponent(
            color: .init(red: 0.80, green: 0.87, blue: 1.0, alpha: 1), intensity: 700)
        fillLight.isRealWorldProxy = false
        fill.components.set(fillLight)
        fill.look(at: [0, 0, 0], from: [-0.4, 0.35, -0.2], relativeTo: nil)
        rig.addChild(fill)

        if let ibl = makeImageBasedLight() { rig.addChild(ibl) }
        return rig
    }

    /// 스튜디오 환경광. 외부 HDR 파일 없이 코드로 등장방형 이미지를 만든다 (스펙 §13).
    /// 수신 컴포넌트는 여기 붙이지 않는다 — 비출 대상의 조상(root)에 붙는다 (DiceSceneBuilder 참고).
    static func makeImageBasedLight() -> Entity? {
        guard let image = makeStudioEnvironment().makeImage(),
              let resource = try? EnvironmentResource(equirectangular: image, withName: "studio")
        else { return nil }

        let entity = Entity()
        entity.name = "ibl"
        var component = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.9)
        component.inheritsRotation = true
        entity.components.set(component)
        return entity
    }

    /// 위는 따뜻한 크림색 천장, 아래는 어두운 나무 바닥. 천장 앞쪽에 커다란 소프트박스 하나,
    /// 뒤쪽에 작은 보조광 하나가 있는 실내다. 이 두 밝은 면이 주사위 클리어코트에 비친다.
    nonisolated static func makeStudioEnvironment(width: Int = 512, height: Int = 256) -> PixelCanvas {
        var canvas = PixelCanvas(width: width, height: height)
        let ceiling = SIMD3<Float>(0.92, 0.86, 0.76)
        let horizon = SIMD3<Float>(0.42, 0.34, 0.27)
        let floor = SIMD3<Float>(0.10, 0.07, 0.05)
        canvas.fill { u, v in
            // v: 0 = 천정(+Y), 1 = 바닥(-Y)
            var color = v < 0.5
                ? lerp(ceiling, horizon, smoothstep(0.0, 0.5, v))
                : lerp(horizon, floor, smoothstep(0.5, 1.0, v))
            // 소프트박스: 앞쪽(u ≈ 0.5) 천장 근처의 넓은 타원
            color += softbox(u: u, v: v, center: SIMD2(0.5, 0.18), radius: SIMD2(0.16, 0.11)) * SIMD3(1.0, 0.97, 0.90)
            // 보조광: 뒤쪽(u ≈ 0)의 작은 타원, 약간 차갑다
            color += softbox(u: u, v: v, center: SIMD2(0.02, 0.30), radius: SIMD2(0.07, 0.08)) * SIMD3(0.55, 0.62, 0.75)
            color += softbox(u: u, v: v, center: SIMD2(0.98, 0.30), radius: SIMD2(0.07, 0.08)) * SIMD3(0.55, 0.62, 0.75)
            return SIMD4(color, 1)
        }
        return canvas
    }

    nonisolated private static func softbox(u: Float, v: Float, center: SIMD2<Float>, radius: SIMD2<Float>) -> Float {
        let d = (SIMD2(u, v) - center) / radius
        let r = simd_length(d)
        return 1 - smoothstep(0.7, 1.0, r)
    }
}

